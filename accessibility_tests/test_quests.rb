# Exercises AccessibilityQuests: the Main/Side tab, the detail page readout,
# and the spoken "Quest added / completed" toasts.
#
#   ruby test_quests.rb ../patch/Mods/AccessibilityQuests.rb
$pass = 0; $fail = 0
def check(c, n); c ? ($pass += 1; puts "PASS: #{n}") : ($fail += 1; puts "FAIL: #{n}"); end
def check_eq(a, e, n)
  if a == e then $pass += 1; puts "PASS: #{n}"
  else $fail += 1; puts "FAIL: #{n}\n        expected: #{e.inspect}\n        actual:   #{a.inspect}" end
end

$spoken = []
module AccessibilitySpeech
  def self.speak(t, force = false, interrupt: true); $spoken << t.to_s; end
  def self.log(*a); end
end
def said; $spoken; end
def _INTL(s, *a); s; end

# ── The quest data, exactly the game's shape ────────────────────────────────
# [title, state-as-string, [[goal_state, goal_text], ...], main?-as-string]
$quests = [
  ["Restore the Beacon", "1",
   [[2, "Speak to the engineer."], [1, "Find three parts."], [0, "Return them."]],
   "true"],
  ["Lost Growlithe", "0",
   [[0, "Search the docks."]],
   "false"]
]
class VarStore
  def initialize; @d = {}; end
  def [](k); @d[k]; end
  def []=(k, v); @d[k] = v; end
end
$game_variables = VarStore.new
$game_variables[:QuestLog] = $quests.map { |q| Marshal.load(Marshal.dump(q)) }
$game_variables[:QuestLogMainOrSide] = true

def load_data(path)
  # pbSetQuestGoal pulls undiscovered quests from the master file.
  Marshal.load(Marshal.dump($quests))
end

# The map toast target.
class LocationWindow; def initialize(text); $toast = text; end; end
class SpritesetStub; def addUserSprite(s); end; end
class SceneStub; def spriteset; SpritesetStub.new; end; end
$scene = SceneStub.new

# ── The two scenes, shaped like Quest_Log.rb ────────────────────────────────
class ListWindow
  attr_accessor :commands, :index, :a11y_announced
end
class Subheader; attr_accessor :text; def initialize(t); @text = t; end; end

class QuestLog_Scene
  attr_accessor :sprites
  def initialize
    @sprites = { "commands" => ListWindow.new, "subheader" => Subheader.new("Main Quests") }
  end
  def pbSetCommands(newcommands, newindex)
    @sprites["commands"].commands = newcommands
    @sprites["commands"].index = newindex
  end
end

class QuestInfo_Scene
  attr_accessor :scrolling, :screens, :screen_index, :index
  def initialize(index)
    @index = index; @scrolling = false; @screens = []; @screen_index = 0
    @currentlog = $game_variables[:QuestLog].select { |n| n[3] == $game_variables[:QuestLogMainOrSide].to_s }
  end
  def createSprites(*a); $sprites_created = ($sprites_created || 0) + 1; end
end

# The game's own pbSetQuestGoal, condensed from Quest_Log.rb:460 - the mod
# wraps this, so the harness must provide it.
def pbSetQuestGoal(title, goal, newstate, shouldrevealnextgoal = false, shouldcomplete = false, nopopup = false)
  quest = $game_variables[:QuestLog].detect { |q| q[0].downcase == title.downcase }
  if quest.nil?
    $game_variables[:QuestLog].push(load_data("Data/quests.dat").detect { |q| q[0].downcase == title.downcase })
    quest = $game_variables[:QuestLog].detect { |q| q[0].downcase == title.downcase }
  end
  quest[2][goal][0] = newstate
  status = "In Progress : "
  allstates = quest[2].map { |g| g[0] }
  if (allstates.uniq.size <= 1 && allstates[0] == 2) || shouldcomplete
    quest[1] = "2"
    status = "Completed : "
  end
  if quest[1] == "0"
    quest[1] = "1"
    status = "Added : "
  end
  unless nopopup
    $scene.spriteset.addUserSprite(LocationWindow.new(_INTL("Quest " + status + title)))
  end
end

mod = File.expand_path(ARGV[0] || "../patch/Mods/AccessibilityQuests.rb")
ok = true
begin
  load mod
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
  puts "        #{e.backtrace.first(3).join("\n        ")}"
end
check ok, "the mod loads with no error"

# ── The tab ─────────────────────────────────────────────────────────────────
scene = QuestLog_Scene.new
$spoken = []
scene.pbSetCommands(["Restore the Beacon", "Back"], 0)
check said.include?("Main Quests"), "flipping to a tab says which tab, from the header the player sees"
check_eq scene.sprites["commands"].commands, ["Restore the Beacon", "Back"],
         "the real list update still happened"
check_eq scene.sprites["commands"].a11y_announced, false,
         "and the selected row is queued to re-announce after the tab name"

scene.sprites["subheader"].text = ""
$game_variables[:QuestLogMainOrSide] = false
$spoken = []
scene.pbSetCommands(["???", "Back"], 0)
check said.include?("Side Quests"), "with no header text it falls back to the boolean"
$game_variables[:QuestLogMainOrSide] = true

# ── The detail page ─────────────────────────────────────────────────────────
info = QuestInfo_Scene.new(0)
$spoken = []
info.createSprites
check_eq $sprites_created, 1, "the real page still draws"
check said.first == "Restore the Beacon, in progress.",
      "the page opens with the quest name and its state"
check said.include?("Done: Speak to the engineer."), "a finished objective says Done"
check said.include?("Find three parts."), "a current objective is read plainly"
check said.none? { |s| s.include?("Return them") },
      "an objective you have not reached is NOT read - the log does not spoil"

info.scrolling = true
info.screens = [1, 2, 3]
info.screen_index = 1
$spoken = []
info.createSprites
check said.any? { |s| s =~ /Page 2 of 3/ }, "a long quest reads its page position"

# ── The map toasts ──────────────────────────────────────────────────────────
$spoken = []
pbSetQuestGoal("Lost Growlithe", 0, 1)
check_eq $toast, "Quest Added : Lost Growlithe", "the game's own toast still appears"
check said.include?("Quest added: Lost Growlithe"), "and is spoken, as 'added' for a new quest"

$spoken = []
pbSetQuestGoal("Restore the Beacon", 1, 2)
check said.include?("Quest updated: Restore the Beacon"),
      "progress on a known quest is spoken as 'updated'"

$spoken = []
pbSetQuestGoal("Restore the Beacon", 2, 2, false, true)
check said.include?("Quest completed: Restore the Beacon"),
      "finishing every objective is spoken as 'completed'"
q = $game_variables[:QuestLog].find { |x| x[0] == "Restore the Beacon" }
check_eq q[1], "2", "and the quest data really is complete"

$spoken = []
$toast = nil
pbSetQuestGoal("Lost Growlithe", 0, 2, false, true, true)   # nopopup
check_eq $toast, nil, "nopopup shows no toast"
check $spoken.empty?, "and speaks nothing either - silent means silent"

# ── Reloading ───────────────────────────────────────────────────────────────
ok = true
begin
  2.times { load mod }
  scene.pbSetCommands(["Back"], 0)
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
end
check ok, "a soft reset reloads it without recursing"

puts "=" * 56
puts " RESULTS: #{$pass} passed, #{$fail} failed"
puts "=" * 56
exit($fail == 0 ? 0 : 1)
