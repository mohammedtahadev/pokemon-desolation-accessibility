# Exercises AccessibilityOptions: the settings, their defaults, how they are
# stored on $Settings, and that they really land in the game's option list.
#
#   ruby test_options.rb ../patch/Mods/AccessibilityOptions.rb
$pass = 0; $fail = 0
def check(c, n); c ? ($pass += 1; puts "PASS: #{n}") : ($fail += 1; puts "FAIL: #{n}"); end
def check_eq(a, e, n)
  if a == e then $pass += 1; puts "PASS: #{n}"
  else $fail += 1; puts "FAIL: #{n}\n        expected: #{e.inspect}\n        actual:   #{a.inspect}" end
end

def _INTL(s, *a); a.each_with_index { |v, i| s = s.gsub("{#{i + 1}}", v.to_s) }; s; end

# ── The game's option classes, as Options.rb defines them ──────────────────
class EnumOption
  attr_reader :name, :values, :description
  def initialize(name, values, getter, setter, description = nil)
    @name, @values, @getter, @setter, @description = name, values, getter, setter, description
  end
  def get; @getter.call; end
  def set(v); @setter.call(v); end
end
class NumberOption
  attr_reader :name, :format, :min, :max, :description
  def initialize(name, format, min, max, getter, setter, description = nil)
    @name, @format, @min, @max = name, format, min, max
    @getter, @setter, @description = getter, setter, description
  end
  def get; @getter.call; end
  def set(v); @setter.call(v); end
end
class PokemonOptions
  attr_accessor :sevolume
  def initialize; @sevolume = 100; end
end
class PokemonOptionScene
  # One pre-existing option, so we can prove ours are appended after it.
  OptionList = [EnumOption.new("Text Speed", %w[Normal Fast Max],
                               proc { 0 }, proc { |v| })]
end
$Settings = PokemonOptions.new
$saved = 0
def saveSettings(set = $Settings); $saved += 1; end

# The speech mod, so the Speech option has something to push its value into.
module AccessibilitySpeech
  class << self; attr_accessor :enabled; end
  self.enabled = true
  def self.log(*a); end
end

mod = File.expand_path(ARGV[0] || "../patch/Mods/AccessibilityOptions.rb")
ok = true
begin
  load mod
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
  puts "        #{e.backtrace.first(3).join("\n        ")}"
end
check ok, "the mod loads with no error"

# ── Defaults, with nothing stored ──────────────────────────────────────────
check_eq A11ySettings.get(:speech), 0, "speech defaults to on"
check_eq A11ySettings.get(:speaker_names), 0, "speaker names default to on"
check_eq A11ySettings.get(:event_names), 0, "event names default to on"
check_eq A11ySettings.get(:tile_sounds), 0, "tile sounds default to on"
check_eq A11ySettings.get(:step_volume), 70,
         "tile volume defaults to 70, what STEP_VOLUME was before this existed"
check_eq A11ySettings.get(:beacon), 0, "the beacon defaults to on"
check_eq A11ySettings.get(:spoken_directions), 0,
         "spoken directions default to 'if no 3D sound'"
check_eq A11ySettings.get(:battle_speech), 0, "battle speech defaults to on"
check_eq A11ySettings.get(:spoken_damage), 0, "spoken damage defaults to on"

sd = nil  # checked properly once the list exists, below
check A11ySettings.on?(:speech), "on? reads 0 as on"

# ── An old Settings.dat, with no a11y field at all ─────────────────────────
$Settings.a11y = nil
check_eq A11ySettings.get(:step_volume), 70,
         "a Settings.dat saved before this mod existed still gives defaults"
check_eq A11ySettings.on?(:beacon), true, "and everything stays switched on"

# ── Storing ────────────────────────────────────────────────────────────────
$saved = 0
A11ySettings.set(:step_volume, 40)
check_eq A11ySettings.get(:step_volume), 40, "a changed value is kept"
check_eq $saved, 1, "and written to disk, because the game's own screen does not"
A11ySettings.set(:step_volume, 40)
check_eq $saved, 1, "setting the same value again does not write again"
A11ySettings.set(:tile_sounds, 1)
check_eq A11ySettings.on?(:tile_sounds), false, "switching something off reads back off"
check_eq A11ySettings.get(:step_volume), 40, "and does not disturb the others"

# Only one ivar is added to $Settings, whatever the number of settings.
check_eq $Settings.a11y.class, Hash, "everything lives in one Hash"
check $Settings.a11y.keys.length <= A11ySettings::DEFAULTS.length,
      "so $Settings grows by exactly one field"

# ── Clamping ───────────────────────────────────────────────────────────────
A11ySettings.set(:step_volume, 500)
check_eq A11ySettings.step_volume, 100, "an absurd volume is clamped to 100"
A11ySettings.set(:step_volume, -20)
check_eq A11ySettings.step_volume, 0, "and a negative one to 0"
A11ySettings.set(:step_volume, 70)

# ── The Speech option drives the speech mod ────────────────────────────────
AccessibilitySpeech.enabled = true
A11ySettings.set(:speech, 1)
check_eq AccessibilitySpeech.enabled, false, "switching Speech off silences the speech mod"
A11ySettings.set(:speech, 0)
check_eq AccessibilitySpeech.enabled, true, "and switching it back on restores it"

# ── They are actually in the game's list ───────────────────────────────────
list = PokemonOptionScene::OptionList
names = list.map { |o| o.name }
%w[Speech].each { |n| check names.include?(n), "'#{n}' is in the options list" }
["Speaker Names", "Event Names", "Tile Sounds", "Tile Sound Volume",
 "Directional Beacon", "Spoken Directions", "Battle Speech",
 "Spoken Damage"].each do |n|
  check names.include?(n), "'#{n}' is in the options list"
end
check_eq names.first, "Text Speed", "the game's own options still come first"
check_eq list.length, 10, "one existing option plus our nine"

sd = list.find { |o| o.name == "Spoken Directions" }
check sd.is_a?(EnumOption), "Spoken Directions is an enum"
check_eq sd.values.length, 3,
         "with three choices, because 'as well as 3D' and 'only without 3D' differ"

vol = list.find { |o| o.name == "Tile Sound Volume" }
check vol.is_a?(NumberOption), "the volume is a slider, not an on/off"
check_eq [vol.min, vol.max], [0, 100], "with a sensible range"
check list.all? { |o| o.description.nil? || !o.description.empty? },
      "every option we added explains itself"

# The option's own getter and setter must go through the settings.
speech_opt = list.find { |o| o.name == "Speech" }
A11ySettings.set(:speech, 0)
check_eq speech_opt.get, 0, "an option reads its current value"
speech_opt.set(1)
check_eq A11ySettings.get(:speech), 1, "and writing through it stores the value"
speech_opt.set(0)

# ── A soft reset must not stack a second copy of every row ────────────────
before = PokemonOptionScene::OptionList.length
2.times { load mod }
check_eq PokemonOptionScene::OptionList.length, before,
         "reloading does not add the options twice"

# ── Nothing may explode when $Settings is missing entirely ────────────────
saved_settings = $Settings
$Settings = nil
ok = true
begin
  check_eq A11ySettings.get(:beacon), 0, "with no $Settings at all, defaults still answer"
  A11ySettings.set(:beacon, 1)
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
end
check ok, "and setting one is ignored rather than crashing"
$Settings = saved_settings

puts "=" * 56
puts " RESULTS: #{$pass} passed, #{$fail} failed"
puts "=" * 56
exit($fail == 0 ? 0 : 1)
