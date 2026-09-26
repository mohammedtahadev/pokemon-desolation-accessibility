# Exercises AccessibilitySummary: the "Accessible Summary" menu entry, the
# self-speaking list screen behind it, the K key, and the lines every view
# builds from a Pokemon.
#
#   ruby test_summary.rb ../patch/Mods/AccessibilitySummary.rb
$pass = 0; $fail = 0
def check(c, n); c ? ($pass += 1; puts "PASS: #{n}") : ($fail += 1; puts "FAIL: #{n}"); end
def check_eq(a, e, n)
  if a == e then $pass += 1; puts "PASS: #{n}"
  else $fail += 1; puts "FAIL: #{n}\n        expected: #{e.inspect}\n        actual:   #{a.inspect}" end
end

module AccessibilitySpeech
  def self.speak(*a, **k); end
  def self.log(*a); end
  def self.enabled; true; end
end
def _INTL(s, *a); a.each_with_index { |v, i| s = s.gsub("{#{i + 1}}", v.to_s) }; s; end
def getAbilityName(a); a.to_s.capitalize; end
def getAbilityDesc(a); "Lowers the foe's Attack."; end

module PBStatuses
  SLEEP = 1; POISON = 2; BURN = 3; PARALYSIS = 4; FROZEN = 5
end
module PBNatures
  # Desolation's real one indexes an array, so a Symbol raises. If the mod
  # ever calls this with a nature again, these tests fail.
  def self.getName(n)
    raise TypeError, "no implicit conversion of Symbol into Integer" if n.is_a?(Symbol)
    ["Hardy", "Lonely", "Brave", "Adamant", "Naughty", "Bold"][n]
  end
end

# Stat indexes: 0 HP, 1 Attack, 2 Defense, 3 Special Attack, 4 Special
# Defense, 5 Speed - Desolation's order.
NatureData = Struct.new(:name, :incStat, :decStat)
def getNatureName(sym); ($cache.natures[sym] && $cache.natures[sym].name).to_s; end

MonData = Struct.new(:name, :dexnum, :kind, :Type1, :Type2, :dexentry, :BaseStats)
ItemData = Struct.new(:name, :desc)
MoveData = Struct.new(:name, :type, :category, :basedamage, :accuracy, :desc)
class CacheStub
  attr_reader :pkmn, :items, :moves, :natures
  def initialize
    @natures = { :BOLD => NatureData.new("Bold", 2, 1),        # Defense up, Attack down
                 :HARDY => NatureData.new("Hardy", 0, 0) }     # neutral
    @pkmn = { :GROWLITHE => MonData.new("Growlithe", 58, "Puppy", :FIRE, nil,
                                        "It is very protective of its territory.",
                                        [55, 70, 45, 70, 50, 60]) }
    @items = { :ORANBERRY => ItemData.new("Oran Berry", "Restores 10 HP in a pinch.") }
    @moves = { :EMBER => MoveData.new("Ember", :FIRE, :special, 40, 100, "May burn the target."),
               :GROWL => MoveData.new("Growl", :NORMAL, :status, 0, 100, "Lowers Attack.") }
  end
end
$cache = CacheStub.new

FakeMove = Struct.new(:move, :pp) do
  def totalpp; 25; end
end

class FakePokemon
  attr_accessor :name, :species, :level, :nature, :ability, :item, :status,
                :hp, :totalhp, :attack, :defense, :spatk, :spdef, :speed,
                :happiness, :moves, :ot, :obtainLevel, :eggsteps
  def initialize
    @name = "Growlithe"; @species = :GROWLITHE; @level = 14; @nature = :BOLD
    @ability = :INTIMIDATE; @item = :ORANBERRY; @status = PBStatuses::PARALYSIS
    @hp = 30; @totalhp = 41; @attack = 22; @defense = 17; @spatk = 21
    @spdef = 16; @speed = 19; @happiness = 120
    @moves = [FakeMove.new(:EMBER, 20), FakeMove.new(:GROWL, 25)]
    @ot = "Ash"; @obtainLevel = 5; @eggsteps = 0
    # Desolation's array order: HP, Atk, Def, SpAtk, SpDef, Speed
    @iv = [31, 20, 15, 31, 10, 25]
    @ev = [4, 252, 0, 0, 0, 252]
    @exp = 2884
  end
  attr_accessor :iv, :ev, :exp
  def gender; 0; end
  def isShiny?; true; end
  def isEgg?; @eggsteps.to_i > 0; end
  def growthrate; 0; end
  def getAbilityList; [:INTIMIDATE, :FLASHFIRE]; end
end

module PBExp
  def self.startExperience(level, growth); level * 1000; end
end

# ── The pieces the self-speaking list screen runs on ────────────────────────
module Graphics
  def self.update; end
  def self.width; 480; end
  def self.height; 320; end
end

# Scripted input. Each Input.update consumes the next frame from the script:
# :down / :up move the window cursor, :c and :b are the confirm and cancel
# keys, :none is an idle frame. An exhausted script keeps answering :b so no
# loop can hang the tests.
module Input
  B = 112; C = 113; UP = 108; DOWN = 102
  @keys = {}
  @script = []
  @current = :none
  class << self
    attr_accessor :script, :current
    def press(k); @keys[k] = true; end
    def clear; @keys = {}; end
    def triggerex?(k); !!@keys[k]; end
    def update
      @keys = {}
      @current = @script.shift || :b
    end
    def trigger?(k)
      (k == B && @current == :b) || (k == C && @current == :c)
    end
    def repeat?(k)
      (k == DOWN && @current == :down) || (k == UP && @current == :up)
    end
  end
end

$windows = []
class Window_CommandPokemon
  attr_accessor :index, :z, :height, :a11y_silent
  attr_reader :commands
  def initialize(commands, width = nil)
    @commands = commands
    @index = 0
    @height = commands.length * 32
    $windows << self
  end
  def update
    case Input.current
    when :down then @index += 1 if @index < @commands.length - 1
    when :up   then @index -= 1 if @index > 0
    end
  end
  def dispose; @disposed = true; end
  def disposed?; !!@disposed; end
end

class PokemonScreen_Scene
  attr_accessor :shown
  def initialize(party); @party = party; @activecmd = 0; @shown = nil; end
  def activecmd=(v); @activecmd = v; end
  def update; $base_updates = ($base_updates || 0) + 1; end
  def pbShowCommands(helptext, commands, index = 0)
    @shown = [helptext, commands]
    # The real one runs its own loop that calls self.update - prove the
    # re-entrancy guard holds by doing the same.
    update
    $show_ret || 0
  end
end

mod = File.expand_path(ARGV[0] || "../patch/Mods/AccessibilitySummary.rb")
ok = true
begin
  load mod
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
  puts "        #{e.backtrace.first(3).join("\n        ")}"
end
check ok, "the mod loads with no error"

# ── The lines themselves ────────────────────────────────────────────────────
pkmn = FakePokemon.new
lines = A11ySummary.lines_for(pkmn)
joined = lines.join(" | ")

check_eq lines.first, "Growlithe", "a Pokemon with no nickname reads as just its species"
pkmn.name = "Rex"
check_eq A11ySummary.lines_for(pkmn).first, "Rex, a Growlithe",
         "a nicknamed one reads nickname and species"
pkmn.name = "Growlithe"

check joined.include?("Dex number 58."), "dex number"
check joined.include?("The Puppy Pokemon."), "the kind line"
check joined.include?("Fire type."), "a single type reads alone"
check joined.include?("Level 14."), "level"
check joined.include?("Male."), "gender"
check joined.include?("Shiny."), "shininess"
check joined.include?("Bold nature: Defense up, Attack down."),
      "the nature reads by name, with the stats it raises and lowers"
check joined.include?("Currently paralyzed."), "the status condition"
pkmn.nature = :HARDY
check A11ySummary.lines_for(pkmn).include?("Hardy nature, no stat changes."),
      "a neutral nature says it changes nothing"
pkmn.nature = :BOLD
check joined.include?("HP 30 of 41."), "current HP"
check joined.include?("Attack 22, Defense 17."), "physical stats"
check joined.include?("Special Attack 21, Special Defense 16."), "special stats"
check joined.include?("Speed 19."), "speed"
check joined.include?("Happiness 120 of 255."), "happiness"
check joined.include?("Ability: Intimidate."), "the ability"
check joined.include?("Lowers the foe's Attack."), "and its description as its own row"
check joined.include?("Holding Oran Berry."), "the held item"
check joined.include?("Restores 10 HP in a pinch."), "and its description"
check joined.include?("Ember, Fire type, Special, 40 power, 100 accuracy, 20 of 25 PP."),
      "a damaging move reads power, accuracy and PP"
check joined.include?("Growl, Normal type, Status, 100 accuracy, 25 of 25 PP."),
      "a status move skips the power it does not have"
check joined.include?("May burn the target."), "each move's description follows it"
check joined.include?("It is very protective of its territory."), "the Pokedex entry"
check joined.include?("Original trainer: Ash."), "the original trainer"
check joined.include?("Met at level 5."), "and where it started"
check_eq lines.last, "That is everything.", "the list says when it is done"

# Dual types read together.
$cache.pkmn[:GROWLITHE] = MonData.new("Growlithe", 58, "Puppy", :FIRE, :ROCK, "x")
check A11ySummary.lines_for(pkmn).join.include?("Fire and Rock type."),
      "a dual type reads both"

# No held item.
pkmn.item = nil
check A11ySummary.lines_for(pkmn).join(" ").include?("No held item."),
      "no item says so instead of going silent"
pkmn.item = :ORANBERRY

# An egg spoils nothing.
egg = FakePokemon.new
egg.eggsteps = 3000
egg_lines = A11ySummary.lines_for(egg)
check_eq egg_lines.first, "Egg.", "an egg reads as an egg"
check egg_lines.join.include?("3000 steps"), "with its steps to hatch"
check egg_lines.none? { |l| l.include?("Growlithe") },
      "and never names what is inside"

# ── Biology ─────────────────────────────────────────────────────────────────
require "fileutils"
FileUtils.mkdir_p("patch")
File.binwrite("patch/biology.dat", Marshal.dump({
  "GROWLITHE" => { "default" => "Growlithe is a loyal canine Pokemon." },
  "VULPIX"    => { "default" => "Vulpix has six tails.",
                   "alolan"  => "Alolan Vulpix is icy." }
}))
A11yBiology.instance_variable_set(:@data, nil)      # force a fresh load
check A11yBiology.available?, "the biology database loads from patch/biology.dat"
check_eq A11yBiology.text_for("Growlithe"), "Growlithe is a loyal canine Pokemon.",
         "a species finds its default text"
check_eq A11yBiology.text_for("ALOLAN VULPIX"), "Vulpix has six tails.",
         "a prefixed name falls back to the base species, as Reborn's mod does"
check_eq A11yBiology.text_for("Vulpix", "Alolan Form"), "Alolan Vulpix is icy.",
         "a named form finds its own text"
check_eq A11yBiology.text_for("MISSINGNO"), nil, "an unknown species reads nothing"

bio_lines = A11ySummary.lines_for(pkmn)
check bio_lines.include?("Biology:"), "the summary gains a Biology section"
check bio_lines.include?("Growlithe is a loyal canine Pokemon."), "with the prose"
i_bio = bio_lines.index("Biology:")
check i_bio && bio_lines[i_bio + 1] == "Growlithe is a loyal canine Pokemon." &&
      bio_lines[i_bio + 2] == "That is everything.",
      "placed at the end, just before the closing line"

FileUtils.rm_rf("patch")
A11yBiology.instance_variable_set(:@data, nil)
check_eq A11yBiology.text_for("Growlithe"), nil,
         "with no database file the summary simply has no Biology section"
check A11ySummary.lines_for(pkmn).none? { |l| l == "Biology:" },
      "and does not leave an empty header behind"

# ── The game's own summary screen, page by page ─────────────────────────────
$page_speech = []
AccessibilitySpeech.define_singleton_method(:speak) do |t, force = false, interrupt: true|
  $page_speech << [t.to_s, interrupt]
end

class PokemonSummaryScene
  def drawPageOne(pokemon);    $pages_drawn = ($pages_drawn || []) << :one; end
  def drawPageThree(pokemon);  $pages_drawn = ($pages_drawn || []) << :three; end
  def drawPageFour(pokemon);   $pages_drawn = ($pages_drawn || []) << :four; end
  def drawPageFive(pokemon);   $pages_drawn = ($pages_drawn || []) << :five; end
  def drawAbilPage(pokemon);   $pages_drawn = ($pages_drawn || []) << :abil; end
end
load mod   # wrap the freshly defined page methods

sscene = PokemonSummaryScene.new
$page_speech = []
sscene.drawPageOne(pkmn)
p1 = $page_speech.map(&:first).join(" | ")
check $pages_drawn.include?(:one), "the real page still draws"
check p1.include?("Info page."), "page one announces itself"
check p1.include?("Level 14."), "with the basics"
check p1.include?("Holding Oran Berry."), "and the held item"

$page_speech = []
sscene.drawPageOne(pkmn)
check $page_speech.empty?, "redrawing the same page for the same Pokemon stays quiet"

$page_speech = []
sscene.drawPageThree(pkmn)
p3 = $page_speech.map(&:first).join(" | ")
check p3.include?("Skills page."), "the skills page announces itself"
check p3.include?("Attack 22, Defense 17."), "with the stats"
check p3.include?("Ability: Intimidate. Press C for its description."),
      "and the ability, with the hint that C explains it"

$page_speech = []
sscene.drawPageFour(pkmn)
p4 = $page_speech.map(&:first).join(" | ")
check p4.include?("EV and IV page."), "the EV and IV page announces itself"
check p4.include?("EVs: HP 4, Attack 252, Defense 0, Special Attack 0, Special Defense 0, Speed 252."),
      "EVs read in DESOLATION's stat order - Speed last, not third"
check p4.include?("IVs: HP 31, Attack 20, Defense 15, Special Attack 31, Special Defense 10, Speed 25."),
      "and so do IVs"
check p4.include?("508 EVs used of 510."), "with the EV total"

$page_speech = []
sscene.drawAbilPage(pkmn)
pa = $page_speech.map(&:first).join(" | ")
check pa.include?("Intimidate."), "the ability page names the ability"
check pa.include?("Lowers the foe's Attack."), "and reads its full description"

$page_speech = []
sscene.drawPageFive(pkmn)
p5 = $page_speech.map(&:first).join(" | ")
check p5.include?("Moves page."), "the moves page announces itself"
check p5 =~ /Ember, 20 of 25 PP/, "listing each move with PP"

# A different Pokemon on the same page must speak again.
other = FakePokemon.new
other.name = "Vulpix"
$page_speech = []
sscene.drawPageFive(other)
check !$page_speech.empty?, "switching Pokemon re-reads the page"

# ── Learning and browsing moves ─────────────────────────────────────────────
# drawSelectedMove fires on every cursor movement over moves - on the summary
# move page and in the level-up "forget which move?" flow alike.
$move_speech = []
AccessibilitySpeech.define_singleton_method(:speak) do |t, force = false, interrupt: true|
  $move_speech << [t.to_s, interrupt]
end

class PokemonSummaryScene
  def drawSelectedMove(pokemon, moveToLearn, move); $drawn = move; end
end
load mod    # re-load so the hook wraps the freshly defined scene method

scene = PokemonSummaryScene.new
$move_speech = []
scene.drawSelectedMove(pkmn, 0, :EMBER)
check_eq $drawn, :EMBER, "the real drawing still happens"
first = $move_speech.map(&:first)
check first.any? { |t| t == "Ember, Fire type, Special, 40 power, 100 accuracy, 20 of 25 PP" },
      "landing on a known move reads it in full, with its real remaining PP"
check first.include?("May burn the target."), "followed by its description"
check_eq $move_speech.last[1], false, "which queues, so it can be listened through"

$move_speech = []
scene.drawSelectedMove(pkmn, 0, :EMBER)
check $move_speech.empty?, "a redraw of the same move stays quiet"

$move_speech = []
scene.drawSelectedMove(pkmn, :GROWL, :GROWL)
growl = $move_speech.map(&:first)
check growl.any? { |t| t == "New move: Growl, Normal type, Status, 100 accuracy" },
      "the move being LEARNED is prefixed New move, with no PP it does not have yet"
check growl.include?("Lowers Attack."), "and its description"

# ── Everything from here on captures speech into $spoken ───────────────────
$spoken = []
AccessibilitySpeech.define_singleton_method(:speak) do |t, force = false, interrupt: true|
  ($spoken ||= []) << [t.to_s, interrupt]
end
def spoken_texts; $spoken.map(&:first); end

# ── The view builders ───────────────────────────────────────────────────────
sd = A11ySummary.stat_detail_lines(pkmn)
check sd.include?("Bold nature: Defense up, Attack down."),
      "the stats view opens with the nature"
check sd.include?("HP: 41 total. IV 31, EV 4."), "HP with its IV and EV"
check sd.include?("Attack: 22 total. IV 20, EV 252."), "Attack likewise"
check sd.include?("Special Attack: 21 total. IV 31, EV 0."),
      "Special Attack reads index 3 - Desolation's order, not standard"
check sd.include?("Speed: 19 total. IV 25, EV 252."), "and Speed reads index 5, LAST"
check sd.include?("508 EVs used of 510."), "with the EV total"
check sd.include?("12116 experience points to the next level."),
      "and the experience still needed"
check_eq sd.last, "That is all the stats.", "the view says when it is done"

# The species entry was replaced without base stats by the dual-type test;
# restore the full one.
$cache.pkmn[:GROWLITHE] = MonData.new("Growlithe", 58, "Puppy", :FIRE, nil,
                                      "It is very protective of its territory.",
                                      [55, 70, 45, 70, 50, 60])
bl = A11ySummary.base_stat_lines(pkmn)
check bl.include?("Growlithe."), "the base stats view names the species"
check bl.include?("Fire type."), "and its typing"
check bl.include?("Base HP 55."), "base HP"
check bl.include?("Base Special Attack 70."), "base Special Attack from index 3"
check bl.include?("Base Speed 60."), "base Speed from index 5"
check bl.include?("Base stat total 350."), "and the BST"
check bl.include?("Possible abilities: Intimidate, Flashfire."),
      "every ability the species can have"
check bl.include?("Its ability: Intimidate."), "and the one this Pokemon has"
check bl.include?("Lowers the foe's Attack."), "with its description"

FileUtils.mkdir_p("patch")
File.binwrite("patch/biology.dat", Marshal.dump({
  "GROWLITHE" => { "default" => "First sentence. Second one! A third?" }
}))
A11yBiology.instance_variable_set(:@data, nil)
rows = A11ySummary.biology_lines(pkmn)
check_eq rows[0], "First sentence.", "biology splits into sentences"
check_eq rows[1], "Second one!", "at every terminator"
check_eq rows[2], "A third?", "question marks included"
check_eq rows.last, "That is the whole entry.", "and closes"
FileUtils.rm_rf("patch")
A11yBiology.instance_variable_set(:@data, nil)
check_eq A11ySummary.biology_lines(pkmn), ["No biology entry for Growlithe."],
         "no database reads as no entry, not as silence"

# ── The menu entry injection ────────────────────────────────────────────────
ext, added = A11ySummary.extend_commands(["Summary", "Switch", "Cancel"])
check added, "a Pokemon action menu gains the entry"
check_eq ext, ["Summary", "Switch", "Cancel", "Accessible Summary"],
         "appended AFTER Cancel - no game index moves"
_, added2 = A11ySummary.extend_commands(["Yes", "No"])
check !added2, "a menu without Summary is left alone"
_, added3 = A11ySummary.extend_commands(ext)
check !added3, "and it never doubles up"
AccessibilitySpeech.define_singleton_method(:enabled) { false }
_, added4 = A11ySummary.extend_commands(["Summary", "Cancel"])
check !added4, "with speech off the game menus stay untouched"
AccessibilitySpeech.define_singleton_method(:enabled) { true }

# ── The self-speaking list ──────────────────────────────────────────────────
$spoken = []
Input.script = [:none, :down, :c, :b]
ret = A11ySummary.browse("Test list", ["Row one", "Row two"])
check_eq ret, -1, "B closes a browse list"
check spoken_texts[0].include?("Test list") && spoken_texts[0].include?("2 rows"),
      "the list announces itself and its size"
check_eq spoken_texts[1], "Row one", "then reads the first row unprompted"
check spoken_texts.include?("Row two"), "arrowing down reads the next row"
check spoken_texts.include?("Row 2 of 2. Row two"),
      "C repeats the row with its position"
check_eq $windows.last.a11y_silent, true,
         "the generic menu reader is silenced - this list speaks for itself"
check $windows.last.disposed?, "and the window is disposed on close"

$spoken = []
Input.script = [:down, :c]
ret = A11ySummary.choose("Pick", ["A", "B", "C"])
check_eq ret, 1, "in menu mode C chooses the focused row"

# ── The Accessible Summary menu itself ──────────────────────────────────────
$spoken = []
Input.script = [:c, :b, :b]           # open Everything, close it, close menu
A11ySummary.run_menu(pkmn)
check spoken_texts.any? { |t| t.include?("Accessible summary of Growlithe") },
      "the menu announces whose summary it is"
check spoken_texts.include?("Everything"), "and its first option"
check spoken_texts.any? { |t| t.include?("Everything about Growlithe") },
      "choosing Everything opens the full readout"
check spoken_texts.include?("Growlithe"), "which reads the Pokemon"

egg = FakePokemon.new
egg.eggsteps = 3000
$spoken = []
Input.script = [:b]
A11ySummary.run_menu(egg)
check spoken_texts.any? { |t| t.include?("Egg") }, "an egg opens a plain egg readout"
check spoken_texts.none? { |t| t.include?("Growlithe") }, "that spoils nothing"

# ── Export team ─────────────────────────────────────────────────────────────
$Trainer = Struct.new(:name, :party).new("Tester", [pkmn])
teamfile = "Tester's team.txt"
File.delete(teamfile) if File.exist?(teamfile)
$spoken = []
A11ySummary.export_team
check File.exist?(teamfile), "the team file is written"
team = File.read(teamfile)
check team.include?("Growlithe (M) @ Oran Berry"), "species, gender and item"
check team.include?("Ability: Intimidate"), "the ability"
check team.include?("Bold Nature"), "the nature"
check team.include?("EVs: 4 HP / 252 Atk / 0 Def / 0 SpA / 0 SpD / 252 Spe"),
      "EVs in showdown order, mapped from Desolation's array order"
check team.include?("IVs: 31 HP / 20 Atk / 15 Def / 31 SpA / 10 SpD / 25 Spe"),
      "IVs likewise"
check team.include?("- Ember"), "and the moves"
check spoken_texts.any? { |t| t.include?("Team exported") }, "spoken confirmation"
File.delete(teamfile) if File.exist?(teamfile)

# ── The party scene menu wrapper ────────────────────────────────────────────
wscene = PokemonScreen_Scene.new([pkmn])
$show_ret = 0
wscene.pbShowCommands("Do what with Growlithe?", ["Summary", "Cancel"])
check_eq wscene.shown[1], ["Summary", "Cancel", "Accessible Summary"],
         "the party action menu shows the extra entry"
check_eq wscene.pbShowCommands("Do what with Growlithe?", ["Summary", "Cancel"]), 0,
         "choosing Summary still returns Summary's index"

$show_ret = 2                          # the appended entry
Input.script = [:b]
$spoken = []
ret = wscene.pbShowCommands("Do what with Growlithe?", ["Summary", "Cancel"])
check_eq ret, -1, "choosing it is handled here; the game sees only a cancel"
check spoken_texts.any? { |t| t.include?("Accessible summary of Growlithe") },
      "and the accessible summary menu opened"

$show_ret = 0
wscene.pbShowCommands("Really quit?", ["Yes", "No"])
check_eq wscene.shown[1], ["Yes", "No"], "a non-Pokemon menu passes through untouched"
$show_ret = nil

# ── The K key on the party screen ───────────────────────────────────────────
scene = PokemonScreen_Scene.new([pkmn])
Input.clear
$base_updates = 0
$spoken = []
scene.update
check $spoken.empty?, "without K, nothing opens"
check $base_updates >= 1, "and the original update ran"

Input.press(0x4B)
Input.script = [:b]
$spoken = []
scene.update
check spoken_texts.any? { |t| t.include?("Accessible summary of Growlithe") },
      "K opens the accessible summary menu for the highlighted Pokemon"
Input.clear

# K on an empty slot (confirm/cancel row) must do nothing.
scene2 = PokemonScreen_Scene.new([pkmn])
scene2.activecmd = 6
Input.press(0x4B)
$spoken = []
scene2.update
check $spoken.empty?, "K on the confirm or cancel row does nothing"
Input.clear

# ── Reloading ───────────────────────────────────────────────────────────────
ok = true
begin
  2.times { load mod }
  scene.update
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
end
check ok, "a soft reset reloads it without recursing"

puts "=" * 56
puts " RESULTS: #{$pass} passed, #{$fail} failed"
puts "=" * 56
exit($fail == 0 ? 0 : 1)
