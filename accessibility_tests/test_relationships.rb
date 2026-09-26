# Exercises AccessibilityRelationships: the R and Shift+R readouts, the
# spoken change, and the pop-up window that follows it.
#
#   ruby test_relationships.rb ../patch/Mods/AccessibilityRelationships.rb
$pass = 0; $fail = 0
def check(c, n); c ? ($pass += 1; puts "PASS: #{n}") : ($fail += 1; puts "FAIL: #{n}"); end
def check_eq(a, e, n)
  if a == e then $pass += 1; puts "PASS: #{n}"
  else $fail += 1; puts "FAIL: #{n}\n        expected: #{e.inspect}\n        actual:   #{a.inspect}" end
end

$spoken = []
module AccessibilitySpeech
  def self.speak(t, force = false, interrupt: true); $spoken << [t.to_s, interrupt]; end
  def self.log(*a); end
  def self.enabled; true; end
end
def said; $spoken.map(&:first); end

# Desolation's variable names, as Data/System.rxdata really has them.
NAMES = []
NAMES[47] = "NovaRep"; NAMES[48] = "ShivRep"; NAMES[51] = "ConnorRep"
NAMES[80] = "Cellia FC Rep"; NAMES[110] = "AARON REP"; NAMES[29] = "ConnorDialogue"
class SystemStub; def variables; NAMES; end; end
class CacheStub; def RXsystem; SystemStub.new; end; end
$cache = CacheStub.new

# Desolation's Game_Variables: symbol keys go through the Variables table.
Variables = { :ConnorRep => 51 }
class Game_Variables
  def initialize; @d = []; end
  def [](id); id = Variables[id] if id.is_a?(Symbol); (id && @d[id]) || 0; end
  def []=(id, v); id = Variables[id] if id.is_a?(Symbol); @d[id] = v if id; end
end

module Input
  @keys = {}
  class << self
    def update; $base_input_updates = ($base_input_updates || 0) + 1; end
    def press(*k); @keys = {}; k.each { |x| @keys[x] = true }; end
    def clear; @keys = {}; end
    def triggerex?(k); !!@keys[k]; end
    def pressex?(k); !!@keys[k]; end
    def text_input; $typing ? true : false; end
  end
end

class GameTemp; attr_accessor :message_window_showing; end
$game_temp = GameTemp.new
class GameMap; def map_id; 1; end; def name; "Redcliff Town"; end; end
$game_map = GameMap.new

$toasts = []
class LocationWindow; def initialize(text); $toasts << text; end; end
class SpritesetStub; def addUserSprite(s); end; end
class SceneStub; def spriteset; SpritesetStub.new; end; end
class Scene_Map
  def spriteset; SpritesetStub.new; end
  def update; $map_updates = ($map_updates || 0) + 1; end
end
$scene = Scene_Map.new
$game_variables = Game_Variables.new

mod = File.expand_path(ARGV[0] || "../patch/Mods/AccessibilityRelationships.rb")
ok = true
begin
  load mod
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
  puts "        #{e.backtrace.first(3).join("\n        ")}"
end
check ok, "the mod loads with no error"

# ── Who has a reputation ────────────────────────────────────────────────────
t = A11yRelationships.table
check_eq t[47], "Nova", "a Rep variable becomes a character"
check_eq t[110], "Aaron", "a shouty variable name is tidied up"
check_eq t[80], "Cellia Fight Club", "and FC is spelled out"
check !t.key?(29), "a variable that merely ends in something else is not one"
check_eq t.length, 5, "only the Rep variables are picked up"

# ── Shift+R: the whole list ─────────────────────────────────────────────────
$game_variables[47] = 3        # Nova
$game_variables[51] = 7        # Connor
$spoken = []
A11yRelationships.speak_all
check_eq said, ["Reputations: Connor 7, Nova 3."],
         "the list reads everyone you have met, best standing first"
check said.none? { |s| s.include?("Shiv") }, "and leaves out anyone still at zero"

# ── R: the character who is talking ─────────────────────────────────────────
AccessibilitySpeech.instance_variable_set(:@last_speaker, "Connor")
$spoken = []
A11yRelationships.speak_current
check_eq said, ["Connor reputation: 7."], "R reads the speaker's own reputation"

AccessibilitySpeech.instance_variable_set(:@last_speaker, "Kuiki")
$spoken = []
A11yRelationships.speak_current
check said.first.to_s.start_with?("Reputations:"),
      "a speaker with no reputation falls back to the whole list"

AccessibilitySpeech.instance_variable_set(:@last_speaker, nil)
$spoken = []
A11yRelationships.speak_current
check said.first.to_s.start_with?("Reputations:"), "and so does nobody talking"

# With nothing at all, it says so rather than reading an empty list.
$game_variables[47] = 0; $game_variables[51] = 0
$spoken = []
A11yRelationships.speak_all
check_eq said, ["No reputations yet."], "no reputations yet is said plainly"
$game_variables[47] = 3; $game_variables[51] = 7

# ── The keys ────────────────────────────────────────────────────────────────
AccessibilitySpeech.instance_variable_set(:@last_speaker, "Connor")
$spoken = []
$base_input_updates = 0
Input.clear
Input.update
check $spoken.empty?, "without R, nothing is said"
check_eq $base_input_updates, 1, "and the game's own input update still ran"

Input.press(0x52)
$spoken = []
Input.update
check_eq said, ["Connor reputation: 7."], "R speaks the speaker's reputation"

Input.press(0x52, 0x10)
$spoken = []
Input.update
check said.first.to_s.start_with?("Reputations:"), "Shift+R speaks the whole list"

$typing = true
Input.press(0x52)
$spoken = []
Input.update
check $spoken.empty?, "R types an R when you are naming something, and says nothing"
$typing = false
Input.clear

# ── A change speaks, then pops up ───────────────────────────────────────────
A11yRelationships.pending = []
$toasts = []
$spoken = []
$game_variables[51] = 8
check_eq said, ["Connor reputation up 1, now 8."], "a rise is spoken the moment it happens"
check_eq $game_variables[51], 8, "and the real variable is set"
check_eq $toasts, [], "the pop-up waits for the next map frame"
$scene.update
check_eq $toasts, ["Connor reputation up 1, now 8."], "which then shows the same words"
$scene.update
check_eq $toasts.length, 1, "once only"

$spoken = []
$game_variables[51] = 5
check_eq said, ["Connor reputation down 3, now 5."], "a fall says how far it fell"

$spoken = []
$game_variables[51] = 5
check $spoken.empty?, "setting the same number again says nothing"
$spoken = []
$game_variables[29] = 4
check $spoken.empty?, "and an ordinary variable is never announced"

# A symbol key resolves through the game's table.
$spoken = []
$game_variables[:ConnorRep] = 9
check_eq said, ["Connor reputation up 4, now 9."], "a change made by symbol is caught too"

# During dialogue the pop-up waits.
A11yRelationships.pending = []
$toasts = []
$game_variables[47] = 4
$game_temp.message_window_showing = true
$scene.update
check_eq $toasts, [], "no pop-up while someone is talking"
$game_temp.message_window_showing = false
$scene.update
check_eq $toasts, ["Nova reputation up 1, now 4."], "it appears when the dialogue is done"

# ── Reloading ───────────────────────────────────────────────────────────────
ok = true
begin
  2.times { load mod }
  $spoken = []
  $game_variables[47] = 6
  ok = (said.count("Nova reputation up 2, now 6.") == 1)
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
end
check ok, "a soft reset reloads it without announcing twice"

puts "=" * 56
puts " RESULTS: #{$pass} passed, #{$fail} failed"
puts "=" * 56
exit($fail == 0 ? 0 : 1)
