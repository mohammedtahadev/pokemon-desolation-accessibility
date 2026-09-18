# =============================================================================
# AccessibilitySummary.rb - the accessible summary, like Reborn's
# pra-accessible-summary: everything about a Pokemon as spoken lists you arrow
# through, instead of a picture.
#
# HOW TO USE IT
#   Highlight a Pokemon and open its action menu (press C) - the LAST entry is
#   "Accessible Summary". It is there on the party screen, in the PC boxes,
#   and on the in-battle switch menu, exactly where Reborn's mod puts it. It
#   opens a menu: Everything, Stats EVs and IVs, Base stats and abilities,
#   Moves, Biology, Export team. Pick one, arrow through the rows, every row
#   is read out. B goes back.
#
#   K on the party screen or in the PC opens the same menu directly.
#
# WHY THIS SCREEN SPEAKS FOR ITSELF
# ---------------------------------
# The first version of this mod leaned on the generic menu reader to speak
# the rows of a stock command window, and on hooks inside the game's own
# graphics summary. In practice that left the player in silence. This version
# trusts nothing: every list here is drawn by this mod and every row is read
# through AccessibilitySpeech directly - on open, on every arrow press, and
# again with its position when C is pressed on it.
#
# WHY A MENU ENTRY, NOT A COPIED METHOD
# -------------------------------------
# Reborn's mod copies the whole 200-line pbPokemonScreen method to inject its
# entry, which breaks every time the game updates the original. Here the
# scene's pbShowCommands is wrapped instead: any action menu that contains
# both "Summary" and "Cancel" gets "Accessible Summary" appended AFTER Cancel,
# so every index the game checks stays exactly where it was. Choosing the new
# entry is handled inside the wrapper; the game itself sees only a cancel.
# =============================================================================

module A11ySummary
  STATUS_WORDS = {}

  class << self
    def status_word(status)
      return nil if status.nil? || status == 0
      if STATUS_WORDS.empty?
        begin
          STATUS_WORDS[PBStatuses::SLEEP]     = "asleep"
          STATUS_WORDS[PBStatuses::POISON]    = "poisoned"
          STATUS_WORDS[PBStatuses::BURN]      = "burned"
          STATUS_WORDS[PBStatuses::PARALYSIS] = "paralyzed"
          STATUS_WORDS[PBStatuses::FROZEN]    = "frozen"
        rescue Exception
        end
      end
      STATUS_WORDS[status]
    end

    def type_word(t)
      return nil if t.nil?
      t.to_s.capitalize
    end

    # DESOLATION'S ORDER, verified against Pokemon.rb calcStats: index 3 is
    # Special Attack and 5 is Speed - NOT the standard Essentials order, which
    # puts Speed at 3. Reading these with the standard order would quietly
    # swap three stats.
    STAT_LABELS = ["HP", "Attack", "Defense", "Special Attack",
                   "Special Defense", "Speed"]

    def stat_spread(arr)
      a = Array(arr)
      STAT_LABELS.each_with_index.map { |n, i| "#{n} #{a[i].to_i}" }.join(", ")
    rescue Exception
      ""
    end

    # Every known move as rows: the full line (name, type, category, power,
    # accuracy, PP) followed by the move's description as its own row.
    def move_lines(pkmn)
      lines = []
      Array(pkmn.moves).each do |m|
        next if m.nil? || (m.move rescue nil).nil?
        md = ($cache.moves[m.move] rescue nil)
        next unless md
        row = "#{md.name}, #{type_word(md.type)} type, #{md.category.to_s.capitalize}"
        row += ", #{md.basedamage} power" if md.category != :status && md.basedamage.to_i > 1
        row += ", #{md.accuracy.to_i == 0 ? "perfect" : md.accuracy} accuracy"
        begin
          row += ", #{m.pp} of #{m.totalpp} PP"
        rescue Exception
        end
        lines << row + "."
        d = (md.desc rescue nil)
        lines << d.to_s if d && !d.to_s.empty?
      end
      lines
    rescue Exception
      []
    end

    # One fact per row. Every row is guarded on its own, so a field this game
    # version does not have simply is not read, rather than killing the list.
    def lines_for(pkmn)
      lines = []
      if (pkmn.isEgg? rescue false)
        lines << "Egg."
        steps = (pkmn.eggsteps rescue nil)
        lines << "About #{steps} steps until it hatches." if steps && steps.to_i > 0
        return lines
      end

      data = ($cache.pkmn[pkmn.species] rescue nil)

      begin
        species = data ? data.name.to_s : pkmn.species.to_s.capitalize
        nick = pkmn.name.to_s
        lines << (nick == species ? species : "#{nick}, a #{species}")
      rescue Exception
      end
      begin
        lines << "Dex number #{data.dexnum}." if data && data.dexnum
      rescue Exception
      end
      begin
        lines << "The #{data.kind} Pokemon." if data && data.kind && !data.kind.to_s.empty?
      rescue Exception
      end
      begin
        if data
          t1 = type_word(data.Type1)
          t2 = type_word(data.Type2)
          lines << (t2 && t2 != t1 ? "#{t1} and #{t2} type." : "#{t1} type.") if t1
        end
      rescue Exception
      end
      begin
        lines << "Level #{pkmn.level}."
      rescue Exception
      end
      begin
        g = pkmn.gender
        lines << ["Male.", "Female.", "Genderless."][g] if g && g <= 2
      rescue Exception
      end
      begin
        lines << "Shiny." if pkmn.isShiny?
      rescue Exception
      end
      begin
        n = PBNatures.getName(pkmn.nature)
        lines << "#{n} nature." if n
      rescue Exception
      end
      begin
        sw = status_word(pkmn.status)
        lines << "Currently #{sw}." if sw
      rescue Exception
      end
      begin
        lines << "HP #{pkmn.hp} of #{pkmn.totalhp}."
      rescue Exception
      end
      begin
        lines << "Attack #{pkmn.attack}, Defense #{pkmn.defense}."
        lines << "Special Attack #{pkmn.spatk}, Special Defense #{pkmn.spdef}."
        lines << "Speed #{pkmn.speed}."
      rescue Exception
      end
      begin
        lines << "Happiness #{pkmn.happiness} of 255."
      rescue Exception
      end
      begin
        lines << "EVs: #{A11ySummary.stat_spread(pkmn.ev)}."
        lines << "IVs: #{A11ySummary.stat_spread(pkmn.iv)}."
      rescue Exception
      end
      begin
        ab = pkmn.ability
        if ab
          lines << "Ability: #{getAbilityName(ab)}."
          d = (getAbilityDesc(ab) rescue nil)
          lines << d.to_s if d && !d.to_s.empty?
        end
      rescue Exception
      end
      begin
        it = pkmn.item
        if it
          lines << "Holding #{$cache.items[it].name}."
          d = ($cache.items[it].desc rescue nil)
          lines << d.to_s if d && !d.to_s.empty?
        else
          lines << "No held item."
        end
      rescue Exception
      end
      begin
        move_lines(pkmn).each { |l| lines << l }
      rescue Exception
      end
      begin
        d = data && (data.dexentry rescue nil)
        lines << d.to_s if d && !d.to_s.empty?
      rescue Exception
      end
      begin
        lines << "Original trainer: #{pkmn.ot}." if pkmn.ot && !pkmn.ot.to_s.empty?
        lines << "Met at level #{pkmn.obtainLevel}." if (pkmn.obtainLevel rescue nil).to_i > 0
      rescue Exception
      end
      begin
        if defined?(A11yBiology)
          species_name = data ? data.name.to_s : pkmn.species.to_s
          bio = A11yBiology.text_for(species_name)
          if bio
            lines << "Biology:"
            lines << bio
          end
        end
      rescue Exception
      end
      lines << "That is everything."
      lines
    rescue Exception
      ["Could not read this Pokemon."]
    end
  end
end

# ---------------------------------------------------------------------------
# The biology text: long prose descriptions of every species, from the Reborn
# accessibility project's pokemon_biology.json, shipped pre-converted as
# patch/biology.dat (a Marshal file) because Desolation's no-stdlib Ruby cannot
# be trusted to have the json library. tools/build_biology.rb regenerates it.
# ---------------------------------------------------------------------------
module A11yBiology
  PATHS = ["patch/biology.dat", "biology.dat"]

  class << self
    def data
      return @data unless @data.nil?
      @data = false                      # false = tried and failed; nil = untried
      PATHS.each do |p|
        next unless File.exist?(p)
        begin
          @data = Marshal.load(File.binread(p))
          break
        rescue Exception
          @data = false
        end
      end
      @data
    end

    def available?
      !!data
    end

    # The prose for a species (upcased name), preferring its form when named.
    def text_for(species_name, form_name = nil)
      d = data
      return nil unless d
      entry = d[species_name.to_s.upcase]
      # "Alolan Vulpix" -> "VULPIX", the same fallback Reborn's mod uses.
      if entry.nil?
        parts = species_name.to_s.upcase.split(" ")
        entry = d[parts.last] if parts.length > 1
      end
      return nil unless entry
      if form_name && !form_name.to_s.empty?
        want = form_name.to_s.downcase.gsub(" form", "").gsub("forme", "").strip
        entry.each { |k, v| return v if k.include?(want) }
      end
      entry["default"] || entry.values.first
    rescue Exception
      nil
    end
  end
end

# ---------------------------------------------------------------------------
# The K key on the party screen. The scene's update runs every frame of
# pbChoosePokemon, whichever path opened the party - pause menu, battle
# switch, or using an item.
# ---------------------------------------------------------------------------
if defined?(PokemonScreen_Scene)
  class PokemonScreen_Scene
    unless method_defined?(:a11y_summary_update)
      alias_method :a11y_summary_update, :update
      def update
        a11y_summary_update
        begin
          return if @a11y_summary_open
          return unless Input.triggerex?(0x4B)          # K
          party = instance_variable_get(:@party)
          idx = instance_variable_get(:@activecmd)
          return unless party && idx && idx >= 0 && party[idx]
          pkmn = party[idx]
          @a11y_summary_open = true
          begin
            A11ySummary.run_menu(pkmn)
          ensure
            @a11y_summary_open = false
          end
        rescue Exception
        end
      end
    end
  end
end

# ---------------------------------------------------------------------------
# The Pokedex entry page: N reads the biology of the species on screen. The
# menus mod already speaks the name, kind and dex entry when the page opens;
# this adds the long-form description on the same "tell me more" key as
# everywhere else.
# ---------------------------------------------------------------------------
if defined?(PokemonPokedexScene)
  class PokemonPokedexScene
    if method_defined?(:pbChangeToDexEntry) && !method_defined?(:a11y_bio_dex_entry)
      alias_method :a11y_bio_dex_entry, :pbChangeToDexEntry
      def pbChangeToDexEntry(species)
        @a11y_dex_species = species
        a11y_bio_dex_entry(species)
      end
    end

    if method_defined?(:pbUpdate) && !method_defined?(:a11y_bio_dex_update)
      alias_method :a11y_bio_dex_update, :pbUpdate
      def pbUpdate
        a11y_bio_dex_update
        begin
          if @a11y_dex_species && Input.triggerex?(0x4E)      # N
            name = (getMonName(@a11y_dex_species) rescue nil)
            name ||= ($cache.pkmn[@a11y_dex_species].name rescue @a11y_dex_species.to_s)
            bio = defined?(A11yBiology) ? A11yBiology.text_for(name) : nil
            if bio
              AccessibilitySpeech.speak(bio, true, interrupt: true) if defined?(AccessibilitySpeech)
            elsif defined?(AccessibilitySpeech)
              AccessibilitySpeech.speak("No biology entry for #{name}.", true, interrupt: true)
            end
          end
        rescue Exception
        end
      end
    end
  end
end

# ---------------------------------------------------------------------------
# Learning and browsing moves. drawSelectedMove(pokemon, moveToLearn, move) is
# called with the exact move under the cursor - on the summary's move page AND
# in the forget-a-move flow that level-up learning opens, in battle and out of
# it. One hook makes every move-choosing moment read the move in full.
# ---------------------------------------------------------------------------
module A11ySummary
  class << self
    # "Ember, Fire type, Special, 40 power, 100 accuracy, 20 of 25 PP" plus the
    # description as a follow-on utterance.
    def speak_move_details(move_sym, pp: nil, totalpp: nil, prefix: nil)
      md = ($cache.moves[move_sym] rescue nil)
      return unless md
      row = "#{md.name}, #{type_word(md.type)} type, #{md.category.to_s.capitalize}"
      row += ", #{md.basedamage} power" if md.category != :status && md.basedamage.to_i > 1
      row += ", #{md.accuracy.to_i == 0 ? "perfect" : md.accuracy} accuracy"
      row += ", #{pp} of #{totalpp} PP" if pp && totalpp
      row = "#{prefix}#{row}" if prefix
      if defined?(AccessibilitySpeech)
        AccessibilitySpeech.speak(row, true, interrupt: true)
        d = (md.desc rescue nil)
        AccessibilitySpeech.speak(d.to_s, true, interrupt: false) if d && !d.to_s.empty?
      end
    rescue Exception
      nil
    end
  end
end

if defined?(PokemonSummaryScene)
  class PokemonSummaryScene
    if method_defined?(:drawSelectedMove) && !method_defined?(:a11y_draw_selected_move)
      alias_method :a11y_draw_selected_move, :drawSelectedMove
      def drawSelectedMove(pokemon, moveToLearn, move)
        result = a11y_draw_selected_move(pokemon, moveToLearn, move)
        begin
          # Repeating the same move (a redraw, not a cursor move) stays quiet.
          unless @a11y_last_selected_move == move
            @a11y_last_selected_move = move
            learning = moveToLearn && moveToLearn != 0 && move == moveToLearn
            pp = tot = nil
            # A move being LEARNED has no PP yet; only known moves report it.
            unless learning
              begin
                known = Array(pokemon.moves).find { |m| m && m.move == move }
                if known
                  pp = known.pp
                  tot = known.totalpp
                end
              rescue Exception
              end
            end
            A11ySummary.speak_move_details(move, pp: pp, totalpp: tot,
                                           prefix: learning ? "New move: " : nil)
          end
        rescue Exception
        end
        result
      end
    end
  end
end

# ---------------------------------------------------------------------------
# K inside the PC. Reborn's accessible-summary covers the storage boxes too;
# this brings the same K key there. The cursor position arrives through the
# same pbSetArrow / pbPartySetArrow calls the menus mod already reads, so this
# only remembers WHERE the cursor is and resolves the Pokemon under it.
# ---------------------------------------------------------------------------
if defined?(PokemonStorageScene)
  class PokemonStorageScene
    if method_defined?(:pbSetArrow) && !method_defined?(:a11y_sum_set_arrow)
      alias_method :a11y_sum_set_arrow, :pbSetArrow
      def pbSetArrow(arrow, selection)
        @a11y_pc_context = [:box, selection]
        a11y_sum_set_arrow(arrow, selection)
      end
    end

    if method_defined?(:pbPartySetArrow) && !method_defined?(:a11y_sum_party_arrow)
      alias_method :a11y_sum_party_arrow, :pbPartySetArrow
      def pbPartySetArrow(arrow, selection)
        @a11y_pc_context = [:party, selection]
        a11y_sum_party_arrow(arrow, selection)
      end
    end

    if method_defined?(:update) && !method_defined?(:a11y_sum_pc_update)
      alias_method :a11y_sum_pc_update, :update
      def update
        a11y_sum_pc_update
        begin
          return if @a11y_summary_open
          return unless Input.triggerex?(0x4B)          # K
          pkmn = A11ySummary.pc_pokemon(self)
          if pkmn.nil?
            AccessibilitySpeech.speak("Empty slot.", true, interrupt: true) if defined?(AccessibilitySpeech)
            return
          end
          @a11y_summary_open = true
          begin
            A11ySummary.run_menu(pkmn)
          ensure
            @a11y_summary_open = false
          end
        rescue Exception
        end
      end
    end
  end
end

# ---------------------------------------------------------------------------
# THE GAME'S OWN SUMMARY SCREEN, page by page. Every page is drawn as pure
# graphics - drawPageOne through Five plus the ability page - so LEFT/RIGHT
# through the summary was silent except for moves. Each draw method now reads
# its own page: Info, Trainer Memo, Skills, EV and IV, Moves, Ability. Moving
# up or down to another Pokemon re-reads the page for the new one.
# ---------------------------------------------------------------------------
module A11ySummary
  class << self
    def speak_page(scene, page_id, pkmn, lines)
      return if lines.nil? || lines.empty?
      key = [page_id, (pkmn.object_id rescue nil)]
      # Returning from a sub-screen redraws the same page for the same Pokemon;
      # the player just heard it, so stay quiet. A new page or a new Pokemon
      # always speaks.
      last = scene.instance_variable_get(:@a11y_last_page)
      return if last == key
      scene.instance_variable_set(:@a11y_last_page, key)
      return unless defined?(AccessibilitySpeech)
      AccessibilitySpeech.speak(lines.shift.to_s, true, interrupt: true)
      lines.each { |l| AccessibilitySpeech.speak(l.to_s, true, interrupt: false) }
    rescue Exception
      nil
    end

    def page_info(pkmn)
      data = ($cache.pkmn[pkmn.species] rescue nil)
      lines = ["Info page."]
      begin
        species = data ? data.name.to_s : pkmn.species.to_s.capitalize
        nick = pkmn.name.to_s
        lines << (nick == species ? species : "#{nick}, a #{species}")
      rescue Exception
      end
      begin
        lines << "Dex number #{data.dexnum}." if data && data.dexnum
      rescue Exception
      end
      begin
        if data
          t1 = type_word(data.Type1); t2 = type_word(data.Type2)
          lines << (t2 && t2 != t1 ? "#{t1} and #{t2} type." : "#{t1} type.") if t1
        end
      rescue Exception
      end
      begin
        lines << "Level #{pkmn.level}."
        g = pkmn.gender
        lines << ["Male.", "Female.", "Genderless."][g] if g && g <= 2
        lines << "Shiny." if (pkmn.isShiny? rescue false)
      rescue Exception
      end
      begin
        it = pkmn.item
        lines << (it ? "Holding #{$cache.items[it].name}." : "No held item.")
      rescue Exception
      end
      begin
        lines << "Original trainer: #{pkmn.ot}." if pkmn.ot && !pkmn.ot.to_s.empty?
        lines << "Experience #{pkmn.exp}." if (pkmn.exp rescue nil)
      rescue Exception
      end
      lines
    end

    def page_memo(pkmn)
      lines = ["Trainer memo page."]
      begin
        n = PBNatures.getName(pkmn.nature)
        lines << "#{n} nature." if n
      rescue Exception
      end
      begin
        lines << "Met at level #{pkmn.obtainLevel}." if (pkmn.obtainLevel rescue nil).to_i > 0
        lines << "Original trainer: #{pkmn.ot}." if pkmn.ot && !pkmn.ot.to_s.empty?
        lines << "Happiness #{pkmn.happiness} of 255."
      rescue Exception
      end
      lines
    end

    def page_skills(pkmn)
      lines = ["Skills page."]
      begin
        lines << "HP #{pkmn.hp} of #{pkmn.totalhp}."
        lines << "Attack #{pkmn.attack}, Defense #{pkmn.defense}."
        lines << "Special Attack #{pkmn.spatk}, Special Defense #{pkmn.spdef}."
        lines << "Speed #{pkmn.speed}."
      rescue Exception
      end
      begin
        sw = status_word(pkmn.status)
        lines << "Currently #{sw}." if sw
      rescue Exception
      end
      begin
        ab = pkmn.ability
        lines << "Ability: #{getAbilityName(ab)}. Press C for its description." if ab
      rescue Exception
      end
      lines
    end

    def page_evsivs(pkmn)
      lines = ["EV and IV page."]
      begin
        lines << "EVs: #{stat_spread(pkmn.ev)}."
        ev_total = Array(pkmn.ev).map { |v| v.to_i }.sum
        lines << "#{ev_total} EVs used of 510."
        lines << "IVs: #{stat_spread(pkmn.iv)}."
      rescue Exception
      end
      lines
    end

    def page_moves(pkmn)
      lines = ["Moves page. Press C to browse the moves in detail."]
      begin
        Array(pkmn.moves).each do |m|
          next if m.nil? || (m.move rescue nil).nil?
          md = ($cache.moves[m.move] rescue nil)
          next unless md
          row = md.name.to_s
          begin
            row += ", #{m.pp} of #{m.totalpp} PP"
          rescue Exception
          end
          lines << row + "."
        end
      rescue Exception
      end
      lines
    end

    def page_ability(pkmn)
      lines = ["Ability page."]
      begin
        ab = pkmn.ability
        if ab
          lines << "#{getAbilityName(ab)}."
          d = (getAbilityDesc(ab) rescue nil)
          lines << d.to_s if d && !d.to_s.empty?
        end
      rescue Exception
      end
      lines << "Press B to go back."
      lines
    end

    def page_egg(pkmn)
      lines = ["Egg."]
      begin
        steps = pkmn.eggsteps
        lines << "About #{steps} steps until it hatches." if steps.to_i > 0
      rescue Exception
      end
      lines
    end
  end
end

if defined?(PokemonSummaryScene)
  class PokemonSummaryScene
    {
      :drawPageOne    => [:info,   :page_info],
      :drawPageOneEgg => [:egg,    :page_egg],
      :drawPageTwo    => [:memo,   :page_memo],
      :drawPageThree  => [:skills, :page_skills],
      :drawPageFour   => [:evsivs, :page_evsivs],
      :drawPageFive   => [:moves,  :page_moves],
      :drawAbilPage   => [:abil,   :page_ability]
    }.each do |meth, (page_id, builder)|
      aliased = "a11y_page_#{meth}".to_sym
      next unless method_defined?(meth)
      next if method_defined?(aliased)
      alias_method aliased, meth
      define_method(meth) do |pokemon, *args|
        result = send(aliased, pokemon, *args)
        begin
          A11ySummary.speak_page(self, page_id, pokemon, A11ySummary.send(builder, pokemon))
        rescue Exception
        end
        result
      end
    end
  end
end

# ---------------------------------------------------------------------------
# THE ACCESSIBLE SUMMARY SCREEN. Everything below is self-contained: its own
# list windows, its own input loop, and every row spoken directly through
# AccessibilitySpeech - nothing here depends on the generic menu reader or on
# the game's graphics summary.
# ---------------------------------------------------------------------------
module A11ySummary
  MENU_LABEL = "Accessible Summary"

  class << self
    def say(text, interrupt: true)
      return unless defined?(AccessibilitySpeech)
      AccessibilitySpeech.speak(text.to_s, false, interrupt: interrupt)
    rescue Exception
      nil
    end

    def speech_on?
      defined?(AccessibilitySpeech) && AccessibilitySpeech.enabled
    rescue Exception
      false
    end

    # One list window that reads itself. On open it speaks the title and the
    # first row; every arrow press speaks the new row. B closes. C either
    # chooses the row (select: true, returns its index) or repeats it with
    # its position (select: false). Returns -1 when closed with B.
    def show_list(title, rows, select: false)
      rows = ["Nothing to read."] if !rows.is_a?(Array) || rows.empty?
      rows = rows.map { |r| r.to_s }
      say("#{title}. #{rows.length} rows. Arrow through them; B goes back.", interrupt: true)
      say(rows[0], interrupt: false)
      win = nil
      ret = -1
      begin
        width = begin; Graphics.width; rescue Exception; 480; end
        win = Window_CommandPokemon.new(rows, width)
        win.z = 999999
        begin
          maxh = Graphics.height
          win.height = maxh if win.height > maxh
        rescue Exception
        end
        win.a11y_silent = true if win.respond_to?(:a11y_silent=)
        win.index = 0
        last = 0
        loop do
          Graphics.update
          Input.update
          win.update
          if win.index != last
            last = win.index
            say(rows[last], interrupt: true)
          end
          if Input.trigger?(Input::B)
            pbPlayCancelSE() if defined?(pbPlayCancelSE)
            ret = -1
            break
          end
          if Input.trigger?(Input::C)
            if select
              pbPlayDecisionSE() if defined?(pbPlayDecisionSE)
              ret = win.index
              break
            else
              say("Row #{win.index + 1} of #{rows.length}. #{rows[win.index]}", interrupt: true)
            end
          end
        end
      ensure
        begin
          win.dispose if win
        rescue Exception
        end
      end
      ret
    rescue Exception => e
      begin
        AccessibilitySpeech.log("accessible summary list: #{e.class}: #{e.message}")
      rescue Exception
      end
      -1
    end

    def browse(title, rows)
      show_list(title, rows, select: false)
    end

    def choose(title, rows)
      show_list(title, rows, select: true)
    end

    # The Accessible Summary menu for one Pokemon - what opens from the
    # "Accessible Summary" entry and from K. Loops until closed, like
    # Reborn's sub-menu does.
    def run_menu(pkmn)
      return unless pkmn
      if (pkmn.isEgg? rescue false)
        browse("Egg", lines_for(pkmn))
        return
      end
      name = begin; pkmn.name.to_s; rescue Exception; "this Pokemon"; end
      loop do
        choice = choose("Accessible summary of #{name}. C opens an entry",
                        ["Everything",
                         "Stats, EVs and IVs",
                         "Base stats and abilities",
                         "Moves",
                         "Biology",
                         "Export team to text file",
                         "Close"])
        case choice
        when 0 then browse("Everything about #{name}", lines_for(pkmn))
        when 1 then browse("Stats of #{name}", stat_detail_lines(pkmn))
        when 2 then browse("Base stats of #{name}", base_stat_lines(pkmn))
        when 3 then browse("Moves of #{name}", move_lines(pkmn) + ["That is every move."])
        when 4 then browse("Biology of #{name}", biology_lines(pkmn))
        when 5 then export_team
        else break
        end
      end
    rescue Exception
      nil
    end

    # The real stats: for each stat its current total, its IV and its EV -
    # Reborn's "Pokemon Details" view, in Desolation's stat order (Speed
    # LAST; see STAT_LABELS).
    STAT_GETTERS = [:totalhp, :attack, :defense, :spatk, :spdef, :speed]

    def stat_detail_lines(pkmn)
      lines = []
      begin
        n = PBNatures.getName(pkmn.nature)
        lines << "#{n} nature." if n
      rescue Exception
      end
      begin
        iv = Array(pkmn.iv)
        ev = Array(pkmn.ev)
        STAT_LABELS.each_with_index do |label, i|
          total = begin; pkmn.send(STAT_GETTERS[i]); rescue Exception; nil; end
          row = "#{label}: "
          row += "#{total} total. " if total
          row += "IV #{iv[i].to_i}, EV #{ev[i].to_i}."
          lines << row
        end
        lines << "#{ev.map { |v| v.to_i }.sum} EVs used of 510."
      rescue Exception
      end
      begin
        if pkmn.level.to_i < 100 && defined?(PBExp)
          remexp = PBExp.startExperience(pkmn.level + 1, pkmn.growthrate) - pkmn.exp
          lines << "#{remexp} experience points to the next level." if remexp > 0
        end
      rescue Exception
      end
      lines << "That is all the stats."
      lines
    end

    # The species itself: typing, base stats with their total, and every
    # ability the species can have - Reborn's "Display BST" view.
    def base_stat_lines(pkmn)
      lines = []
      data = begin; $cache.pkmn[pkmn.species]; rescue Exception; nil; end
      begin
        species = data ? data.name.to_s : pkmn.species.to_s.capitalize
        lines << "#{species}."
        if data
          t1 = type_word(data.Type1)
          t2 = type_word(data.Type2)
          lines << (t2 && t2 != t1 ? "#{t1} and #{t2} type." : "#{t1} type.") if t1
        end
      rescue Exception
      end
      begin
        # baseStats on the Pokemon is form-aware; the cache entry is the
        # fallback for anything that lacks it.
        bs = begin; pkmn.baseStats; rescue Exception; nil; end
        bs ||= begin; data && data.BaseStats; rescue Exception; nil; end
        if bs
          bs = Array(bs)
          STAT_LABELS.each_with_index { |label, i| lines << "Base #{label} #{bs[i].to_i}." }
          lines << "Base stat total #{bs.map { |v| v.to_i }.sum}."
        end
      rescue Exception
      end
      begin
        ab = begin; pkmn.getAbilityList; rescue Exception; nil; end
        if ab && !Array(ab).empty?
          names = Array(ab).map { |a|
            begin; getAbilityName(a); rescue Exception; a.to_s.capitalize; end
          }.uniq
          lines << "Possible abilities: #{names.join(", ")}."
        end
        cur = pkmn.ability
        if cur
          lines << "Its ability: #{getAbilityName(cur)}."
          d = (getAbilityDesc(cur) rescue nil)
          lines << d.to_s if d && !d.to_s.empty?
        end
      rescue Exception
      end
      lines << "That is everything."
      lines
    end

    # The biology prose, split into sentences so it can be arrowed through
    # at the reader's own pace.
    def biology_lines(pkmn)
      data = begin; $cache.pkmn[pkmn.species]; rescue Exception; nil; end
      species_name = data ? data.name.to_s : pkmn.species.to_s
      form = begin; pkmn.getFormName; rescue Exception; nil; end
      bio = defined?(A11yBiology) ? A11yBiology.text_for(species_name, form) : nil
      return ["No biology entry for #{species_name}."] unless bio
      rows = bio.to_s.split(/(?<=[.!?])\s+/)
      rows << "That is the whole entry."
      rows
    end

    # The whole party to a Showdown-style text file in the game folder, like
    # Reborn's Export Team.
    def export_team
      trainer = begin; $Trainer; rescue Exception; nil; end
      party = (trainer && (trainer.party rescue nil)) || []
      party = party.compact
      if party.empty?
        say("No party to export.")
        return
      end
      tname = begin; trainer.name.to_s; rescue Exception; "My"; end
      filename = "#{tname}'s team.txt"
      File.open(filename, "w") do |f|
        party.each do |poke|
          name = begin; $cache.pkmn[poke.species].name.to_s; rescue Exception; poke.species.to_s.capitalize; end
          line = name.dup
          begin
            case poke.gender
            when 0 then line << " (M)"
            when 1 then line << " (F)"
            end
          rescue Exception
          end
          begin
            line << " @ #{$cache.items[poke.item].name}" if poke.item
          rescue Exception
          end
          f.write(line + "\n")
          ab = begin; getAbilityName(poke.ability); rescue Exception; nil; end
          f.write("Ability: #{ab}\n") if ab
          lv = begin; poke.level; rescue Exception; nil; end
          f.write("Level: #{lv}\n") if lv
          f.write("Shiny: Yes\n") if (poke.isShiny? rescue false)
          n = begin; PBNatures.getName(poke.nature); rescue Exception; nil; end
          f.write("#{n} Nature\n") if n
          # Desolation's array order is HP, Atk, Def, SpAtk, SpDef, Speed.
          ev = Array(begin; poke.ev; rescue Exception; []; end)
          if ev.length >= 6
            f.write("EVs: #{ev[0].to_i} HP / #{ev[1].to_i} Atk / #{ev[2].to_i} Def / #{ev[3].to_i} SpA / #{ev[4].to_i} SpD / #{ev[5].to_i} Spe\n")
          end
          iv = Array(begin; poke.iv; rescue Exception; []; end)
          if iv.length >= 6
            f.write("IVs: #{iv[0].to_i} HP / #{iv[1].to_i} Atk / #{iv[2].to_i} Def / #{iv[3].to_i} SpA / #{iv[4].to_i} SpD / #{iv[5].to_i} Spe\n")
          end
          Array(begin; poke.moves; rescue Exception; []; end).each do |m|
            next if m.nil? || (m.move rescue nil).nil?
            mn = begin; $cache.moves[m.move].name; rescue Exception; m.move.to_s.capitalize; end
            f.write("- #{mn}\n")
          end
          f.write("\n")
        end
      end
      say("Team exported to #{filename}, in the game folder.")
    rescue Exception => e
      say("Export failed: #{e.message}")
    end

    # The Pokemon under the PC cursor, from the context the arrow hooks keep.
    def pc_pokemon(scene)
      ctx = scene.instance_variable_get(:@a11y_pc_context)
      return nil unless ctx
      where, sel = ctx
      return nil unless where && sel && sel >= 0
      storage = scene.instance_variable_get(:@storage)
      return nil unless storage
      where == :party ? storage[-1, sel] : storage[storage.currentBox, sel]
    rescue Exception
      nil
    end

    # Appends the menu entry AFTER Cancel (so no game index moves) when this
    # looks like a Pokemon action menu. Returns the possibly-extended list
    # and whether it was extended.
    def extend_commands(commands)
      return [commands, false] unless speech_on?
      return [commands, false] unless commands.is_a?(Array)
      return [commands, false] unless commands.include?("Summary") && commands.include?("Cancel")
      return [commands, false] if commands.include?(MENU_LABEL)
      [commands + [MENU_LABEL], true]
    rescue Exception
      [commands, false]
    end
  end
end

# ---------------------------------------------------------------------------
# "Accessible Summary" in every Pokemon action menu that the party scene
# shows: the party screen's "Do what with X?", the Entry screens, and the
# in-battle switch menu - they all come through this one pbShowCommands.
# ---------------------------------------------------------------------------
if defined?(PokemonScreen_Scene) && PokemonScreen_Scene.method_defined?(:pbShowCommands)
  class PokemonScreen_Scene
    unless method_defined?(:a11y_accsum_show_commands)
      alias_method :a11y_accsum_show_commands, :pbShowCommands
      def pbShowCommands(helptext, commands, index = 0)
        added = false
        pkmn = nil
        begin
          commands, added = A11ySummary.extend_commands(commands)
          if added
            party = instance_variable_get(:@party)
            sel = instance_variable_get(:@activecmd)
            pkmn = (party && sel && sel >= 0) ? party[sel] : nil
            if pkmn.nil?
              commands = commands[0...-1]
              added = false
            end
          end
        rescue Exception
          added = false
        end
        ret = a11y_accsum_show_commands(helptext, commands, index)
        if added && ret == commands.length - 1
          begin
            A11ySummary.run_menu(pkmn)
          rescue Exception
          end
          return -1
        end
        ret
      end
    end
  end
end

# ---------------------------------------------------------------------------
# The same entry in the PC's menus - Withdraw, Deposit and Move mode all show
# their action menus through the storage scene's pbShowCommands.
# ---------------------------------------------------------------------------
if defined?(PokemonStorageScene) && PokemonStorageScene.method_defined?(:pbShowCommands)
  class PokemonStorageScene
    unless method_defined?(:a11y_accsum_pc_commands)
      alias_method :a11y_accsum_pc_commands, :pbShowCommands
      def pbShowCommands(message, commands, index = 0)
        added = false
        pkmn = nil
        begin
          commands, added = A11ySummary.extend_commands(commands)
          if added
            pkmn = A11ySummary.pc_pokemon(self)
            if pkmn.nil?
              commands = commands[0...-1]
              added = false
            end
          end
        rescue Exception
          added = false
        end
        ret = a11y_accsum_pc_commands(message, commands, index)
        if added && ret == commands.length - 1
          begin
            A11ySummary.run_menu(pkmn)
          rescue Exception
          end
          return -1
        end
        ret
      end
    end
  end
end
