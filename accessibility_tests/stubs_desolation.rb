# stubs_desolation.rb - just enough of Pokemon Essentials for the accessibility
# mods to load and run outside the game.
#
# Shared by test_a11y.rb and test_load_order.rb. test_pathfind.rb keeps its own
# deliberately: it stubs the map factory and the event lists to specific shapes
# that would fight with the ones here.
#
# Anything added here must be additive. If a stub changes shape, run both
# harnesses before committing.

# ── Minimal engine stubs ─────────────────────────────────────────────────────

# No NVDA here: make the binding fail so speak() falls through to the log path
# and we capture text via the module's own state instead.
class Win32API
  def initialize(*args); raise "no dll in test harness"; end
end

def toUnformattedText(s); s.to_s.gsub(/<[^>]+>/, ""); end
def pbIsImportantItem?(item); item == :HM01; end
def getMonName(sym); ($cache.pkmn[sym] && $cache.pkmn[sym].name) || sym.to_s; end

Struct.new("ItemData", :name, :desc)
Struct.new("MonData", :name, :kind, :dexentry)

class FakeCache
  attr_accessor :items, :pkmn
  def initialize
    @items = {
      :POTION => Struct::ItemData.new("Potion", "Restores 20 HP."),
      :HM01   => Struct::ItemData.new("HM01", "Cut."),
      :ORAN   => Struct::ItemData.new("Oran Berry", "Restores HP.")
    }
    @pkmn = {
      :PIKACHU => Struct::MonData.new("Pikachu", "Mouse", "It stores electricity.")
    }
  end
end
$cache = FakeCache.new

class FakePokemon
  attr_accessor :name, :level, :hp, :totalhp, :status, :item, :egg
  def initialize(name, level, hp, totalhp, status = 0, item = nil, egg = false)
    @name, @level, @hp, @totalhp, @status, @item, @egg = name, level, hp, totalhp, status, item, egg
  end
  def isEgg?; @egg; end
end

class FakeBag
  attr_accessor :pockets, :contents
  def initialize
    @pockets  = { 1 => [:POTION, :HM01] }
    @contents = { :POTION => 5, :HM01 => 1 }
  end
end

class FakeTrainerPokedex
  def dexList
    { :PIKACHU => { :name => "Pikachu", :seen? => true, :owned? => true },
      :MEW     => { :name => "Mew",     :seen? => false, :owned? => false },
      :EEVEE   => { :name => "Eevee",   :seen? => true,  :owned? => false } }
  end
  def getSeenCount; 42; end
  def getOwnedCount; 7; end
end
class FakeTrainer
  def pokedex; FakeTrainerPokedex.new; end
  def name; "Ash"; end
  def money; 3000; end
  def badges; [true, true, false]; end
  def party; [FakePokemon.new("Bulbasaur", 5, 20, 20)]; end
end
$Trainer = FakeTrainer.new

# Window hierarchy mirroring SW Subclasses.rb
class SpriteWindow_Base; end
class SpriteWindow_Selectable < SpriteWindow_Base
  attr_reader :index
  def initialize; @index = 0; end
  def index=(v); @index = v; end
  def update; end
end
class Window_DrawableCommand < SpriteWindow_Selectable; end
class Window_CommandPokemon < Window_DrawableCommand
  attr_reader :commands
  def initialize(cmds); super(); @commands = cmds; end
end
class Window_AdvancedCommandPokemon < Window_DrawableCommand
  attr_reader :commands
  def initialize(cmds); super(); @commands = cmds; end
end
class Window_PokemonBag < Window_DrawableCommand
  attr_reader :pocket
  def initialize(bag, pocket); super(); @bag = bag; @pocket = pocket; end
  def item; @bag.pockets[@pocket][@index]; end
end
class Window_PokemonItemStorage < Window_DrawableCommand
  def item; nil; end
end
class FakeOption
  attr_reader :name, :values, :optstart
  def initialize(name, values = nil, optstart = nil); @name, @values, @optstart = name, values, optstart; end
end
class Window_PokemonOption < Window_DrawableCommand
  attr_accessor :pending_value   # test hook: stands in for a LEFT/RIGHT press
  attr_accessor :active
  attr_reader :options
  def initialize(options); super(); @options = options; @optvalues = [0] * options.length; @active = true; end
  def [](i); @optvalues[i]; end
  def []=(i, v); @optvalues[i] = v; end
  def update
    # Mirrors the real window: update() itself changes the VALUE of the
    # current row when left/right is pressed, without moving @index.
    if @pending_value
      @optvalues[@index] = @pending_value
      @pending_value = nil
    end
  end
end
class FakeAdapter
  def getDisplayName(item); $cache.items[item].name; end
  def getDisplayPrice(item, selling); "$200"; end
end
class Window_PokemonMart < Window_DrawableCommand
  def initialize(stock); super(); @stock = stock; @adapter = FakeAdapter.new; end
  def item; @stock[@index]; end
end
class Window_Pokedex < Window_DrawableCommand
  def initialize(list); super(); @list = list; end
  def species; @list[@index]; end
end

# Scenes with custom cursors
class PokemonScreen_Scene
  attr_accessor :sprites
  def initialize(party); @party = party; @activecmd = 0; @sprites = {}; end
  def update; end
end
class PokemonSummaryScene
  def initialize(pkmn); @pokemon = pkmn; @page = 0; @partyindex = 0; @abilpage = false; end
  def pbUpdate; end
end
class SpriteWrapper; end
class MoveSelectionSprite < SpriteWrapper
  attr_reader :index
  def initialize; @index = 0; end
  def index=(v); @index = v; end
end
class FakeBox
  attr_accessor :name
  def initialize(name, mons); @name = name; @mons = mons; end
  def nitems; @mons.compact.length; end
  def [](i); @mons[i]; end
end
class FakeStorage
  attr_accessor :currentBox
  attr_reader :party
  def initialize(boxes, party); @boxes = boxes; @party = party; @currentBox = 0; end
  def [](x, y = nil)
    return @boxes[x] if y.nil?
    @boxes[x][y]
  end
end
class PokemonStorageScene
  def initialize(storage); @storage = storage; end
  def pbSetArrow(arrow, selection); end
  def pbPartySetArrow(arrow, selection); end
  def pbUpdateOverlay(selection, party = nil); end
end
class MapBottomSprite < SpriteWrapper
  attr_reader :mapname, :maplocation
  def maplocation=(v); @maplocation = v; end
end
class Window_TextEntry
  attr_reader :text
  def initialize; @text = ""; end
  def insert(ch); @text += ch; end
  def delete; @text = @text[0...-1] if @text.length > 0; end
end
class PokemonTrainerCardScene
  def pbDrawTrainerCardFront(*args); end
end
class PokemonPokedexScene
  def pbChangeToDexEntry(species); end
end
module Kernel
  class << self
    def pbMessageDisplay(*args, &block); end
  end
end
module Input
  class << self
    def update; end
    def text_input; false; end
    def triggerex?(k); false; end
  end
end


# Event interpreter stubs (for AccessibilityEvents.rb)
module Graphics
  @frame_count = 0
  class << self
    attr_accessor :frame_count
    def update; @frame_count += 1; end
  end
end
class Interpreter
  attr_accessor :parameters
  def initialize; @parameters = []; end
  def command_105; :ok105; end
  def command_231; :ok231; end
  def command_235; :ok235; end
end
class Scene_Map
  def main; :mainran; end
end


# World stubs (for AccessibilityWorld.rb)
class Game_Character
  attr_accessor :x, :y, :direction
  def initialize; @x = 0; @y = 0; @direction = 2; end
  def increase_steps; $steps_taken = ($steps_taken || 0) + 1; end
end
class Game_Player < Game_Character
  attr_accessor :blocked_dirs
  def initialize; super; @blocked_dirs = []; end
  def passable?(x, y, dir); !@blocked_dirs.include?(dir); end
  def move_one; increase_steps; end
end
class Game_Map
  attr_accessor :map_id, :tags
  def initialize; @map_id = 1; @tags = {}; end
  def terrain_tag(x, y); @tags[[x, y]] || 13; end
end
class Game_Temp
  attr_accessor :in_battle, :message_window_showing
  def initialize; @in_battle = false; @message_window_showing = false; end
end
class Scene_Map2 < Scene_Map; end
def pbMapInterpreterRunning?; false; end
$played_se = []
def pbSEPlay(name, volume = nil, pitch = nil); $played_se << [name.to_s, volume]; end
module Audio
  def self.se_play(name, volume = nil, pitch = nil); $played_se << [name.to_s, volume]; end
end
# Mirrors the real engine: Audio_se_play exists but calls an undefined
# getPlaySound, so anything relying on it raises. The mod must not use it.
def Audio_se_play(name, volume = nil, pitch = nil, position = 0); getPlaySound(); end
$map_names = { 1 => "Route 1" }
def pbGetMapNameFromId(id); $map_names[id] || "MAP%03d" % id; end
class PBTerrain; Ledge = 1; end
$facing_ledge = false
module Kernel
  def self.pbFacingTerrainTag(event = nil, dir = nil)
    $facing_ledge ? PBTerrain::Ledge : 13
  end
end
def pbLedge(x, y)
  return false unless $facing_ledge
  $game_player.increase_steps
  true
end
class FakeSettings; def sevolume; 100; end; end
$Settings = FakeSettings.new
module FileTest
  def self.exist?(path)
    ($existing_audio ||= []).include?(path)
  end
end
# The engine's own existence helper, which the mod prefers.
def safeExists?(f); ($existing_audio ||= []).include?(f); end
$game_player = Game_Player.new
$game_map = Game_Map.new
$game_temp = Game_Temp.new
$scene = Scene_Map.new


# ── Extra surface the pathfinder needs ───────────────────────────────────────
# AccessibilityPathfind reopens Game_Map, Game_Player and Scene_Map and reaches
# for a good deal more of the engine than the other mods do.

class Game_Map
  def name; "Route 1"; end
  def width; 20; end
  def height; 15; end
  def valid?(x, y); x >= 0 && y >= 0 && x < width && y < height; end
  def passable?(x, y, d, self_event = nil); true; end
  def passableStrict?(x, y, d, self_event = nil); true; end
  def events; @events ||= {}; end
  def events=(v); @events = v; end
end

class Game_Character
  attr_accessor :through, :character_name
  def moving?; false; end
  def map; $game_map; end
  def update; end
  def move_down(t = true); @y += 1; end
  def move_left(t = true); @x -= 1; end
  def move_right(t = true); @x += 1; end
  def move_up(t = true); @y -= 1; end
  def opacity; 255; end
end

class Game_Event < Game_Character
  attr_accessor :id, :name, :list, :trigger
  def initialize(id = 1, name = "Ev"); super(); @id = id; @name = name; @list = []; @trigger = 0; end
end

class Game_System
  def map_interpreter; @mi ||= Object.new.tap { |o| def o.running?; false; end }; end
  def update; end
end
$game_system = Game_System.new

# Deliberately NOT assigned to $game_variables here: the speech mod's
# sanitizer substitutes \v[n], and giving it a live store would change what
# the sanitize tests see. test_load_order.rb assigns one; test_a11y.rb does
# not, and checks the no-variable path.
class Game_Variables
  def initialize; @d = {}; end
  def [](k); @d[k] || 0; end
  def []=(k, v); @d[k] = v; end
end

class MapFactoryStub
  def isPassable?(m, x, y, ev = nil); true; end
  def getMap(id); nil; end
  def getNewMap(x, y); nil; end
  def maps; []; end
end
$MapFactory = MapFactoryStub.new

class PokemonTempStub; end
$PokemonTemp = PokemonTempStub.new

class PokemonMapMetadata
  attr_reader :movedEvents
  def initialize; @movedEvents = {}; end
  def addMovedEvent(id); end
end

class PBTerrain
  Ledge = 1; Water = 7; DeepWater = 5; StillWater = 6
  Waterfall = 8; WaterfallCrest = 9
end
def pbIsPassableWaterTag?(t); [5, 6, 7, 8, 9].include?(t); end

module Kernel
  class << self
    def pbMessage(*a); 0; end
    def pbMessageFreeText(*a); ""; end
    def pbOnStepTaken(*a); end
  end
end
def pbTurnDependentEvents(*a); end
def pbCheckEventTriggerFromDistance(*a); end
def pbPokemonMart(*a); end
def _INTL(s, *a); s; end

module Input
  class << self
    def pressex?(k); false; end
    def repeatex?(k); false; end
    def trigger?(k); false; end
  end
end

$game_player.instance_variable_set(:@x, 5)
$game_player.instance_variable_set(:@y, 5)

# ── The Options screen, enough for AccessibilityOptions to add rows to it ────
unless defined?(EnumOption)
  class EnumOption
    attr_reader :name, :values, :description
    def initialize(name, values, getter, setter, description = nil)
      @name, @values, @getter, @setter, @description = name, values, getter, setter, description
    end
    def get; @getter.call; end
    def set(v); @setter.call(v); end
  end
  class NumberOption
    attr_reader :name, :min, :max, :description
    def initialize(name, format, min, max, getter, setter, description = nil)
      @name, @min, @max, @getter, @setter, @description = name, min, max, getter, setter, description
    end
    def get; @getter.call; end
    def set(v); @setter.call(v); end
  end
end
unless defined?(PokemonOptions)
  class PokemonOptions; attr_accessor :sevolume; end
end
# $Settings is already a FakeSettings by this point (test_a11y needs its
# sevolume). AccessibilityOptions adds `attr_accessor :a11y` to PokemonOptions,
# so give FakeSettings the same field - otherwise the settings silently fall
# back to defaults here and a test that meant to exercise storage exercises
# nothing. The mod degrading quietly instead of crashing is correct; the
# harness pretending that is the normal path is not.
if defined?(FakeSettings)
  class FakeSettings; attr_accessor :a11y; end
end
unless defined?(PokemonOptionScene)
  class PokemonOptionScene; OptionList = []; end
end
$Settings = PokemonOptions.new unless defined?($Settings) && $Settings
def saveSettings(set = nil); end
