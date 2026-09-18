# Exercises AccessibilityBattle: messages, the command and fight menus,
# targeting, Mega registration, spoken damage, and the K readouts - against
# battle-shaped stubs mirroring Desolation's Battle_Scene structure.
#
#   ruby test_battle.rb ../patch/Mods/AccessibilityBattle.rb
$pass = 0; $fail = 0
def check(c, n); c ? ($pass += 1; puts "PASS: #{n}") : ($fail += 1; puts "FAIL: #{n}"); end
def check_eq(a, e, n)
  if a == e then $pass += 1; puts "PASS: #{n}"
  else $fail += 1; puts "FAIL: #{n}\n        expected: #{e.inspect}\n        actual:   #{a.inspect}" end
end

# ── Speech capture, with interrupt recorded ─────────────────────────────────
$spoken = []
module AccessibilitySpeech
  class << self; attr_accessor :enabled; end
  self.enabled = true
  def self.speak(text, force = false, interrupt: true)
    $spoken << [text.to_s, interrupt]
  end
  def self.log(*a); end
end
def said; $spoken.map(&:first); end

module A11ySettings
  @v = {}
  class << self
    def get(k); @v.key?(k) ? @v[k] : 0; end
    def set(k, val); @v[k] = val; end
    def on?(k); get(k) == 0; end
  end
end

def _INTL(s, *a); a.each_with_index { |v, i| s = s.gsub("{#{i + 1}}", v.to_s) }; s; end
def getAbilityName(a); a.to_s.capitalize; end
def getItemName(i); i.to_s.capitalize; end
def getMoveName(m); m.to_s.capitalize; end

module Input
  L = :L_BUTTON; R = :R_BUTTON
  @keys = {}
  class << self
    def press(code); @keys[code] = true; end
    def clear; @keys = {}; end
    def triggerex?(k); !!@keys[k]; end
    def pressex?(k); !!@keys[k]; end
    def trigger?(k); !!@keys[k]; end
  end
end

# ── The battle objects, shaped like Desolation's ────────────────────────────
module PBStats
  ATTACK = 1; DEFENSE = 2; SPEED = 3; SPATK = 4; SPDEF = 5; ACCURACY = 6; EVASION = 7
end

FakeMove = Struct.new(:name, :type, :pp, :totalpp, :move) do
  def pbType(battler); type; end
end

class FakeBattler
  attr_accessor :name, :level, :hp, :totalhp, :status, :stages, :ability, :item, :moves
  attr_accessor :type1, :type2
  def initialize(name, hp, totalhp)
    @name = name; @level = 12; @hp = hp; @totalhp = totalhp
    @stages = Hash.new(0); @moves = []
  end
  def isFainted?; @hp <= 0; end
  def pbThis; @name; end
end

class FakeSide
  attr_accessor :effects
  def initialize; @effects = Hash.new(0); end
end

class FakeAI
  attr_accessor :memory
  def initialize; @memory = {}; end
  def getAIMemory(battler, inspecting = false); @memory[battler] || []; end
end

class FakeField
  attr_accessor :effect, :duration
  def initialize; @effect = :FOREST; @duration = 0; end
end

class PokeBattle_Battle
  attr_accessor :battlers, :sides, :trickroom, :field, :ai, :registered
  def initialize
    @battlers = []; @sides = [FakeSide.new, FakeSide.new]
    @trickroom = 0; @field = FakeField.new; @ai = FakeAI.new
    @registered = []
  end
  def pbOwnedByPlayer?(i); i % 2 == 0; end
  def pbWeather; @weather || 0; end
  def weather=(w); @weather = w; end
  def pbRegisterMegaEvolution(i); @registered << [:mega, i]; end
  def pbRegisterUltraBurst(i); @registered << [:ultra, i]; end
  def pbRegisterZMove(i); @registered << [:z, i]; end
end

class PokeBattle_Battler < FakeBattler
  def pbReduceHP(amt, anim = false, emercheck = true)
    amt = @hp if amt > @hp
    @hp -= amt
    amt
  end
end

class PokeBattle_Field
  def self.getFieldName(f); f.to_s.capitalize; end
end

# The scene, with the same method shapes the mod aliases.
class PokeBattle_Scene
  attr_accessor :battle, :selected_calls
  def initialize(battle); @battle = battle; @selected_calls = []; end
  def pbDisplayMessage(msg, brief = false); $displayed = msg; end
  def pbDisplayPausedMessage(msg); $displayed = msg; end
  def pbShowCommands(msg, commands, defaultValue); $displayed = msg; 0; end
  def pbUpdateSelected(index); @selected_calls << index; end
  def pbFrameUpdate(cw = nil, update_cw = true); $frames = ($frames || 0) + 1; end
end

# The two menu displays, embedding a window the menus mod would read.
class EmbeddedWindow
  attr_accessor :index, :commands, :a11y_silent
  def initialize; @index = 0; @commands = []; end
end

class CommandMenuDisplay
  attr_accessor :mode
  def initialize
    @window = EmbeddedWindow.new
    @msgbox = Struct.new(:text).new("")
  end
  def index; @window.index; end
  def index=(v); @window.index = v; end
  def setTexts(value)
    @msgbox.text = value[0]
    @window.commands = value[1..4].compact
  end
  def window; @window; end
end

class FightMenuDisplay
  attr_reader :battler, :index
  def initialize(battler)
    @window = EmbeddedWindow.new
    @battler = battler
    @index = 0
  end
  def battler=(v); @battler = v; end
  def setIndex(value)
    if @battler && @battler.moves[value]
      @index = value
      @window.index = value
      return true
    end
    false
  end
  def window; @window; end
end

mod = File.expand_path(ARGV[0] || "../patch/Mods/AccessibilityBattle.rb")
ok = true
begin
  load mod
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
  puts "        #{e.backtrace.first(3).join("\n        ")}"
end
check ok, "the mod loads with no error"

battle = PokeBattle_Battle.new
me  = PokeBattle_Battler.new("Growlithe", 51, 60)
foe = PokeBattle_Battler.new("Hiker's Geodude", 40, 40)
me.moves  = [FakeMove.new("Ember", :FIRE, 24, 25, :EMBER),
             FakeMove.new("Bite", :DARK, 25, 25, :BITE)]
foe.moves = [FakeMove.new("Tackle", :NORMAL, 35, 35, :TACKLE)]
me.ability = :INTIMIDATE; me.item = :ORANBERRY
battle.battlers = [me, foe]
scene = PokeBattle_Scene.new(battle)

# ── Messages ────────────────────────────────────────────────────────────────
$spoken = []
scene.pbDisplayMessage("Growlithe used Ember!")
check said.include?("Growlithe used Ember!"), "a battle message is spoken"
check_eq $spoken.last[1], false, "and queued, so sequences read in order"
check_eq $displayed, "Growlithe used Ember!", "the original display still runs"

$spoken = []
scene.pbDisplayPausedMessage("It's super effective!")
check said.include?("It's super effective!"), "a paused message is spoken too"

$spoken = []
scene.pbDisplayMessage("But it failed!")
scene.pbDisplayMessage("But it failed!")
check_eq said.count("But it failed!"), 2,
         "the same message twice is spoken twice - two events, not an echo"

$spoken = []
scene.pbShowCommands("Learn which move?", ["Yes", "No"], 1)
check said.include?("Learn which move?"), "a choice prompt speaks its question"

# ── The command menu ────────────────────────────────────────────────────────
cmd = CommandMenuDisplay.new
$spoken = []
cmd.setTexts(["What will Growlithe do?", "Fight", "Bag", "Pokémon", "Run"])
check said.include?("What will Growlithe do?"), "opening the command menu asks the question"
check said.include?("Fight"), "and says the command the cursor is on"
check_eq cmd.window.a11y_silent, true,
         "the embedded window is muted so the menus mod does not double-speak"

$spoken = []
cmd.index = 1
check said.include?("Bag"), "moving the cursor says the new command"
$spoken = []
cmd.index = 1
check $spoken.empty?, "but not when the index did not actually change"

# ── The fight menu ──────────────────────────────────────────────────────────
fight = FightMenuDisplay.new(nil)
fight.battler = me
$spoken = []
fight.setIndex(0)
check said.any? { |s| s =~ /Ember.*Fire type.*24 of 25 PP/ },
      "landing on a move says name, type and PP"
check_eq fight.window.a11y_silent, true, "the fight window is muted too"

$spoken = []
fight.setIndex(1)
check said.any? { |s| s =~ /Bite.*Dark type/ }, "moving to another move announces it"

$spoken = []
fight.setIndex(1)
check $spoken.empty?, "staying put announces nothing"

$spoken = []
fight.setIndex(3)
check $spoken.empty?, "an empty move slot announces nothing and does not crash"

# Re-entering the menu next turn must re-announce even at the same index.
fight.battler = me
$spoken = []
fight.setIndex(1)
check said.any? { |s| s =~ /Bite/ }, "re-entering the fight menu announces the move again"

# ── Targeting ───────────────────────────────────────────────────────────────
$spoken = []
scene.pbUpdateSelected(1)
check said.include?("Hiker's Geodude"), "the targeting cursor says who you are aiming at"
$spoken = []
5.times { scene.pbUpdateSelected(1) }
check $spoken.empty?, "and not sixty times a second while it sits there"
scene.pbUpdateSelected(-1)
$spoken = []
scene.pbUpdateSelected(1)
check said.include?("Hiker's Geodude"), "closing and reopening the selector announces again"
check_eq scene.selected_calls.count(1), 7, "the original selection drawing always ran"

# ── Mega / Ultra / Z ────────────────────────────────────────────────────────
$spoken = []
battle.pbRegisterMegaEvolution(0)
check said.include?("Mega Evolution activated"), "registering a Mega speaks"
battle.pbRegisterZMove(0)
check said.include?("Z-Move activated"), "and a Z-Move"
check_eq battle.registered, [[:mega, 0], [:z, 0]], "the real registration still happened"

# ── Spoken damage ───────────────────────────────────────────────────────────
$spoken = []
me.pbReduceHP(24)
check said.include?("Growlithe took 24 damage. 27 HP left."), "damage says amount and HP left"
$spoken = []
foe.pbReduceHP(100)
check said.include?("Hiker's Geodude took 40 damage and fainted."),
      "a fatal hit says fainted, with the damage capped at real HP"
foe.hp = 40

$spoken = []
me.pbReduceHP(0)
check $spoken.empty?, "zero damage says nothing"

A11ySettings.set(:spoken_damage, 1)
$spoken = []
me.pbReduceHP(5)
check $spoken.empty?, "Options -> Spoken Damage off silences the damage lines"
check_eq me.hp, 22, "but the damage itself still lands"
A11ySettings.set(:spoken_damage, 0)
me.hp = 51

# ── The K readouts ──────────────────────────────────────────────────────────
me.stages[PBStats::ATTACK] = 2
foe.stages[PBStats::SPEED] = -1
foe.status = :PARALYSIS
battle.ai.memory[foe] = [foe.moves[0]]
$spoken = []
A11yBattle.status_report(scene)
all = said.join(" | ")
check all.include?("Your Growlithe"), "K reads your own Pokemon"
check all =~ /51 of 60 HP/, "with exact HP for yours"
check all.include?("Attack plus 2"), "and its stat changes"
check all =~ /ability Intimidate/, "and its ability"
check all =~ /holding Oranberry/, "and its held item"
check all.include?("Enemy Hiker's Geodude"), "and the enemy"
check all =~ /100 percent HP/, "with percentage HP for theirs"
check all.include?("paralyzed"), "and their status"
check all.include?("Speed minus 1"), "and their stat drops"
check all =~ /revealed moves: Tackle/, "and only their REVEALED moves"

$spoken = []
battle.weather = :RAINDANCE
battle.sides[0].effects[:Reflect] = 3
battle.sides[1].effects[:StealthRock] = true
battle.trickroom = 2
A11yBattle.field_report(scene)
all = said.join(" | ")
check all =~ /Weather: Raindance/, "Shift+K reads the weather"
check all =~ /Field: Forest/, "and the field effect"
check all =~ /Your side: Reflect 3/, "and your screens with turns"
check all =~ /Enemy side: Stealth Rock/, "and the enemy's hazards"
check all =~ /Trick Room, 2 turns/, "and Trick Room"

# ── The keys route through pbFrameUpdate ────────────────────────────────────
$frames = 0
$spoken = []
Input.clear
Input.press(0x4B)
scene.pbFrameUpdate(nil, true)
check said.any? { |s| s.include?("Your Growlithe") }, "K during a menu frame reads status"
check_eq $frames, 1, "and the original frame update still ran"
Input.clear
$spoken = []
Input.press(0x10); Input.press(0x4B)
scene.pbFrameUpdate(nil, true)
check said.any? { |s| s =~ /Weather/ }, "Shift+K reads the field instead"
Input.clear

# ── Q and W: whole sides in detail ─────────────────────────────────────────
me.type1 = :FIRE; me.type2 = nil
foe.type1 = :ROCK; foe.type2 = :GROUND
$spoken = []
Input.clear
Input.press(Input::L)                      # the Q key
scene.pbFrameUpdate(nil, true)
own = said.join(" | ")
check own.include?("Your Growlithe") || own.include?("Growlithe"),
      "Q reads your side"
check own.include?("Fire type"), "with its types"
check own =~ /Ember, 24 of 25 PP/, "and your moves with exact PP"
check own =~ /Bite, 25 of 25 PP/, "all of them"
check !own.include?("Geodude"), "and nothing about the enemy"
Input.clear

$spoken = []
Input.press(Input::R)                      # the W key
scene.pbFrameUpdate(nil, true)
foe_read = said.join(" | ")
check foe_read.include?("Hiker's Geodude"), "W reads the enemy side"
check foe_read.include?("Rock and Ground type"), "with both its types"
check foe_read =~ /revealed moves: Tackle/, "and only REVEALED enemy moves"
check !(foe_read =~ /Tackle, 35 of 35 PP/), "never the enemy's exact PP"
check !foe_read.include?("Your Growlithe"), "and nothing about your side"
Input.clear

# ── Z on the fight menu: the move card, spoken ─────────────────────────────
$cache_moves = { :EMBER => Struct.new(:name, :category, :basedamage, :accuracy, :desc)
                            .new("Ember", :special, 40, 100, "May burn the target.") }
class BattleCacheStub
  def moves; $cache_moves; end
end
$cache = BattleCacheStub.new
class FakeMove
  def totalpp; self[:totalpp]; end
end
fightcw = FightMenuDisplay.new(me)
fightcw.setIndex(0)
$spoken = []
Input.clear
Input.press(0x5A)                                # Z
scene.pbFrameUpdate(fightcw, true)
z = said.join(" | ")
check z.include?("Ember, Special, 40 power, 100 accuracy, 24 of 25 PP"),
      "Z reads the focused move's full card"
check z.include?("May burn the target."), "including the description"
Input.clear

$spoken = []
Input.press(0x5A)
scene.pbFrameUpdate(cmd, true)                   # the COMMAND menu, not fight
check $spoken.empty?, "Z outside the fight menu says nothing"
Input.clear
$cache = nil

# ── The master switch ───────────────────────────────────────────────────────
A11ySettings.set(:battle_speech, 1)
$spoken = []
scene.pbDisplayMessage("Should be silent")
cmd.index = 0
me.pbReduceHP(3)
check $spoken.empty?, "Options -> Battle Speech off silences all of it"
A11ySettings.set(:battle_speech, 0)
me.hp = 51

AccessibilitySpeech.enabled = false
$spoken = []
scene.pbDisplayMessage("Also silent")
check $spoken.empty?, "and speech off (F2) silences battle too, despite force"
AccessibilitySpeech.enabled = true

# ── Reloading ───────────────────────────────────────────────────────────────
ok = true
begin
  2.times { load mod }
  scene.pbDisplayMessage("still fine")
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
end
check ok, "a soft reset reloads it without recursing"

puts "=" * 56
puts " RESULTS: #{$pass} passed, #{$fail} failed"
puts "=" * 56
exit($fail == 0 ? 0 : 1)
