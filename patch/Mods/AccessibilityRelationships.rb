# =============================================================================
# Pokemon Desolation Accessibility Pack - by Mohammed Taha (mohammedtahadev).
# AccessibilityRelationships.rb - how people feel about you, by ear.
#
# Desolation quietly tracks your standing with the characters in variables
# named "<Name>Rep" - Nova, Shiv, Scar, Ava, Connor, Tristan, Amelia,
# Rosetta, Aurora, Aaron, Garret - plus the Cellia Fight Club's reputation.
# The game never shows those numbers and never says when one moves, so a
# blind player had no way to know where they stood (a player request).
#
# KEYS (on the map, and while someone is talking)
#   R         the reputation of the character who is speaking. When nobody is
#             speaking, or the speaker has no reputation of their own, it
#             reads the whole list instead.
#   Shift+R   always the whole list, highest first.
#
# WHEN A NUMBER CHANGES
#   It is spoken the moment it happens - "Connor reputation up 1, now 6" -
#   and the game's own drop-down window shows the same words, the one the
#   game uses for map names and quest updates, so a sighted player watching
#   sees it too. A change during a cutscene waits for the dialogue to finish
#   instead of fighting it for the screen.
#
# The characters are read from the game's own variable names
# ($cache.RXsystem), so nothing here needs a list of its own: a Rep variable
# added by a later version of Desolation is picked up automatically.
# =============================================================================

module A11yRelationships
  # "NovaRep", "AARON REP", "Cellia FC Rep" - the word Rep at the end.
  SUFFIX = /[\s_]*rep\s*\z/i
  TOAST_LIMIT = 3            # never queue more than this many pop-ups at once

  class << self
    attr_accessor :pending

    def say(text, interrupt: true)
      return unless defined?(AccessibilitySpeech)
      return if text.nil? || text.to_s.empty?
      AccessibilitySpeech.speak(text.to_s, true, interrupt: interrupt)
    rescue Exception
      nil
    end

    # { variable index => character name }, read once from the game's data.
    def table
      return @table if @table
      @table = {}
      begin
        vars = $cache.RXsystem.variables
        vars.each_with_index do |name, i|
          next unless name.is_a?(String) && name =~ SUFFIX
          who = tidy(name.sub(SUFFIX, ""))
          @table[i] = who unless who.empty?
        end
      rescue Exception
        @table = {}
      end
      @table
    end

    # "AARON" -> "Aaron", "Cellia FC" -> "Cellia Fight Club".
    def tidy(raw)
      s = raw.to_s.strip
      s = s.split(/\s+/).map { |w| w.upcase == w ? w.capitalize : w }.join(" ")
      s.sub(/\bFC\b/i, "Fight Club")
    rescue Exception
      raw.to_s
    end

    def relationship?(index)
      table.key?(index)
    end

    def name_for(index)
      table[index]
    end

    def value(index)
      $game_variables[index].to_i
    rescue Exception
      0
    end

    # Everyone whose number has moved off zero, best standing first. A
    # character you have not met yet has nothing to report.
    def known
      table.map { |i, who| [who, value(i)] }.reject { |_, v| v == 0 }
           .sort_by { |who, v| [-v, who] }
    rescue Exception
      []
    end

    def speak_all
      list = known
      if list.empty?
        say("No reputations yet.")
        return
      end
      say("Reputations: " + list.map { |who, v| "#{who} #{v}" }.join(", ") + ".")
    end

    # Who is talking: the name the speech mod worked out from the portrait.
    def speaker
      return nil unless defined?(AccessibilitySpeech)
      n = AccessibilitySpeech.instance_variable_get(:@last_speaker)
      (n.nil? || n.to_s.empty?) ? nil : n.to_s
    rescue Exception
      nil
    end

    def speak_for(who)
      entry = table.find { |_, n| n.casecmp(who.to_s) == 0 }
      return false unless entry
      say("#{entry[1]} reputation: #{value(entry[0])}.")
      true
    rescue Exception
      false
    end

    # R: the speaker if they have a reputation, otherwise everyone.
    def speak_current
      who = speaker
      return if who && speak_for(who)
      speak_all
    end

    def note_change(index, old_value, new_value)
      who = name_for(index)
      return unless who
      diff = new_value.to_i - old_value.to_i
      return if diff == 0
      text = "#{who} reputation #{diff > 0 ? "up" : "down"} #{diff.abs}, now #{new_value.to_i}."
      say(text)
      self.pending ||= []
      pending.push(text) if pending.length < TOAST_LIMIT
    rescue Exception
      nil
    end

    # The game's own drop-down window - the one map names and quest updates
    # use. It disposes itself the moment a message appears, so it is only
    # shown when the screen is free.
    def flush_toasts
      return if pending.nil? || pending.empty?
      return if $game_temp && $game_temp.message_window_showing
      return unless defined?(LocationWindow)
      return unless $scene && $scene.respond_to?(:spriteset) && $scene.spriteset
      $scene.spriteset.addUserSprite(LocationWindow.new(pending.shift))
    rescue Exception
      self.pending = []
    end
  end
end

# ── R and Shift+R, wherever the game is reading input ──────────────────────
module Input
  class << self
    unless method_defined?(:a11y_rel_update) || private_method_defined?(:a11y_rel_update)
      alias a11y_rel_update update

      def update
        a11y_rel_update
        begin
          # Never steal the key while a name is being typed.
          return if Input.text_input == true
        rescue Exception
        end
        begin
          if Input.triggerex?(0x52)                        # R
            if Input.pressex?(0x10)                        # Shift+R
              A11yRelationships.speak_all
            else
              A11yRelationships.speak_current
            end
          end
        rescue Exception
        end
      end
    end
  end
end

# ── Catch the change itself ────────────────────────────────────────────────
# Map events set these with the ordinary Control Variables command, so the
# one place that sees every change is the variable store.
if defined?(Game_Variables) && Game_Variables.method_defined?(:[]=)
  class Game_Variables
    unless method_defined?(:a11y_rel_set)
      alias_method :a11y_rel_set, :[]=
      def []=(variable_id, value)
        index = variable_id
        index = (Variables[variable_id] rescue nil) if variable_id.is_a?(Symbol)
        old = nil
        begin
          old = self[index] if index && A11yRelationships.relationship?(index)
        rescue Exception
        end
        r = a11y_rel_set(variable_id, value)
        begin
          A11yRelationships.note_change(index, old, value) unless old.nil?
        rescue Exception
        end
        r
      end
    end
  end
end

# ── Show the waiting pop-ups once the screen is free ───────────────────────
if defined?(Scene_Map) && Scene_Map.method_defined?(:update)
  class Scene_Map
    unless method_defined?(:a11y_rel_map_update)
      alias_method :a11y_rel_map_update, :update
      def update
        a11y_rel_map_update
        A11yRelationships.flush_toasts
      end
    end
  end
end
