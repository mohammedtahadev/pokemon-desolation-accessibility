# Exercises the number box speech in AccessibilityMenus: the digit-by-digit
# Window_InputNumberPokemon (the Jinx-Scent's encounter rate, event "Input
# Number", pbMessageChooseNumber), and the Jinx-Scent's own announcements.
#
#   ruby test_numbox.rb ../patch/Mods/AccessibilityMenus.rb
$pass = 0; $fail = 0
def check(c, n); c ? ($pass += 1; puts "PASS: #{n}") : ($fail += 1; puts "FAIL: #{n}"); end
def check_eq(a, e, n)
  if a == e then $pass += 1; puts "PASS: #{n}"
  else $fail += 1; puts "FAIL: #{n}\n        expected: #{e.inspect}\n        actual:   #{a.inspect}" end
end

require_relative "stubs_desolation"

$spoken = []
module AccessibilitySpeech
  def self.speak(t, force = false, interrupt: true); $spoken << [t.to_s, interrupt]; end
  def self.log(*a); end
  def self.enabled; true; end
end
def said; $spoken.map(&:first); end

# Scripted keys: one symbol per update - :up :down :left :right :none.
module Input
  UP = 8; DOWN = 2; LEFT = 4; RIGHT = 6
  class << self
    attr_accessor :cur
    def repeat?(k); { UP => :up, DOWN => :down, LEFT => :left, RIGHT => :right }[k] == @cur; end
  end
end
def pbPlayCursorSE; end

class SpriteWindow_Base
  attr_accessor :active
  def initialize(*a); end
  def update; end
end

# The game's Window_InputNumberPokemon (SW Subclasses.rb:1147), its state and
# update logic exactly; drawing left out.
class Window_InputNumberPokemon < SpriteWindow_Base
  def initialize(digits_max)
    @digits_max = digits_max; @number = 0; @frame = 0
    @sign = false; @negative = false
    super(0, 0, 32, 32)
    @index = digits_max - 1
    self.active = true
  end
  def number; @number * (@sign && @negative ? -1 : 1); end
  def sign=(v); @sign = v; @index = (@digits_max - 1) + (@sign ? 1 : 0); end
  def number=(value)
    value = 0 if !value.is_a?(Numeric)
    if @sign
      @negative = (value < 0); @number = [value.abs, 10 ** @digits_max - 1].min
    else
      @number = [[value, 0].max, 10 ** @digits_max - 1].min
    end
  end
  def update
    super
    digits = @digits_max + (@sign ? 1 : 0)
    if self.active
      if Input.repeat?(Input::UP) || Input.repeat?(Input::DOWN)
        pbPlayCursorSE()
        if @index == 0 && @sign
          @negative = !@negative
        else
          place = 10 ** (digits - 1 - @index)
          n = @number / place % 10
          @number -= n * place
          if Input.repeat?(Input::UP)
            n = (n + 1) % 10
          elsif Input.repeat?(Input::DOWN)
            n = (n + 9) % 10
          end
          @number += n * place
        end
      elsif Input.repeat?(Input::RIGHT)
        if digits >= 2 then pbPlayCursorSE(); @index = (@index + 1) % digits; @frame = 0 end
      elsif Input.repeat?(Input::LEFT)
        if digits >= 2 then pbPlayCursorSE(); @index = (@index + digits - 1) % digits; @frame = 0 end
      end
    end
    @frame = (@frame + 1) % 30
  end
end

# The Jinx-Scent scene, shaped like DesoPokegear.rb: it opens a 4-digit box
# on the current rate (100 = normal) and stores the result / 100.
class VarStore; def initialize; @d = {}; end; def [](k); @d[k]; end; def []=(k, v); @d[k] = v; end; end
$game_variables = VarStore.new
$game_variables[:EncounterRateModifier] = 1
class Scene_EncounterRate
  def main
    w = Window_InputNumberPokemon.new(4)
    w.number = ($game_variables[:EncounterRateModifier].to_f * 100).to_i
    $jinx_script.each { |k| Input.cur = k; w.update }
    $game_variables[:EncounterRateModifier] = w.number.to_f / 100
  end
end

# The title screen's save-file list, shaped like Load.rb's PokemonLoadScene:
# entries are [number, name, ..., saved time, filename].
class PokemonLoadScene
  attr_reader :savefiles, :moved
  def pbDrawSaveCommands(savefiles); @savefiles = savefiles; $drawn = true; end
  def pbMoveSaveSel(index); @moved = index; end
end

mod = File.expand_path(ARGV[0] || "../patch/Mods/AccessibilityMenus.rb")
ok = true
begin
  load mod
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
  puts "        #{e.backtrace.first(3).join("\n        ")}"
end
check ok, "the menus mod loads with no error"

def press(w, *keys); keys.each { |k| Input.cur = k; w.update }; end

# ── Opening the box ─────────────────────────────────────────────────────────
w = Window_InputNumberPokemon.new(4)
w.number = 100
$spoken = []
press(w, :none)
intro = said.first.to_s
check intro.include?("Number: 100."), "opening says the whole number"
check intro.include?("Up and down change the selected digit"), "and how to use it"
check intro.include?("Selected: Ones, 0."), "and which digit is selected - the last one"
check_eq $spoken.first[1], false, "queued, so the question that opened it is not cut off"
$spoken = []
press(w, :none)
check $spoken.empty?, "an idle frame says nothing"

# ── Changing digits ─────────────────────────────────────────────────────────
$spoken = []
press(w, :up)
check_eq said, ["101"], "up changes the selected digit and speaks the whole number"
check_eq $spoken.last[1], true, "interrupting, so fast presses stay current"
press(w, :left)
check_eq said.last, "Tens, 0", "left moves to the tens digit and says its value"
press(w, :up, :up, :up, :up, :up)
check_eq said.last, "151", "tens up five times: 151"
press(w, :left)
check_eq said.last, "Hundreds, 1", "hundreds"
press(w, :down)
check_eq said.last, "51", "hundreds down: 51"
press(w, :down)
check_eq said.last, "951", "and down again wraps the digit to 9: 951"
press(w, :left)
check_eq said.last, "Thousands, 0", "thousands"
press(w, :left)
check_eq said.last, "Ones, 1", "left from the first digit wraps round to the ones"
check_eq w.number, 951, "the number the game gets is the number that was spoken"

# ── A box with a sign ───────────────────────────────────────────────────────
s = Window_InputNumberPokemon.new(2)
s.sign = true
s.number = -5
$spoken = []
press(s, :none)
check said.first.include?("Number: -5."), "a signed box reads the negative number"
press(s, :left, :left)
check_eq said.last, "Sign, minus", "and names the sign position"
press(s, :up)
check_eq said.last, "5", "flipping the sign speaks the new number"

# ── The Jinx-Scent ──────────────────────────────────────────────────────────
$jinx_script = [:none, :left, :left, :up, :none]      # 100 -> 200
$spoken = []
Scene_EncounterRate.new.main
check said.first.to_s.start_with?("Jinx Scent: wild encounter rate, in percent."),
      "the Jinx-Scent says what the number means"
check said.first.to_s.include?("0 turns wild encounters off"), "including how to turn encounters off"
check said.first.to_s.include?("Number: 100."), "then the current rate"
check said.include?("200"), "the change is spoken"
check_eq said.last, "Encounter rate set to 200 percent.", "and the result is confirmed on leaving"
check_eq A11yNumberBox.label, nil, "the label never leaks into the next number box"

$game_variables[:EncounterRateModifier] = 1
$jinx_script = [:none, :left, :left, :down, :none]     # 100 -> 000
$spoken = []
Scene_EncounterRate.new.main
check_eq said.last, "Wild encounters off.", "setting 0 says wild encounters are off"


# ── The save file list ──────────────────────────────────────────────────────
FILES = [[1, "Save Slot 1 - Ash, 4 badges", false, true, "Mon 22 Sep 10:00", "Game.rxdata"],
         [2, "Save Slot 2 - Rosa, 1 badge", false, true, "Sun 21 Sep 18:30", "Game_2.rxdata"],
         [3, "Anna's Wish - Anna", false, true, nil, "Anna's Wish 1.rxdata"]]
load_scene = PokemonLoadScene.new
$spoken = []
$drawn = false
load_scene.pbDrawSaveCommands(FILES)
check $drawn, "the real list is still drawn"
check said.first.to_s.start_with?("Other save files: 3."), "opening says how many save files there are"
check said.first.to_s.include?("Up and down choose one"), "and how to use the list"
check_eq said[1], "Save Slot 1 - Ash, 4 badges, 1 of 3. Saved Mon 22 Sep 10:00.",
         "then the first file: its name, its position, and when it was saved"
check_eq $spoken[1][1], false, "queued behind the header"

$spoken = []
load_scene.pbMoveSaveSel(1)
check_eq load_scene.moved, 1, "moving still moves the real highlight"
check_eq said, ["Save Slot 2 - Rosa, 1 badge, 2 of 3. Saved Sun 21 Sep 18:30."],
         "each file is read as you move to it"
$spoken = []
load_scene.pbMoveSaveSel(2)
check_eq said, ["Anna's Wish - Anna, 3 of 3."],
         "a file with no saved time simply leaves it out"
$spoken = []
load_scene.pbMoveSaveSel(9)
check $spoken.empty?, "an index with no file says nothing rather than crashing"

# ── Reloading ───────────────────────────────────────────────────────────────
ok = true
begin
  2.times { load mod }
  r = Window_InputNumberPokemon.new(3)
  $spoken = []
  press(r, :none, :up)
  ok = (said.count("1") == 1)
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
end
check ok, "a soft reset reloads it without stacking the hook"

puts "=" * 56
puts " RESULTS: #{$pass} passed, #{$fail} failed"
puts "=" * 56
exit($fail == 0 ? 0 : 1)
