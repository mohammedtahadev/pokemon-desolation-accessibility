# Converts pokemon_biology.json (from the Reborn accessibility project,
# github.com/fclorenzo/pkreborn-access) into patch/biology.dat, a Ruby Marshal
# file, so the game can read it WITHOUT the json library - Desolation's
# embedded Ruby ships no stdlib, and json may not be compiled in. Marshal
# always is.
#
#   ruby tools/build_biology.rb [path\to\pokemon_biology.json]
require 'json'
GAME = File.expand_path("..", __dir__)
src = ARGV[0] || File.join(GAME, "patch", "pokemon_biology.json")
src = "E:/Guide/Reborn-19.5.0-windows/pokemon_biology.json" unless File.exist?(src)
raise "no source json found" unless File.exist?(src)
raw = File.open(src, "r:UTF-8") { |f| f.read }.sub("\xEF\xBB\xBF", "")
data = JSON.parse(raw)
out = {}
data.each do |species, entry|
  forms = entry["forms"]
  next unless forms.is_a?(Hash) && !forms.empty?
  out[species.upcase] = forms.each_with_object({}) { |(k, v), h| h[k.to_s.downcase] = v.to_s }
end
target = File.join(GAME, "patch", "biology.dat")
File.open(target, "wb") { |f| f.write(Marshal.dump(out)) }
puts "wrote #{target}: #{out.length} species, #{File.size(target)} bytes"
