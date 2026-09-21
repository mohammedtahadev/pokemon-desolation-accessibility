# =============================================================================
# Pokemon Desolation Accessibility Pack - by Mohammed Taha (mohammedtahadev).
# AccessibilityPathfindNames.rb - gives the pathfinder's event list real names.
#
# THE PROBLEM
# -----------
# Of the 8,959 events the pathfinder would list across Desolation's 479 maps,
# 7,083 - 79% of them - are still called EV027, EV016 and so on, because that is
# the name RPG Maker generates and the writers only renamed about a fifth of
# their events. So four times out of five, cycling the list with J and L tells
# you nothing at all.
#
# THE APPROACH
# ------------
# Every one of those events still knows what it IS. It carries a sprite, a page
# of commands, and usually some dialogue. This reads those and works out a name:
#
#   sprite "CustomScarlett"        -> "Scarlett"
#   dialogue "GARRET: Took you..." -> "Garret"
#   a portrait code \ff[07a]       -> "Rosetta"        (via the speech mod)
#   Transfer Player to map 84      -> "Door to Celeste City"
#   sprite "trchar018"             -> "Hiker"          (via the trainer types)
#   sprite "pkmn_growlithe"        -> "Growlithe"
#   pbItemBall(:POTION)            -> "Item ball: Potion"
#   no sprite, but it talks        -> "Sign: Sunshell Town Teleporter"
#
# All of it comes from the game's own authored data - $cache.mapinfos,
# $cache.trainertypes, $cache.pkmn and the event's own command list. Nothing
# here is guessed, and nothing here is a hardcoded table of map contents that
# could go stale.
#
# WHY IT RUNS LIVE INSTEAD OF FROM A FILE
# ---------------------------------------
# A generated name file has to be keyed on coordinates, and the pathfinder looks
# events up by where they are NOW. Around a thousand event pages in Desolation
# use random movement, so every wandering NPC would walk off its tile and lose
# its label. Deriving on the spot follows them, and can never go out of date.
#
# tools/generate_event_labels.rb can still write the whole set out to a text
# file if you want to read or edit it - see the README.
#
# WHAT IT WILL NEVER DO
# ---------------------
# It only fills in blanks. A name you set yourself with Shift+K wins, and so
# does a name Desolation's own writers gave the event. This only speaks up when
# the alternative was "EV027".
# =============================================================================

module A11yNames
  # How much dialogue to read before giving up. Events are scanned once per map
  # load, and the busiest map in the game has 482 of them, so this stays small.
  TEXT_SCAN_LIMIT   = 400
  SNIPPET_LENGTH    = 48

  # Sprites that are things rather than people.
  OBJECT_SPRITES = {
    /\Aobject ball/i => "Item ball",
    /\Ahealbell/i    => "Healing machine",
    /\Apc\b/i        => "PC",
    /\Adoor/i        => "Door",
    /\Asign/i        => "Sign"
  }

  class << self
    # ---------------------------------------------------------------- caches
    # Built once, lazily, and thrown away on a soft reset.

    # Desolation's trainer types are keyed by symbol but the overworld sprites
    # are named by number (trchar018), so index them the other way round.
    def trainer_titles
      return @trainer_titles if @trainer_titles
      @trainer_titles = {}
      begin
        $cache.trainertypes.each do |_sym, td|
          id = td.flags[:ID] rescue nil
          next if id.nil?
          title = td.title.to_s
          @trainer_titles[id.to_i] = title unless title.empty?
        end
      rescue Exception
      end
      @trainer_titles
    end

    def species_names
      return @species_names if @species_names
      @species_names = {}
      begin
        $cache.pkmn.each do |_sym, data|
          n = data.name.to_s
          @species_names[n.upcase] = n unless n.empty?
        end
      rescue Exception
      end
      @species_names
    end

    def map_name(id)
      return nil if id.nil?
      @map_names ||= {}
      return @map_names[id] if @map_names.key?(id)
      name = begin
        info = $cache.mapinfos[id]
        info ? info.name.to_s : nil
      rescue Exception
        nil
      end
      @map_names[id] = (name && !name.empty?) ? name : nil
    end

    def reset_caches
      @trainer_titles = nil
      @species_names  = nil
      @map_names      = nil
    end

    # ------------------------------------------------------------- utilities

    # True when the event's own name tells a player nothing: RPG Maker's
    # generated EV000 names, bare numbers, and blanks.
    def useless_name?(n)
      s = n.to_s.strip
      return true if s.empty?
      return true if s =~ /\AEV\d+\z/i
      return true if s =~ /\A\d+\z/
      return true if s =~ /\AEv\z/i
      false
    end

    # The dialogue on this page, joined, capped, with the game's control codes
    # left in - speaker_name and portrait_name both need them.
    def raw_text(list)
      out = ""
      list.each do |cmd|
        code = cmd.code rescue nil
        next unless code == 101 || code == 401
        p = (cmd.parameters rescue nil)
        next unless p && p[0].is_a?(String)
        out << p[0] << " "
        break if out.length >= TEXT_SCAN_LIMIT
      end
      out
    rescue Exception
      ""
    end

    # Strip the control codes so the text can be read aloud or shown.
    def plain(text)
      text.to_s.gsub(/\\[A-Za-z]+\[[^\]]*\]/, "").gsub(/\\[A-Za-z]/, "")
          .gsub(/\s+/, " ").strip
    rescue Exception
      ""
    end

    def scripts(list)
      out = ""
      list.each do |cmd|
        code = cmd.code rescue nil
        next unless code == 355 || code == 655
        p = (cmd.parameters rescue nil)
        out << p[0].to_s << " " if p && p[0].is_a?(String)
      end
      out
    rescue Exception
      ""
    end

    def transfer_map_id(list)
      list.each do |cmd|
        next unless (cmd.code rescue nil) == 201
        p = (cmd.parameters rescue nil)
        return p[1] if p
      end
      nil
    rescue Exception
      nil
    end

    # "GARRET: Took you long enough." -> "Garret".
    #
    # Desolation writes every one of these prefixes in capitals - all 289 of
    # them - so requiring capitals is what separates a real speaker from a
    # sentence that merely contains a colon. Accepting mixed case turned
    # "Well: that was odd" into a character called Well.
    def speaker_name(text)
      s = plain(text)
      m = s.match(/\A([A-Z][A-Z'\-]*(?: [A-Z][A-Z'\-]*)*)\s*:/)
      return nil unless m
      name = m[1].strip
      return nil if name.length < 2 || name.length > 20
      titleize(name)
    rescue Exception
      nil
    end

    # The portrait code the speech mod already knows how to name.
    def portrait_name(text)
      marker = 92.chr + "ff["
      i = text.to_s.index(marker)
      return nil unless i
      j = text.index("]", i + marker.length)
      return nil unless j
      id = text[(i + marker.length)...j].to_s.split(",").first.to_s.strip
      return nil unless defined?(AccessibilitySpeech)
      AccessibilitySpeech::FACE_NAMES[id]
    rescue Exception
      nil
    end

    def titleize(s)
      s.to_s.split(/\s+/).map { |w| w.capitalize }.join(" ")
    end

    # A species this event talks about, so a nameless trainer can be "Hiker,
    # about Growlithe" rather than just another "Hiker".
    def species_topic(text)
      s = plain(text)
      return nil if s.empty?
      names = species_names
      return nil if names.empty?
      found = nil
      s.scan(/[A-Za-z][A-Za-z'\-]{3,}/) do |w|
        hit = names[w.upcase]
        next unless hit
        return nil if found && found != hit    # more than one: too vague to use
        found = hit
      end
      found
    rescue Exception
      nil
    end

    def sprite_label(sprite)
      return nil if sprite.to_s.empty?
      # Strip the "(2)" palette-variant suffix FIRST. Without this,
      # "pkmn_skitty (2)" fails the anchored match below and a perfectly
      # identifiable Skitty comes out as "Object".
      s = tidy_sprite(sprite)

      # CustomScarlett -> Scarlett
      if s =~ /\ACustom([A-Z][A-Za-z]+)\z/
        return $1
      end
      # pkmn_growlithe / pkmn_Munna -> Growlithe / Munna
      if s =~ /\Apkmn[_ ]([A-Za-z][A-Za-z0-9_\-]*)\z/i
        raw = $1.tr("_", " ")
        known = species_names[raw.upcase]
        return known || titleize(raw)
      end
      # trchar018 -> Hiker. A few sprites have no matching trainer type in
      # ttypes.dat, and "Trainer" beats reading the file name out loud.
      if s =~ /\Atrchar0*(\d+)/i
        return trainer_titles[$1.to_i] || "Trainer"
      end
      OBJECT_SPRITES.each { |re, label| return label if s =~ re }
      nil
    rescue Exception
      nil
    end

    # ------------------------------------------------------------ the label

    def derive(event)
      list   = (event.list rescue nil) || []
      sprite = (event.character_name rescue "").to_s
      text   = raw_text(list)
      src    = scripts(list)

      # A door says where it goes. $MapFactory only knows maps that are loaded,
      # so this goes to $cache.mapinfos, which knows all 480.
      dest = transfer_map_id(list)
      if dest
        n = map_name(dest)
        return n ? "Door to #{n}" : "Door"
      end

      # Who is it? A name beats every other kind of label.
      by_sprite = sprite_label(sprite)
      return by_sprite if by_sprite && sprite =~ /\ACustom/

      named = speaker_name(text) || portrait_name(text)
      return named if named

      # What is it?
      if src =~ /pbItemBall\s*\(?\s*:?([A-Z][A-Z0-9_]*)/
        return "Item ball: #{titleize($1.tr('_', ' '))}"
      end
      if src =~ /pbHiddenItem\s*\(?\s*:?([A-Z][A-Z0-9_]*)/
        return "Hidden item: #{titleize($1.tr('_', ' '))}"
      end
      return "Shop counter" if src =~ /pbPokemonMart/
      if src =~ /pbTrainerIntro\s*\(?\s*:?([A-Z][A-Z0-9_]*)/
        return "Trainer: #{titleize($1.tr('_', ' '))}"
      end

      topic = species_topic(text)

      # A trainer sprite carries its type, which is the description you want:
      # Hiker, Beauty, Bug Catcher, Gentleman.
      if by_sprite
        return topic ? "#{by_sprite}, about #{topic}" : by_sprite
      end

      body = plain(text)
      unless body.empty?
        # Nothing standing on it means nobody is there: it is a sign.
        return "Sign: #{shorten(body)}" if sprite.empty?
        return "Person, about #{topic}" if topic
        return "Person: #{shorten(body)}"
      end

      # No sprite and nothing to say: an invisible tile that fires when you step
      # on it. Roughly 1,100 of these exist and they used to be the bulk of what
      # had no label at all. Worth hearing precisely because you cannot see one
      # coming - most are ledge hops and stairs that move you against your will.
      #
      # A LEVER is drawn into the scenery, so it is invisible too - but it is
      # the one kind you must go and use. Its shape, across the whole game:
      # activated with the action button, flips a game switch (the gate), and
      # says nothing. Exactly the Keneph Caves levers match; they used to read
      # "Trigger tile", and a player could not find them (a player report).
      if sprite.empty?
        trig = (event.trigger rescue nil)
        return "Lever" if trig == 0 && flips_switch?(list)
        return "Move trigger" if move_route?(list)
        return "Step trigger, fires when you walk onto it" if trig == 1 || trig == 2
        return "Hidden object, check it with the action button" if trig == 0
        return "Invisible trigger"
      end

      # A sprite, but silent. NPC sprites are people standing around; anything
      # else is scenery, and its sprite name is the only thing that tells two
      # of them apart.
      return "Person" if sprite =~ /\ANPC\b/i
      "Object (#{tidy_sprite(sprite)})"
    rescue Exception
      nil
    end

    # Set Move Route (209) - the event shoves something around when touched.
    def move_route?(list)
      list.any? { |cmd| (cmd.code rescue nil) == 209 }
    rescue Exception
      false
    end

    # Control Switches (121) - turns a game switch on or off.
    def flips_switch?(list)
      list.any? { |cmd| (cmd.code rescue nil) == 121 }
    rescue Exception
      false
    end

    # "trchar037 (3)" -> "trchar037". The numbered suffixes are palette variants
    # of the same graphic and say nothing useful out loud.
    def tidy_sprite(s)
      s.to_s.sub(/\s*\(\d+\)\s*\z/, "").strip
    rescue Exception
      s.to_s
    end

    def shorten(s)
      t = s.to_s.strip
      return t if t.length <= SNIPPET_LENGTH
      cut = t[0, SNIPPET_LENGTH]
      sp = cut.rindex(" ")
      (sp && sp > SNIPPET_LENGTH / 2 ? cut[0, sp] : cut).rstrip + "..."
    rescue Exception
      s.to_s
    end

    # Fills in the blanks in a list the pathfinder has already built. Runs after
    # the grouping and sorting, so neither is affected - only what you hear.
    def apply(events)
      return unless events.is_a?(Array)
      # Options -> Event Names.
      if defined?(A11ySettings) && !A11ySettings.on?(:event_names)
        return
      end
      events.each do |event|
        begin
          # Virtual events (connections, your own points of interest) are
          # already named, and there is nothing to read on them anyway.
          next unless event.respond_to?(:character_name)
          # A name you set, or one the grouper worked out, wins.
          existing = (event.custom_name rescue nil)
          next if existing && !existing.to_s.strip.empty?
          # A name Desolation's writers gave it wins too.
          own_name = (event.name rescue nil)
          next unless useless_name?(own_name)
          label = derive(event)
          event.custom_name = label if label && !label.empty?
        rescue Exception
        end
      end
    rescue Exception
    end
  end
end

# The pathfinder builds the list; this fills in the names right after it. Doing
# it here rather than inside populate_event_list keeps AccessibilityPathfind.rb
# byte-identical to the Reborn original, which tools/port_pathfind.rb relies on.
#
# populate_event_list is written at column 0 in that file, which makes it LOOK
# like a top-level method, but the `class Game_Player` block above it is still
# open - so it is a public instance method of Game_Player and has to be aliased
# there. Aliasing at the top level instead would silently patch nothing.
class Game_Player
  if method_defined?(:populate_event_list)
    unless method_defined?(:a11y_names_populate_event_list)
      alias_method :a11y_names_populate_event_list, :populate_event_list

      def populate_event_list
        a11y_names_populate_event_list
        A11yNames.apply(PraSession.mapevents) if defined?(PraSession)
      end
    end
  end
end

# A soft reset reloads the game's data, so drop the cached lookups with it.
class Scene_Map
  unless method_defined?(:a11y_names_main)
    alias_method :a11y_names_main, :main
    def main
      A11yNames.reset_caches
      a11y_names_main
    end
  end
end
