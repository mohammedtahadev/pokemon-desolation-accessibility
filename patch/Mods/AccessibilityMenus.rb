# =============================================================================
# Pokemon Desolation Accessibility Pack - by Mohammed Taha (mohammedtahadev).
# AccessibilityMenus.rb - makes every menu outside battle speak.
#
# Speech engine lives in AccessibilitySpeech.rb. This file only decides WHAT
# to say and WHEN.
#
# WHY THE OLD MOD MISSED ALMOST EVERYTHING
# ----------------------------------------
# It hooked Window_CommandPokemon, which is one leaf of a family tree:
#
#   SpriteWindow_Selectable          <- every cursor move passes through here
#     Window_DrawableCommand
#       Window_CommandPokemon        <- the old hook (plain command lists only)
#       Window_AdvancedCommandPokemon
#       Window_PokemonBag, Window_PokemonOption, Window_PokemonMart,
#       Window_Pokedex, Window_ComplexCommandPokemon, Window_CharacterEntry,
#       Window_FieldEffectNotes, ...
#
# So the pause menu spoke, and the bag, options, shop and Pokedex did not.
# Hooking the ROOT (SpriteWindow_Selectable#update, where @index is actually
# mutated by the D-pad) lights up all of them at once, and a per-class
# describe() adds the detail that matters - item quantities, option values,
# shop prices.
#
# Screens that draw their own cursor instead of using a window class - the
# party screen, the PC boxes, the summary pages, the region map - are not
# reachable that way and get their own hooks further down.
# =============================================================================

module A11yMenus
  class << self
    # ── Small helpers ────────────────────────────────────────────────────────

    # Marked-up command text (Window_AdvancedCommandPokemon) has colour tags.
    def plain(text)
      s = text.to_s
      s = toUnformattedText(s) if defined?(toUnformattedText)
      s
    rescue Exception
      text.to_s
    end

    def item_name(item)
      return nil if item.nil?
      return $cache.items[item].name if defined?($cache) && $cache && $cache.items[item]
      item.to_s
    rescue Exception
      item.to_s
    end

    def item_desc(item)
      return nil if item.nil?
      $cache.items[item].desc if defined?($cache) && $cache && $cache.items[item]
    rescue Exception
      nil
    end

    # "Pikachu, level 25, 40 of 60 HP, poisoned" - the line a sighted player
    # reads off a party panel at a glance.
    def describe_pokemon(pkmn, include_status: true)
      return nil if pkmn.nil?
      return "Egg" if (pkmn.isEgg? rescue false)
      parts = []
      parts << (pkmn.name rescue nil)
      lv = (pkmn.level rescue nil)
      parts << "level #{lv}" if lv
      hp = (pkmn.hp rescue nil)
      tot = (pkmn.totalhp rescue nil)
      if hp && tot
        parts << (hp <= 0 ? "fainted" : "#{hp} of #{tot} HP")
      end
      if include_status && hp && hp > 0
        st = status_name(pkmn)
        parts << st if st
      end
      held = (pkmn.item rescue nil)
      if held && held != 0
        n = item_name(held)
        parts << "holding #{n}" if n
      end
      parts.compact.join(", ")
    rescue Exception
      nil
    end

    def status_name(pkmn)
      st = (pkmn.status rescue 0)
      return nil if st.nil? || st == 0
      case st
      when 1 then "poisoned"
      when 2 then "burned"
      when 3 then "frozen"
      when 4 then "paralyzed"
      when 5 then "asleep"
      else nil
      end
    rescue Exception
      nil
    end

    # ── The universal describer ──────────────────────────────────────────────
    # Given any selectable window, return the line to speak for its current
    # row. Falls back through progressively more generic accessors so a window
    # class this mod has never heard of still says something useful.
    def describe_window(win)
      return nil if win.nil?
      idx = (win.index rescue nil)
      return nil if idx.nil? || idx < 0
      cls = win.class.name.to_s

      # --- Bag: item, quantity, and what it does -------------------------
      if cls == "Window_PokemonBag"
        bag = win.instance_variable_get(:@bag)
        pocket = (win.pocket rescue nil)
        if bag && pocket
          list = (bag.pockets[pocket] rescue nil)
          if list && idx >= list.length
            return "Close bag"
          end
          it = (win.item rescue nil)
          return "Close bag" if it.nil?
          name = item_name(it)
          qty = (bag.contents[it] rescue nil)
          important = (pbIsImportantItem?(it) rescue false)
          line = name.to_s
          line += " times #{qty}" if qty && !important
          # The little "registered" badge is drawn as a sprite; say it, or the
          # player has no way to know which key item is on the hotkey.
          registered = (bag.pbIsRegistered?(it) rescue false)
          line += ", registered" if registered
          return line
        end
      end

      # --- PC item storage ------------------------------------------------
      if cls == "Window_PokemonItemStorage"
        it = (win.item rescue nil)
        return "Close" if it.nil?
        return item_name(it).to_s
      end

      # --- Options: name AND current value --------------------------------
      if cls == "Window_PokemonOption"
        opts = (win.options rescue nil) || win.instance_variable_get(:@options)
        if opts
          # itemCount is options.length + 1: the extra final row has no entry
          # in the options array and was therefore announced as nothing.
          # The game DRAWS it as "Cancel", but pressing C there simply closes
          # the screen and every change has already been applied live - so to
          # the player it is the confirm button, and that is what it is called
          # here.
          return "Confirm" if idx >= opts.length
          if opts[idx]
            opt = opts[idx]
            name = (opt.name rescue nil)
            val = option_value_text(win, opt, idx)
            return [name, val].compact.join(", ")
          end
        end
      end

      # --- Shop: item and price -------------------------------------------
      if cls == "Window_PokemonMart"
        it = (win.item rescue nil)
        return "Cancel" if it.nil?
        adapter = win.instance_variable_get(:@adapter)
        name = (adapter ? (adapter.getDisplayName(it) rescue nil) : nil) || item_name(it)
        price = nil
        begin
          price = adapter.getDisplayPrice(it, false) if adapter
        rescue Exception
        end
        line = name.to_s
        line += ", #{price}" if price && !price.to_s.strip.empty?
        return line
      end

      # --- Pokedex list ----------------------------------------------------
      if cls == "Window_Pokedex"
        sp = (win.species rescue nil)
        if sp
          begin
            entry = $Trainer.pokedex.dexList[sp] if defined?($Trainer) && $Trainer
            if entry
              name = entry[:name] || sp.to_s
              return "#{name}, not yet seen" if !entry[:seen?]
              return "#{name}, seen" if !entry[:owned?]
              return "#{name}, caught"
            end
          rescue Exception
          end
          return sp.to_s
        end
      end

      # --- Windows that expose a commands array ---------------------------
      if win.respond_to?(:commands)
        cmds = (win.commands rescue nil)
        if cmds.is_a?(Array) && idx < cmds.length
          c = cmds[idx]
          # Window_Pokedex-style rows are arrays; take the label.
          c = c[1] || c[0] if c.is_a?(Array)
          return plain(c)
        end
      end

      # --- Last resorts ----------------------------------------------------
      if win.respond_to?(:item)
        it = (win.item rescue nil)
        return item_name(it).to_s if it
      end
      if win.respond_to?(:character)
        ch = (win.character rescue nil)
        return ch.to_s if ch && !ch.to_s.empty?
      end
      nil
    rescue Exception
      nil
    end

    # The displayed value of an option row (EnumOption shows a word,
    # NumberOption shows a number).
    def option_value_text(win, opt, idx)
      raw = (win[idx] rescue nil)
      return nil if raw.nil?
      begin
        if opt.respond_to?(:values) && opt.values
          vals = opt.values
          return plain(vals[raw]) if vals.is_a?(Array) && raw.is_a?(Integer) && vals[raw]
        end
      rescue Exception
      end
      begin
        if opt.respond_to?(:optstart)
          return (opt.optstart + raw).to_s
        end
      rescue Exception
      end
      raw.to_s
    rescue Exception
      nil
    end
  end
end

# =============================================================================
# 1. THE UNIVERSAL HOOK
# SpriteWindow_Selectable#update is where every D-pad move mutates @index.
# =============================================================================
class SpriteWindow_Selectable
  # Re-entry guard: a second load (F12 soft reset) would otherwise
  # chain the alias onto itself and recurse forever.
  unless method_defined?(:a11y_update)
    alias a11y_update update
    def update
      old = @index
      a11y_update
      a11y_announce_row if @index != old
    end

    alias a11y_index_set index=
    def index=(value)
      old = @index
      a11y_index_set(value)
      # Also announce when the value did NOT change but nothing has been said
      # for this window yet: a screen that opens with the cursor already on
      # row 0 (the bag, the options list) would otherwise be silent until the
      # player moved, which reads as "the menu is broken".
      a11y_announce_row if @index != old || !@a11y_announced
    end

    def a11y_announce_row
      # Battle hides its command/fight windows and drives them manually; those
      # get purpose-built announcements in the battle mod instead.
      return if @a11y_silent
      line = A11yMenus.describe_window(self)
      return if line.nil?
      # The FIRST line from a window must not interrupt. A yes/no or story
      # choice appears immediately after its question is spoken, and cutting
      # the question off to say "Yes" means the player never hears what they
      # are answering. Queue the first one; interrupt every move after it, so
      # scrolling a long list stays responsive.
      first = !@a11y_announced
      @a11y_announced = true
      AccessibilitySpeech.speak(line, false, interrupt: !first)
    rescue Exception
      nil
    end

    # Lets other hooks suppress the generic line when they say something richer.
    attr_accessor :a11y_silent
  end
end

# A command window is usually filled AFTER it is built, so assigning the list
# is the moment the menu becomes real - announce the row the cursor is on.
[:Window_CommandPokemon, :Window_AdvancedCommandPokemon].each do |sym|
  next unless Object.const_defined?(sym)
  klass = Object.const_get(sym)
  next unless klass.method_defined?(:commands=)
  next if klass.method_defined?(:a11y_commands_set)
  klass.class_eval do
    alias a11y_commands_set commands=
    def commands=(value)
      a11y_commands_set(value)
      a11y_announce_row
    rescue Exception
      nil
    end
  end
end

# =============================================================================
# 2. OPTIONS - value changes
# Window_PokemonOption#update calls super (row movement, covered above) and
# then handles LEFT/RIGHT to change the VALUE, which the generic hook cannot
# see because @index does not move.
# =============================================================================
class Window_PokemonOption
  # Re-entry guard: a second load (F12 soft reset) would otherwise
  # chain the alias onto itself and recurse forever.
  unless method_defined?(:a11y_opt_update)
    # How long after a value change the option's name is considered "already
    # said", so holding right on a volume slider reads 51, 52, 53 rather than
    # "BGM Volume 51, BGM Volume 52" - while a fresh adjustment still tells
    # you WHAT you are changing.
    A11Y_NAME_REPEAT_AFTER = 1.2

    alias a11y_opt_update update
    def update
      before = (self[self.index] rescue nil)
      a11y_opt_update
      begin
        after = (self[self.index] rescue nil)
        opts = (self.options rescue nil) || instance_variable_get(:@options)

        # The options screen never assigns index=, so the row the cursor
        # starts on was announced by nothing at all. Say it once, when the
        # window first becomes the active one.
        if !@a11y_opt_seen && (self.active rescue true)
          @a11y_opt_seen = true
          line = A11yMenus.describe_window(self)
          AccessibilitySpeech.speak(line, false, interrupt: false) if line
        end

        if after != before
          opt = opts ? opts[self.index] : nil
          val = opt ? A11yMenus.option_value_text(self, opt, self.index) : after.to_s
          name = opt ? (opt.name rescue nil) : nil
          now = Time.now.to_f
          same_row = (@a11y_val_row == self.index)
          spinning = same_row && @a11y_val_at &&
                     (now - @a11y_val_at) < A11Y_NAME_REPEAT_AFTER
          @a11y_val_row = self.index
          @a11y_val_at = now
          if val
            # Sliders and multi-value options are unusable if every press
            # says only a bare number: name the setting on the first change.
            a11y(spinning || name.nil? ? val : "#{name}, #{val}")
          end
        end
      rescue Exception
      end
    end
  end
end

# =============================================================================
# 3. PARTY SCREEN
# Fully custom: the cursor is the integer @activecmd and each slot is a
# PokeSelectionSprite. Slot 6 is Cancel, slot 7 is Confirm in multi-select.
# =============================================================================
class PokemonScreen_Scene
  # Re-entry guard: a second load (F12 soft reset) would otherwise
  # chain the alias onto itself and recurse forever.
  unless method_defined?(:a11y_party_update)
    alias a11y_party_update update
    def update
      a11y_party_update
      begin
        cur = instance_variable_get(:@activecmd)
        return if cur.nil?
        return if cur == @a11y_last_party_sel
        @a11y_last_party_sel = cur
        a11y(a11y_party_line(cur))
      rescue Exception
      end
    end

    def a11y_party_line(sel)
      party = instance_variable_get(:@party)
      count = party ? party.length : 0
      return "Confirm" if sel == 7
      return "Cancel"  if sel == 6 || (party && sel >= count && sel != 7)
      spr = @sprites && @sprites["pokemon#{sel}"]
      pkmn = spr ? (spr.pokemon rescue nil) : nil
      pkmn ||= party ? party[sel] : nil
      line = A11yMenus.describe_pokemon(pkmn)
      line || "Slot #{sel + 1}, empty"
    rescue Exception
      nil
    end
  end
end

# =============================================================================
# 4. POKEMON SUMMARY
# Page tabs (@page), party cycling (@partyindex) and the move cursor each
# need announcing; none of them move a window index.
# =============================================================================
class PokemonSummaryScene
  # Re-entry guard: a second load (F12 soft reset) would otherwise
  # chain the alias onto itself and recurse forever.
  unless method_defined?(:a11y_sum_update)
    PAGE_NAMES = ["Info", "Trainer memo", "Skills", "EVs and IVs", "Moves"]

    alias a11y_sum_update pbUpdate
    def pbUpdate
      a11y_sum_update
      begin
        page = instance_variable_get(:@page)
        pidx = instance_variable_get(:@partyindex)
        abil = instance_variable_get(:@abilpage)
        key = [page, pidx, abil]
        return if key == @a11y_last_sum_key
        first = @a11y_last_sum_key.nil?
        changed_mon = @a11y_last_sum_key && @a11y_last_sum_key[1] != pidx
        @a11y_last_sum_key = key

        pkmn = instance_variable_get(:@pokemon)
        parts = []
        parts << A11yMenus.describe_pokemon(pkmn) if first || changed_mon
        if abil
          parts << "Ability page"
        else
          parts << (PAGE_NAMES[page] || "Page #{page + 1}")
        end
        a11y_parts(*parts)
      rescue Exception
      end
    end
  end
end

# The move cursor on the Moves page is its own sprite with its own index.
class MoveSelectionSprite
  # Re-entry guard: a second load (F12 soft reset) would otherwise
  # chain the alias onto itself and recurse forever.
  unless method_defined?(:a11y_move_index_set)
    alias a11y_move_index_set index=
    def index=(value)
      old = (@index rescue nil)
      a11y_move_index_set(value)
      begin
        # The bare "Move slot N" line is superseded: AccessibilitySummary hooks
        # drawSelectedMove and reads the actual move in full - name, type,
        # power, accuracy, PP and description - on the same cursor movement.
        # Announcing the slot number too would only talk over it.
        nil if value != old
      rescue Exception
      end
    end
  end
end

# =============================================================================
# 5. PC / STORAGE BOXES
# The box grid is 6 columns by 5 rows over the integer @selection, with
# negative sentinels for the header buttons. pbSetArrow / pbPartySetArrow are
# called on every cursor move, which makes them the reliable hook.
# =============================================================================
class PokemonStorageScene
  # Re-entry guard: a second load (F12 soft reset) would otherwise
  # chain the alias onto itself and recurse forever.
  unless method_defined?(:a11y_set_arrow)
    alias a11y_set_arrow pbSetArrow
    def pbSetArrow(arrow, selection)
      a11y_set_arrow(arrow, selection)
      begin
        return if selection == @a11y_last_box_sel
        @a11y_last_box_sel = selection
        a11y(a11y_box_line(selection))
      rescue Exception
      end
    end

    def a11y_box_line(selection)
      storage = instance_variable_get(:@storage)
      case selection
      when -1
        box = storage ? storage.currentBox : nil
        name = (box && storage[box]) ? (storage[box].name rescue nil) : nil
        return name ? "Box #{name}" : "Box name"
      when -2 then return "Party"
      when -3 then return "Close box"
      when -4 then return "Previous box"
      when -5 then return "Next box"
      end
      return nil if selection.nil? || selection < 0
      col = (selection % 6) + 1
      row = (selection / 6) + 1
      pkmn = nil
      begin
        pkmn = storage[storage.currentBox, selection] if storage
      rescue Exception
      end
      desc = A11yMenus.describe_pokemon(pkmn, include_status: false)
      desc ? "#{desc}, row #{row} column #{col}" : "Empty, row #{row} column #{col}"
    rescue Exception
      nil
    end

    alias a11y_party_set_arrow pbPartySetArrow
    def pbPartySetArrow(arrow, selection)
      a11y_party_set_arrow(arrow, selection)
      begin
        return if selection == @a11y_last_boxparty_sel
        @a11y_last_boxparty_sel = selection
        if selection == 6
          a11y("Close box")
        else
          # The party is not an ivar of the scene; it hangs off the storage
          # object, with the trainer's party as a last resort.
          storage = instance_variable_get(:@storage)
          party = (storage ? storage.party : nil) rescue nil
          party ||= ($Trainer.party rescue nil)
          pkmn = party ? party[selection] : nil
          desc = A11yMenus.describe_pokemon(pkmn, include_status: false)
          a11y(desc || "Party slot #{selection + 1}, empty")
        end
      rescue Exception
      end
    end

    # Announce the box itself when it changes, so the player knows where they are.
    alias a11y_update_overlay pbUpdateOverlay
    def pbUpdateOverlay(selection, party = nil)
      a11y_update_overlay(selection, party)
      begin
        storage = instance_variable_get(:@storage)
        return if storage.nil?
        box = storage.currentBox
        return if box == @a11y_last_box_number
        @a11y_last_box_number = box
        name = (storage[box].name rescue nil)
        count = (storage[box].nitems rescue nil)
        line = name ? "Box #{name}" : "Box #{box + 1}"
        line += ", #{count} Pokemon" if count
        a11y(line)
      rescue Exception
      end
    end
  end
end

# =============================================================================
# 6. REGION MAP
# MapBottomSprite#maplocation= is assigned every frame by the scene and already
# no-ops when the value is unchanged, so it is the natural place to speak.
# =============================================================================
class MapBottomSprite
  # Re-entry guard: a second load (F12 soft reset) would otherwise
  # chain the alias onto itself and recurse forever.
  unless method_defined?(:a11y_maplocation_set)
    alias a11y_maplocation_set maplocation=
    def maplocation=(value)
      old = (@maplocation rescue nil)
      a11y_maplocation_set(value)
      begin
        a11y(value.to_s) if value && value != old && !value.to_s.strip.empty?
      rescue Exception
      end
    end
  end
end

# =============================================================================
# 7. TEXT ENTRY
# Speak each character as it is typed and confirm deletions, so a name can be
# entered without sight.
# =============================================================================
class Window_TextEntry
  # Re-entry guard: a second load (F12 soft reset) would otherwise
  # chain the alias onto itself and recurse forever.
  unless method_defined?(:a11y_insert)
    alias a11y_insert insert
    def insert(ch)
      a11y_insert(ch)
      begin
        a11y(ch.to_s == " " ? "space" : ch.to_s)
      rescue Exception
      end
    end

    alias a11y_delete delete
    def delete
      before = (self.text rescue "")
      a11y_delete
      begin
        after = (self.text rescue "")
        if after.length < before.length
          removed = before[after.length, 1]
          a11y(removed.to_s.strip.empty? ? "deleted space" : "deleted #{removed}")
        end
      rescue Exception
      end
    end
  end
end

# =============================================================================
# 8. TRAINER CARD
# Nothing on it is selectable, so read the whole card when it opens.
# =============================================================================
class PokemonTrainerCardScene
  # Re-entry guard: a second load (F12 soft reset) would otherwise
  # chain the alias onto itself and recurse forever.
  unless method_defined?(:a11y_card_draw)
    alias a11y_card_draw pbDrawTrainerCardFront
    def pbDrawTrainerCardFront(*args)
      a11y_card_draw(*args)
      begin
        lines = ["Trainer card"]
        t = (defined?($Trainer) ? $Trainer : nil)
        if t
          lines << "Name #{t.name}" rescue nil
          lines << "Money #{t.money}" rescue nil
          badges = (t.badges.is_a?(Array) ? t.badges.count { |b| b } : nil) rescue nil
          lines << "#{badges} badges" if badges
          seen = (t.pokedex.getSeenCount rescue nil)
          owned = (t.pokedex.getOwnedCount rescue nil)
          lines << "Pokedex #{owned} caught, #{seen} seen" if seen && owned
        end
        a11y_parts(*lines)
      rescue Exception
      end
    end
  end
end

# =============================================================================
# 9. POKEDEX ENTRY
# The entry body is drawn, never selected - announce it when it is shown.
# =============================================================================
class PokemonPokedexScene
  # Re-entry guard: a second load (F12 soft reset) would otherwise
  # chain the alias onto itself and recurse forever.
  unless method_defined?(:a11y_dex_entry)
    alias a11y_dex_entry pbChangeToDexEntry
    def pbChangeToDexEntry(species)
      a11y_dex_entry(species)
      begin
        parts = []
        sp = ($cache.pkmn[species] rescue nil)
        if sp
          parts << (getMonName(species) rescue (sp.name rescue species.to_s))
          parts << "the #{sp.kind} Pokemon" if (sp.kind rescue nil)
          parts << (sp.dexentry rescue nil)
        else
          parts << species.to_s
        end
        a11y_parts(*parts)
      rescue Exception
      end
    end
  end
end

# ---------------------------------------------------------------------------
# THE SAVE FILE LIST on the title screen ("Choose Save File"). The files are
# drawn as panels with their names painted onto a bitmap, and the highlight is
# moved by a hand-rolled input loop - so switching between save files was
# silent (a player report). The scene's two drawing methods carry everything
# needed: the list when it opens, and the new file each time you move.
#
# Each entry is [number, name, ..., saved time, filename], where the name is
# already the readable "Save Slot 3 - Ash, 4 badges" the game paints.
# ---------------------------------------------------------------------------
module A11ySaveFiles
  class << self
    def say(text, interrupt: true)
      return unless defined?(AccessibilitySpeech)
      AccessibilitySpeech.speak(text.to_s, true, interrupt: interrupt)
    rescue Exception
      nil
    end

    def entry_line(files, index)
      return nil unless files && files[index]
      f = files[index]
      name = f[1].to_s.strip
      name = "Save file #{index + 1}" if name.empty?
      line = "#{name}, #{index + 1} of #{files.length}"
      saved = f[4]
      line += ". Saved #{saved}" if saved && !saved.to_s.strip.empty?
      line + "."
    rescue Exception
      nil
    end
  end
end

if defined?(PokemonLoadScene)
  class PokemonLoadScene
    if method_defined?(:pbDrawSaveCommands) && !method_defined?(:a11y_draw_save_commands)
      alias_method :a11y_draw_save_commands, :pbDrawSaveCommands
      def pbDrawSaveCommands(savefiles)
        r = a11y_draw_save_commands(savefiles)
        begin
          n = savefiles ? savefiles.length : 0
          A11ySaveFiles.say("Other save files: #{n}. Up and down choose one, C loads it, B goes back.")
          first = A11ySaveFiles.entry_line(savefiles, 0)
          A11ySaveFiles.say(first, interrupt: false) if first
        rescue Exception
        end
        r
      end
    end

    if method_defined?(:pbMoveSaveSel) && !method_defined?(:a11y_move_save_sel)
      alias_method :a11y_move_save_sel, :pbMoveSaveSel
      def pbMoveSaveSel(index)
        r = a11y_move_save_sel(index)
        begin
          line = A11ySaveFiles.entry_line(@savefiles, index)
          A11ySaveFiles.say(line) if line
        rescue Exception
        end
        r
      end
    end
  end
end

# ---------------------------------------------------------------------------
# The digit-by-digit NUMBER BOX (Window_InputNumberPokemon). Every number the
# game asks for this way - the Jinx-Scent's encounter rate, an event's "Input
# Number", pbMessageChooseNumber - draws its digits into a bitmap: LEFT and
# RIGHT pick a digit, UP and DOWN change it, and nothing was spoken (a player
# report: "the Jinx-Scent does not speak the numbers"). The box is hooked
# itself, so every screen that uses it speaks:
#   when it opens   the whole number, then how to use it, and which digit is
#                   selected
#   up / down       the whole new number
#   left / right    which digit is now selected, and its value: "Tens, 5"
# ---------------------------------------------------------------------------
module A11yNumberBox
  PLACES = ["Ones", "Tens", "Hundreds", "Thousands", "Ten thousands",
            "Hundred thousands", "Millions", "Ten millions", "Hundred millions"]

  class << self
    # Set by a screen that knows what the number MEANS; read once on open.
    attr_accessor :label

    def say(text, interrupt: true)
      return unless defined?(AccessibilitySpeech)
      AccessibilitySpeech.speak(text.to_s, true, interrupt: interrupt)
    rescue Exception
      nil
    end

    # "Hundreds, 1" for the digit the cursor is on (index counts from the
    # left, and includes the +/- sign position when the box has one).
    def selected(win)
      digits_max = win.instance_variable_get(:@digits_max).to_i
      sign = win.instance_variable_get(:@sign)
      idx = win.instance_variable_get(:@index).to_i
      if sign && idx == 0
        return win.instance_variable_get(:@negative) ? "Sign, minus" : "Sign, plus"
      end
      pos = idx - (sign ? 1 : 0)                       # 0 = leftmost digit
      from_right = digits_max - 1 - pos
      digit = sprintf("%0*d", digits_max, win.instance_variable_get(:@number).to_i.abs)[pos, 1]
      "#{PLACES[from_right] || "Digit #{pos + 1}"}, #{digit}"
    rescue Exception
      nil
    end
  end
end

if defined?(Window_InputNumberPokemon) && Window_InputNumberPokemon.method_defined?(:update)
  class Window_InputNumberPokemon
    unless method_defined?(:a11y_numbox_update)
      alias_method :a11y_numbox_update, :update
      def update
        before = [@number, @negative, @index]
        a11y_numbox_update
        begin
          return unless self.active
          if !@a11y_announced
            @a11y_announced = true
            label = A11yNumberBox.label
            A11yNumberBox.label = nil
            parts = []
            parts << label if label && !label.to_s.empty?
            parts << "Number: #{self.number}."
            parts << "Up and down change the selected digit, left and right move between digits. C confirms, B cancels."
            sel = A11yNumberBox.selected(self)
            parts << "Selected: #{sel}." if sel
            # Queued: the question that opened the box is usually still being read.
            A11yNumberBox.say(parts.join(" "), interrupt: false)
          elsif before[0] != @number || before[1] != @negative
            A11yNumberBox.say(self.number.to_s)
          elsif before[2] != @index
            sel = A11yNumberBox.selected(self)
            A11yNumberBox.say(sel) if sel
          end
        rescue Exception
        end
      end
    end
  end
end

# The Jinx-Scent (Pokegear): says what the number means, and what was set.
if defined?(Scene_EncounterRate) && Scene_EncounterRate.method_defined?(:main)
  class Scene_EncounterRate
    unless method_defined?(:a11y_jinx_main)
      alias_method :a11y_jinx_main, :main
      def main
        A11yNumberBox.label = "Jinx Scent: wild encounter rate, in percent. 100 is normal, " \
                              "higher means more wild Pokemon, 0 turns wild encounters off."
        a11y_jinx_main
        begin
          rate = ($game_variables[:EncounterRateModifier].to_f * 100).round
          A11yNumberBox.say(rate == 0 ? "Wild encounters off." : "Encounter rate set to #{rate} percent.")
        rescue Exception
        end
      ensure
        A11yNumberBox.label = nil
      end
    end
  end
end

# Mods load in alphabetical order, so THIS file is loaded BEFORE
# AccessibilitySpeech.rb defines the module. Every hook above only reaches for
# it from inside a method body (by which time both files are loaded), and this
# is the one line that runs at load time - so it has to be guarded.
AccessibilitySpeech.log("Menu hooks loaded.") if defined?(AccessibilitySpeech)
