# Installs any audio file as the beacon sound.
#
#   ruby tools/set_beacon_sound.rb Data/audio/beacon.ogg
#   ruby tools/set_beacon_sound.rb "C:/somewhere/my ping.mp3"
#   ruby tools/set_beacon_sound.rb --restore      put the original back
#
# WHY THIS EXISTS
# ---------------
# beacon.dll is built on miniaudio, which decodes WAV and MP3 but NOT OGG
# Vorbis. Every sound Desolation itself ships is .ogg, so dropping one in as the
# beacon is the obvious thing to try - and it quietly does not work, because the
# engine cannot read it and falls back to speaking directions.
#
# This converts whatever you give it to exactly what the engine wants: mono,
# 48000 Hz, 16-bit PCM WAV. Mono matters - a stereo file already carries its own
# left/right, which fights the HRTF that is supposed to be placing it for you.
#
# It writes Data/audio/beacon.wav, which is first in the mod's search order, so
# your sound wins over the one that shipped. The shipped one stays untouched at
# patch/audio/beacon.wav, and --restore simply removes yours.
#
# Needs ffmpeg on PATH. If the file is already mono 48k WAV it is just copied.

require "fileutils"

GAME = File.expand_path("..", __dir__)
DEST = File.join(GAME, "Data", "audio", "beacon.wav")
SHIPPED = File.join(GAME, "patch", "audio", "beacon.wav")

def die(msg)
  warn "  #{msg}"
  exit 1
end

if ARGV.include?("--restore")
  if File.exist?(DEST)
    File.delete(DEST)
    puts "  removed #{DEST}"
    puts "  the beacon falls back to #{SHIPPED}"
  else
    puts "  nothing to remove - already using #{SHIPPED}"
  end
  exit 0
end

src = ARGV.first
die("usage: ruby tools/set_beacon_sound.rb <audio file>   (or --restore)") unless src
src = File.expand_path(src, GAME)
die("no such file: #{src}") unless File.exist?(src)

have_ffmpeg = system("ffmpeg -version > #{File::NULL} 2>&1")
die("ffmpeg is not on PATH, and it is needed to convert audio.") unless have_ffmpeg

FileUtils.mkdir_p(File.dirname(DEST))

puts "  source     #{src}"
info = `ffmpeg -hide_banner -i "#{src}" 2>&1`
if (m = info[/Stream .*Audio: .*/])
  puts "  format     #{m.sub(/\s*Stream #\d+:\d+[^:]*:\s*Audio:\s*/, '')}"
end

tmp = DEST + ".tmp.wav"
cmd = %Q{ffmpeg -hide_banner -loglevel error -y -i "#{src}" -ac 1 -ar 48000 -c:a pcm_s16le "#{tmp}"}
unless system(cmd)
  File.delete(tmp) if File.exist?(tmp)
  die("ffmpeg could not convert that file.")
end
die("ffmpeg produced nothing.") unless File.exist?(tmp) && File.size(tmp) > 44

FileUtils.mv(tmp, DEST)
puts "  installed  #{DEST}"
puts "             mono, 48000 Hz, 16-bit PCM - what the engine decodes"
puts

# Say plainly if this changes nothing, rather than letting them wonder why the
# beacon sounds the same.
if File.exist?(SHIPPED)
  a = `ffmpeg -hide_banner -loglevel error -i "#{DEST}" -f s16le - 2>#{File::NULL}`
  b = `ffmpeg -hide_banner -loglevel error -i "#{SHIPPED}" -f s16le - 2>#{File::NULL}`
  if !a.empty? && a == b
    puts "  NOTE: this decodes to exactly the same audio as the sound that was"
    puts "  already installed, so the beacon will not sound any different."
    puts
  end
end

puts "  check it with:  ruby tools/check_beacon_audio.rb"
