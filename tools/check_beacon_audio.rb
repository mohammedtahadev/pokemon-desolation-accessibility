# Checks whether the Steam Audio beacon can actually start on this machine.
#
#   ruby tools/check_beacon_audio.rb
#
# Run it from the GAME FOLDER, because the mod looks for its files relative to
# the working directory - the same way the game does.
#
# It loads the real beacon.dll and phonon.dll, points a source, and plays about
# half a second of the beacon sound. If you hear it, Steam Audio works.
#
# ONE CAVEAT WORTH KNOWING
# ------------------------
# This runs under whatever Ruby is on your PATH. The game runs its own
# interpreter, embedded in x64-msvcrt-ruby310.dll. They are not the same build,
# so a pass here proves the DLLs, the paths and the C calling convention are
# right - it does not prove the game's interpreter can require fiddle.
#
# The game's own verdict is written to beacon_error.txt in the game folder the
# first time you press Shift+B. That file is the real answer.

Dir.chdir(File.expand_path("..", __dir__))

# The mod expects these from the game; stub just enough to load it.
def tts(*a); end
module PraSession; end
class Game_Character; def update; end; end
class Game_Player < Game_Character; end
class Scene_Map; def main; end; end
$game_temp = nil

load "patch/Mods/AccessibilityBeacon.rb"

puts "ruby       : #{RUBY_VERSION} #{RUBY_PLATFORM}"
puts "working dir: #{Dir.pwd}"
puts

{ "beacon.dll" => PraBeaconAudio.locate("beacon.dll"),
  "phonon.dll" => PraBeaconAudio.locate("phonon.dll"),
  "the sound"  => PraBeaconAudio.sound_file }.each do |what, path|
  puts format("  %-11s %s", what, path || "*** NOT FOUND")
end
puts

ok = PraBeaconAudio.init
puts "  init       #{ok ? "ok" : "failed - see beacon_error.txt"}"
puts "  available  #{PraBeaconAudio.available}"

if PraBeaconAudio.available
  puts
  puts "  Walking the beacon around you. The beacon is a COMPASS - screen-"
  puts "  fixed, like Reborn's - so north on the map is always in front and"
  puts "  south always behind, whichever way your sprite faces. Listen for"
  puts "  the pitch dropping and the sound going dull on the south side."
  puts
  [["north of you - in front",             0, -5],
   ["east of you - to your right",         5,  0],
   ["SOUTH of you - behind, low and dull", 0,  5],
   ["west of you - to your left",         -5,  0],
   ["north again - back to normal pitch",  0, -5]].each do |label, dx, dy|
    puts "    #{label}"
    PraBeaconAudio.point(dx, dy, 5.0)
    sleep 1.0
  end
  PraBeaconAudio.stop
  puts
  puts "  done. Lower and duller = the target is south of you on the map."
else
  puts
  puts "  Steam Audio did not start, so the beacon will speak directions"
  puts "  instead. beacon_error.txt says why."
end
