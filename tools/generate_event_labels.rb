# Runs AccessibilityPathfindNames' label logic over every event on every map,
# without launching the game.
#
#   ruby tools/generate_event_labels.rb                 report only
#   ruby tools/generate_event_labels.rb --write         also write pra-custom-names.txt
#   ruby tools/generate_event_labels.rb --sample 40     show more examples
#
# It loads the mod itself rather than reimplementing anything, so what you read
# here is exactly what you will hear in game. If the two ever disagree, this
# file is wrong, not the mod.
#
# READ THIS BEFORE USING --write
# ------------------------------
# pra-custom-names.txt is keyed on where an event IS, and the pathfinder looks
# events up by their CURRENT position. Around a thousand event pages in
# Desolation use random movement, so a written-out label follows a wandering
# NPC only until it takes its first step. The mod derives labels live and does
# not have that problem, so --write is for reading and editing the whole set,
# not something you need for the names to work.
#
# --write also merges: any name already in the file is kept, because it is
# either yours or one you edited.

GAME = File.expand_path("..", __dir__)
MOD  = File.join(GAME, "patch", "Mods", "AccessibilityPathfindNames.rb")
OUT  = File.join(GAME, "pra-custom-names.txt")

write_file = ARGV.include?("--write")
sample_n   = (ARGV[ARGV.index("--sample") + 1].to_i if ARGV.include?("--sample")) || 12

# ── RPG Maker / Essentials stubs, enough for Marshal to rebuild the data ─────
class GenericRPG
  def marshal_load(h); h.each { |k, v| instance_variable_set(k, v) } if h.is_a?(Hash); end
  def ivget(n); instance_variable_get("@#{n}"); end
  def method_missing(m, *a)
    n = "@#{m}"
    instance_variable_defined?(n) ? instance_variable_get(n) : nil
  end
  def respond_to_missing?(*); true; end
end
module RPG
  class Map < GenericRPG; end
  class MapInfo < GenericRPG; end
  class Event < GenericRPG
    class Page < GenericRPG
      class Condition < GenericRPG; end
      class Graphic   < GenericRPG; end
    end
  end
  class EventCommand < GenericRPG; end
  class MoveRoute    < GenericRPG; end
  class MoveCommand  < GenericRPG; end
  class AudioFile    < GenericRPG; end
end
class DataObject  < GenericRPG; end
class TrainerData < GenericRPG; end
class MonData     < GenericRPG; end
class Table
  def self._load(s)
    t = allocate
    _n, xs, ys, zs, _c = s[0, 20].unpack("l5")
    t.instance_variable_set(:@xsize, xs)
    t.instance_variable_set(:@ysize, ys)
    t.instance_variable_set(:@data, s[20..-1].unpack("v*"))
    t
  end
end
class Tone;  def self._load(s); new; end; end
class Color; def self._load(s); new; end; end

# Marshalled RMXP strings arrive as ASCII-8BIT.
def u(s); s.to_s.dup.force_encoding("UTF-8").scrub(""); end

def load_dat(name)
  Marshal.load(File.binread(File.join(GAME, "Data", name)))
rescue Exception => e
  warn "  could not read #{name}: #{e.class}: #{e.message}"
  nil
end

# ── Stand in for the game's $cache, which is all the mod actually needs ──────
Wrapped = Struct.new(:name)
class CacheStub
  attr_reader :trainertypes, :pkmn, :mapinfos
  def initialize(tt, mons, infos); @trainertypes = tt; @pkmn = mons; @mapinfos = infos; end
end

tt = load_dat("ttypes.dat") || {}
tt.each_value do |td|
  td.instance_variable_set(:@title, u(td.instance_variable_get(:@title)))
end
mons = load_dat("mons.dat") || {}
mons.each_value do |md|
  md.instance_variable_set(:@name, u(md.instance_variable_get(:@name)))
end
infos_raw = Marshal.load(File.binread(File.join(GAME, "Data", "MapInfos.rxdata")))
infos = {}
infos_raw.each { |id, i| infos[id] = Wrapped.new(u(i.ivget("name"))) }

$cache = CacheStub.new(tt, mons, infos)

# The mod hooks Game_Player and Scene_Map; give it something harmless to hook.
class Game_Player; def populate_event_list; end; end
class Scene_Map;   def main; end; end
load MOD

# ── An event shaped the way the mod expects to find one ─────────────────────
FakeEvent = Struct.new(:name, :character_name, :list, :x, :y) do
  def custom_name; @cn; end
  def custom_name=(v); @cn = v; end
end

puts "trainer titles: #{A11yNames.trainer_titles.size}   " \
     "species: #{A11yNames.species_names.size}   maps: #{infos.size}"
puts

listed = 0
already = 0
labelled = 0
unlabelled = 0
kinds = Hash.new(0)
examples = Hash.new { |h, k| h[k] = [] }
rows = []

Dir[File.join(GAME, "Data", "Map[0-9][0-9][0-9].rxdata")].sort.each do |f|
  map_id = File.basename(f)[/\d+/].to_i
  map_nm = infos[map_id] ? infos[map_id].name : "map #{map_id}"
  begin; m = Marshal.load(File.binread(f)); rescue Exception; next; end
  (m.ivget("events") || {}).each do |_eid, ev|
    pages = ev.ivget("pages") || []
    page = pages.reverse.find { |p| (p.ivget("list") || []).size > 1 }
    next unless page
    list = page.ivget("list")
    trig = page.ivget("trigger")
    next if trig == 3 || trig == 4              # the pathfinder skips these
    listed += 1

    gfx = page.ivget("graphic")
    sprite = gfx ? u(gfx.ivget("character_name")) : ""
    name = u(ev.ivget("name"))

    # Text comes out of Marshal as binary; the running game has it as UTF-8.
    list.each do |c|
      p = c.ivget("parameters")
      next unless p.is_a?(Array)
      p.each_with_index { |v, i| p[i] = u(v) if v.is_a?(String) }
    end

    unless A11yNames.useless_name?(name)
      already += 1
      next
    end

    e = FakeEvent.new(name, sprite, list, ev.ivget("x"), ev.ivget("y"))
    label = A11yNames.derive(e)

    if label && !label.empty?
      labelled += 1
      kind =
        case label
        when /\ADoor to /       then "door"
        when /\AItem ball/      then "item ball"
        when /\AHidden item/    then "hidden item"
        when /\AShop counter/   then "shop"
        when /\ASign: /         then "sign"
        when /\APerson[:,] /    then "person (from dialogue)"
        when /\ATrainer: /      then "trainer (from script)"
        when /\AObject/        then "object"
        when /\AMove trigger/  then "move trigger (invisible)"
        when /\ATrigger tile/  then "trigger tile (invisible)"
        when /\APerson\z/      then "person (silent)"
        else                         "named or described"
        end
      kinds[kind] += 1
      examples[kind] << "#{map_nm}: #{label}" if examples[kind].size < sample_n
      rows << [map_id, map_nm, e.x, e.y, label]
    else
      unlabelled += 1
      examples["*** no label"] << "#{map_nm} sprite=#{sprite.inspect}" if examples["*** no label"].size < sample_n
    end
  end
end

puts "events the pathfinder would list : #{listed}"
puts "  already named by the writers   : #{already}"
puts "  named by this mod              : #{labelled}"
puts "  still unnamed                  : #{unlabelled}"
covered = already + labelled
puts "  ------------------------------------------"
puts "  usefully named                 : #{covered} of #{listed}  " \
     "(#{(100.0 * covered / listed).round(1)}%)"
puts
puts "WHAT THE NEW NAMES LOOK LIKE"
puts "-" * 72
kinds.sort_by { |_, v| -v }.each do |kind, n|
  puts format("  %-26s %6d", kind, n)
  examples[kind].first(sample_n).each { |s| puts "        #{s}" }
end
unless examples["*** no label"].empty?
  puts format("  %-26s %6d", "no label derivable", unlabelled)
  examples["*** no label"].first(6).each { |s| puts "        #{s}" }
end

if write_file
  existing = {}
  header_lines = []
  if File.exist?(OUT)
    File.readlines(OUT).each do |line|
      if line.start_with?("#") || line.strip.empty?
        header_lines << line
        next
      end
      parts = line.strip.split(";")
      next if parts.length < 5
      existing["#{parts[0]};#{parts[2]};#{parts[3]}"] = line.strip
    end
  end
  kept = 0
  File.open(OUT, "w") do |fh|
    if header_lines.empty?
      fh.puts "# Pokemon Desolation - event names"
      fh.puts "# map_id;map_name;coord_x;coord_y;event_name;notes;type"
      fh.puts "# Generated by tools/generate_event_labels.rb. Lines you add or edit"
      fh.puts "# are kept when it is run again. Do not use semicolons in a name."
      fh.puts "#"
    else
      header_lines.each { |l| fh.print l }
    end
    rows.each do |map_id, map_nm, x, y, label|
      key = "#{map_id};#{x};#{y}"
      if existing[key]
        fh.puts existing[key]
        kept += 1
      else
        fh.puts [map_id, map_nm, x, y, label, "", "event"].join(";")
      end
    end
  end
  puts
  puts "wrote #{OUT}"
  puts "  #{rows.size} lines (#{kept} of them yours, kept as they were)"
end
