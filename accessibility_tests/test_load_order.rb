# Loads the whole mod stack exactly the way the GAME does: ClientData.rb loads
# Data\Mods\*.rb (which now holds only AccessibilityLoader.rb), and that loader
# loads everything out of patch\Mods - accessibility mods first, extras after.
#
#   ruby test_load_order.rb ..        (the game folder)
#
# WHY THIS EXISTS
# ---------------
# Mods load alphabetically, so AccessibilityEvents, Menus and Pathfind all load
# BEFORE AccessibilitySpeech, and anything one of them calls on
# AccessibilitySpeech at load time raises NameError and crashes the game at
# startup. That happened once for real. The single-mod harnesses cannot see
# it; only loading everything in the true order can.
$pass = 0; $fail = 0
def check(c, n); c ? ($pass += 1; puts "PASS: #{n}") : ($fail += 1; puts "FAIL: #{n}"); end
def check_eq(a, e, n)
  if a == e then $pass += 1; puts "PASS: #{n}"
  else $fail += 1; puts "FAIL: #{n}
        expected: #{e.inspect}
        actual:   #{a.inspect}" end
end

require_relative "stubs_desolation"
$game_variables = Game_Variables.new   # pra-walk reads the encounter-rate one

game_root = File.expand_path(ARGV[0] || "..")
Dir.chdir(game_root)                   # the game's own working directory

# Stage 1: what ClientData.rb finds. There must be exactly one file - the
# bootstrap - because everything else has moved to patch/Mods.
data_mods = Dir["Data/Mods/*.rb"].sort
check_eq data_mods.map { |f| File.basename(f) }, ["AccessibilityLoader.rb"],
         "Data/Mods holds only the bootstrap - the game's native loader has one job"

patch_mods = Dir["patch/Mods/*.rb"].sort.map { |f| File.basename(f) }
check patch_mods.size >= 11, "patch/Mods holds the mods (#{patch_mods.size} files)"
puts "  patch load order: " + patch_mods.join(", ")

# Load it the way the game does, once.
def game_boot(data_mods)
  data_mods.each { |f| load File.expand_path(f) }
end

ok = true
begin
  game_boot(data_mods)
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
  puts "        #{e.backtrace.first(4).join("\n        ")}"
end
check ok, "the bootstrap loads without error"

check defined?(A11yPatchMods) ? true : false, "the patch loader exists"
check_eq A11yPatchMods.failed, [], "every mod in patch/Mods loaded cleanly"
check A11yPatchMods.loaded.size >= 11, "and all of them actually loaded (#{A11yPatchMods.loaded.size})"
check A11yPatchMods.loaded.first.start_with?("Accessibility"),
      "accessibility mods load first, whatever else is in the folder"
check File.exist?("patch/Mods/load_log.txt"), "the load log was written"
check !File.exist?("ACCESSIBILITY_NOT_LOADED.txt"),
      "and no missing-folder warning, because nothing is missing"

# The whole stack has to survive frames without any mod stepping on another's
# alias chain.
ok = true
begin
  10.times { $game_player.update }
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
  puts "        #{e.backtrace.first(4).join("\n        ")}"
end
check ok, "ten frames run with every mod hooked at once"

# F12 soft reset: the game re-loads Data/Mods on top of what is already loaded,
# and the bootstrap re-loads all of patch/Mods in turn.
ok = true
begin
  game_boot(data_mods)
  10.times { $game_player.update }
rescue Exception => e
  ok = false
  puts "        #{e.class}: #{e.message}"
  puts "        #{e.backtrace.first(4).join("\n        ")}"
end
check ok, "a soft reset re-loads the whole stack without recursing"

# A setting that lives in ANOTHER mod has to survive the load order.
# AccessibilityOptions loads at "O", AccessibilitySpeech at "S", so the options
# mod's own apply_all runs before the speech mod exists and does nothing. The
# bootstrap re-applies after everything, which is what makes a stored "off"
# stick across a restart. This caught a real bug.
if defined?(A11ySettings) && defined?(AccessibilitySpeech)
  A11ySettings.set(:speech, 1)
  AccessibilitySpeech.enabled = true          # as the speech mod loads
  game_boot(data_mods)                        # a full restart, in game order
  check_eq AccessibilitySpeech.enabled, false,
           "a stored 'speech off' survives a full boot in game order"
  A11ySettings.set(:speech, 0)
  AccessibilitySpeech.enabled = false
  game_boot(data_mods)
  check_eq AccessibilitySpeech.enabled, true, "and so does switching it back on"
end

check defined?(tts) ? true : false, "the pathfinder's tts shim is present"
check defined?(AccessibilitySpeech) ? true : false, "the speech engine loaded"
check $game_player.respond_to?(:populate_event_list), "the pathfinder is hooked"
check $game_player.respond_to?(:follow_autowalk_path), "auto-walk is hooked"

File.delete(CUSTOM_NAMES_FILE) if defined?(CUSTOM_NAMES_FILE) && File.exist?(CUSTOM_NAMES_FILE)

puts "=" * 56
puts " RESULTS: #{$pass} passed, #{$fail} failed"
puts "=" * 56
exit($fail == 0 ? 0 : 1)
