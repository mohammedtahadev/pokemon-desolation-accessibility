# Exercises AccessibilityBeacon: target selection, guiding, arrival, losing the
# path, and the spoken fallback used when Steam Audio is not available.
#
#   ruby test_beacon.rb ../patch/Mods/AccessibilityBeacon.rb
#
# This runs from accessibility_tests, so the mod's SEARCH_DIRS ("patch/lib",
# "patch/audio", ".") do NOT find the real DLLs and it takes the fallback path.
# That is deliberate: the tests must not load a 53 MB audio engine or make
# noise. Whether Steam Audio itself loads is checked separately, by
# tools/check_beacon_audio.rb, which has to run from the game folder.
$pass = 0; $fail = 0
def check(c, n); c ? ($pass += 1; puts "PASS: #{n}") : ($fail += 1; puts "FAIL: #{n}"); end
def check_eq(a, e, n)
  if a == e then $pass += 1; puts "PASS: #{n}"
  else $fail += 1; puts "FAIL: #{n}\n        expected: #{e.inspect}\n        actual:   #{a.inspect}" end
end

$spoken = []
def tts(text, interrupt = false); $spoken << text.to_s; end

# Stands in for AccessibilityOptions, which the beacon consults for the
# Directional Beacon and Spoken Directions settings.
module A11ySettings
  DEFAULTS = { :beacon => 0, :spoken_directions => 0 }
  @values = {}
  class << self
    def get(k); @values.key?(k) ? @values[k] : DEFAULTS[k]; end
    def set(k, v); @values[k] = v; end
    def on?(k); get(k) == 0; end
    def reset; @values = {}; end
  end
end
$played = []
module Audio; def self.se_play(f, v = nil, p = nil); $played << f.to_s; end; end
def safeExists?(f); $existing_files.include?(f); end
$existing_files = ["Audio/SE/Entering Door.ogg"]

class Game_Character
  attr_accessor :x, :y
  def initialize; @x = 0; @y = 0; end
  def update; $updated = true; end
end

# The pathfinder supplies these; the beacon calls them.
class Game_Player < Game_Character
  class Node
    attr_accessor :x, :y
    def initialize(x, y); @x = x; @y = y; end
  end
  # Route the test wants aStern to return, or :none for "no path".
  def self.route=(r); @route = r; end
  def self.route; @route; end
  def aStern(a, b)
    r = Game_Player.route
    return [] if r.nil? || r == :none
    r.map { |x, y| Node.new(x, y) }
  end
  def findRelativeDirection(from, to)
    return from.y < to.y ? "down" : "up" if from.x == to.x
    from.x < to.x ? "right" : "left"
  end
end

class Scene_Map; def main; :ran; end; end

# Real battles enter through the battle scene - in Desolation the event bus
# below never fires outside the battle test environment.
class PokeBattle_Scene
  def pbStartBattle(battle); $battles_started = ($battles_started || 0) + 1; end
end

# The game's battle event bus, recording what gets subscribed.
$battle_start_handlers = []
module Events
  class Bus
    def initialize(store); @store = store; end
    def +(handler); @store << handler; self; end
  end
  def self.respond_to?(m, include_all = false)
    m == :onStartBattle ? true : super
  end
  def self.onStartBattle; Bus.new($battle_start_handlers); end
  def self.onStartBattle=(v); v; end
end
class MapStub; def map_id; 1; end; end
class TempStub; attr_accessor :in_battle, :message_window_showing; end
$game_map = MapStub.new
$game_temp = TempStub.new

module Input
  @shift = false; @b = false
  class << self
    attr_accessor :shift, :b
    def pressex?(k);   k == 0x10 && @shift; end
    def triggerex?(k); k == 0x42 && @b; end
  end
end
def press_shift_b; Input.shift = true; Input.b = true; end
def release_keys;  Input.shift = false; Input.b = false; end

module PraSession
  class << self; attr_accessor :selected_event_index, :mapevents; end
  self.selected_event_index = -1
  self.mapevents = []
end
Ev = Struct.new(:x, :y, :name, :custom_name, :candidates)

mod = File.expand_path(ARGV[0] || "../patch/Mods/AccessibilityBeacon.rb")
ok = true
begin
  load mod
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
  puts "        #{e.backtrace.first(3).join("\n        ")}"
end
check ok, "the mod loads with no error"

# Running from here, the binaries are out of reach, so it must degrade quietly.
check_eq PraBeaconAudio.init, false, "with no DLLs in reach, Steam Audio stays off"
check_eq PraBeaconAudio.available, false, "and reports itself unavailable"
ok = true
begin
  PraBeaconAudio.point(1, 0, 5.0)
  PraBeaconAudio.stop
rescue Exception => e
  ok = false; puts "        #{e.class}: #{e.message}"
end
check ok, "pointing and stopping an unavailable beacon does nothing rather than crash"

# ── The startup probe ───────────────────────────────────────────────────────
# The whole Steam Audio question is "can THIS interpreter require fiddle?", and
# the probe is what asks it inside the game rather than outside.
check File.exist?("beacon_error.txt"), "loading the mod writes a startup probe line"
probe_line = File.readlines("beacon_error.txt").grep(/startup probe/).last.to_s
check !probe_line.empty?, "the line is there to be read"
check probe_line.include?(RUBY_VERSION),
      "it records which Ruby asked - the point of the whole exercise"
check probe_line =~ /fiddle: (yes|NO)/, "and whether fiddle is available"
check [true, false].include?(PraBeaconAudio.fiddle?), "the answer is readable in code"
before = File.read("beacon_error.txt")
PraBeaconAudio.probe
check_eq File.read("beacon_error.txt"), before, "probing twice does not write twice"

# -- The beacon is a compass, on purpose -------------------------------------
# A head-relative version (rotating the sound by the sprite facing) was tried
# and REMOVED at the player's request: walking always turns you in this game,
# so the beacon swung with every step. Screen-fixed is what Reborn ships and
# what the player asked to keep - north is always in front, south always
# behind. These pin that decision so it does not quietly come back.
check !PraBeaconAudio.respond_to?(:listener_space),
      "no facing rotation exists - the beacon is screen-fixed, as requested"
check_eq PraBeaconAudio.method(:point).arity, 3,
         "point takes dx, dy, dist and no facing argument"

# ── The fiddle bookkeeping shim ────────────────────────────────────────────
# Ruby 3.1's fiddle calls back into Fiddle.win32_last_error= after every FFI
# call. That method lives in the pure-Ruby fiddle.rb, which Desolation does not
# ship, so the game died with:
#
#   NoMethodError: undefined method `win32_last_error=' for Fiddle:Module
#
# Note this CANNOT be reproduced on Ruby 3.2, which does not make that callback
# - so the test checks the shim supplies the methods, which is the part that
# matters and is version-independent.
require 'fiddle'
removed = []
[:win32_last_error, :win32_last_error=, :win32_last_socket_error,
 :win32_last_socket_error=, :last_error, :last_error=].each do |m|
  if Fiddle.respond_to?(m)
    Fiddle.singleton_class.send(:remove_method, m)
    removed << m
  end
end
check !Fiddle.respond_to?(:win32_last_error=), "the game's missing method is simulated"

added = PraBeaconAudio.patch_fiddle_error_methods
check Fiddle.respond_to?(:win32_last_error=), "the shim supplies win32_last_error="
check Fiddle.respond_to?(:win32_last_error), "and its reader"
check Fiddle.respond_to?(:last_error=), "and last_error=, which Function#call also uses"
check Fiddle.respond_to?(:win32_last_socket_error=), "and the socket pair"
Fiddle.win32_last_error = 42
check_eq Fiddle.win32_last_error, 42, "the shim actually stores and returns a value"
Fiddle.last_error = 7
check_eq Fiddle.last_error, 7, "and so does last_error"
check_eq Thread.current[:__FIDDLE_WIN32_LAST_ERROR__], 42,
         "in the same thread-local slot fiddle.rb uses, not a private one"

# It must leave a Ruby that already HAS these alone.
PraBeaconAudio.instance_variable_set(:@fiddle_patched, false)
again = PraBeaconAudio.patch_fiddle_error_methods
check_eq again, [], "with the methods already present it adds nothing"

# ── Where it looks for the sound, and what it will accept ──────────────────
check_eq PraBeaconAudio::SEARCH_DIRS.first, "Data/audio",
         "Data/audio is searched first, so a sound you drop there wins"
check PraBeaconAudio::PLAYABLE.include?("beacon.wav"), "WAV is accepted"
check PraBeaconAudio::PLAYABLE.include?("beacon.mp3"), "so is MP3"
check !PraBeaconAudio::PLAYABLE.any? { |n| n.end_with?(".ogg") },
      "OGG is NOT, because miniaudio cannot decode Vorbis - every sound " \
      "Desolation ships is .ogg, so this is the easy mistake to make"

require "fileutils"
begin
  FileUtils.mkdir_p("Data/audio")
  check_eq PraBeaconAudio.sound_file, nil, "with no playable sound anywhere, there is none"

  File.binwrite("Data/audio/beacon.ogg", "OggS")
  check_eq PraBeaconAudio.sound_file, nil, "an ogg on its own is still not playable"

  File.binwrite("Data/audio/beacon.wav", "RIFF")
  found = PraBeaconAudio.sound_file
  check found && found.downcase.include?("data"),
        "a wav in Data/audio IS found, and beats the ogg beside it"
  check found && (found.include?(92.chr) || found.include?("/")),
        "and comes back as an absolute path, which fiddle requires"
ensure
  FileUtils.rm_rf("Data")
end

player = Game_Player.new
player.x = 5; player.y = 5

# ── Toggling with nothing selected ──────────────────────────────────────────
$spoken = []
PraSession.selected_event_index = -1
player.pra_beacon_toggle
check $spoken.any? { |s| s =~ /no target/i }, "toggling with nothing selected says so"
check_eq PraBeacon.active, false, "and does not switch on"

# ── Toggling with a target ──────────────────────────────────────────────────
PraSession.mapevents = [Ev.new(10, 5, "EV001", "Hiker", nil)]
PraSession.selected_event_index = 0
Game_Player.route = [[6, 5], [7, 5], [8, 5], [9, 5], [10, 5]]
$spoken = []
player.pra_beacon_toggle
check_eq PraBeacon.active, true, "toggling with a target switches the beacon on"
check $spoken.any? { |s| s =~ /Hiker/ }, "and says which target, by the name you hear on K"
check_eq PraBeacon.target[:x], 10, "the target coordinates are stored"

# ── Guiding: the spoken fallback ────────────────────────────────────────────
$spoken = []
player.pra_beacon_tick
check_eq $spoken.first, "right", "the first cue says which way to go"
$spoken = []
30.times { player.pra_beacon_tick }
check $spoken.empty? || $spoken.uniq == ["right"],
      "it does not chatter while the direction is unchanged"

# A turn in the route must be announced immediately.
player.x = 8
Game_Player.route = [[8, 4], [8, 3]]
$spoken = []
player.pra_beacon_tick
check_eq $spoken.first, "up", "a change of direction is spoken at once"

# ── Arrival ─────────────────────────────────────────────────────────────────
$spoken = []; $played = []
player.x = 10; player.y = 5              # adjacent to the target at 10,5
player.pra_beacon_tick
check $spoken.any? { |s| s =~ /arrived/i }, "arriving is announced"
check $played.any? { |f| f =~ /Entering Door/ }, "and plays the arrival chime"
check_eq PraBeacon.active, false, "the beacon switches itself off on arrival"
check_eq PraBeacon.target, nil, "and forgets the target"

# A sound you supply beats the game's own SE, and may be .ogg because this one
# plays through the GAME's audio engine, not beacon.dll.
require "fileutils"
begin
  FileUtils.mkdir_p("Data/audio")
  File.binwrite("Data/audio/arrive.ogg", "OggS")
  $existing_files << "Data/audio/arrive.ogg"
  check_eq PraBeaconAudio.arrival_file, "Data/audio/arrive.ogg",
           "an arrive.ogg you supply is found"
  $spoken = []; $played = []
  PraSession.mapevents = [Ev.new(10, 5, "EV009", "Hiker", nil)]
  PraSession.selected_event_index = 0
  Game_Player.route = [[10, 5]]
  player.x = 0; player.y = 0
  player.pra_beacon_toggle
  player.x = 10; player.y = 5
  player.pra_beacon_tick
  check $played.any? { |f| f =~ /arrive\.ogg/ }, "and is what plays on arrival"
  check !$played.any? { |f| f =~ /Entering Door/ }, "instead of the game's SE"
ensure
  FileUtils.rm_rf("Data")
  $existing_files.delete("Data/audio/arrive.ogg")
end
check_eq PraBeaconAudio.arrival_file, nil, "with nothing supplied there is no override"

# ── Spoken Directions: three modes, not just a fallback ────────────────────
def guide_and_listen(player)
  PraBeacon.reset
  PraSession.mapevents = [Ev.new(10, 5, "EV010", "Hiker", nil)]
  PraSession.selected_event_index = 0
  Game_Player.route = [[6, 5], [7, 5]]
  player.x = 5; player.y = 5
  player.pra_beacon_toggle
  $spoken = []
  player.pra_beacon_tick
  $spoken.dup
end

# Steam Audio is unavailable here (no DLLs in reach), which is the case the
# three modes have to disagree about.
check_eq PraBeaconAudio.available, false, "3D is unavailable in this harness"

A11ySettings.set(:spoken_directions, 0)   # If no 3D sound
check guide_and_listen(player).include?("right"),
      "mode 'If no 3D sound' speaks when there is no 3D"

A11ySettings.set(:spoken_directions, 2)   # Never
check !guide_and_listen(player).include?("right"),
      "mode 'Never' stays quiet even with no 3D at all"

A11ySettings.set(:spoken_directions, 1)   # Always
check guide_and_listen(player).include?("right"), "mode 'Always' speaks"
A11ySettings.set(:spoken_directions, 0)

# ── The master switch ──────────────────────────────────────────────────────
A11ySettings.set(:beacon, 1)              # Directional Beacon = Off
PraBeacon.reset
$spoken = []
PraSession.selected_event_index = 0
player.pra_beacon_toggle
check_eq PraBeacon.active, false, "with the beacon switched off, Shift+B does nothing"
check $spoken.any? { |s| s =~ /switched off in Options/i }, "and says why"
A11ySettings.set(:beacon, 0)
PraBeacon.reset

# ── No path ─────────────────────────────────────────────────────────────────
player.x = 0; player.y = 0
PraSession.mapevents = [Ev.new(30, 30, "EV002", nil, nil)]
PraSession.selected_event_index = 0
player.pra_beacon_toggle
Game_Player.route = :none
$spoken = []
player.pra_beacon_tick
check $spoken.any? { |s| s =~ /no path/i }, "an unreachable target says so"
$spoken = []
10.times { player.pra_beacon_tick }
check $spoken.empty?, "but only once, not every frame"

# ── Turning it off ──────────────────────────────────────────────────────────
$spoken = []
player.pra_beacon_toggle
check $spoken.any? { |s| s =~ /beacon off/i }, "toggling again turns it off"
check_eq PraBeacon.active, false, "and it stays off"
$spoken = []
10.times { player.pra_beacon_tick }
check $spoken.empty?, "a beacon that is off says nothing at all"

# ── It must be silent in battle and mid-message ─────────────────────────────
PraSession.mapevents = [Ev.new(10, 5, "EV003", "Hiker", nil)]
PraSession.selected_event_index = 0
Game_Player.route = [[1, 0]]
player.x = 0; player.y = 0
player.pra_beacon_toggle
$game_temp.in_battle = true
$spoken = []
10.times { player.pra_beacon_tick }
check $spoken.empty?, "the beacon is silent during a battle"
$game_temp.in_battle = false
$game_temp.message_window_showing = true
$spoken = []
10.times { player.pra_beacon_tick }
check $spoken.empty?, "and while a message is on screen"
$game_temp.message_window_showing = false

# ── The key, and the update chain ───────────────────────────────────────────
check Game_Player.method_defined?(:pra_beacon_original_update),
      "Game_Player#update is hooked"
$updated = false
release_keys
player.update
check $updated, "the original update still runs"

PraBeacon.reset
release_keys
$spoken = []
press_shift_b
player.update
check_eq PraBeacon.active, true, "Shift+B switches the beacon on"
release_keys
$spoken = []
press_shift_b
player.update
check_eq PraBeacon.active, false, "and Shift+B again switches it off"
release_keys

# ── A battle PAUSES the beacon, and only pauses it ─────────────────────────
# Game_Player#update stops running in battle, so the loop would drone through
# the whole fight unless the battle-start event silences it. Active state and
# the target must survive, so it resumes by itself afterwards.
check_eq $battle_start_handlers.length, 1, "exactly one battle-start handler is registered"
2.times { load mod }
check_eq $battle_start_handlers.length, 1,
         "and a soft reset does not stack more of them"

PraBeacon.reset
PraSession.mapevents = [Ev.new(10, 5, "EV020", "Hiker", nil)]
PraSession.selected_event_index = 0
Game_Player.route = [[6, 5]]
player.x = 5; player.y = 5
player.pra_beacon_toggle
PraBeaconAudio.instance_variable_set(:@available, true)
PraBeaconAudio.instance_variable_set(:@fn, { :stop => proc { } })
PraBeaconAudio.instance_variable_set(:@playing, true)   # as if the loop runs
$battle_start_handlers.each { |h| h.call }
check_eq PraBeaconAudio.playing, false, "battle start stops the beacon loop"
check_eq PraBeacon.active, true, "but the beacon stays ACTIVE - it is a pause"
check PraBeacon.target != nil, "and the target survives, so it resumes after"

# The path REAL battles take: the scene's pbStartBattle. A player caught the
# beacon droning through fights because Desolation never fires the event bus
# outside its battle test environment.
PraBeaconAudio.instance_variable_set(:@playing, true)   # loop running again
$battles_started = 0
PokeBattle_Scene.new.pbStartBattle(:battle)
check_eq $battles_started, 1, "pbStartBattle still starts the real battle"
check_eq PraBeaconAudio.playing, false,
         "and stops the beacon - the fix for the beacon droning through fights"
check_eq PraBeacon.active, true, "still a pause, not a cancel"
PraBeaconAudio.instance_variable_set(:@available, false)
PraBeaconAudio.instance_variable_set(:@fn, nil)
PraBeacon.reset

# ── Changing map drops the beacon ───────────────────────────────────────────
PraSession.selected_event_index = 0
player.pra_beacon_toggle
Scene_Map.new.main
check_eq PraBeacon.active, false, "leaving the map switches the beacon off"

# A target left over from another map must not steer you around this one.
PraBeacon.reset
PraBeacon.active = true
PraBeacon.target = { map_id: 99, x: 3, y: 3, candidates: [], name: "Elsewhere" }
$spoken = []
player.pra_beacon_tick
check $spoken.any? { |s| s =~ /another map/i }, "a target on another map is reported"
check_eq PraBeacon.active, false, "and the beacon stops"

# ── Reloading ───────────────────────────────────────────────────────────────
ok = true
begin
  2.times { load mod }
  release_keys
  player.update
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
end
check ok, "a soft reset reloads it without recursing"

File.delete("beacon_error.txt") if File.exist?("beacon_error.txt")

puts "=" * 56
puts " RESULTS: #{$pass} passed, #{$fail} failed"
puts "=" * 56
exit($fail == 0 ? 0 : 1)
