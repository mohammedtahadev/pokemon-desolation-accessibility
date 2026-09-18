# Exercises AccessibilityBag: pocket announcements, the N description key,
# sort feedback, and the speaking quantity chooser.
#
#   ruby test_bag.rb ../patch/Mods/AccessibilityBag.rb
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
def _ISPRINTF(fmt, *a); sprintf(fmt.gsub(/\{(\d+):([^}]*)\}/) { "%#{$2}" }, *a); end

module Input
  LEFT = 4; RIGHT = 6; UP = 8; DOWN = 2; C = 13; B = 27
  @script = []
  class << self
    def script=(keys); @script = keys; end
    def update; @now = @script.shift; end
    def repeat?(k); @now == k; end
    def trigger?(k); @now == k; end
    def triggerex?(k); @now == k; end
  end
end
module Graphics; def self.update; end; end
def pbPlayCursorSE; end
def pbPlayDecisionSE; end
def pbPlayCancelSE; end
def pbBottomRight(w); end
def pbBottomLeft(w); end
def using_block(obj); yield; end

ItemData = Struct.new(:name, :desc)
class CacheStub
  attr_reader :items
  def initialize
    @items = { :POTION => ItemData.new("Potion", "Restores 20 HP of one Pokemon."),
               :BIKE   => ItemData.new("Bicycle", "A folding bike for fast travel.") }
  end
end
$cache = CacheStub.new

module PokemonBag
  def self.pocketNames; ["", "Items", "Medicine", "Poke Balls"]; end
end

class FakeBag
  attr_accessor :pockets, :contents
  def initialize
    @pockets = { 1 => [:POTION], 2 => [], 3 => [] }
    @contents = { :POTION => 5 }
  end
  def getChoice(p); 0; end
end

# The window, shaped like Bag.rb's: pocket= goes through a setter, item reads
# the current row, active gates input, and the menus mod's re-announce flag
# lives in @a11y_announced.
class Window_PokemonBag
  attr_accessor :active, :index
  attr_reader :pocket
  def initialize(bag); @bag = bag; @pocket = 1; @index = 0; @active = true; end
  def pocket=(v); @pocket = v; @index = @bag.getChoice(v); end
  def item; @bag.pockets[@pocket][@index]; end
  def update; $base_updates = ($base_updates || 0) + 1; end
end

class Window_PokemonItemStorage
  attr_accessor :active
  def initialize(item); @it = item; @active = true; end
  def item; @it; end
  def update; end
end

class PokemonBag_Scene
  def pbHandleSortByType(*a); $sorted = true; end
end

class Window_UnformattedTextPokemon
  attr_accessor :text, :viewport, :letterbyletter
  def initialize(t = ""); @text = t; end
  def resizeToFit(t, w); end
  def width; 100; end
  def update; end
end

class HelpWindow < Window_UnformattedTextPokemon
  attr_accessor :visible
  def resizeHeightToFit(t, w); end
end

module UIHelper
  def self.pbChooseNumber(helpwindow, helptext, maximum); :original; end
end

mod = File.expand_path(ARGV[0] || "../patch/Mods/AccessibilityBag.rb")
ok = true
begin
  load mod
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
  puts "        #{e.backtrace.first(3).join("\n        ")}"
end
check ok, "the mod loads with no error"

# ── Pocket switching ────────────────────────────────────────────────────────
bag = FakeBag.new
win = Window_PokemonBag.new(bag)
$spoken = []
win.pocket = 2
check said.include?("Medicine pocket"), "changing pocket says the pocket's name"
check_eq win.instance_variable_get(:@a11y_announced), false,
         "and clears the menus mod's flag so the row re-announces after it"
$spoken = []
win.pocket = 2
check $spoken.empty?, "setting the same pocket again says nothing"
$spoken = []
win.pocket = 9
check said.include?("Pocket 9 pocket"), "an unnamed pocket still gets a spoken label"
win.pocket = 1

# ── The N key ───────────────────────────────────────────────────────────────
$spoken = []
Input.script = [0x4E]
Input.update
win.update
check said.any? { |s| s.include?("Potion") && s.include?("Restores 20 HP") },
      "N reads the selected item's name and description"
check ($base_updates || 0) > 0, "and the original update still ran"

win.active = false
$spoken = []
Input.script = [0x4E]; Input.update
win.update
check $spoken.empty?, "an inactive window ignores N"
win.active = true

win.index = 1                                  # past the last item = CLOSE BAG
$spoken = []
Input.script = [0x4E]; Input.update
win.update
check said.include?("Close bag."), "N on the Close Bag row says so instead of crashing"
win.index = 0

st = Window_PokemonItemStorage.new(:BIKE)
$spoken = []
Input.script = [0x4E]; Input.update
st.update
check said.any? { |s| s.include?("Bicycle") }, "the PC item list gets the same N key"

# ── Sort feedback ───────────────────────────────────────────────────────────
$spoken = []
PokemonBag_Scene.new.pbHandleSortByType
check $sorted, "the real sort still happens"
check said.include?("Pocket sorted."), "and is finally announced"

# ── The quantity chooser ────────────────────────────────────────────────────
help = HelpWindow.new
$spoken = []
Input.script = [Input::UP, Input::UP, Input::RIGHT, Input::DOWN, Input::C]
ret = UIHelper.pbChooseNumber(help, "Toss how many?", 30)
check_eq ret, 12, "up, up, right(+10), down and C picks 12, exactly as before"
check said.first =~ /Toss how many\?.*1 of 30/, "opening it explains the starting number and the keys"
check_eq said.grep(/\A\d+\z/), ["2", "3", "13", "12"], "every change is spoken as it happens"

$spoken = []
Input.script = [Input::B]
ret = UIHelper.pbChooseNumber(help, "Toss how many?", 30)
check_eq ret, 0, "B still cancels and returns zero"

# ── Reloading ───────────────────────────────────────────────────────────────
ok = true
begin
  2.times { load mod }
  win.pocket = 3
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
end
check ok, "a soft reset reloads it without recursing"

puts "=" * 56
puts " RESULTS: #{$pass} passed, #{$fail} failed"
puts "=" * 56
exit($fail == 0 ? 0 : 1)
