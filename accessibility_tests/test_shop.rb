# Exercises AccessibilityShop: the quantity chooser, the shop's own messages,
# money on entry and after a purchase, and N for the description.
#
#   ruby test_shop.rb ../patch/Mods/AccessibilityShop.rb
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
end
def said; $spoken.map(&:first); end

def _INTL(s, *a); a.each_with_index { |v, i| s = s.gsub("{#{i + 1}}", v.to_s) }; s; end
def _ISPRINTF(s, *a); _INTL(s.gsub(":d", ""), *a); end
def pbCommaNumber(n); n.to_s.reverse.scan(/\d{1,3}/).join(",").reverse; end
def pbPlayCursorSE; end
def pbPlayDecisionSE; end
def pbPlayCancelSE; end
def pbBottomRight(w); end
def pbBottomLeft(w); end
def using_block(obj); yield obj; end
class Color; def initialize(*a); end; end
module Graphics; def self.update; end; end

# Scripted input, one frame per Input.update: :up :down :left :right :c :b :n
# :none. An exhausted script answers :b so no loop can hang.
module Input
  LEFT = 4; RIGHT = 6; UP = 8; DOWN = 2; C = 13; B = 12
  @script = []; @cur = :none
  class << self
    attr_accessor :script
    def update; @cur = @script.shift || :b; end
    def repeat?(k); { LEFT => :left, RIGHT => :right, UP => :up, DOWN => :down }[k] == @cur; end
    def trigger?(k); (k == C && @cur == :c) || (k == B && @cur == :b); end
    def triggerex?(k); k == 0x4E && @cur == :n; end
    def current=(v); @cur = v; end
  end
end

class Window_AdvancedTextPokemon
  attr_accessor :text, :viewport, :width, :height, :baseColor, :shadowColor, :visible, :y, :letterbyletter
  def initialize(t = ""); @text = t; @y = 0; @height = 64; end
  def update; end
end
class ItemWin; attr_accessor :item; end

class Adapter
  attr_accessor :money
  def initialize; @money = 4500; @bag = { :POKEBALL => 3 }; end
  def getMoney; @money; end
  def getPrice(item, selling = false); 200; end
  def getQuantity(item); @bag[item] || 0; end
  def getDescription(item); item == :POKEBALL ? "A device for catching wild Pokemon." : ""; end
end

# The scene, shaped like Mart.rb's PokemonMartScene - the methods the mod
# wraps or calls, with the originals recording that they still ran.
class PokemonMartScene
  attr_accessor :adapter, :sprites
  def initialize(buying = true)
    @buying = buying; @adapter = Adapter.new
    @sprites = { "helpwindow" => Window_AdvancedTextPokemon.new, "itemwindow" => ItemWin.new }
  end
  def update; end
  def pbPrepareWindow(w); w.visible = true; end
  def pbDisplay(msg, brief = false); $shown = msg; end
  def pbDisplayPaused(msg); $shown = msg; end
  def pbConfirm(msg); $shown = msg; true; end
  def pbRefresh; $refreshed = true; end
  def pbStartBuyScene(stock, adapter); pbRefresh; :started; end
  def pbStartSellScene(bag, adapter); pbRefresh; :started; end
  def pbChooseNumber(helptext, item, maximum); :original; end
end

mod = File.expand_path(ARGV[0] || "../patch/Mods/AccessibilityShop.rb")
ok = true
begin
  load mod
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
  puts "        #{e.backtrace.first(3).join("\n        ")}"
end
check ok, "the mod loads with no error"

# ── Entering the shop ───────────────────────────────────────────────────────
scene = PokemonMartScene.new
$spoken = []
check_eq scene.pbStartBuyScene([], scene.adapter), :started, "the real shop still opens"
check said.include?("You have $4,500."), "entering the shop says your money"
check_eq $spoken.last[1], false, "queued, so it does not cut off the first item"

# ── How many? ───────────────────────────────────────────────────────────────
$spoken = []
Input.script = [:up, :up, :right, :left, :down, :c]
ret = scene.pbChooseNumber("Poke Ball?  Certainly.\r\nHow many would you like?", :POKEBALL, 22)
check said.first.include?("How many would you like?"), "the question is spoken"
check !said.first.include?("\r") && !said.first.include?("\n"), "without the line break in the middle"
intro = said[1].to_s
check intro.start_with?("1, $200."), "then the starting amount and its total"
check intro.include?("3 in your bag"), "how many you already have"
check intro.include?("You have $4,500"), "and your money"
check intro.include?("Up and down change by one"), "with how to change it"
check_eq $spoken[1][1], false, "queued behind the question"
check said.include?("2, $400"), "up adds one and speaks the new total"
check said.include?("3, $600"), "again"
check said.include?("13, $2,600"), "right adds ten"
check said.count("3, $600") == 2, "left takes ten off"
check said.include?("2, $400"), "down takes one off"
check_eq ret, 2, "C returns the number that was spoken last"

$spoken = []
Input.script = [:b]
check_eq scene.pbChooseNumber("How many?", :POKEBALL, 5), 0, "B cancels, as before"

$spoken = []
Input.script = [:down, :c]
check_eq scene.pbChooseNumber("How many?", :POKEBALL, 5), 5, "down from 1 wraps to the maximum"
check said.include?("5, $1,000"), "and says so"

# Selling: the price is halved, and it says how many you own instead.
sell = PokemonMartScene.new(false)
$spoken = []
Input.script = [:up, :c]
sell.pbChooseNumber("Poke Ball?\r\nHow many would you like to sell?", :POKEBALL, 3)
check said[1].to_s.start_with?("1, $100."), "selling quotes the sale price, half the buy price"
check said[1].to_s.include?("You have 3"), "and how many you own"
check said.include?("2, $200"), "each change is spoken when selling too"

# ── The shop's own messages ─────────────────────────────────────────────────
$spoken = []
scene.pbConfirm("Poke Ball, and you want 2.\r\nThat will be $400. OK?")
check said.include?("Poke Ball, and you want 2. That will be $400. OK?"),
      "the Yes/No question is spoken"
check_eq $shown, "Poke Ball, and you want 2.\r\nThat will be $400. OK?", "and still shown"
$spoken = []
scene.pbDisplayPaused("Here you are!\r\nThank you!")
check said.include?("Here you are! Thank you!"), "a paused message is spoken"
$spoken = []
scene.pbDisplay("You don't have enough money.")
check said.include?("You don't have enough money."), "and a plain one"

# ── Money after buying ──────────────────────────────────────────────────────
$spoken = []
scene.adapter.money = 4100
scene.pbRefresh
check said.include?("You now have $4,100."), "after a purchase, the new total is spoken"
$spoken = []
scene.pbRefresh
check $spoken.empty?, "a redraw with no change says nothing"

# ── N: the description ──────────────────────────────────────────────────────
scene.sprites["itemwindow"].item = :POKEBALL
$spoken = []
Input.current = :n
scene.update
check said.include?("A device for catching wild Pokemon."), "N reads the item's description"
scene.sprites["itemwindow"].item = nil
$spoken = []
scene.update
check said.include?("Quit shopping."), "and on the last row says it is Quit shopping"
Input.current = :none

# ── Reloading ───────────────────────────────────────────────────────────────
ok = true
begin
  2.times { load mod }
  $spoken = []
  scene.pbDisplay("Once.")
  ok = (said.count("Once.") == 1)
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
end
check ok, "a soft reset reloads it without stacking the wrappers"

puts "=" * 56
puts " RESULTS: #{$pass} passed, #{$fail} failed"
puts "=" * 56
exit($fail == 0 ? 0 : 1)
