# =============================================================================
# Pokemon Desolation Accessibility Pack - by Mohammed Taha (mohammedtahadev).
# beacon.dll, the 3D audio engine, was written by Mohammed Taha with the help
# of Claude (Anthropic's AI).
# AccessibilityBeacon.rb - a directional beacon that guides you to the selected
# target BY EAR, turn by turn, following the walkable route around walls rather
# than pointing in a straight line through them.
#
# Ported from Reborn's pra-beacon.rb (github.com/fclorenzo/pkreborn-access),
# from the copy in E:/Guide/Reborn-19.5.0-windows/patch/Mods.
#
# HOW TO USE IT
#   1. Pick a target with J and L, the same way you always do.
#   2. Shift+B starts guiding. Shift+B again stops.
#   The sound is placed in true 3D toward your NEXT step along the route and
#   re-steers as you walk. A chime plays when you arrive.
#
# THE AUDIO
# ---------
# This is real binaural audio, not stereo panning: beacon.dll (built from
# beacon_src/beacon.c) driving Valve's Steam Audio through phonon.dll, called
# from Ruby with fiddle. You get genuine left/right, front/back and distance.
#
#   patch/lib/beacon.dll     the wrapper
#   patch/lib/phonon.dll     Steam Audio 4.8.1
#   patch/audio/beacon.wav   the beacon sound (mono spatialises cleanest)
#
# Generic HRTF renders front/back weakly, so the wrapper adds a pitch and
# muffling cue on top: higher and clearer in front, lower and duller behind.
# PITCH_RANGE and BACK_DAMP below control how strong that is.
#
# WHAT WAS CHANGED FOR DESOLATION
# -------------------------------
#   1. Reborn puts an on/off switch in Options -> Accessibility. That needs
#      Reborn's PokemonOptions, EnumOption and a saved $Settings field that
#      Desolation has no equivalent for, and bolting a new field onto a
#      Marshal'd settings object risks the save file. Dropped: Shift+B is the
#      switch, and it costs nothing when you are not using it.
#   2. Reborn's fallback (used when Steam Audio will not load) plays panned
#      Blindstep footstep sounds through pbAccessibilitySEPlay. Desolation has
#      neither that helper nor those sounds, and RGSS's Audio.se_play cannot
#      pan at all - so the fallback here SPEAKS the direction instead, which is
#      the one thing that stays useful without spatial audio.
#   3. tts() comes from AccessibilityPathfind.rb, as everywhere else.
#
# The pathfinding, the route caching, the arrival test and the Steam Audio
# backend are otherwise untouched.
#
# IF IT FALLS BACK TO SPEECH
# --------------------------
# The mod writes beacon_error.txt in the game folder saying exactly why. That
# file is the first thing to read if the beacon is not doing what you expect.
# =============================================================================

module PraBeaconAudio
  # Front/back cue strength. Generic HRTF renders front/back weakly, so the
  # wrapper adds pitch and muffling. Raise these if it is still too subtle.
  PITCH_RANGE = 0.22   # pitch is higher in front, LOWER behind
  BACK_DAMP   = 0.85   # how muffled a sound behind you gets (0.0 - 0.95)

  @available = false
  @started   = false
  @playing   = false

  class << self
    attr_reader :available, :started, :playing
  end

  def self.log(msg)
    File.open("beacon_error.txt", "a") { |f| f.puts("[#{Time.now}] #{msg}") } rescue nil
  end

  # Where to look for the DLLs and the beacon sound, in order - the first hit
  # wins, so Data/audio comes first: a sound you drop there overrides the one
  # that shipped with the mod. fiddle will not accept a relative path, so every
  # hit is expanded to an absolute one.
  SEARCH_DIRS = ["Data/audio", "patch/lib", "patch/audio", "Audio", "."]

  # miniaudio, which beacon.dll is built on, decodes WAV and MP3 but NOT OGG
  # Vorbis. Desolation's own sounds are all .ogg, so dropping one in as the
  # beacon is the obvious thing to try and it silently will not work.
  PLAYABLE = ["beacon.wav", "beacon.mp3"]

  def self.locate(name)
    SEARCH_DIRS.each do |d|
      p = File.join(d, name)
      return File.expand_path(p).tr("/", 92.chr) if File.exist?(p)
    end
    nil
  end

  def self.sound_file
    PLAYABLE.each { |n| p = locate(n); return p if p }
    nil
  end

  # locate() returns an absolute path with backslashes, which is what fiddle
  # needs. The game's own Audio.se_play wants a path relative to the game
  # folder instead, so the arrival chime uses this one.
  def self.locate_relative(name)
    SEARCH_DIRS.each do |d|
      p = File.join(d, name)
      return p if File.exist?(p)
    end
    nil
  end

  # The arrival chime goes through the GAME's audio engine, not beacon.dll, and
  # that engine plays .ogg perfectly well - so unlike the beacon loop this one
  # needs no conversion. Drop arrive.ogg in Data/audio or patch/audio.
  ARRIVE_NAMES = ["arrive.ogg", "arrive.wav", "arrive.mp3"]

  def self.arrival_file
    ARRIVE_NAMES.each { |n| p = locate_relative(n); return p if p }
    nil
  end

  # The engine (miniaudio, inside beacon.dll) decodes WAV and MP3 but NOT OGG
  # Vorbis - beacon_init on an .ogg returns -4 and says so. Desolation's own
  # sounds are ALL .ogg, so dropping one in as the beacon is the natural thing
  # to do and it would simply not work.
  #
  # So if the only beacon sound present is an .ogg, convert it once with ffmpeg
  # and cache the result next to it. After that the .wav is found directly and
  # this never runs again.
  #
  # Mono, 48000 Hz: exactly what the decoder wants, and mono matters because a
  # stereo file carries its own left/right, which fights the HRTF that is meant
  # to be placing the sound for you.
  def self.convert_ogg
    ogg = locate("beacon.ogg")
    return nil unless ogg
    target = File.expand_path(File.join("Data", "audio", "beacon.wav"))
    begin
      require 'fileutils'
      FileUtils.mkdir_p(File.dirname(target))
    rescue Exception
      return nil
    end
    null = (File::NULL rescue "NUL")
    cmd = %Q{ffmpeg -hide_banner -loglevel error -y -i "#{ogg}" -ac 1 -ar 48000 -c:a pcm_s16le "#{target}" > #{null} 2>&1}
    ok = (system(cmd) rescue false)
    if ok && File.exist?(target) && File.size(target) > 44
      log("Converted beacon.ogg to WAV automatically (#{target}).")
      return target.tr("/", 92.chr)
    end
    File.delete(target) if File.exist?(target) && File.size(target) <= 44 rescue nil
    nil
  rescue Exception => e
    log("Automatic OGG conversion failed (#{e.class}: #{e.message}).")
    nil
  end

  # ---------------------------------------------------------------------------
  # Fiddle's C code calls BACK into Ruby methods that live in the pure-Ruby
  # fiddle.rb - which Desolation does not ship.
  #
  # Fiddle::Handle.new records the OS error by calling Fiddle.win32_last_error=
  # on Windows. With fiddle.rb absent that method does not exist, and creating a
  # Handle dies with:
  #
  #   NoMethodError: undefined method `win32_last_error=' for Fiddle:Module
  #
  # which is exactly what the game logged. Nothing about the DLLs or the C ABI
  # was wrong; fiddle simply could not finish its own bookkeeping.
  #
  # These four are copied from fiddle.rb verbatim - thread-local slots, same
  # key names - and only defined when they are genuinely missing, so a Ruby
  # that HAS fiddle.rb (Reborn's, or any normal install) is left alone.
  # ---------------------------------------------------------------------------
  def self.patch_fiddle_error_methods
    return if @fiddle_patched
    @fiddle_patched = true
    added = []
    unless Fiddle.respond_to?(:win32_last_error=)
      Fiddle.define_singleton_method(:win32_last_error) do
        Thread.current[:__FIDDLE_WIN32_LAST_ERROR__]
      end
      Fiddle.define_singleton_method(:win32_last_error=) do |error|
        Thread.current[:__FIDDLE_WIN32_LAST_ERROR__] = error
      end
      added << "win32_last_error"
    end
    unless Fiddle.respond_to?(:win32_last_socket_error=)
      Fiddle.define_singleton_method(:win32_last_socket_error) do
        Thread.current[:__FIDDLE_WIN32_LAST_SOCKET_ERROR__]
      end
      Fiddle.define_singleton_method(:win32_last_socket_error=) do |error|
        Thread.current[:__FIDDLE_WIN32_LAST_SOCKET_ERROR__] = error
      end
      added << "win32_last_socket_error"
    end
    unless Fiddle.respond_to?(:last_error=)
      Fiddle.define_singleton_method(:last_error) do
        Thread.current[:__FIDDLE_LAST_ERROR__]
      end
      Fiddle.define_singleton_method(:last_error=) do |error|
        Thread.current[:__DL2_LAST_ERROR__] = error
        Thread.current[:__FIDDLE_LAST_ERROR__] = error
      end
      added << "last_error"
    end
    log("Supplied missing fiddle bookkeeping methods: #{added.join(', ')}.") unless added.empty?
    added
  rescue Exception => e
    log("Could not patch fiddle error methods (#{e.class}: #{e.message}).")
    nil
  end

  def self.init
    return @available if @started
    @started = true
    snd    = sound_file
    dll    = locate("beacon.dll")
    phonon = locate("phonon.dll")
    snd = convert_ogg if snd.nil?
    if snd.nil? && locate("beacon.ogg")
      log("Found beacon.ogg, but the audio engine decodes WAV and MP3 only - not OGG Vorbis - and ffmpeg was not available to convert it. Run:  ruby tools/set_beacon_sound.rb Data/audio/beacon.ogg  from a shell that has ffmpeg. Speaking directions instead for now.")
      return false
    end
    unless dll && phonon && snd
      log("Steam Audio mode off: need patch/lib/beacon.dll, patch/lib/phonon.dll and patch/audio/beacon.wav. Speaking directions instead.")
      return false
    end
    begin
      require 'fiddle'
      # NOTE: no `require 'fiddle/import'` here, deliberately.
      #
      # Reborn's version uses Fiddle::Importer, whose `extern "void f(float)"`
      # DSL lives in fiddle/import.rb. Desolation's Ruby has fiddle compiled
      # into x64-msvcrt-ruby310.dll but ships no stdlib tree, and only some of
      # fiddle's Ruby-level files came along with it: closure, function, handle
      # and memory_view are there; import, cparser, struct, value, pack, types
      # and version are NOT. So `require 'fiddle/import'` raises LoadError and
      # the whole beacon falls back to speech - which is exactly what the log
      # said when the game first ran this.
      #
      # Fiddle::Importer is only a convenience wrapper. Fiddle::Handle and
      # Fiddle::Function are C-level and always present, so binding through
      # them directly needs no .rb files at all and works in both games.
      patch_fiddle_error_methods
      # phonon.dll MUST be resident before beacon.dll loads, or Windows cannot
      # resolve the import of it inside beacon.dll. Keeping the handle in an
      # ivar is what stops it being collected and unloaded again.
      @phonon_handle ||= Fiddle::Handle.new(phonon)
      @lib_handle    ||= Fiddle::Handle.new(dll)
      h = @lib_handle

      @fn ||= {
        :init  => Fiddle::Function.new(h["beacon_init"],  [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT),
        :ready => Fiddle::Function.new(h["beacon_ready"], [], Fiddle::TYPE_INT),
        :start => Fiddle::Function.new(h["beacon_start"], [], Fiddle::TYPE_INT),
        :stop  => Fiddle::Function.new(h["beacon_stop"],  [], Fiddle::TYPE_VOID),
        :dir   => Fiddle::Function.new(h["beacon_set_direction"],
                    [Fiddle::TYPE_FLOAT, Fiddle::TYPE_FLOAT, Fiddle::TYPE_FLOAT], Fiddle::TYPE_VOID),
        :gain  => Fiddle::Function.new(h["beacon_set_gain"],   [Fiddle::TYPE_FLOAT], Fiddle::TYPE_VOID),
        :tune  => Fiddle::Function.new(h["beacon_set_tuning"],
                    [Fiddle::TYPE_FLOAT, Fiddle::TYPE_FLOAT], Fiddle::TYPE_VOID),
        :err   => Fiddle::Function.new(h["beacon_last_error"], [], Fiddle::TYPE_VOIDP)
      }

      rc = @fn[:init].call(snd)
      if rc != 0
        log("Steam Audio init failed (code #{rc}: #{last_error}). Speaking directions instead.")
        @available = false
        return false
      end
      @fn[:tune].call(PITCH_RANGE, BACK_DAMP)
      @available = true
      log("Steam Audio HRTF beacon ready (sound: #{snd}).")
      true
    rescue Exception => e
      log("Steam Audio load failed (#{e.class}: #{e.message}). Speaking directions instead.")
      @available = false
      false
    end
  end

  # beacon_last_error returns char*, which comes back as an address.
  def self.last_error
    addr = @fn[:err].call
    return "" if addr.nil? || addr.to_i == 0
    Fiddle::Pointer.new(addr).to_s
  rescue Exception
    ""
  end

  # Point the beacon along the next route step.
  #
  # Steam Audio is right-handed: +x right, +y up, -z FORWARD. Game grid:
  # +x east, +y south. North (up) => dy negative => z negative => in front of
  # you, so passing (dx, 0, dy) through unrotated is already correct.
  #
  # DELIBERATELY NOT ROTATED BY YOUR FACING - THE BEACON IS A COMPASS.
  # A head-relative version was tried and removed at the player's request: in
  # this game walking always turns you, so the beacon swung with every step and
  # every turn, and a cue that keeps moving on its own is worse than one that
  # holds still. Screen-fixed, like Reborn: up on the map is always "in front",
  # down is always "behind" - lower in pitch and muffled - whichever way your
  # character sprite happens to face. Learn it once and it never shifts.
  def self.point(dx, dy, dist)
    return false unless @available
    @fn[:dir].call(dx.to_f, 0.0, dy.to_f)
    gain = 0.35 + (0.65 * (1.0 - [dist / 25.0, 1.0].min)) # louder as you close in
    @fn[:gain].call(gain)
    unless @playing
      @fn[:start].call
      @playing = true
    end
    true
  rescue Exception => e
    log("point error: #{e.message}")
    false
  end

  def self.stop
    return unless @available && @playing
    begin
      @fn[:stop].call
    rescue Exception
    end
    @playing = false
  end

  # ---------------------------------------------------------------------------
  # Startup probe.
  #
  # Everything about Steam Audio here hangs on one question: can THIS Ruby -
  # the one embedded in x64-msvcrt-ruby310.dll, not whatever is on your PATH -
  # require fiddle? Running tools/check_beacon_audio.rb answers it for the
  # system Ruby, which is not the same interpreter and so is not proof.
  #
  # So this asks the real one, at load, and writes the answer to
  # beacon_error.txt. It requires fiddle and nothing else: no DLLs are opened,
  # no audio device is created, phonon.dll (53 MB) is not touched. The full
  # init stays lazy, on the first Shift+B.
  #
  # If beacon_error.txt says "fiddle: yes", Steam Audio can work in this game.
  # ---------------------------------------------------------------------------
  def self.probe
    return if @probed
    @probed = true
    where = { "sound" => sound_file, "beacon.dll" => locate("beacon.dll"),
              "phonon.dll" => locate("phonon.dll") }
    missing = where.select { |_, v| v.nil? }.keys
    begin
      require 'fiddle'
      # Bare `require 'fiddle'` is not the real question - Reborn's version also
      # needs fiddle/import, which Desolation does NOT have. What actually
      # matters is Handle, Function and a float type, so check for those.
      unless defined?(Fiddle::Handle) && defined?(Fiddle::Function) &&
             defined?(Fiddle::TYPE_FLOAT)
        raise LoadError, "fiddle loaded but Handle/Function/TYPE_FLOAT missing"
      end
      @fiddle = true
    rescue Exception => e
      @fiddle = false
      @fiddle_error = "#{e.class}: #{e.message}"
    end
    log("startup probe | ruby #{RUBY_VERSION} #{RUBY_PLATFORM} | " \
        "fiddle: #{@fiddle ? "yes" : "NO (#{@fiddle_error})"} | " \
        "files: #{missing.empty? ? "all present" : "MISSING #{missing.join(', ')}"}" \
        "#{where["sound"] ? " | sound: #{where["sound"]}" : ""}")
  rescue Exception
    nil
  end

  def self.fiddle?
    @fiddle
  end
end

# Ask the question at load, so simply starting the game answers it.
PraBeaconAudio.probe

#==============================================================================
# Beacon state
#==============================================================================
module PraBeacon
  ARRIVED_SOUND = "Entering Door"    # Desolation ships this one
  ARRIVED_VOLUME = 80

  # Fallback only, when Steam Audio could not load. RGSS cannot pan, so the
  # direction is spoken rather than placed.
  BASE_INTERVAL = 45                 # frames between spoken cues, far away
  MIN_INTERVAL  = 20                 # ...and close up
  NEAR_TILES    = 20.0

  class << self
    attr_accessor :active, :target, :counter, :no_path_announced
    attr_accessor :route_cache, :last_pos, :recalc, :last_spoken_dir
  end
  self.active = false
  self.target = nil
  self.counter = 0
  self.no_path_announced = false
  self.route_cache = nil
  self.last_pos = nil
  self.recalc = 0
  self.last_spoken_dir = nil

  def self.reset
    self.active = false
    self.target = nil
    self.route_cache = nil
    self.last_pos = nil
    self.recalc = 0
    self.counter = 0
    self.no_path_announced = false
    self.last_spoken_dir = nil
  end
end

#==============================================================================
# Player hook
#==============================================================================
class Game_Player < Game_Character
  unless method_defined?(:pra_beacon_original_update)
    alias_method :pra_beacon_original_update, :update
    def update
      pra_beacon_original_update
      pra_beacon_handle_input
      pra_beacon_tick
    end
  end

  def pra_beacon_handle_input
    return if $game_temp && ($game_temp.in_battle || $game_temp.message_window_showing)
    if Input.pressex?(0x10) && Input.triggerex?(0x42) # Shift + B
      pra_beacon_toggle
    end
  rescue Exception
    nil
  end

  def pra_beacon_play_arrival
    file = PraBeaconAudio.arrival_file
    file ||= "Audio/SE/#{PraBeacon::ARRIVED_SOUND}.ogg"
    return unless (defined?(safeExists?) ? safeExists?(file) : File.exist?(file))
    Audio.se_play(file, PraBeacon::ARRIVED_VOLUME, 100)
  rescue Exception
    nil
  end

  def pra_beacon_toggle
    # Options -> Directional Beacon.
    if defined?(A11ySettings) && !A11ySettings.on?(:beacon)
      tts("The directional beacon is switched off in Options.")
      return
    end
    if PraBeacon.active
      PraBeacon.reset
      PraBeaconAudio.stop
      tts("Beacon off.")
      return
    end
    tgt = pra_beacon_selected_target
    unless tgt
      tts("No target selected. Use J and L to pick one first.")
      return
    end
    PraBeaconAudio.init # lazy: sets up HRTF the first time, else speech fallback
    PraBeacon.reset
    PraBeacon.target = tgt
    PraBeacon.active = true
    label = tgt[:name] && !tgt[:name].empty? ? tgt[:name] : "target"
    mode = PraBeaconAudio.available ? "3D beacon" : "Beacon"
    tts("#{mode} tracking #{label}.")
  end

  def pra_beacon_selected_target
    return nil unless defined?(PraSession) && PraSession.respond_to?(:selected_event_index)
    idx = PraSession.selected_event_index
    list = PraSession.mapevents
    return nil if idx.nil? || idx < 0 || list.nil? || list[idx].nil?
    ev = list[idx]
    cands = (ev.respond_to?(:candidates) && ev.candidates) ? ev.candidates.map { |c| [c[0], c[1]] } : []
    # Prefer the name you actually hear when you press K.
    label = nil
    label = ev.custom_name if ev.respond_to?(:custom_name) && ev.custom_name
    label = ev.name if label.nil? || label.to_s.strip.empty?
    real = (defined?(VirtualEvent) && ev.is_a?(VirtualEvent)) ? nil : ev
    { map_id: $game_map.map_id, x: ev.x, y: ev.y, candidates: cands, name: (label rescue nil), event: real }
  rescue Exception
    nil
  end

  def pra_beacon_route
    t = PraBeacon.target
    return [] unless t && t[:map_id] == $game_map.map_id
    # The pathfinder's shared search, so P and the beacon always agree on
    # whether a target is reachable. The code below is the fallback for a
    # pathfinder too old to have it.
    if respond_to?(:a11y_best_route)
      return a11y_best_route(t[:x], t[:y], t[:candidates], t[:event])
    end
    if t[:candidates] && !t[:candidates].empty?
      t[:candidates].each do |tile|
        r = aStern(Node.new(@x, @y), Node.new(tile[0], tile[1]))
        return r unless r.empty?
      end
    end
    r = aStern(Node.new(@x, @y), Node.new(t[:x], t[:y]))
    return r unless r.empty?
    [[t[:x] + 1, t[:y]], [t[:x] - 1, t[:y]], [t[:x], t[:y] + 1], [t[:x], t[:y] - 1]].each do |ax, ay|
      alt = aStern(Node.new(@x, @y), Node.new(ax, ay))
      return alt unless alt.empty?
    end
    []
  rescue Exception
    []
  end

  def pra_beacon_arrive
    PraBeaconAudio.stop
    pra_beacon_play_arrival
    tts("Arrived.")
    PraBeacon.reset
  end

  def pra_beacon_tick
    return unless PraBeacon.active && PraBeacon.target
    return if $game_temp && ($game_temp.in_battle || $game_temp.message_window_showing)

    t = PraBeacon.target
    if t[:map_id] != $game_map.map_id
      tts("Beacon target is on another map. Beacon off.")
      PraBeacon.reset
      PraBeaconAudio.stop
      return
    end

    dist = Math.sqrt((t[:x] - @x)**2 + (t[:y] - @y)**2)
    if (t[:x] - @x).abs <= 1 && (t[:y] - @y).abs <= 1
      pra_beacon_arrive
      return
    end

    PraBeacon.recalc = PraBeacon.recalc.to_i + 1
    moved = (PraBeacon.last_pos != [@x, @y])
    rc = PraBeacon.route_cache

    # Walking ALONG the route costs nothing: stepping onto its next tile just
    # consumes that tile. The full search only runs when the route is stale,
    # missing, or you wander off it. Before this, every single step re-ran
    # A* - and with no path, several exhausted searches PER STEP, which froze
    # event-dense maps like Keneph Jungle (a player report).
    if rc && !rc.empty? && moved && rc[0].x == @x && rc[0].y == @y
      rc.shift
      PraBeacon.last_pos = [@x, @y]
      PraBeacon.recalc   = 0
      moved = false
    end

    need = if PraBeacon.route_cache.nil?
             true
           elsif PraBeacon.no_path_announced
             # No path last time. Standing still cannot create one, so only
             # retry once the player has moved, and at most every 2 seconds.
             moved && PraBeacon.recalc >= 120
           elsif PraBeacon.route_cache.empty?
             true
           else
             moved || PraBeacon.recalc >= 60
           end
    if need
      PraBeacon.route_cache = pra_beacon_route
      PraBeacon.last_pos    = [@x, @y]
      PraBeacon.recalc      = 0
    elsif moved
      PraBeacon.last_pos = [@x, @y]
    end
    route = PraBeacon.route_cache
    if route.nil? || route.empty?
      if dist <= 2.5
        pra_beacon_arrive
        return
      end
      PraBeaconAudio.stop
      unless PraBeacon.no_path_announced
        tts("No path to the beacon target from here.")
        PraBeacon.no_path_announced = true
      end
      return
    end
    PraBeacon.no_path_announced = false

    # The 3D beacon: continuously position a looping source, updated every tick
    # so the direction and loudness track you smoothly.
    if PraBeaconAudio.available
      PraBeaconAudio.point(route[0].x - @x, route[0].y - @y, dist)
    end

    # Spoken directions, which are now a setting of their own rather than only
    # a fallback. Options -> Spoken Directions:
    #   0  If no 3D sound   speak only when Steam Audio could not start
    #   1  Always           speak as well as the 3D beacon
    #   2  Never            stay quiet even with no 3D beacon at all
    return unless pra_beacon_should_speak?

    # Only when the direction changes, or on a slow timer that tightens as you
    # close in, so it does not talk over everything else.
    dir = findRelativeDirection(Node.new(@x, @y), route[0])
    closeness = 1.0 - [dist / PraBeacon::NEAR_TILES, 1.0].min
    interval = (PraBeacon::BASE_INTERVAL -
                (PraBeacon::BASE_INTERVAL - PraBeacon::MIN_INTERVAL) * closeness).to_i
    PraBeacon.counter = PraBeacon.counter.to_i + 1
    changed = (dir != PraBeacon.last_spoken_dir)
    return unless changed || PraBeacon.counter >= interval
    PraBeacon.counter = 0
    PraBeacon.last_spoken_dir = dir
    tts(dir)
  rescue Exception
    nil
  end

  def pra_beacon_should_speak?
    mode = defined?(A11ySettings) ? A11ySettings.get(:spoken_directions) : 0
    case mode
    when 1 then true                      # Always
    when 2 then false                     # Never
    else !PraBeaconAudio.available        # If no 3D sound
    end
  rescue Exception
    !PraBeaconAudio.available
  end
end

# The beacon PAUSES for battles. Game_Player#update stops running the moment a
# battle begins, so nothing in the normal tick can silence the loop - it would
# simply drone through the whole fight. The game's own battle events are the
# reliable signal: stop the audio at battle start, and leave PraBeacon.active
# and the target alone, so the first map tick after the battle points the
# source again and the loop starts itself - a pause, not a cancel.
#
# The global guard is what stops an F12 soft reset stacking a second handler
# every time the mods reload; globals survive reloads, module state may not.
if defined?(Events) && Events.respond_to?(:onStartBattle) && !$a11y_beacon_battle_pause_hooked
  $a11y_beacon_battle_pause_hooked = true
  Events.onStartBattle += proc { |*args|
    begin
      PraBeaconAudio.stop
    rescue Exception
    end
  }
end

# In Desolation, Events.onStartBattle turned out to be triggered ONLY by the
# battle test environment - a real wild or trainer battle never fires it, so
# the hook above sat armed and useless and the beacon droned through fights
# (a player caught this). Every real battle DOES go through the battle
# scene's pbStartBattle, so the pause rides that instead. Both hooks stay:
# stopping an already-stopped beacon is a no-op.
if defined?(PokeBattle_Scene) && PokeBattle_Scene.method_defined?(:pbStartBattle)
  class PokeBattle_Scene
    unless method_defined?(:pra_beacon_start_battle)
      alias_method :pra_beacon_start_battle, :pbStartBattle
      def pbStartBattle(*args)
        begin
          PraBeaconAudio.stop
        rescue Exception
        end
        pra_beacon_start_battle(*args)
      end
    end
  end
end

# Leaving the map invalidates the route, and a stuck looping beacon would carry
# into a cutscene or a battle.
class Scene_Map
  unless method_defined?(:pra_beacon_map_main)
    alias_method :pra_beacon_map_main, :main
    def main
      PraBeaconAudio.stop rescue nil
      PraBeacon.reset rescue nil
      pra_beacon_map_main
    end
  end
end
