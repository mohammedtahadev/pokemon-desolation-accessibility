# Loads the ported pathfinder against Desolation-shaped stubs to prove it has
# no load-time errors, that the guards hold on a second load, and that the
# features the newer Reborn version added (points of interest, notes, the map
# connection scan, the extra filters) actually run here.
#
#   ruby test_pathfind.rb ../patch/Mods/AccessibilityPathfind.rb
#
# The stubs mirror Desolation's own signatures, not Reborn's, so a method the
# port needs that Desolation spells differently shows up as a failure here
# rather than as a crash in play.
$pass = 0; $fail = 0
def check(c, n); c ? ($pass += 1; puts "PASS: #{n}") : ($fail += 1; puts "FAIL: #{n}"); end

MAP_W = 20
MAP_H = 15

class Game_Character
  attr_accessor :x, :y, :direction, :through, :character_name
  def initialize; @x = 5; @y = 5; @direction = 2; @through = false; @character_name = ""; end
  def update; end
  def moving?; false; end
  def passable?(x, y, d); true; end
  def map; $game_map; end
  def move_down(t = true); @y += 1; end
  def move_left(t = true); @x -= 1; end
  def move_right(t = true); @x += 1; end
  def move_up(t = true); @y -= 1; end
  def screen_x; 0; end
  def screen_y; 0; end
  def opacity; 255; end
end
class Game_Player < Game_Character; end
# RPG::EventCommand-shaped: the mod reads .code and .parameters off every one.
class Cmd
  attr_accessor :code, :parameters
  def initialize(code, parameters = []); @code = code; @parameters = parameters; end
end
SHOW_TEXT = 101   # a sign or a talking NPC
TRANSFER  = 201   # a door or map transfer
SCRIPT    = 355   # pbPokemonMart lives in one of these
DONE      = 0

class Game_Event < Game_Character
  attr_accessor :id, :name, :list, :trigger
  def initialize(id = 1, name = "Ev", x = 0, y = 0, trigger = 0, list = nil)
    super()
    @id = id; @name = name; @x = x; @y = y; @trigger = trigger
    # list.size must be > 1 or populate_event_list skips the event entirely
    @list = list || [Cmd.new(SHOW_TEXT, ["Hello."]), Cmd.new(DONE)]
  end
end
class Game_Map
  attr_accessor :map_id, :events
  def initialize; @map_id = 1; @events = {}; end
  def name; "Test Map"; end
  def width; MAP_W; end
  def height; MAP_H; end
  def valid?(x, y); x >= 0 && y >= 0 && x < MAP_W && y < MAP_H; end
  def terrain_tag(x, y); 13; end
  def passable?(x, y, d, self_event = nil); true; end
  def passableStrict?(x, y, d, self_event = nil); true; end
end
class Scene_Map; def main; :ran; end; end
class Game_Temp; attr_accessor :in_battle, :message_window_showing; end
class Game_System; end
class Game_Variables
  def initialize; @d = {}; end
  def [](k); @d[k] || 0; end
  def []=(k, v); @d[k] = v; end
end
class PokemonMapMetadata
  attr_reader :movedEvents
  def initialize; @movedEvents = {}; end
  def addMovedEvent(id); @movedEvents[[1, id]] = true; end
end
class PBTerrain
  Ledge = 1; Water = 7; DeepWater = 5; StillWater = 6
  Waterfall = 8; WaterfallCrest = 9
end
def pbIsPassableWaterTag?(t); [5, 6, 7, 8, 9].include?(t); end

# Desolation's map factory: getMap(id), getNewMap(x, y) -> [map_or_id, x, y].
class MapFactoryStub
  attr_accessor :connections           # {[x, y] => connected_map_id}
  def initialize; @connections = {}; end
  def isPassable?(m, x, y, ev = nil); true; end
  def getMap(id); id == 2 ? OtherMap.new : nil; end
  def getNewMap(x, y)
    id = @connections[[x, y]]
    id ? [id, x, y] : nil
  end
end
class OtherMap; def map_id; 2; end; def name; "Next Door"; end; end

$MapFactory     = MapFactoryStub.new
$game_map       = Game_Map.new
$game_player    = Game_Player.new
$game_temp      = Game_Temp.new
$game_system    = Game_System.new
$game_variables = Game_Variables.new
class PokemonTempStub; end
$PokemonTemp = PokemonTempStub.new

# Text the mod asks for, queued up so create_poi and the rename prompts can be
# driven without a keyboard.
$freetext_queue = []
module Kernel
  def self.pbMessage(*a); 0; end
  def self.pbMessageFreeText(*a); $freetext_queue.shift.to_s; end
  def self.pbOnStepTaken(*a); end
end
def pbTurnDependentEvents(*a); end
def pbCheckEventTriggerFromDistance(*a); end
def pbPokemonMart(*a); end
def _INTL(s, *a); s; end
module Input
  def self.triggerex?(k); false; end
  def self.pressex?(k); false; end
  def self.trigger?(k); false; end
  def self.update; end
end
$spoken = []
module AccessibilitySpeech
  def self.speak(t, force = false, interrupt: true); $spoken << t.to_s; end
  def self.log(m); end
end

# Absolute first: the chdir below would otherwise break a relative path.
mod = File.expand_path(ARGV[0])
Dir.chdir(File.dirname(mod))   # so pra-custom-names.txt resolves harmlessly

ok = true
begin
  load mod
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
  puts "        #{e.backtrace.first(3).join("\n        ")}"
end
check ok, "the ported mod loads with no error"

check defined?(tts) ? true : false, "the tts shim is defined"
tts("hello there")
check $spoken.last == "hello there", "tts reaches the speech engine"

check defined?(Game_Player::Node) || defined?(Node), "the Node class came across"
%w[populate_event_list pathfind_to_selected_event announce_selected_event
   announce_selected_coordinates announce_selected_notes cycle_event_filter
   cycle_hm_toggle create_poi rename_selected_event add_note_to_selected_event
   start_autowalk follow_autowalk_path clear_autowalk_route].each do |m|
  check $game_player.respond_to?(m), "#{m} is available"
end

# Desolation restores $game_player from the save with Marshal, which skips
# initialize - exactly what this stub player did by existing before the load.
# The mod has to notice and fix itself on the first frame.
check PraSession.event_filter_modes.nil?,
      "a Marshal'd player really does arrive with the session uninitialised"
$game_player.update
check !PraSession.event_filter_modes.nil?,
      "the first frame self-heals the session on a loaded save"
check $game_player.instance_variable_get(:@auto_refresh_map_list) == true,
      "auto-refresh is switched on rather than left nil"
check $game_player.instance_variable_get(:@sort_by_distance) == true,
      "distance sorting is switched on rather than left nil"

# A second load must not chain the aliases onto themselves.
ok2 = true
begin
  load mod
  $game_player.update          # would blow the stack if the guards failed
rescue Exception => e
  ok2 = false
  puts "        #{e.class}: #{e.message}"
  puts "        #{e.backtrace.first(3).join("\n        ")}"
end
check ok2, "a second load does not recurse (guards hold)"

# ---------------------------------------------------------------- filters
check PraSession.event_filter_modes.include?(:pois),
      "the points-of-interest filter arrived with the newer version"
$spoken = []
$game_player.cycle_event_filter(1)
check $spoken.any? { |s| s =~ /Filter set to/i }, "cycling the filter announces the new mode"
$spoken = []
$game_player.cycle_event_filter(-1)
check $spoken.any? { |s| s =~ /Filter set to/i }, "cycling backwards announces too"
PraSession.event_filter_index = 0   # back to :all

# ------------------------------------------------------- the event scan
joy  = Game_Event.new(1, "Nurse Joy", 8, 4, 0)
joy.character_name = "NPC 01"
sign = Game_Event.new(2, "Sign", 3, 9, 0)              # no sprite -> a sign
door = Game_Event.new(3, "Door", 6, 0, 0, [Cmd.new(TRANSFER, [0, 2, 4, 4, 2]), Cmd.new(DONE)])
mart = Game_Event.new(4, "Clerk", 2, 2, 0,
                      [Cmd.new(SCRIPT, ["pbPokemonMart([1,2])"]), Cmd.new(DONE)])
mart.character_name = "NPC 02"
$game_map.events = { 1 => joy, 2 => sign, 3 => door, 4 => mart }
$MapFactory.connections = { [10, -1] => 2 }   # a north-edge connection to map 2

scan_ok = true
begin
  $game_player.populate_event_list
rescue Exception => e
  scan_ok = false
  puts "        #{e.class}: #{e.message}"
  puts "        #{e.backtrace.first(3).join("\n        ")}"
end
check scan_ok, "populate_event_list runs against Desolation's map API"
check PraSession.mapevents.is_a?(Array) && !PraSession.mapevents.empty?,
      "the scan found something to select"
check PraSession.mapevents.any? { |e| e.respond_to?(:type) && e.type == :connection },
      "the map-connection scan produced a virtual edge event"

# ----------------------------------------------------------- announcing
$spoken = []
PraSession.selected_event_index = 0
$game_player.announce_selected_event
check !$spoken.empty?, "the selected event is announced"
$spoken = []
$game_player.announce_selected_coordinates
check $spoken.any? { |s| s =~ /\d/ }, "Shift+P reads out coordinates"
$spoken = []
$game_player.announce_selected_notes
check !$spoken.empty?, "N reads out notes (or says there are none)"

# ------------------------------------------------------ points of interest
$freetext_queue = ["12", "7", "My Landmark", "the thing I keep losing"]
$spoken = []
poi_ok = true
begin
  $game_player.create_poi
rescue Exception => e
  poi_ok = false
  puts "        #{e.class}: #{e.message}"
  puts "        #{e.backtrace.first(3).join("\n        ")}"
end
check poi_ok, "create_poi runs"
check $custom_event_names["1;12;7"] &&
      $custom_event_names["1;12;7"][:event_name] == "My Landmark",
      "the point of interest was stored under map;x;y"
check $custom_event_names["1;12;7"][:type] == :poi,
      "it is flagged as a POI, not a renamed event"
check $spoken.any? { |s| s =~ /My Landmark/ }, "creating a POI is confirmed aloud"
check File.exist?(CUSTOM_NAMES_FILE), "the POI file was written to disk"

# It has to survive a round trip through that file.
$custom_event_names = {}
$game_player.instance_eval { load_custom_names }
check $custom_event_names["1;12;7"] &&
      $custom_event_names["1;12;7"][:event_name] == "My Landmark" &&
      $custom_event_names["1;12;7"][:type] == :poi,
      "the POI reloads from disk with its type intact"
check $custom_event_names["1;12;7"][:notes] == "the thing I keep losing",
      "the note survived the round trip too"

# And it has to show up in the event list.
$game_player.populate_event_list
check PraSession.mapevents.any? { |e| e.name == "My Landmark" },
      "the POI appears in the event list"

# ------------------------------------------------------------- HM toggle
$spoken = []
3.times { $game_player.cycle_hm_toggle }
check $spoken.any? { |s| s =~ /surf/i }, "the HM toggle cycles through Surf"
check $spoken.any? { |s| s =~ /waterfall/i }, "and through Waterfall"

# --------------------------------------------------------------- autowalk
$spoken = []
$game_player.clear_autowalk_route
$game_player.start_autowalk([Game_Player::Node.new($game_player.x, $game_player.y + 1)])
check $spoken.any? { |s| s =~ /auto/i }, "starting auto-walk says so"
before = $game_player.y
$game_player.follow_autowalk_path
check $game_player.y == before + 1, "auto-walk steps toward the next node"

# Cleanup: don't leave a test POI file behind.
File.delete(CUSTOM_NAMES_FILE) rescue nil

puts "=" * 56
puts " RESULTS: #{$pass} passed, #{$fail} failed"
puts "=" * 56
exit($fail == 0 ? 0 : 1)
