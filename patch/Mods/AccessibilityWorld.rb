# =============================================================================
# Pokemon Desolation Accessibility Pack - by Mohammed Taha (mohammedtahadev).
# AccessibilityWorld.rb - tile sounds.
#
# THE LEGEND RPG SYSTEM
# ---------------------
# Sounds live in Audio/tile_sounds/<surface>/ and each surface folder holds:
#
#     step1.ogg .. step5.ogg   walking variants, chosen at random
#     land.ogg                 landing after a ledge hop
#     fall.ogg                 the drop itself
#
# Five variants per surface is what stops walking becoming a metronome: one
# repeated sample turns maddening within about ten steps, and the ear starts
# filtering it out - which defeats the point, because the footstep is the
# thing telling you what you are standing on.
#
# Steps are played FLAT: no panning, no pitch shifting by direction. You know
# which way you are walking because you are holding the key. The step is there
# to say what is under your feet, and nothing else.
#
# land.ogg and fall.ogg NEVER play while walking. They belong to ledge hops
# only - the drop and the landing - so that hearing one always means you just
# went down a ledge.
#
# HOW A SURFACE IS CHOSEN
# -----------------------
# Two layers, and the order matters:
#
#   1. Real terrain wins. Desolation tags every tile - grass, water, ice,
#      sand, bridge - and a tagged tile always sounds like what it is,
#      whatever map it sits on.
#
#   2. Featureless ground takes the character of its map. Most indoor floors,
#      paths and cave bottoms carry the same "neutral" tag, so on their own
#      they would all sound identical. MAP_SURFACE_RULES reads the map's NAME
#      and gives it a fitting surface: an apartment sounds like hardwood, a
#      cavern like cave floor, a city like pavement, a route like dirt.
#
# Matching on the name rather than a list of map IDs means all 480 maps are
# covered, and any map added later is covered too.
# =============================================================================

module A11yWorld
  # All mod content lives under patch\ now, the Reborn layout - but an older
  # install with the sounds still in Audio	ile_sounds keeps working.
  TILE_ROOT = File.directory?("patch/audio/tile_sounds") ? "patch/audio/tile_sounds" : "Audio/tile_sounds"

  # Footstep volume, 0-100. Scaled again by the game's own SE volume setting.
  STEP_VOLUME = 70

  # Desolation terrain tag (PBTerrain, Field.rb) -> surface folder.
  # A tagged tile always sounds like itself, on every map.
  TERRAIN = {
    1  => "ledge",        # Ledge
    2  => "grass",        # Grass
    3  => "sand",         # Sand
    4  => "stone",        # Rock
    5  => "deepwater",    # DeepWater
    6  => "shallow",      # StillWater
    7  => "water",        # Water
    8  => "water",        # Waterfall
    9  => "water",        # WaterfallCrest
    10 => "brush",        # TallGrass
    11 => "underwater",   # UnderwaterGrass
    12 => "ice",          # Ice
    14 => "ash",          # SootGrass
    15 => "bridge",       # Bridge
    16 => "puddle",       # Puddle
    17 => "sewer",        # Grime
    18 => "puddle",       # PokePuddle
    20 => "metal",        # DownConveyor
    21 => "metal",        # LeftConveyor
    22 => "metal",        # RightConveyor
    23 => "metal",        # UpConveyor
    24 => "deepsand",     # SandDune
    25 => "sand"          # Sand
  }

  # Tags with no character of their own - these are the ones a map's name gets
  # to colour. 13 is Neutral (ordinary floors and paths), 19 is Dummy.
  PLAIN_TAGS = [0, 13, 19]

  # Map name -> surface, first match wins, so the specific patterns come
  # before the general ones. Built from Desolation's own 480 map names.
  MAP_SURFACE_RULES = [
    # Rooms and buildings first - "Cellia Apartments" must be hardwood, not
    # the pavement its city name would otherwise give it.
    [/sewer/i,                                          "sewer"],
    [/prison|\bcell\b|jail/i,                           "concrete"],
    [/apartment|manor|house|home\b|bedroom|residence|\broom\b/i, "hardwood"],
    [/center|centre|hospital|clinic/i,                  "linoleum"],
    [/\blab\b|laboratory|facility/i,                    "tile"],
    [/library|archive|study/i,                          "carpet"],
    [/\bgym\b|arena|stadium|fight club/i,               "concrete"],
    [/cafe|\bmart\b|store|shop\b|market/i,              "tile"],
    [/nightclub|\bclub\b|guild|\bbar\b|lounge/i,        "hardwood"],
    # Natural and structural places.
    [/cave|cavern|grotto|depth|underground|tunnel|mine\b|labyrinth|hideout|lair/i, "cavegrounds"],
    [/ruins|rubble|debris|settler/i,                    "rubble"],
    [/\broof\b|rooftop/i,                               "roof"],
    [/mountain|\brise\b|peak|cliff|hardened|summit|ridge|\bmt\.?\b/i, "rocks"],
    [/forest|grove|woods|woodland|jungle/i,             "leaves"],
    [/beach|shore|coast|\bisle\b|island|dune/i,         "sand"],
    [/dock|pier|\bship\b|cruise|boat|harbor|harbour|deck/i, "deck"],
    [/swamp|marsh|bog\b|wetland/i,                      "swamp"],
    [/snow|frozen|glacier|tundra|frost/i,               "snow"],
    [/sanctuary|temple|shrine|cathedral|chapel|council|chamber/i, "marble"],
    [/dreamscape|dream\b|void|astral|portal|somnium|nova/i, "synthetic"],
    [/gate|entrance|\bentry\b/i,                        "stone"],
    [/base\b|factory|plant\b|reactor|station|\bcore\b|tower/i, "metal"],
    [/lake|waterscape|pond|river|\bfalls\b/i,           "dirt"],
    # Settlements last, so anything inside one has already claimed its own
    # surface. The proper nouns are Desolation's own towns and cities.
    [/city|town|street|plaza|square|village|outskirts|district/i, "pavement"],
    [/cellia|blackview|addenfall|keneph|bountilia|vejyr|sunshell|celeste|amaria/i, "pavement"],
    [/route|\bpath\b|trail|road|passage/i,              "dirt"]
  ]

  # Used when nothing else matches.
  DEFAULT_SURFACE = "generic"

  class << self
    # True only while a ledge hop is resolving, so the drop and the landing
    # can use fall.ogg and land.ogg. Walking never sets it.
    attr_accessor :landing

    def variant_counts
      @variant_counts ||= {}
    end

    # The engine ships its own existence check (Audio.rb) because
    # FileTest.exist? is unreliable here - it fails on some paths outright.
    # Trying the game's helper first is what makes this work at all; the
    # FileTest call is only a last resort.
    def one_file_exists?(full)
      return true if (safeExists?(full) rescue false)
      return true if (FileTest.exist?(full) rescue false)
      false
    end

    # Returns the full path including extension, or nil.
    def resolve_file(path)
      %w[.ogg .wav .mp3 .wma .mid].each do |ext|
        full = path + ext
        return full if one_file_exists?(full)
      end
      nil
    rescue Exception
      nil
    end

    def file_exists?(path)
      !resolve_file(path).nil?
    end

    # Counts step1, step2, ... until one is missing. Cached, so this touches
    # the disk once per surface per session.
    def variant_count(surface)
      cached = variant_counts[surface]
      return cached unless cached.nil?
      count = 0
      loop do
        break unless file_exists?("#{TILE_ROOT}/#{surface}/step#{count + 1}")
        count += 1
        break if count >= 20
      end
      variant_counts[surface] = count
      count
    end

    # The surface a map's featureless ground should use, from its name.
    def map_surface(map_id = nil)
      map_id ||= ($game_map ? $game_map.map_id : nil)
      return DEFAULT_SURFACE if map_id.nil?
      cached = (@map_surface_cache ||= {})[map_id]
      return cached if cached
      name = (pbGetMapNameFromId(map_id) rescue "").to_s
      surface = DEFAULT_SURFACE
      MAP_SURFACE_RULES.each do |pattern, folder|
        if name =~ pattern
          surface = folder
          break
        end
      end
      @map_surface_cache[map_id] = surface
      surface
    rescue Exception
      DEFAULT_SURFACE
    end

    def surface_for(tag)
      return map_surface if PLAIN_TAGS.include?(tag)
      TERRAIN[tag] || map_surface
    rescue Exception
      DEFAULT_SURFACE
    end

    # STEP_VOLUME is the default; the Options screen can override it.
    def step_volume
      base = defined?(A11ySettings) ? A11ySettings.step_volume : STEP_VOLUME
      se = ($Settings && $Settings.sevolume) rescue nil
      se ? (base * se / 100.0).round : base
    rescue Exception
      STEP_VOLUME
    end

    # Options -> Tile Sounds.
    def tile_sounds_on?
      return true unless defined?(A11ySettings)
      A11ySettings.on?(:tile_sounds)
    rescue Exception
      true
    end

    # Plays a sound from anywhere under the game folder.
    #
    # NOT via pbSEPlay, which hard-codes an "Audio/SE/" prefix, and NOT via
    # Audio_se_play either: that one calls getPlaySound(), which this game
    # never defines anywhere, so it raises NoMethodError for every caller.
    # Audio.se_play is the engine call the game itself ends up using, and it
    # takes a full path from the game folder.
    def play_file(path)
      return unless tile_sounds_on?
      full = resolve_file(path)
      if full.nil?
        # Log the first few misses only. A silent footstep system is very hard
        # to diagnose from the outside, and this says exactly which path was
        # looked for; after that it goes quiet rather than filling the log.
        @miss_logged ||= 0
        if @miss_logged < 5
          @miss_logged += 1
          AccessibilitySpeech.log("Tile sound not found: #{path} (cwd=#{Dir.pwd})") if defined?(AccessibilitySpeech)
        end
        return false
      end
      Audio.se_play(full, step_volume, 100)
      true
    rescue Exception
      @fail_logged ||= 0
      if @fail_logged < 5
        @fail_logged += 1
        AccessibilitySpeech.log("Tile sound failed: #{$!.class}: #{$!.message}") if defined?(AccessibilitySpeech)
      end
      false
    end

    # Resolves a surface that actually has step files, so a missing folder
    # never means silent walking.
    def playable_surface(surface)
      return surface if variant_count(surface) > 0
      return DEFAULT_SURFACE if variant_count(DEFAULT_SURFACE) > 0
      nil
    end

    # One footstep. Random variant, never the same one twice running, so a
    # corridor never develops an audible pattern.
    def play_step(tag)
      surface = playable_surface(surface_for(tag))
      return if surface.nil?
      count = variant_count(surface)
      pick = rand(count) + 1
      if count > 1 && pick == @last_variant && surface == @last_surface
        pick = (pick % count) + 1
      end
      @last_variant = pick
      @last_surface = surface
      play_file("#{TILE_ROOT}/#{surface}/step#{pick}")
    rescue Exception
      nil
    end

    # Ledge hops only. Falls back to a step so a surface without a land.ogg
    # still makes a noise when you come down.
    def play_land(tag)
      surface = playable_surface(surface_for(tag))
      return if surface.nil?
      return if play_file("#{TILE_ROOT}/#{surface}/land")
      play_step(tag)
    rescue Exception
      nil
    end

    # The drop itself. Silent when the surface has no fall.ogg - there is
    # nothing sensible to substitute, and a wrong sound here would be worse
    # than none.
    def play_fall(tag)
      surface = playable_surface(surface_for(tag))
      return if surface.nil?
      play_file("#{TILE_ROOT}/#{surface}/fall")
    rescue Exception
      nil
    end

    # ── The V key: where am I ────────────────────────────────────────────────
    # Names the map, gives coordinates, and says which surface is underfoot -
    # that last part doubles as a way to check the tile sounds are picking
    # what you expect.
    TERRAIN_NAMES = {
      1  => "ledge",            2  => "grass",            3  => "sand",
      4  => "rock",             5  => "deep water",       6  => "still water",
      7  => "water",            8  => "waterfall",        9  => "waterfall crest",
      10 => "tall grass",       11 => "underwater grass", 12 => "ice",
      13 => "ground",           14 => "soot grass",       15 => "bridge",
      16 => "puddle",           17 => "grime",            18 => "puddle",
      20 => "conveyor",         21 => "conveyor",         22 => "conveyor",
      23 => "conveyor",         24 => "sand dune",        25 => "sand"
    }

    def describe_position
      x = $game_player.x
      y = $game_player.y
      tag = ($game_map.terrain_tag(x, y) rescue 0)
      name = (pbGetMapNameFromId($game_map.map_id) rescue "").to_s.strip
      parts = []
      parts << (name.empty? ? "Map #{$game_map.map_id}" : name)
      parts << "Position #{x}, #{y}"
      terrain = TERRAIN_NAMES[tag] || "ground"
      surface = surface_for(tag)
      # Only name the surface separately when it differs from the terrain, so
      # "grass, grass surface" never happens.
      parts << (terrain == surface ? terrain.to_s : "#{terrain}, #{surface} surface")
      parts.join(". ")
    rescue Exception
      nil
    end

    def announce_position
      line = describe_position
      a11y(line, true) if line
    rescue Exception
      nil
    end

    # True only when the player is walking a map under their own control.
    def on_map?
      return false if $game_temp.nil? || $game_player.nil? || $game_map.nil?
      return false if $game_temp.in_battle
      return false if $game_temp.message_window_showing
      return false unless ($scene.is_a?(Scene_Map) rescue false)
      true
    rescue Exception
      false
    end
  end
end

# ── Footsteps ────────────────────────────────────────────────────────────────
# increase_steps runs exactly once per tile actually moved onto - Game_Player's
# move_ methods call it only on a successful move - so it never fires for a
# blocked move and never fires twice for one step.
class Game_Player < Game_Character
  unless method_defined?(:a11y_footstep)
    def increase_steps
      super
      a11y_footstep
    end

    def a11y_footstep
      return unless A11yWorld.on_map?
      tag = $game_map.terrain_tag(@x, @y)
      if A11yWorld.landing
        A11yWorld.play_land(tag)
      else
        A11yWorld.play_step(tag)
      end
    rescue Exception
      nil
    end
  end
end

# ── Ledge hops ───────────────────────────────────────────────────────────────
# pbLedge tests whether the player is facing a ledge and, if so, jumps them
# over it and calls increase_steps itself. Flagging around that call is what
# turns the resulting step into a landing - and because the flag is only ever
# set inside this method, ordinary walking can never produce a land or fall
# sound.
unless defined?(a11y_original_pbLedge)
  alias a11y_original_pbLedge pbLedge

  def pbLedge(xOffset, yOffset)
    was_ledge = (Kernel.pbFacingTerrainTag == PBTerrain::Ledge rescue false)
    if was_ledge
      # The drop, before the jump animation runs.
      tag = ($game_map.terrain_tag($game_player.x, $game_player.y) rescue 0)
      A11yWorld.play_fall(tag)
    end
    A11yWorld.landing = true
    begin
      a11y_original_pbLedge(xOffset, yOffset)
    ensure
      A11yWorld.landing = false
    end
  end
end

# ── The V key ────────────────────────────────────────────────────────────────
# Says the map name, coordinates and the surface underfoot. Map only, so it
# stays quiet in battle and during cutscenes.
module Input
  class << self
    unless method_defined?(:a11y_world_update) || private_method_defined?(:a11y_world_update)
      alias a11y_world_update update

      def update
        a11y_world_update
        begin
          # Never steal the key while a name is being typed (Ctrl+V pastes).
          return if Input.text_input == true
        rescue Exception
        end
        begin
          if Input.triggerex?(:V) && A11yWorld.on_map?
            A11yWorld.announce_position
          end
        rescue Exception
        end
      end
    end
  end
end

AccessibilitySpeech.log("Tile sounds loaded.") if defined?(AccessibilitySpeech)
