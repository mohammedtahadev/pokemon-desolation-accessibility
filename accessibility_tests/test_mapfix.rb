# Proves AccessibilityMapFix.rb does exactly one thing: stops a moved-event
# entry that belongs to a different map from touching the current map, while
# behaving identically to the original on every input the game can actually
# produce.
#
#   ruby test_mapfix.rb ../patch/Mods/AccessibilityMapFix.rb
#
# The original method is reproduced verbatim below so the two can be run over
# the same inputs and compared, rather than the fix being taken on trust.
$pass = 0; $fail = 0
def check(c, n); c ? ($pass += 1; puts "PASS: #{n}") : ($fail += 1; puts "FAIL: #{n}"); end

class Ev
  attr_accessor :id, :x, :y, :direction, :through, :erased
  def initialize(id); @id = id; @x = 0; @y = 0; @direction = 2; @through = false; @erased = false; end
  def moveto(x, y); @x = x; @y = y; end
  def turn_down;  @direction = 2; end
  def turn_left;  @direction = 4; end
  def turn_right; @direction = 6; end
  def turn_up;    @direction = 8; end
  def erase; @erased = true; end
  def state; [@x, @y, @direction, @through, @erased]; end
end

class FakeMap
  attr_accessor :map_id, :events
  def initialize(id, ids); @map_id = id; @events = {}; ids.each { |i| @events[i] = Ev.new(i) }; end
  def state; @events.keys.sort.map { |k| [k, @events[k].state] }; end
end

# ── The ORIGINAL, copied verbatim from Scripts/Map.rb:48-73 ──────────────────
class OriginalMetadata
  attr_accessor :erasedEvents, :movedEvents
  def initialize(erased = {}, moved = {}); @erasedEvents = erased; @movedEvents = moved; end
  def updateMap
    for i in @erasedEvents
      if i[0][0]==$game_map.map_id && i[1]
        event=$game_map.events[i[0][1]]
        event.erase if event
      end
    end
    for i in @movedEvents
      if i[0][0]==$game_map.map_id && i[1]
        next if !$game_map.events[i[0][1]]
        $game_map.events[i[0][1]].moveto(i[1][0],i[1][1])
        case i[1][2]
          when 2
            $game_map.events[i[0][1]].turn_down
          when 4
            $game_map.events[i[0][1]].turn_left
          when 6
            $game_map.events[i[0][1]].turn_right
          when 8
            $game_map.events[i[0][1]].turn_up
        end
      end
      if i[1][3]!=nil
        $game_map.events[i[0][1]].through=i[1][3]
      end
    end
  end
end

# ── The FIXED one, loaded from the mod ──────────────────────────────────────
class PokemonMapMetadata
  attr_accessor :erasedEvents, :movedEvents
  def initialize(erased = {}, moved = {}); @erasedEvents = erased; @movedEvents = moved; end
end
load File.expand_path(ARGV[0] || "../patch/Mods/AccessibilityMapFix.rb")

check PokemonMapMetadata.instance_method(:updateMap) ? true : false,
      "the mod defines updateMap"

# Runs one scenario through a class and reports either the resulting map state
# or the exception it raised.
def run(klass, map_id, event_ids, erased, moved)
  $game_map = FakeMap.new(map_id, event_ids)
  begin
    klass.new(erased, moved).updateMap
    [:ok, $game_map.state]
  rescue Exception => e
    [:raised, e.class.to_s]
  end
end

# ── 1. Every input the game can actually produce ────────────────────────────
# onMapChange empties @movedEvents whenever $game_map changes, so by the time
# updateMap runs every entry belongs to the current map. Over that whole input
# space the fixed method must be indistinguishable from the original.
same_map = [
  ["a moved event, facing down",   1, [1, 2, 3], {}, { [1, 1] => [4, 5, 2, false] }],
  ["a moved event, facing left",   1, [1, 2, 3], {}, { [1, 2] => [6, 7, 4, false] }],
  ["a moved event, facing right",  1, [1, 2, 3], {}, { [1, 3] => [1, 1, 6, true]  }],
  ["a moved event, facing up",     1, [1, 2, 3], {}, { [1, 1] => [2, 2, 8, true]  }],
  ["through explicitly false",     1, [1],       {}, { [1, 1] => [3, 3, 2, false] }],
  ["through explicitly true",      1, [1],       {}, { [1, 1] => [3, 3, 2, true]  }],
  ["an id that is not on the map", 1, [1],       {}, { [1, 9] => [3, 3, 2, false] }],
  ["several at once",              1, [1, 2, 3], {},
     { [1, 1] => [4, 4, 2, true], [1, 2] => [5, 5, 4, false], [1, 3] => [6, 6, 8, true] }],
  ["an erased event",              1, [1, 2],    { [1, 2] => true }, {}],
  ["erased and moved together",    1, [1, 2],    { [1, 2] => true }, { [1, 1] => [7, 7, 6, true] }],
  ["nothing at all",               1, [1, 2],    {}, {}],
]

identical = true
same_map.each do |name, mid, ids, erased, moved|
  a = run(OriginalMetadata,     mid, ids, erased, moved)
  b = run(PokemonMapMetadata,   mid, ids, erased, moved)
  ok = (a == b)
  identical &&= ok
  check ok, "same result as the original: #{name}"
  puts "        original: #{a.inspect}\n        fixed:    #{b.inspect}" unless ok
end
check identical, "the fix is behaviour-preserving on every reachable input"

# ── 2. The case it guards ───────────────────────────────────────────────────
# A legacy save (DataConversion.rb:47 loads :PokemonMap verbatim) could carry an
# entry for a map you are not standing on.

# 2a. id absent from the current map -> the original crashes.
a = run(OriginalMetadata,   2, [1], {}, { [1, 7] => [3, 4, 2, false] })
b = run(PokemonMapMetadata, 2, [1], {}, { [1, 7] => [3, 4, 2, false] })
check a[0] == :raised && a[1] == "NoMethodError",
      "the original really does crash on a foreign entry (#{a[1]})"
check b[0] == :ok, "the fix does not crash"

# 2b. id present on the current map -> the original silently corrupts it.
a = run(OriginalMetadata,   2, [1], {}, { [1, 1] => [9, 9, 2, true] })
b = run(PokemonMapMetadata, 2, [1], {}, { [1, 1] => [9, 9, 2, true] })
orig_through  = a[1][0][1][3]
fixed_through = b[1][0][1][3]
check orig_through == true,  "the original really does corrupt an unrelated event's through flag"
check fixed_through == false, "the fix leaves the unrelated event alone"

# 2c. A foreign entry must not stop the current map's own entries applying.
mixed = { [1, 1] => [9, 9, 2, true], [2, 1] => [4, 5, 8, true] }
r = run(PokemonMapMetadata, 2, [1], {}, mixed)
check r[0] == :ok, "a mixed hash does not crash"
check r[1][0][1][0, 2] == [4, 5], "the current map's own moved event still applies"
check r[1][0][1][3] == true, "and its through flag still applies"

# ── 3. Reloading the mod is harmless (F12 soft reset) ───────────────────────
ok = true
begin
  2.times { load File.expand_path(ARGV[0] || "../patch/Mods/AccessibilityMapFix.rb") }
  run(PokemonMapMetadata, 1, [1], {}, { [1, 1] => [2, 2, 2, true] })
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
end
check ok, "reloading the mod does not break it"

puts "=" * 56
puts " RESULTS: #{$pass} passed, #{$fail} failed"
puts "=" * 56
exit($fail == 0 ? 0 : 1)
