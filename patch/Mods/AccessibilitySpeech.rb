# =============================================================================
# AccessibilitySpeech.rb - screen-reader speech core for Pokemon Desolation.
#
# This file is the ENGINE only: NVDA binding, text cleaning, and the speak /
# repeat plumbing. The hooks that decide WHAT to say live in the sibling mods:
#
#   AccessibilityMenus.rb   - every menu, list and screen outside battle
#   (battle hooks land in AccessibilityBattle.rb)
#
# Mods are loaded by ClientData.rb#startup with
#   Dir["./Data/Mods/*.rb"].each { |file| load File.expand_path(file) }
# which runs AFTER every game script, so aliases here always win. Dir returns
# names in alphabetical order, so AccessibilityMenus.rb loads BEFORE this
# file - which is fine, because it only calls into AccessibilitySpeech at
# runtime, never at load time.
#
# Requires nvdaControllerClient.dll in the game root folder.
# =============================================================================

module AccessibilitySpeech
  @enabled = true
  @last_text = nil
  @last_spoken_at = 0.0
  @nvda_tried = false
  @nvda_loaded = false
  @nvda_speak = nil
  @nvda_test = nil
  @nvda_cancel = nil
  @log_path = begin
    File.expand_path('AccessibilitySpeech.log', Dir.pwd)
  rescue Exception
    File.expand_path('../../AccessibilitySpeech.log', __FILE__)
  end

  # How long an identical line is suppressed. Without a window, holding a
  # direction on a two-item menu would fall silent; without any suppression,
  # a screen that redraws every frame would stutter the same line forever.
  REPEAT_WINDOW = 0.35

  class << self
    attr_accessor :enabled

    # Strips RPG Maker / Essentials control codes so the reader speaks words
    # rather than markup.
    #
    # Bracketed codes are matched GENERICALLY - \<letters>[...] - rather than
    # from a list of known ones. An allow-list looked tidy but silently failed
    # the moment the game used a code it did not name: \ff[08c] (the speaker's
    # face portrait) was read out loud as "backslash f f 0 8 c" in the middle
    # of dialogue. Anything of that shape is markup, never words.
    def sanitize(text)
      s = text.to_s.dup
      return "" if s.empty?

      # Escaped backslash first, so it cannot be mistaken for a code.
      s.gsub!(/\\\\/, " ")

      # Substitutions worth keeping: these carry real words.
      begin
        if defined?($Trainer) && $Trainer
          s.gsub!(/\\[Pp][Nn]Upper/, $Trainer.name.to_s.upcase)
          s.gsub!(/\\[Pp][Nn]Lower/, $Trainer.name.to_s.downcase)
          s.gsub!(/\\[Pp][Nn]/, $Trainer.name.to_s)
          s.gsub!(/\\[Pp][Mm]/, $Trainer.money.to_s)
        end
      rescue Exception
      end
      begin
        s.gsub!(/\\[Vv]\[(\d+)\]/) { ($game_variables ? $game_variables[$1.to_i].to_s : "") }
      rescue Exception
      end
      begin
        s.gsub!(/\\[Nn]\[(\d+)\]/) {
          actor = ($game_actors ? $game_actors[$1.to_i] : nil)
          actor ? actor.name.to_s : " "
        }
      rescue Exception
      end

      # A newline marker is a break between words, not a word. The bracketed
      # form \n[id] was already substituted above, so anything left is a line
      # break. This must run BEFORE the generic letter-code strip below, or
      # "\nworld" would be swallowed whole rather than becoming " world".
      s.gsub!(/\\[Nn]/, " ")

      # Every remaining bracketed code, whatever its name: ff, wt, wtnp, ts,
      # op, cl, ch, se, me, sign, c, ...
      s.gsub!(/\\[A-Za-z]+\[[^\]]*\]/, "")
      # The bare colour form \[XXXXXXXX].
      s.gsub!(/\\\[[0-9A-Fa-f]+\]/, "")
      # Leftover single-letter and punctuation codes: \b \r \pg \pog \1 \.
      s.gsub!(/\\[A-Za-z]+/, "")
      s.gsub!(/\\[^A-Za-z\s]/, "")

      s.gsub!(/<[^>]+>/, "")                  # <br>, <c2=...> and friends
      s.gsub!(/\{\d+\}/, "")                  # {1} format slots
      s.gsub!(/[\r\n\x01-\x08]/, " ")         # newlines and control sentinels
      s.gsub!(/\s+/, " ")
      s.strip!
      s
    end

    def load_nvda
      return if @nvda_tried
      @nvda_tried = true
      begin
        candidates = [
          File.expand_path('nvdaControllerClient.dll', Dir.pwd),
          File.expand_path('../nvdaControllerClient.dll', Dir.pwd),
          File.expand_path('../../../nvdaControllerClient.dll', __FILE__),
          File.expand_path('../../nvdaControllerClient.dll', __FILE__)
        ].uniq
        dll_path = candidates.find { |p| File.exist?(p) }
        log("NVDA DLL candidates: #{candidates.join(' | ')}")
        log("Using NVDA DLL: #{dll_path}") if dll_path
        return if !dll_path
        @nvda_test   = Win32API.new(dll_path, 'nvdaController_testIfRunning', '', 'b')
        @nvda_speak  = Win32API.new(dll_path, 'nvdaController_speakText', 'p', 'v')
        @nvda_cancel = Win32API.new(dll_path, 'nvdaController_cancelSpeech', '', 'v')
        # Reborn behavior: false means NVDA is running and available.
        test_result = @nvda_test.call
        @nvda_loaded = !test_result
        log("nvdaController_testIfRunning result=#{test_result.inspect}, loaded=#{@nvda_loaded}")
      rescue Exception
        @nvda_loaded = false
        log("Failed to initialize NVDA API: #{$!.class}: #{$!.message}")
      end
    end

    def nvda_running?
      load_nvda
      @nvda_loaded
    end

    def now
      Time.now.to_f
    rescue Exception
      0.0
    end

    # speak(text) - the one entry point.
    #   force:     say it even if it repeats the previous line
    #   interrupt: cut off whatever is being spoken (right for cursor moves,
    #              wrong for a queued sequence of related lines)
    def speak(text, force = false, interrupt: true)
      return if !force && !@enabled
      clean = sanitize(text)
      return if clean.empty?
      if !force && clean == @last_text && (now - @last_spoken_at) < REPEAT_WINDOW
        return
      end
      return if !nvda_running?
      @last_text = clean
      @last_spoken_at = now
      begin
        @nvda_cancel.call if interrupt && @nvda_cancel
        @nvda_speak.call(clean.encode('utf-16le'))
        log("Spoke: #{clean}")
      rescue Exception
        log("Speak failed: #{$!.class}: #{$!.message}")
      end
    end

    # Joins parts into one utterance, dropping blanks. Keeps call sites tidy:
    #   say_parts("Potion", "times 5", "Restores 20 HP")
    def say_parts(*parts)
      line = parts.flatten.reject { |p| p.nil? || p.to_s.strip.empty? }.join(". ")
      speak(line)
    end

    def repeat_last
      return if @last_text.nil? || @last_text.empty?
      speak(@last_text, true)
    end

    def toggle
      @enabled = !@enabled
      # Always announce the toggle itself, even when turning speech off.
      speak(@enabled ? "Speech on" : "Speech off", true)
      @enabled
    end

    def log(message)
      begin
        File.open(@log_path, 'ab') { |f| f.write("[#{Time.now}] #{message}\r\n") }
      rescue Exception
      end
    end
  end
end

module AccessibilitySpeech
  # Which character each dialogue portrait belongs to.
  #
  # Desolation marks the speaker with a face graphic - \ff[08c] - which is
  # a picture, and so tells a blind player nothing. Many lines name the
  # speaker in the text ("SCARLETT: ..."), but continuation lines do not,
  # and neither do plenty of single-line exchanges: you hear the words with
  # no idea who said them.
  #
  # This table was not written by hand. It was recovered by scanning every
  # map's dialogue for lines carrying BOTH a portrait code and a spoken name
  # prefix, then taking the name each portrait agreed on - 75 portraits, 25
  # characters, nearly all at 100% agreement over hundreds of lines.
  FACE_NAMES = {
    "01"      => "Aderyn", "01b"     => "Aderyn", "02"      => "Shiv",
    "02a"     => "Shiv", "02b"     => "Shiv", "04a"     => "Connor",
    "04b"     => "Connor", "04c"     => "Connor", "06"      => "Hardy",
    "06a"     => "Hardy", "07a"     => "Rosetta", "07b"     => "Rosetta",
    "08a"     => "Scarlett", "08a1"    => "Scarlett", "08b"     => "Scarlett",
    "08b1"    => "Scarlett", "08c"     => "Scarlett", "08c1"    => "Scarlett",
    "08d"     => "Scarlett", "08d1"    => "Scarlett", "08e"     => "Scarlett",
    "08g"     => "Scarlett", "09a"     => "Ava", "09b"     => "Ava",
    "09c"     => "Ava", "09d"     => "Ava", "10a"     => "Baron",
    "10b"     => "Baron", "10c"     => "Baron", "11"      => "Nova",
    "11b"     => "Nova", "11c"     => "Nova", "11d"     => "Nova",
    "11f"     => "Nova", "13"      => "Emily", "13a"     => "Emily",
    "13b"     => "Emily", "14"      => "Tristan", "14a"     => "Tristan",
    "14b"     => "Tristan", "14c"     => "Tristan", "15"      => "Amelia",
    "16"      => "Sena", "16b"     => "Sena", "17a"     => "Aurora",
    "17b"     => "Aurora", "17c"     => "Aurora", "18"      => "Garret",
    "18a"     => "Garret", "18b"     => "Garret", "18c"     => "Garret",
    "18d"     => "Garret", "19a"     => "Mana", "20"      => "Lilith",
    "20a"     => "Lilith", "21"      => "Darkrai", "22"      => "Aaron",
    "22a"     => "Aaron", "23"      => "Cedric", "23b"     => "Cedric",
    "24"      => "Hardy", "24a"     => "Hardy", "25"      => "Reeve",
    "25a"     => "Reeve", "25b"     => "Reeve", "26"      => "Waldenhall",
    "26a"     => "Waldenhall", "26b"     => "Waldenhall", "26c"     => "Waldenhall",
    "27"      => "Ryder", "27a"     => "Ryder", "27b"     => "Ryder",
    "28"      => "Artem", "29"      => "Eden", "29a"     => "Eden"
  }


  class << self
    # Speaks a line of dialogue, naming the speaker when it changes.
    #
    # Only on a CHANGE: a character with six lines in a row would
    # otherwise have their name read six times, which is worse than not
    # having it at all. And when the writers already put the name in the
    # text ("SCARLETT: ..."), nothing is added - hearing
    # "Scarlett. Scarlett: hello" would be its own kind of silly.
    def speak_dialogue(text)
      body = sanitize(text)
      # Options -> Speaker Names.
      names_on = defined?(A11ySettings) ? A11ySettings.on?(:speaker_names) : true
      name = names_on ? speaker_for(text) : nil
      if name.nil?
        # Narration, or a portrait we could not identify: the next named
        # speaker should be announced again.
        @last_speaker = nil
      elsif name != @last_speaker
        @last_speaker = name
        already = body.downcase.start_with?(name.downcase)
        body = "#{name}. #{body}" unless already || body.empty?
      end
      speak(body)
    end

    def reset_speaker
      @last_speaker = nil
    end

    # The character speaking this line, or nil when the portrait is
    # unknown or the line carries no portrait at all.
    def speaker_for(text)
      s = text.to_s
      marker = 92.chr + 'ff['        # the literal f[ prefix
      i = s.index(marker)
      return nil unless i
      j = s.index(']', i + marker.length)
      return nil unless j
      id = s[(i + marker.length)...j].to_s.split(',').first.to_s.strip
      FACE_NAMES[id]
    rescue Exception
      nil
    end
  end
end

# Convenience shorthand used by the hook files.
def a11y(text, force = false)
  AccessibilitySpeech.speak(text, force)
rescue Exception
  nil
end

def a11y_parts(*parts)
  AccessibilitySpeech.say_parts(*parts)
rescue Exception
  nil
end

# ── Dialogue and message text ────────────────────────────────────────────────
# Every message outside battle funnels through Kernel.pbMessageDisplay.
# (Battle writes straight to its own message window and is handled separately.)
module Kernel
  class << self
    alias accessibilityspeech_pbMessageDisplay pbMessageDisplay

    def pbMessageDisplay(*args, &block)
      AccessibilitySpeech.speak_dialogue(args[1]) if args.length >= 2
      accessibilityspeech_pbMessageDisplay(*args, &block)
    end
  end
end

# ── Global hotkeys ───────────────────────────────────────────────────────────
# Input.update is aliased by the game itself (System.rb) for its screenshot and
# turbo keys, so hooking it here is the established pattern and fires
# everywhere - menus, overworld and battle alike.
#
# Keys were chosen against a full audit of what the game already binds:
#   F1  repeat the last thing spoken
#   F2  toggle speech on and off
# F5-F12, M, ALT and CTRL are all taken by the game; F1/F2/F4 are free.
module Input
  class << self
    unless method_defined?(:a11y_original_update) || private_method_defined?(:a11y_original_update)
      alias a11y_original_update update

      def update
        a11y_original_update
        begin
          # Never steal keys while the player is typing a name.
          return if Input.text_input == true
        rescue Exception
        end
        begin
          if Input.triggerex?(:F1)
            AccessibilitySpeech.repeat_last
          elsif Input.triggerex?(:F2)
            AccessibilitySpeech.toggle
          end
        rescue Exception
        end
      end
    end
  end
end

AccessibilitySpeech.speak('Accessibility speech enabled', true)
AccessibilitySpeech.log("Speech core loaded. cwd=#{Dir.pwd} ruby=#{defined?(RUBY_VERSION) ? RUBY_VERSION : 'unknown'}")
