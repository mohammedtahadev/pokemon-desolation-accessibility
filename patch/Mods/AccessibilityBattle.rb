# =============================================================================
# AccessibilityBattle.rb - makes fights playable by ear.
#
# Modelled directly on Reborn 19.5's native Blindstep battle support
# (Battle_Scene.rb tts calls, Battle_Inspect.rb, and the community
# SpokenDamageAccessibility patch), reproduced here as a mod because Desolation
# ships the same engine with every one of those speech lines missing.
#
# WHAT SPEAKS
# -----------
#   Battle messages        "X used Tackle!", "It's super effective!" - queued in
#                          order, exactly the text on screen
#   The command menu       "What will X do?" then Fight / Bag / Pokemon / Run
#                          as you move
#   The fight menu         each move as you land on it: name, type, PP
#   Targeting              the battler you are aiming at, in doubles
#   Mega / Ultra / Z       activation and deactivation on the X key
#   Damage                 "X took 24 damage. 51 HP left." after every hit
#   Yes/No and choices     through the ordinary menu reading
#
# KEYS IN BATTLE (on the command or fight menu)
#   K          status readout: every active Pokemon - HP, status, stat changes,
#              your own ability and item, the enemy's revealed moves
#   Shift+K    field readout: weather, field effect, screens and hazards
#
# These are the same K = "tell me about the selected thing" muscle memory as
# the pathfinder outside battle, where those keys are dead during a fight.
#
# HOW IT HOOKS
# ------------
# Reborn edits its Battle_Scene loops directly; a mod cannot, so this hooks the
# join points those loops already call every frame:
#
#   CommandMenuDisplay#setTexts / #index=   the command menu's state changes
#   FightMenuDisplay#battler= / #setIndex   the fight menu's state changes
#   PokeBattle_Scene#pbUpdateSelected       targeting cursor movement
#   PokeBattle_Scene#pbFrameUpdate          every menu frame - carries the K keys
#   PokeBattle_Scene#pbDisplayMessage etc.  the message pipeline
#   PokeBattle_Battler#pbReduceHP           damage, from the damage itself
#
# Both menu displays embed a Window_CommandPokemon that AccessibilityMenus
# would read generically ("Fight", bare move names). Those windows are marked
# a11y_silent - the opt-out the menus mod provides for exactly this - so the
# richer battle announcements are the only voice.
#
# Options -> Battle Speech turns all of it off; Options -> Spoken Damage turns
# off just the damage lines (they are the chattiest part).
# =============================================================================

module A11yBattle
  STAT_NAMES = {}
  STATUS_NAMES = {
    :SLEEP => "asleep", :FROZEN => "frozen", :BURN => "burned",
    :PARALYSIS => "paralyzed", :POISON => "poisoned"
  }

  class << self
    attr_accessor :last_target

    def on?
      return false unless defined?(AccessibilitySpeech) && AccessibilitySpeech.enabled
      return true unless defined?(A11ySettings)
      A11ySettings.on?(:battle_speech)
    rescue Exception
      true
    end

    def damage_on?
      return false unless on?
      return true unless defined?(A11ySettings)
      A11ySettings.on?(:spoken_damage)
    rescue Exception
      true
    end

    # force = true bypasses the speech mod's repeat-suppression, because "But
    # it failed!" twice in a row is two real events. Enabled-ness was already
    # checked in on?, so force cannot talk over a switched-off reader.
    def say(text, interrupt: true)
      return unless on?
      t = text.to_s.strip
      return if t.empty?
      AccessibilitySpeech.speak(t, true, interrupt: interrupt)
    rescue Exception
      nil
    end

    def queue(text)
      say(text, interrupt: false)
    end

    def stat_names
      return STAT_NAMES unless STAT_NAMES.empty?
      begin
        STAT_NAMES[PBStats::ATTACK]   = "Attack"
        STAT_NAMES[PBStats::DEFENSE]  = "Defense"
        STAT_NAMES[PBStats::SPATK]    = "Special Attack"
        STAT_NAMES[PBStats::SPDEF]    = "Special Defense"
        STAT_NAMES[PBStats::SPEED]    = "Speed"
        STAT_NAMES[PBStats::ACCURACY] = "Accuracy"
        STAT_NAMES[PBStats::EVASION]  = "Evasion"
      rescue Exception
      end
      STAT_NAMES
    end

    # Z on the fight menu: the whole move card, spoken - what Reborn's
    # pbDrawMoveDetails reads out. Category, power, accuracy, then the
    # description as its own utterance so it can be repeated with F1.
    def move_details(battler, move_index)
      return unless battler
      move = (battler.moves[move_index] rescue nil)
      return unless move
      md = ($cache.moves[move.move] rescue nil)
      return unless md
      row = "#{md.name}, #{md.category.to_s.capitalize}"
      row += ", #{md.basedamage} power" if md.category != :status && md.basedamage.to_i > 1
      row += ", #{md.accuracy.to_i == 0 ? "perfect" : md.accuracy} accuracy"
      begin
        row += ", #{move.pp} of #{move.totalpp} PP"
      rescue Exception
      end
      say(row)
      d = (md.desc rescue nil)
      queue(d.to_s) if d && !d.to_s.empty?
    rescue Exception
      nil
    end

    # "Tackle, Normal type, 35 of 35 PP" - what Reborn's ttsMove says, minus
    # the Reborn-only field-boost phrasing.
    def move_phrase(battler, move_index)
      move = battler.moves[move_index]
      return nil unless move
      name = (move.name rescue nil) || (getMoveName(move.move) rescue "move")
      t = begin
        move.pbType(battler)
      rescue Exception
        (move.type rescue nil)
      end
      # Desolation types are Symbols, and on Ruby 3 Symbol#name EXISTS - so a
      # bare respond_to?(:name) check reads :FIRE as "FIRE", shouting the type.
      tname = if t.is_a?(Symbol)
                t.to_s.capitalize
              elsif t.respond_to?(:name)
                t.name
              else
                t.to_s.capitalize
              end
      pp = (move.pp rescue nil)
      tot = (move.totalpp rescue nil)
      phrase = name.to_s
      phrase += ", #{tname} type" unless tname.to_s.empty?
      phrase += ", #{pp} of #{tot} PP" if pp && tot
      phrase
    rescue Exception
      nil
    end

    # One battler's line for the K readout.
    def battler_line(battle, b, own)
      return nil if b.nil? || (b.isFainted? rescue true)
      parts = []
      parts << "#{b.name}, level #{b.level}"
      if own
        parts << "#{b.hp} of #{b.totalhp} HP"
      else
        pct = ((b.hp.to_f / b.totalhp.to_f) * 100).round
        parts << "#{pct} percent HP"
      end
      st = STATUS_NAMES[(b.status rescue nil)]
      parts << st if st
      begin
        stg = b.stages
        stat_names.each do |id, label|
          v = stg[id].to_i
          next if v == 0
          parts << "#{label} #{v > 0 ? "plus" : "minus"} #{v.abs}"
        end
      rescue Exception
      end
      if own
        begin
          ab = b.ability
          parts << "ability #{getAbilityName(ab)}" if ab
        rescue Exception
        end
        begin
          it = b.item
          parts << "holding #{getItemName(it)}" if it
        rescue Exception
        end
      else
        begin
          known = battle.ai.getAIMemory(b, true)
          if known && !known.empty?
            parts << "revealed moves: " + known.map { |m| m.name rescue "?" }.join(", ")
          end
        rescue Exception
        end
      end
      parts.join(", ")
    rescue Exception
      nil
    end

    # Q and W: one SIDE in full - Reborn's L/R inspect, spoken. Types, HP,
    # status, every stat change, and the moves: yours with exact PP, the
    # enemy's only as revealed.
    def side_report(scene, own_side)
      battle = scene.instance_variable_get(:@battle)
      return unless battle
      lines = []
      battle.battlers.each_with_index do |b, i|
        next if b.nil? || (b.isFainted? rescue true)
        # SIDE, not ownership. A partner trainer's Pokemon (Connor's, in the
        # Keneph caves doubles) is NOT pbOwnedByPlayer?, but it fights on
        # YOUR side: sides in this engine are index parity - even indexes
        # yours, odd the enemy's. Grouping by ownership put allies in the W
        # report, which is exactly the bug a player caught.
        own = (i % 2 == 0)
        next if own != own_side
        line = battler_line(battle, b, own)
        next unless line
        types = begin
          t1 = b.type1; t2 = b.type2
          tw = t1 ? t1.to_s.capitalize : nil
          tw = "#{tw} and #{t2.to_s.capitalize}" if t2 && t2 != t1
          tw ? "#{tw} type" : nil
        rescue Exception
          nil
        end
        line = "#{line}, #{types}" if types
        if own
          begin
            Array(b.moves).each do |m|
              next unless m
              mline = "#{m.name rescue "move"}"
              begin
                mline += ", #{m.pp} of #{m.totalpp} PP"
              rescue Exception
              end
              line += ". #{mline}"
            end
          rescue Exception
          end
        end
        lines << line
      end
      if lines.empty?
        say(own_side ? "No Pokemon on your side." : "No enemy to report.")
      else
        say(lines.shift)
        lines.each { |l| queue(l) }
      end
    rescue Exception
      nil
    end

    # K: everything alive on the field, yours first.
    def status_report(scene)
      battle = scene.instance_variable_get(:@battle)
      return unless battle
      lines = []
      battle.battlers.each_with_index do |b, i|
        next if b.nil? || (b.isFainted? rescue true)
        own = (i % 2 == 0)                # side by index parity, as above
        line = battler_line(battle, b, own)
        next unless line
        label = if !own
                  "Enemy"
                elsif (battle.pbOwnedByPlayer?(i) rescue true)
                  "Your"
                else
                  "Ally"                  # a partner trainer's Pokemon
                end
        lines << "#{label} #{line}"
      end
      if lines.empty?
        say("No battlers to report.")
      else
        say(lines.shift)
        lines.each { |l| queue(l) }
      end
    rescue Exception
      nil
    end

    # Shift+K: the conditions everyone is fighting under.
    def field_report(scene)
      battle = scene.instance_variable_get(:@battle)
      return unless battle
      parts = []
      begin
        w = battle.pbWeather
        parts << "Weather: #{w.to_s.capitalize}" if w && w != 0
      rescue Exception
      end
      begin
        f = battle.field
        if f && f.respond_to?(:effect) && f.effect
          fname = begin
            PokeBattle_Field.getFieldName(f.effect)
          rescue Exception
            f.effect.to_s.capitalize
          end
          parts << "Field: #{fname}"
          parts << "#{f.duration} turns left" if (f.duration rescue 0).to_i > 0
        end
      rescue Exception
      end
      # Side conditions, both sides, only the ones actually up.
      side_effects = {
        :Reflect => "Reflect", :LightScreen => "Light Screen",
        :AuroraVeil => "Aurora Veil", :Safeguard => "Safeguard",
        :Tailwind => "Tailwind", :Mist => "Mist", :LuckyChant => "Lucky Chant",
        :Spikes => "Spikes", :ToxicSpikes => "Toxic Spikes",
        :StealthRock => "Stealth Rock", :StickyWeb => "Sticky Web"
      }
      [["Your side", 0], ["Enemy side", 1]].each do |label, si|
        begin
          side = battle.sides[si]
          active = []
          side_effects.each do |key, name|
            v = (side.effects[key] rescue nil)
            next if v.nil? || v == false || v == 0 || v == -1
            active << (v.is_a?(Integer) && v > 1 ? "#{name} #{v}" : name)
          end
          parts << "#{label}: #{active.join(", ")}" unless active.empty?
        rescue Exception
        end
      end
      begin
        tr = battle.trickroom
        parts << "Trick Room, #{tr} turns" if tr && tr != 0
      rescue Exception
      end
      if parts.empty?
        say("No weather, field, or side effects.")
      else
        say(parts.shift)
        parts.each { |p| queue(p) }
      end
    rescue Exception
      nil
    end
  end
end

# -----------------------------------------------------------------------------
# The message pipeline. Speech FIRST, then the original, so the reader starts
# while the letter-by-letter animation plays - the same order Reborn uses.
# -----------------------------------------------------------------------------
if defined?(PokeBattle_Scene)
  class PokeBattle_Scene
    unless method_defined?(:a11y_battle_display_message)
      alias_method :a11y_battle_display_message, :pbDisplayMessage
      def pbDisplayMessage(msg, brief = false)
        A11yBattle.queue(msg)
        a11y_battle_display_message(msg, brief)
      end

      alias_method :a11y_battle_display_paused, :pbDisplayPausedMessage
      def pbDisplayPausedMessage(msg)
        A11yBattle.queue(msg)
        a11y_battle_display_paused(msg)
      end

      # The choice window this opens is a plain Window_CommandPokemon, which
      # AccessibilityMenus reads on its own - only the question needs saying.
      alias_method :a11y_battle_show_commands, :pbShowCommands
      def pbShowCommands(msg, commands, defaultValue)
        A11yBattle.queue(msg)
        a11y_battle_show_commands(msg, commands, defaultValue)
      end

      # Target selection calls this every frame with the current target, and
      # with -1 when the selector closes.
      alias_method :a11y_battle_update_selected, :pbUpdateSelected
      def pbUpdateSelected(index)
        if index != A11yBattle.last_target
          A11yBattle.last_target = index
          if index && index >= 0
            begin
              b = @battle.battlers[index]
              A11yBattle.say(b.name) if b && !b.isFainted?
            rescue Exception
            end
          end
        end
        a11y_battle_update_selected(index)
      end

      # Runs once per frame in the command menu, the fight menu AND choice
      # windows - the one place a mod can add battle-wide keys.
      alias_method :a11y_battle_frame_update, :pbFrameUpdate
      def pbFrameUpdate(cw = nil, update_cw = true)
        begin
          if A11yBattle.on?
            if Input.pressex?(0x10) && Input.triggerex?(0x4B)      # Shift+K
              A11yBattle.field_report(self)
            elsif Input.triggerex?(0x4B)                           # K
              A11yBattle.status_report(self)
            elsif defined?(Input::L) && Input.trigger?(Input::L)   # Q key
              A11yBattle.side_report(self, true)
            elsif defined?(Input::R) && Input.trigger?(Input::R)   # W key
              A11yBattle.side_report(self, false)
            elsif defined?(FightMenuDisplay) && cw.is_a?(FightMenuDisplay) &&
                  Input.triggerex?(0x5A)                           # Z, on a move
              A11yBattle.move_details(cw.battler, cw.index)
            end
          end
        rescue Exception
        end
        a11y_battle_frame_update(cw, update_cw)
      end
    end
  end
end

# -----------------------------------------------------------------------------
# The command menu: "What will X do?" and the four commands.
# -----------------------------------------------------------------------------
if defined?(CommandMenuDisplay)
  class CommandMenuDisplay
    unless method_defined?(:a11y_battle_set_texts)
      alias_method :a11y_battle_set_texts, :setTexts
      def setTexts(value)
        result = a11y_battle_set_texts(value)
        begin
          @a11y_texts = value
          w = instance_variable_get(:@window)
          w.a11y_silent = true if w.respond_to?(:a11y_silent=)
          A11yBattle.queue(value[0])                       # "What will X do?"
          A11yBattle.queue(value[self.index + 1])          # the selected command
        rescue Exception
        end
        result
      end

      alias_method :a11y_battle_index_set, :index=
      def index=(v)
        old = self.index
        result = a11y_battle_index_set(v)
        begin
          if @a11y_texts && self.index != old && @a11y_texts[self.index + 1]
            A11yBattle.say(@a11y_texts[self.index + 1])
          end
        rescue Exception
        end
        result
      end
    end
  end
end

# -----------------------------------------------------------------------------
# The fight menu: every move as the cursor lands on it.
# -----------------------------------------------------------------------------
if defined?(FightMenuDisplay)
  class FightMenuDisplay
    unless method_defined?(:a11y_battle_set_index)
      alias_method :a11y_battle_set_index, :setIndex
      def setIndex(value)
        old = @index
        moved = a11y_battle_set_index(value)
        begin
          w = instance_variable_get(:@window)
          w.a11y_silent = true if w.respond_to?(:a11y_silent=)
          if moved && @battler && (value != old || !@a11y_menu_entered)
            @a11y_menu_entered = true
            phrase = A11yBattle.move_phrase(@battler, value)
            A11yBattle.say(phrase) if phrase
          end
        rescue Exception
        end
        moved
      end

      alias_method :a11y_battle_battler_set, :battler=
      def battler=(value)
        @a11y_menu_entered = false                # re-announce on re-entry
        a11y_battle_battler_set(value)
      end
    end
  end
end

# -----------------------------------------------------------------------------
# Mega Evolution, Ultra Burst and Z-Moves - the X key gives no other feedback.
# -----------------------------------------------------------------------------
if defined?(PokeBattle_Battle)
  class PokeBattle_Battle
    { :pbRegisterMegaEvolution => "Mega Evolution activated",
      :pbRegisterUltraBurst    => "Ultra Burst activated",
      :pbRegisterZMove         => "Z-Move activated" }.each do |meth, line|
      aliased = "a11y_battle_#{meth}".to_sym
      next unless method_defined?(meth)
      next if method_defined?(aliased)
      alias_method aliased, meth
      define_method(meth) do |*args|
        result = send(aliased, *args)
        A11yBattle.say(line)
        result
      end
    end
  end
end

# -----------------------------------------------------------------------------
# Spoken damage, from the community SpokenDamageAccessibility patch: announce
# from the HP change itself, so every source of damage is covered - moves,
# recoil, weather, hazards, status.
# -----------------------------------------------------------------------------
if defined?(PokeBattle_Battler)
  class PokeBattle_Battler
    if method_defined?(:pbReduceHP) && !method_defined?(:a11y_battle_reduce_hp)
      alias_method :a11y_battle_reduce_hp, :pbReduceHP
      def pbReduceHP(amt, anim = false, emercheck = true)
        oldhp = self.hp
        dealt = a11y_battle_reduce_hp(amt, anim, emercheck)
        begin
          actual = oldhp - self.hp
          if actual > 0 && A11yBattle.damage_on?
            who = (pbThis rescue name)
            if self.hp <= 0
              A11yBattle.queue("#{who} took #{actual} damage and fainted.")
            else
              A11yBattle.queue("#{who} took #{actual} damage. #{self.hp} HP left.")
            end
          end
        rescue Exception
        end
        dealt
      end
    end
  end
end
