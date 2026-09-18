# Exercises AccessibilityPathfindNames: the label it derives for each kind of
# event, and - just as important - the cases where it must keep quiet and let
# an existing name stand.
#
#   ruby test_names.rb ../patch/Mods/AccessibilityPathfindNames.rb
$pass = 0; $fail = 0
def check(c, n); c ? ($pass += 1; puts "PASS: #{n}") : ($fail += 1; puts "FAIL: #{n}"); end
def check_eq(a, e, n)
  if a == e then $pass += 1; puts "PASS: #{n}"
  else $fail += 1; puts "FAIL: #{n}\n        expected: #{e.inspect}\n        actual:   #{a.inspect}" end
end

# ── The game's data, shaped the way $cache exposes it ───────────────────────
TType = Struct.new(:title, :flags)
Mon   = Struct.new(:name)
Info  = Struct.new(:name)
class CacheStub
  attr_reader :trainertypes, :pkmn, :mapinfos
  def initialize
    @trainertypes = {
      :HIKER       => TType.new("Hiker",       { :ID => 18 }),
      :BEAUTY      => TType.new("Beauty",      { :ID => 7  }),
      :BUGCATCHER  => TType.new("Bug Catcher", { :ID => 10 }),
      :NOID        => TType.new("Nameless",    {})            # must not crash
    }
    @pkmn = {
      :GROWLITHE => Mon.new("Growlithe"),
      :SKITTY    => Mon.new("Skitty"),
      :RATTATA   => Mon.new("Rattata")
    }
    @mapinfos = { 84 => Info.new("Celeste City"), 7 => Info.new("Route 4") }
  end
end
$cache = CacheStub.new

module AccessibilitySpeech
  FACE_NAMES = { "07a" => "Rosetta", "02" => "Shiv" }
  def self.speak(*a); end
  def self.log(*a); end
end

Cmd = Struct.new(:code, :parameters)
SHOW_TEXT = 101; MORE_TEXT = 401; TRANSFER = 201; SCRIPT = 355
MOVE_ROUTE = 209; SWITCH = 121; DONE = 0

class Ev
  attr_accessor :name, :character_name, :list, :x, :y, :custom_name
  def initialize(name: "EV001", sprite: "", list: nil, x: 1, y: 1)
    @name = name; @character_name = sprite; @list = list || [Cmd.new(DONE)]
    @x = x; @y = y
  end
end
def text(*lines)
  lines.each_with_index.map { |l, i| Cmd.new(i.zero? ? SHOW_TEXT : MORE_TEXT, [l]) } + [Cmd.new(DONE)]
end

# The mod hooks these two; give it something to hook.
module PraSession; class << self; attr_accessor :mapevents; end; end
class Game_Player; def populate_event_list; $populated = true; end; end
class Scene_Map;   def main; :ran; end; end

mod = File.expand_path(ARGV[0] || "../patch/Mods/AccessibilityPathfindNames.rb")
ok = true
begin
  load mod
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
  puts "        #{e.backtrace.first(3).join("\n        ")}"
end
check ok, "the mod loads with no error"

# ── The lookups it builds out of the game's data ────────────────────────────
check_eq A11yNames.trainer_titles[18], "Hiker", "trainer types are indexed by their numeric ID"
check_eq A11yNames.trainer_titles[7],  "Beauty", "and again"
check A11yNames.trainer_titles.size == 3, "a type with no ID is skipped rather than crashing"
check_eq A11yNames.species_names["GROWLITHE"], "Growlithe", "species are indexed by upper-case name"
check_eq A11yNames.map_name(84), "Celeste City", "map names come from mapinfos"
check_eq A11yNames.map_name(999), nil, "an unknown map id gives nil, not a crash"

# ── What counts as a name worth keeping ─────────────────────────────────────
[["EV027", true], ["EV1", true], ["ev999", true], ["", true], ["   ", true],
 ["12", true], ["Ev", true], ["Nurse", false], ["Town Map left", false],
 ["Vending machine 1", false]].each do |n, expected|
  check_eq A11yNames.useless_name?(n), expected, "useless_name?(#{n.inspect})"
end

# ── Each derivation path ────────────────────────────────────────────────────
d = ->(ev) { A11yNames.derive(ev) }

check_eq d.(Ev.new(list: [Cmd.new(TRANSFER, [0, 84, 5, 5, 0, 1]), Cmd.new(DONE)])),
         "Door to Celeste City", "a Transfer Player says where it goes"
check_eq d.(Ev.new(list: [Cmd.new(TRANSFER, [0, 999, 5, 5, 0, 1]), Cmd.new(DONE)])),
         "Door", "an unknown destination still says it is a door"

check_eq d.(Ev.new(sprite: "CustomScarlett")), "Scarlett", "a Custom sprite names the character"
check_eq d.(Ev.new(sprite: "CustomScarlett", list: text("Hi."))), "Scarlett",
         "and beats the dialogue"

check_eq d.(Ev.new(sprite: "NPC 04", list: text("GARRET: Took you long enough."))),
         "Garret", "a NAME: prefix names the speaker"
check_eq d.(Ev.new(sprite: "NPC 04", list: text("Well: that was odd, wasn't it?"))),
         "Person: Well: that was odd, wasn't it?",
         "a sentence that merely contains a colon is not treated as a name"

check_eq d.(Ev.new(sprite: "NPC 04", list: text("\\ff[07a]Where did I put it..."))),
         "Rosetta", "a portrait code names the speaker via the speech mod"

check_eq d.(Ev.new(sprite: "pkmn_growlithe")), "Growlithe", "a Pokemon sprite gives the species"
check_eq d.(Ev.new(sprite: "pkmn_skitty (2)")), "Skitty",
         "a (2) palette variant still resolves - this was a real bug"
check_eq d.(Ev.new(sprite: "trchar018")), "Hiker", "a trainer sprite gives the trainer type"
check_eq d.(Ev.new(sprite: "trchar018 (3)")), "Hiker", "variants of it too"
check_eq d.(Ev.new(sprite: "trchar999")), "Trainer",
         "a trainer sprite with no matching type still says Trainer"

check_eq d.(Ev.new(sprite: "trchar010", list: text("I love my Rattata so much!"))),
         "Bug Catcher, about Rattata",
         "a nameless trainer is described by type and what they talk about"
check_eq d.(Ev.new(sprite: "trchar010", list: text("Rattata beat my Growlithe."))),
         "Bug Catcher",
         "two species mentioned is too vague, so no topic is added"

check_eq d.(Ev.new(list: [Cmd.new(SCRIPT, ["pbItemBall(:POTION)"]), Cmd.new(DONE)])),
         "Item ball: Potion", "an item ball names the item"
check_eq d.(Ev.new(list: [Cmd.new(SCRIPT, ["pbHiddenItem(:RARE_CANDY)"]), Cmd.new(DONE)])),
         "Hidden item: Rare Candy", "a hidden item does too"
check_eq d.(Ev.new(list: [Cmd.new(SCRIPT, ["pbPokemonMart([1,2])"]), Cmd.new(DONE)])),
         "Shop counter", "a mart is a shop counter"
check_eq d.(Ev.new(list: [Cmd.new(SCRIPT, ["pbTrainerIntro(:CAMPER)"]), Cmd.new(DONE)])),
         "Trainer: Camper", "a trainer intro names the class"

check_eq d.(Ev.new(sprite: "", list: text("Sunshell Town Teleporter"))),
         "Sign: Sunshell Town Teleporter",
         "no sprite but it talks means it is a sign"
long = "This is a very long piece of signage indeed, going on well past the limit"
check d.(Ev.new(sprite: "", list: text(long))).length < 60, "a long sign is shortened"
check d.(Ev.new(sprite: "", list: text(long))).end_with?("..."), "and says so"

check_eq d.(Ev.new(sprite: "", list: [Cmd.new(MOVE_ROUTE, [-1, nil]), Cmd.new(DONE)])),
         "Move trigger", "an invisible tile that moves you is called out"
check_eq d.(Ev.new(sprite: "", list: [Cmd.new(SWITCH, [1, 1, 0]), Cmd.new(DONE)])),
         "Trigger tile", "and any other invisible tile too"

check_eq d.(Ev.new(sprite: "NPC 19")), "Person", "a silent NPC sprite is a person"
check_eq d.(Ev.new(sprite: "Whirlpool")), "Object (Whirlpool)",
         "an unrecognised sprite at least names itself"
check_eq d.(Ev.new(sprite: "Object ball")), "Item ball", "the item-ball sprite is recognised"
check_eq d.(Ev.new(sprite: "HealBell")), "Healing machine", "so is the healing machine"

# ── The control codes must never be read out ────────────────────────────────
noisy = d.(Ev.new(sprite: "", list: text("\\ff[99]\\b[3]Careful now.")))
check !noisy.include?("\\"), "control codes are stripped from a sign"
check noisy.include?("Careful"), "but the words survive"

# ── When it must keep quiet ─────────────────────────────────────────────────
writer_named = Ev.new(name: "Vending machine 1", sprite: "trchar018")
mine         = Ev.new(name: "EV001", sprite: "trchar018")
mine.custom_name = "My favourite hiker"
generated    = Ev.new(name: "EV002", sprite: "trchar018")
virtual      = Object.new                     # no character_name: a POI

A11yNames.apply([writer_named, mine, generated, virtual])
check_eq writer_named.custom_name, nil, "a name the game's writers gave is left alone"
check_eq mine.custom_name, "My favourite hiker", "a name you set yourself is left alone"
check_eq generated.custom_name, "Hiker", "only the EV000 ones get filled in"

blank = Ev.new(name: "EV003", sprite: "trchar018")
blank.custom_name = "   "
A11yNames.apply([blank])
check_eq blank.custom_name, "Hiker", "a blank custom name counts as empty"

ok = true
begin
  A11yNames.apply(nil)
  A11yNames.apply([nil, Object.new, "not an event"])
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
end
check ok, "rubbish passed to apply is ignored rather than crashing the game"

# ── The hook, and reloading ─────────────────────────────────────────────────
check Game_Player.method_defined?(:a11y_names_populate_event_list),
      "populate_event_list is hooked on Game_Player, not the top level"
$populated = false
PraSession.mapevents = [Ev.new(name: "EV004", sprite: "trchar007")]
Game_Player.new.populate_event_list
check $populated, "the original populate_event_list still runs"
check_eq PraSession.mapevents[0].custom_name, "Beauty",
         "and the list comes back with names filled in"

ok = true
begin
  2.times { load mod }
  Game_Player.new.populate_event_list
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
end
check ok, "a soft reset reloads it without recursing"

puts "=" * 56
puts " RESULTS: #{$pass} passed, #{$fail} failed"
puts "=" * 56
exit($fail == 0 ? 0 : 1)
