# test_a11y.rb - exercises the Desolation accessibility mods outside the game.
#
# The mods reopen engine classes, so this harness defines just enough of the
# Pokemon Essentials surface for them to load, then checks that each screen
# produces the line a player should hear. Speech is captured instead of spoken.
#
#   ruby test_a11y.rb ../patch/Mods

MODS = ARGV[0] || "."
$pass = 0
$fail = 0

def check(cond, name)
  if cond
    $pass += 1
    puts "PASS: #{name}"
  else
    $fail += 1
    puts "FAIL: #{name}"
  end
end

def check_eq(actual, expected, name)
  if actual == expected
    $pass += 1
    puts "PASS: #{name}"
  else
    $fail += 1
    puts "FAIL: #{name}\n        expected: #{expected.inspect}\n        actual:   #{actual.inspect}"
  end
end

# Engine stubs live in stubs_desolation.rb, shared with test_load_order.rb.
require_relative "stubs_desolation"

# ── Load the mods under test ─────────────────────────────────────────────────
# ClientData.rb does: Dir["./Data/Mods/*.rb"].each { |f| load ... }
# Dir returns names ALPHABETICALLY, so AccessibilityMenus.rb loads BEFORE
# AccessibilitySpeech.rb. Loading them in that same order here is what catches
# load-time references to a module that does not exist yet - the harness
# previously loaded Speech first and so missed exactly that bug.
# The pathfinder needs a far richer environment than this harness provides
# (MapFactory, terrain tags, event lists, the interpreter), so it has its
# own: test_pathfind.rb. Everything else loads here, in the game order.
Dir[File.join(MODS, "*.rb")].sort.each do |f|
  next if File.basename(f) == "AccessibilityPathfind.rb"
  load f
end

# Capture speech instead of speaking it.
$spoken = []
module AccessibilitySpeech
  class << self
    def speak(text, force = false, interrupt: true)
      clean = sanitize(text)
      return if clean.empty?
      return if !force && clean == @last_text
      @last_text = clean
      $spoken << clean
    end
    def log(msg); end
  end
end
def spoke; $spoken.last; end
def reset_spoken; $spoken = []; AccessibilitySpeech.instance_variable_set(:@last_text, nil); end

puts "=" * 60
puts " Desolation accessibility mod - logic tests"
puts "=" * 60

# ── 1. Text sanitizing ───────────────────────────────────────────────────────
check_eq AccessibilitySpeech.sanitize("Hello\\nworld"), "Hello world", "sanitize: newline code"
check_eq AccessibilitySpeech.sanitize("\\c[3]Red text"), "Red text", "sanitize: colour code"
check_eq AccessibilitySpeech.sanitize("HP <br>restored"), "HP restored", "sanitize: html-ish tag"
check_eq AccessibilitySpeech.sanitize("  spaced   out  "), "spaced out", "sanitize: whitespace"
check_eq AccessibilitySpeech.sanitize("\\v[12] items"), "items", "sanitize: variable code"
# The bug the player hit: a face-portrait code read out mid-sentence.
# Single-quoted Ruby strings keep backslashes literal.
check_eq AccessibilitySpeech.sanitize('\ff[08c]Damn it, where did I put it...'),
         "Damn it, where did I put it...", "sanitize: face portrait code is stripped"
check_eq AccessibilitySpeech.sanitize('\ff[face,2]Hello there'), "Hello there",
         "sanitize: face code with several parameters"
check_eq AccessibilitySpeech.sanitize('\zz[whatever]Text'), "Text",
         "sanitize: an unknown bracketed code is stripped too"
check_eq AccessibilitySpeech.sanitize('\wtnp[30]Wait then continue'), "Wait then continue",
         "sanitize: timing codes are stripped"
check_eq AccessibilitySpeech.sanitize('\[6546675A]Coloured'), "Coloured",
         "sanitize: the bare colour form is stripped"
check_eq AccessibilitySpeech.sanitize('\ff[08c]'), "",
         "sanitize: a code-only message says nothing"
check_eq AccessibilitySpeech.sanitize('Line one\nLine two'), "Line one Line two",
         "sanitize: a newline code becomes a gap, not a swallowed word"
check_eq AccessibilitySpeech.sanitize('\c[3]Coloured words'), "Coloured words",
         "sanitize: colour code with text after it"
check_eq AccessibilitySpeech.sanitize("ROSETTA: It is fine!"),
         "ROSETTA: It is fine!", "sanitize: ordinary dialogue is left alone"

# ── 2. The universal window hook ─────────────────────────────────────────────
reset_spoken
w = Window_CommandPokemon.new(["Pokedex", "Pokemon", "Bag", "Save"])
w.index = 2
check_eq spoke, "Bag", "command window: speaks the selected row"

reset_spoken
w2 = Window_AdvancedCommandPokemon.new(["<c=1>Quest One", "Quest Two"])
w2.index = 0
check_eq spoke, "Quest One", "advanced command window: strips markup"

reset_spoken
bagwin = Window_PokemonBag.new(FakeBag.new, 1)
bagwin.index = 0
check_eq spoke, "Potion times 5", "bag: item name and quantity"
bagwin.index = 1
check_eq spoke, "HM01", "bag: key item has no quantity"
bagwin.index = 2
check_eq spoke, "Close bag", "bag: past the last item is Close bag"

reset_spoken
mart = Window_PokemonMart.new([:POTION, nil])
mart.index = 0
check_eq spoke, "Potion, $200", "shop: item name and price"
mart.index = 1
check_eq spoke, "Cancel", "shop: nil entry is Cancel"

reset_spoken
dex = Window_Pokedex.new([:PIKACHU, :MEW, :EEVEE])
dex.index = 0
check_eq spoke, "Pikachu, caught", "pokedex: caught species"
dex.index = 1
check_eq spoke, "Mew, not yet seen", "pokedex: unseen species"
dex.index = 2
check_eq spoke, "Eevee, seen", "pokedex: seen but not caught"

# ── 3. Options: row AND value ────────────────────────────────────────────────
reset_spoken
opts = [FakeOption.new("Sound", ["Stereo", "Mono"]), FakeOption.new("Text Speed", ["Slow", "Normal", "Fast"])]
ow = Window_PokemonOption.new(opts)
ow.index = 0
check_eq spoke, "Sound, Stereo", "options: name and current value"
ow.index = 1
check_eq spoke, "Text Speed, Slow", "options: second row"
# Simulate LEFT/RIGHT changing the value without moving the row.
reset_spoken
ow.pending_value = 2
ow.update
check_eq spoke, "Text Speed, Fast", "options: value change names the setting and reads the value"

reset_spoken
numopt = [FakeOption.new("Volume", nil, 0)]
nw = Window_PokemonOption.new(numopt)
nw.index = 0
check_eq spoke, "Volume, 0", "options: numeric option reads its number"

# ── 4. Party screen ──────────────────────────────────────────────────────────
reset_spoken
party = [FakePokemon.new("Pikachu", 25, 40, 60, 1),
         FakePokemon.new("Eevee", 12, 0, 30),
         FakePokemon.new("Egg", 1, 5, 5, 0, nil, true)]
ps = PokemonScreen_Scene.new(party)
ps.instance_variable_set(:@activecmd, 0)
ps.update
check_eq spoke, "Pikachu, level 25, 40 of 60 HP, poisoned", "party: name, level, HP and status"
ps.instance_variable_set(:@activecmd, 1)
ps.update
check_eq spoke, "Eevee, level 12, fainted", "party: fainted member"
ps.instance_variable_set(:@activecmd, 2)
ps.update
check_eq spoke, "Egg", "party: egg"
ps.instance_variable_set(:@activecmd, 6)
ps.update
check_eq spoke, "Cancel", "party: cancel slot"

# Held item shows up.
reset_spoken
holder = [FakePokemon.new("Snorlax", 30, 100, 100, 0, :ORAN)]
ps2 = PokemonScreen_Scene.new(holder)
ps2.instance_variable_set(:@activecmd, 0)
ps2.update
check spoke.include?("holding Oran Berry"), "party: announces a held item"

# ── 5. Summary pages ─────────────────────────────────────────────────────────
reset_spoken
sum = PokemonSummaryScene.new(FakePokemon.new("Pikachu", 25, 40, 60))
sum.pbUpdate
check spoke.to_s.include?("Info"), "summary: first page announces the page name"
check $spoken.first.to_s.include?("Pikachu"), "summary: first view announces the Pokemon"
sum.instance_variable_set(:@page, 4)
sum.pbUpdate
check_eq spoke, "Moves", "summary: page change announced"
sum.instance_variable_set(:@abilpage, true)
sum.pbUpdate
check_eq spoke, "Ability page", "summary: ability overlay announced"

reset_spoken
ms = MoveSelectionSprite.new
ms.index = 2
check_eq spoke, nil,
         "summary: the bare slot number is silent - AccessibilitySummary reads "          "the actual move in full on the same cursor movement instead"

# ── 6. PC storage ────────────────────────────────────────────────────────────
reset_spoken
boxmons = Array.new(30)
boxmons[0] = FakePokemon.new("Zubat", 8, 20, 20)
boxmons[7] = FakePokemon.new("Onix", 15, 40, 40)
storage = FakeStorage.new([FakeBox.new("Box 1", boxmons)], [FakePokemon.new("Bulbasaur", 5, 20, 20)])
ss = PokemonStorageScene.new(storage)
ss.pbSetArrow(nil, 0)
check_eq spoke, "Zubat, level 8, 20 of 20 HP, row 1 column 1", "storage: occupied slot with grid position"
ss.pbSetArrow(nil, 7)
check_eq spoke, "Onix, level 15, 40 of 40 HP, row 2 column 2", "storage: row/column maths"
ss.pbSetArrow(nil, 1)
check_eq spoke, "Empty, row 1 column 2", "storage: empty slot"
ss.pbSetArrow(nil, -2)
check_eq spoke, "Party", "storage: party button"
ss.pbSetArrow(nil, -3)
check_eq spoke, "Close box", "storage: close button"
ss.pbSetArrow(nil, -1)
check_eq spoke, "Box Box 1", "storage: box name header"

reset_spoken
ss.pbPartySetArrow(nil, 0)
check_eq spoke, "Bulbasaur, level 5, 20 of 20 HP", "storage: party tab reads from storage.party"
ss.pbPartySetArrow(nil, 6)
check_eq spoke, "Close box", "storage: party tab close"

reset_spoken
ss.pbUpdateOverlay(0)
check spoke.to_s.include?("Box 1"), "storage: box announced on first overlay"

# ── 7. Region map ────────────────────────────────────────────────────────────
reset_spoken
mb = MapBottomSprite.new
mb.maplocation = "Emerald City"
check_eq spoke, "Emerald City", "region map: location announced"
mb.maplocation = "Emerald City"
check_eq $spoken.length, 1, "region map: unchanged location is not repeated"

# ── 8. Text entry ────────────────────────────────────────────────────────────
reset_spoken
te = Window_TextEntry.new
te.insert("A")
check_eq spoke, "A", "text entry: speaks typed character"
te.insert(" ")
check_eq spoke, "space", "text entry: speaks space by name"
te.delete
check_eq spoke, "deleted space", "text entry: speaks deletion"

# ── 9. Trainer card and dex entry ────────────────────────────────────────────
reset_spoken
tc = PokemonTrainerCardScene.new
tc.pbDrawTrainerCardFront
check spoke.to_s.include?("Ash"), "trainer card: reads the card"
check spoke.to_s.include?("2 badges"), "trainer card: counts badges"

reset_spoken
pd = PokemonPokedexScene.new
pd.pbChangeToDexEntry(:PIKACHU)
check spoke.to_s.include?("Pikachu"), "dex entry: species name"
check spoke.to_s.include?("stores electricity"), "dex entry: flavour text"

# ── 10. Robustness: nothing may raise ────────────────────────────────────────
reset_spoken
ok = true
begin
  broken = Window_CommandPokemon.new(nil)
  broken.index = 5
  Window_PokemonBag.new(FakeBag.new, 99).index = 3
  PokemonScreen_Scene.new(nil).update
  PokemonStorageScene.new(nil).pbSetArrow(nil, 4)
  PokemonSummaryScene.new(nil).pbUpdate
  MapBottomSprite.new.maplocation = nil
rescue Exception => e
  ok = false
  puts "        raised: #{e.class}: #{e.message}"
end
check ok, "robustness: broken/missing data never raises"

# Re-entry guard: loading twice must not recurse.
reset_spoken
ok2 = true
begin
  load File.join(MODS, "AccessibilityMenus.rb")
  w3 = Window_CommandPokemon.new(["Alpha", "Beta"])
  w3.index = 1
  ok2 = (spoke == "Beta")
rescue Exception => e
  ok2 = false
  puts "        raised: #{e.class}: #{e.message}"
end
check ok2, "re-entry guard: a second load still works and does not recurse"


# ── 11. Options: the unlabeled Cancel row ────────────────────────────────────
reset_spoken
ow2 = Window_PokemonOption.new([FakeOption.new("Sound", ["Stereo", "Mono"])])
ow2.index = 1   # one past the last option = the Cancel button
check_eq spoke, "Confirm", "options: the extra final row is announced as Confirm"

# ── 12. First line must not interrupt (so a question is heard) ───────────────
reset_spoken
$interrupts = []
module AccessibilitySpeech
  class << self
    def speak(text, force = false, interrupt: true)
      clean = sanitize(text)
      return if clean.empty?
      return if !force && clean == @last_text
      @last_text = clean
      $spoken << clean
      $interrupts << interrupt
    end
  end
end
yn = Window_CommandPokemon.new(["Yes", "No"])
yn.index = 0                       # window opens on Yes
check_eq $interrupts.last, false, "choices: the first line queues instead of cutting off the question"
yn.index = 1                       # player moves to No
check_eq spoke, "No", "choices: moving announces the new option"
check_eq $interrupts.last, true, "choices: later moves interrupt so scrolling stays responsive"

# ── 13. Event-driven picture selector (character appearance) ─────────────────
reset_spoken
A11yEvents.reset
interp = Interpreter.new

# A picture swap with NO button wait must stay silent (ordinary cutscene art).
interp.parameters = [1, "charbg1"]; interp.command_231
interp.parameters = [1, "charbg2"]; interp.command_231
check_eq $spoken.length, 0, "event selector: cutscene pictures are not announced"

# After a Button Input Processing, the same swap IS a selection moving.
A11yEvents.reset
interp.parameters = [179]; interp.command_105
interp.parameters = [1, "charbg1"]; interp.command_231
interp.parameters = [1, "charbg3"]; interp.command_231
check_eq spoke, "Look 3 of 6", "event selector: appearance choice is announced with a total"

# An unknown selector still gets a usable announcement.
A11yEvents.reset
interp.parameters = [179]; interp.command_105
interp.parameters = [4, "someUi1"]; interp.command_231
interp.parameters = [4, "someUi2"]; interp.command_231
check_eq spoke, "Option 2", "event selector: unknown picker falls back to Option N"

# A different base name in the same slot is a scene change, not a selection.
A11yEvents.reset
interp.parameters = [179]; interp.command_105
interp.parameters = [1, "charbg1"]; interp.command_231
reset_spoken
interp.parameters = [1, "titleScreen2"]; interp.command_231
check_eq $spoken.length, 0, "event selector: a different picture base is not a selection"

# The window expires, so pictures long after a button press stay quiet.
A11yEvents.reset
interp.parameters = [179]; interp.command_105
interp.parameters = [1, "charbg1"]; interp.command_231
Graphics.frame_count += 5000
reset_spoken
interp.parameters = [1, "charbg2"]; interp.command_231
check_eq $spoken.length, 0, "event selector: the button-input window expires"

# Erasing a picture forgets the slot.
A11yEvents.reset
interp.parameters = [179]; interp.command_105
interp.parameters = [1, "charbg1"]; interp.command_231
interp.parameters = [1]; interp.command_235
reset_spoken
interp.parameters = [1, "charbg2"]; interp.command_231
check_eq $spoken.length, 0, "event selector: erasing a picture clears the slot memory"


# ── 14. Options: names on sliders and the confirm row ────────────────────────
reset_spoken
sliders = [FakeOption.new("BGM Volume", nil, 0),
           FakeOption.new("Screen Size", ["S", "M", "L", "XL", "Full"])]
sw = Window_PokemonOption.new(sliders)
sw.index = 2   # one past the last option
check_eq spoke, "Confirm", "options: the final row is announced as Confirm"

reset_spoken
sw2 = Window_PokemonOption.new(sliders)
sw2.index = 0
sw2.pending_value = 50
sw2.update
check_eq spoke, "BGM Volume, 50", "options: first change on a slider names the setting"
sw2.pending_value = 51
sw2.update
check_eq spoke, "51", "options: holding the key reads bare numbers"
# After the quiet period the name comes back.
sw2.instance_variable_set(:@a11y_val_at, Time.now.to_f - 5.0)
sw2.pending_value = 52
sw2.update
check_eq spoke, "BGM Volume, 52", "options: after a pause the setting is named again"

reset_spoken
sw3 = Window_PokemonOption.new(sliders)
sw3.index = 1
sw3.pending_value = 3
sw3.update
check_eq spoke, "Screen Size, XL", "options: screen size names itself and reads its value"

# The options window announces its starting row without any index= call.
reset_spoken
sw4 = Window_PokemonOption.new(sliders)
sw4.update
check_eq spoke, "BGM Volume, 0", "options: the starting row is announced on open"


# ── 15. Tile sounds (Legend RPG layout) ──────────────────────────────────────
A11yWorld.instance_variable_set(:@variant_counts, nil)
A11yWorld.instance_variable_set(:@map_surface_cache, nil)
$existing_audio = []
%w[grass generic water hardwood cavegrounds pavement dirt].each do |surf|
  (1..5).each { |n| $existing_audio << "Audio/tile_sounds/#{surf}/step#{n}.ogg" }
  $existing_audio << "Audio/tile_sounds/#{surf}/land.ogg"
  $existing_audio << "Audio/tile_sounds/#{surf}/fall.ogg"
end

check_eq A11yWorld.variant_count("grass"), 5, "tile sound: finds all five step variants"
check_eq A11yWorld.variant_count("ice"), 0, "tile sound: a surface with no files reports none"

$played_se = []
$game_map.tags[[3, 4]] = 2        # grass
$game_player.x = 3; $game_player.y = 4
$game_player.move_one
check ($played_se.last && $played_se.last[0]).to_s.start_with?("Audio/tile_sounds/grass/step"),
      "tile sound: a grass tile plays a grass step"

$played_se = []
60.times { $game_player.move_one }
seq = $played_se.map { |p| p[0] }
check seq.uniq.length > 1, "tile sound: variants actually vary (#{seq.uniq.length} distinct)"
repeats = 0
seq.each_cons(2) { |a, b| repeats += 1 if a == b }
check_eq repeats, 0, "tile sound: the same variant never repeats back to back"

# ── Map name decides the surface of featureless ground ───────────────────────
A11yWorld.instance_variable_set(:@map_surface_cache, nil)
$map_names = { 1 => "Route 1", 2 => "Cellia Apartments 3F", 3 => "Weeping Depths",
               4 => "Celeste City", 5 => "Silver Forest", 6 => "Somewhere Odd" }
check_eq A11yWorld.map_surface(2), "hardwood",    "map surface: apartments sound like hardwood"
check_eq A11yWorld.map_surface(3), "cavegrounds", "map surface: depths sound like a cave floor"
check_eq A11yWorld.map_surface(4), "pavement",    "map surface: a city sounds like pavement"
check_eq A11yWorld.map_surface(5), "leaves",      "map surface: a forest sounds like leaves"
check_eq A11yWorld.map_surface(1), "dirt",        "map surface: a route sounds like dirt"
check_eq A11yWorld.map_surface(6), "generic",     "map surface: an unmatched name falls back to generic"

# Plain ground takes the map's surface; real terrain never does.
$game_map.map_id = 2               # apartments
A11yWorld.instance_variable_set(:@map_surface_cache, nil)
check_eq A11yWorld.surface_for(13), "hardwood", "map surface: neutral ground uses the map's surface"
check_eq A11yWorld.surface_for(2),  "grass",    "map surface: a grass tile stays grass indoors or out"
check_eq A11yWorld.surface_for(7),  "water",    "map surface: a water tile stays water"
$game_map.map_id = 1

# ── land and fall belong to ledges only ──────────────────────────────────────
$played_se = []
$facing_ledge = false
$game_map.tags[[3, 4]] = 2
$game_player.x = 3; $game_player.y = 4
40.times { $game_player.move_one }
names = $played_se.map { |p| p[0] }
check_eq names.any? { |n| n.include?("/land") }, false, "walking: never plays a landing sound"
check_eq names.any? { |n| n.include?("/fall") }, false, "walking: never plays a falling sound"

# A real ledge hop plays the drop and then the landing.
$played_se = []
$facing_ledge = true
pbLedge(0, 1)
$facing_ledge = false
names = $played_se.map { |p| p[0] }
check_eq names.first, "Audio/tile_sounds/grass/fall.ogg", "ledge: the drop plays the falling sound"
check_eq names.last,  "Audio/tile_sounds/grass/land.ogg", "ledge: the landing plays the landing sound"
check_eq A11yWorld.landing, false, "ledge: the landing flag is cleared afterwards"

# pbLedge on a non-ledge tile must do nothing at all.
$played_se = []
$facing_ledge = false
pbLedge(0, 1)
check_eq $played_se.length, 0, "ledge: facing an ordinary tile makes no sound"

# ── Fallbacks and quiet states ───────────────────────────────────────────────
$played_se = []
$game_map.tags[[7, 7]] = 12       # ice, no files installed here
$game_player.x = 7; $game_player.y = 7
$game_player.move_one
check ($played_se.last && $played_se.last[0]).to_s.start_with?("Audio/tile_sounds/generic/step"),
      "tile sound: an unavailable surface falls back to generic"

check_eq A11yWorld.step_volume, 70, "tile sound: volume honours the SE setting"

$played_se = []
$game_temp.in_battle = true
$game_player.move_one
check_eq $played_se.length, 0, "tile sound: silent in battle"
$game_temp.in_battle = false
$game_temp.message_window_showing = true
$game_player.move_one
check_eq $played_se.length, 0, "tile sound: silent while a message is showing"
$game_temp.message_window_showing = false

before_steps = $steps_taken
$game_temp.in_battle = true
$game_player.move_one
$game_temp.in_battle = false
check_eq $steps_taken, before_steps + 1, "tile sound: the game's own step counting is never skipped"

# The T key and the surface-override table are both gone.
check_eq defined?(A11yWorld::MAP_SURFACES).nil?, true, "the editable surface table has been removed"

# ── 16. The V readout ────────────────────────────────────────────────────────
A11yWorld.instance_variable_set(:@map_surface_cache, nil)
$map_names = { 1 => "Route 1", 2 => "Cellia Apartments 3F" }
$game_map.map_id = 1
$game_player.x = 12; $game_player.y = 34
$game_map.tags[[12, 34]] = 2          # grass
reset_spoken
A11yWorld.announce_position
line = spoke.to_s
check line.include?("Route 1"), "V key: says the map name"
check line.include?("Position 12, 34"), "V key: gives coordinates"
check line.include?("grass"), "V key: names the terrain underfoot"
check_eq line.scan("grass").length, 1, "V key: does not repeat itself when terrain and surface match"

# On plain ground it names the map's surface as well, which is how you check
# the tile mapping is doing what you expect.
$game_map.map_id = 2
A11yWorld.instance_variable_set(:@map_surface_cache, nil)
$game_map.tags[[12, 34]] = 13         # neutral ground
reset_spoken
A11yWorld.announce_position
line = spoke.to_s
check line.include?("Cellia Apartments"), "V key: names an indoor map"
check line.include?("hardwood surface"), "V key: reports the surface chosen for plain ground"
$game_map.map_id = 1

# The engine's own file check is what the mod relies on.
A11yWorld.instance_variable_set(:@variant_counts, nil)
$existing_audio = ["Audio/tile_sounds/grass/step1.ogg"]
check_eq A11yWorld.file_exists?("Audio/tile_sounds/grass/step1"), true,
         "file check: finds a file through the engine helper"
check_eq A11yWorld.file_exists?("Audio/tile_sounds/grass/step9"), false,
         "file check: reports a missing file as missing"


# The mod must never route through Audio_se_play, which is broken in this
# engine (it calls a getPlaySound that no script defines).
$played_se = []
$game_map.tags[[3, 4]] = 2
$game_player.x = 3; $game_player.y = 4
raised = false
begin
  $game_player.move_one
rescue NoMethodError
  raised = true
end
check_eq raised, false, "playback: does not go through the engine's broken Audio_se_play"
check ($played_se.last && $played_se.last[0]).to_s.end_with?(".ogg"),
      "playback: passes a full path including the extension"


# -- 17. Speaker names from face portraits -----------------------------------
AccessibilitySpeech.reset_speaker
reset_spoken
AccessibilitySpeech.speak_dialogue('\ff[08c]Damn it, where did I put it...')
check_eq spoke, 'Scarlett. Damn it, where did I put it...',
         'speaker: an unnamed line is prefixed with the character'
reset_spoken
AccessibilitySpeech.speak_dialogue('\ff[08c]And another thing.')
check_eq spoke, 'And another thing.', 'speaker: a continuing speaker is not repeated'
reset_spoken
AccessibilitySpeech.speak_dialogue('\ff[09d]Heya.')
check_eq spoke, 'Ava. Heya.', 'speaker: a change of speaker is announced'
AccessibilitySpeech.reset_speaker
reset_spoken
AccessibilitySpeech.speak_dialogue('\ff[08a]SCARLETT: Hello there!')
check_eq spoke, 'SCARLETT: Hello there!', 'speaker: a line that already names them is left alone'
AccessibilitySpeech.reset_speaker
reset_spoken
AccessibilitySpeech.speak_dialogue('\ff[XXX1]Who am I?')
check_eq spoke, 'Who am I?', 'speaker: an unknown portrait adds no name'
AccessibilitySpeech.reset_speaker
reset_spoken
AccessibilitySpeech.speak_dialogue('\ff[11b]First line.')
AccessibilitySpeech.speak_dialogue('A door creaks open.')
reset_spoken
AccessibilitySpeech.speak_dialogue('\ff[11b]Second line.')
check_eq spoke, 'Nova. Second line.', 'speaker: re-announced after narration breaks the run'
check_eq AccessibilitySpeech::FACE_NAMES.length, 75, 'speaker: the whole mined table is present'
check_eq AccessibilitySpeech.speaker_for('\ff[18b]hi'), 'Garret', 'speaker: table lookup works'
check_eq AccessibilitySpeech.speaker_for('no portrait here'), nil, 'speaker: no portrait means no speaker'

puts "=" * 60
puts " RESULTS: #{$pass} passed, #{$fail} failed"
puts "=" * 60
exit($fail == 0 ? 0 : 1)
