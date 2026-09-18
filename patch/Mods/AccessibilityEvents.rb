# =============================================================================
# AccessibilityEvents.rb - speaks selection screens that are built out of map
# event commands rather than window classes.
#
# THE PROBLEM
# -----------
# Desolation's intro asks "what look do you think best suits you?" and then
# runs a hand-built picker:
#
#   command 105  Button Input Processing -> variable 179 (4=left, 6=right, 13=C)
#   command 122  Set Variable            -> variable 180 = highlighted look
#   command 231  Show Picture            -> "charbg1".."charbg6" in slot 1
#
# There is no window, no index and no command list, so nothing in the menu mod
# can see it - the screen is silent and unusable, which blocks the player at
# character creation.
#
# THE APPROACH
# ------------
# A picture swapping to a same-named-but-differently-numbered image, in the
# same picture slot, while an event is asking for a button press, IS a
# selection highlight moving. That pattern is announced; anything else (a
# cutscene showing unrelated art) is left alone.
#
# The button-press requirement is what keeps this quiet: a scene that merely
# displays pictures never triggers it.
# =============================================================================

module A11yEvents
  # Picture-name prefixes worth speaking nicely, with how many there are.
  # Anything not listed still gets announced, just generically.
  KNOWN_SELECTORS = {
    "charbg" => ["Look", 6]
  }

  # Frames after a Button Input Processing during which picture swaps are
  # treated as selection movement. The picker re-arms its button wait every
  # iteration, so this stays fresh for as long as the player is choosing.
  SELECTOR_WINDOW = 300

  class << self
    attr_accessor :last_button_frame

    def selector_active?
      return false if @last_button_frame.nil?
      (Graphics.frame_count - @last_button_frame) < SELECTOR_WINDOW
    rescue Exception
      false
    end

    def note_button_wait
      @last_button_frame = Graphics.frame_count
    rescue Exception
      nil
    end

    # "charbg3" -> ["charbg", 3]; "title" -> nil
    def split_trailing_number(name)
      m = name.to_s.match(/\A(.*?)(\d+)\z/)
      return nil unless m
      [m[1], m[2].to_i]
    end

    def friendly(base, number)
      known = KNOWN_SELECTORS[base.to_s.downcase]
      if known
        label, total = known
        return total ? "#{label} #{number} of #{total}" : "#{label} #{number}"
      end
      "Option #{number}"
    end

    # Remembers the last picture shown in each slot.
    def last_pictures
      @last_pictures ||= {}
    end

    def reset
      @last_pictures = {}
      @last_button_frame = nil
    end
  end
end

class Interpreter
  # Re-entry guard: a second load would chain the alias onto itself.
  unless method_defined?(:a11y_command_105)

    # Button Input Processing - the marker that an event is waiting for the
    # player to choose something.
    alias a11y_command_105 command_105
    def command_105
      A11yEvents.note_button_wait
      a11y_command_105
    end

    # Show Picture.
    alias a11y_command_231 command_231
    def command_231
      result = a11y_command_231
      begin
        slot = @parameters[0]
        name = @parameters[1].to_s
        previous = A11yEvents.last_pictures[slot]
        A11yEvents.last_pictures[slot] = name
        if previous && A11yEvents.selector_active?
          old_parts = A11yEvents.split_trailing_number(previous)
          new_parts = A11yEvents.split_trailing_number(name)
          if old_parts && new_parts &&
             old_parts[0] == new_parts[0] && old_parts[1] != new_parts[1]
            a11y(A11yEvents.friendly(new_parts[0], new_parts[1]))
          end
        end
      rescue Exception
      end
      result
    end

    # Erase Picture - forget the slot so re-entering a picker starts clean.
    if method_defined?(:command_235)
      alias a11y_command_235 command_235
      def command_235
        begin
          A11yEvents.last_pictures.delete(@parameters[0])
        rescue Exception
        end
        a11y_command_235
      end
    end
  end
end

# Leaving the map (or loading a save) invalidates whatever was on screen.
class Scene_Map
  unless method_defined?(:a11y_map_main)
    alias a11y_map_main main
    def main
      A11yEvents.reset
      a11y_map_main
    end
  end
end

AccessibilitySpeech.log("Event selector hooks loaded.") if defined?(AccessibilitySpeech)
