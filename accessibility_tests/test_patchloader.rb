# Exercises AccessibilityZZPatchLoader: loading mods out of patch/Mods, and -
# the part that actually matters - one broken mod not taking the game with it.
#
#   ruby test_patchloader.rb ../Data/Mods/AccessibilityLoader.rb
$pass = 0; $fail = 0
def check(c, n); c ? ($pass += 1; puts "PASS: #{n}") : ($fail += 1; puts "FAIL: #{n}"); end
def check_eq(a, e, n)
  if a == e then $pass += 1; puts "PASS: #{n}"
  else $fail += 1; puts "FAIL: #{n}\n        expected: #{e.inspect}\n        actual:   #{a.inspect}" end
end

require "fileutils"
require "tmpdir"

mod = File.expand_path(ARGV[0] || "../Data/Mods/AccessibilityLoader.rb")

# The loader uses paths relative to the working directory, exactly as the game
# does, so give it a throwaway one.
Dir.mktmpdir("patchloader") do |tmp|
  Dir.chdir(tmp) do
    # ── With no patch folder, it must say so where it can be found ─────────
    # This is not a harmless case any more: no patch folder means NO
    # accessibility mods at all, and a blind player gets a game that simply
    # says nothing. The usual log lives inside the missing folder, so the
    # warning goes to the game root instead.
    ok = true
    begin
      load mod
    rescue Exception => e
      ok = false
      puts "        #{e.class}: #{e.message}"
    end
    check ok, "with no patch folder, loading does not raise"
    check File.exist?("ACCESSIBILITY_NOT_LOADED.txt"),
          "but a warning lands in the game root, where it cannot be missed"
    warning = File.read("ACCESSIBILITY_NOT_LOADED.txt")
    check warning.include?("Re-copy the patch folder"),
          "and it says what to do about it"

    # ── An empty patch folder ──────────────────────────────────────────────
    FileUtils.mkdir_p("patch/Mods")
    load mod
    check_eq A11yPatchMods.loaded, [], "an empty patch folder loads nothing"
    check File.exist?("patch/Mods/load_log.txt"), "but does say so in the log"
    check !File.exist?("ACCESSIBILITY_NOT_LOADED.txt"),
          "and the stale missing-folder warning is cleaned up"

    # ── Accessibility mods load before anything else, regardless of names ──
    File.write("patch/Mods/AccessibilityZebra.rb", "$order2 ||= []; $order2 << :zebra")
    File.write("patch/Mods/aaa_user_mod.rb",       "$order2 ||= []; $order2 << :user")
    $order2 = []
    load mod
    check_eq $order2, [:zebra, :user],
             "an Accessibility mod loads before a user mod named to sort first"
    FileUtils.rm_f(Dir["patch/Mods/*.rb"])

    # ── The real case: good, broken, good ──────────────────────────────────
    File.write("patch/Mods/aaa_first.rb",  "$order ||= []; $order << :first")
    File.write("patch/Mods/bbb_broken.rb", "raise NoMethodError, 'initOptions is Reborn-only'")
    File.write("patch/Mods/ccc_last.rb",   "$order ||= []; $order << :last")

    $order = []
    load mod

    check_eq A11yPatchMods.loaded, ["aaa_first.rb", "ccc_last.rb"], "the good mods load"
    check_eq A11yPatchMods.failed, ["bbb_broken.rb"], "the broken one is recorded as failed"
    check_eq $order, [:first, :last],
             "a mod that raises does NOT stop the ones after it - this is the whole point"

    log = File.read("patch/Mods/load_log.txt")
    check log.include?("FAILED  bbb_broken.rb"), "the log names the file that failed"
    check log.include?("initOptions is Reborn-only"), "and quotes the actual error"
    check log.include?("NoMethodError"), "with its class"
    check log =~ /2 loaded, 1 failed/, "and a tally at the end"
    check log.include?("OK      aaa_first.rb"), "the ones that worked are listed too"

    # ── Alphabetical order, as documented ──────────────────────────────────
    FileUtils.rm_f(Dir["patch/Mods/*.rb"])
    File.write("patch/Mods/2_second.rb", "$seq ||= []; $seq << 2")
    File.write("patch/Mods/1_first.rb",  "$seq ||= []; $seq << 1")
    File.write("patch/Mods/3_third.rb",  "$seq ||= []; $seq << 3")
    $seq = []
    load mod
    check_eq $seq, [1, 2, 3], "files load in alphabetical order"

    # ── A mod that raises something exotic ─────────────────────────────────
    FileUtils.rm_f(Dir["patch/Mods/*.rb"])
    File.write("patch/Mods/nasty.rb", "raise Exception, 'not a StandardError'")
    File.write("patch/Mods/fine.rb",  "$survived = true")
    $survived = false
    ok = true
    begin
      load mod
    rescue Exception => e
      ok = false
      puts "        escaped: #{e.class}: #{e.message}"
    end
    check ok, "even a bare Exception is caught rather than escaping"
    check $survived, "and the other mods still run"

    # ── A syntax error, which fails at parse rather than run ───────────────
    FileUtils.rm_f(Dir["patch/Mods/*.rb"])
    File.write("patch/Mods/broken_syntax.rb", "def oops(\n")
    File.write("patch/Mods/good.rb", "$after_syntax_error = true")
    $after_syntax_error = false
    ok = true
    begin
      load mod
    rescue Exception => e
      ok = false
      puts "        escaped: #{e.class}: #{e.message}"
    end
    check ok, "a syntax error is caught too"
    check $after_syntax_error, "and does not stop the rest"
    check_eq A11yPatchMods.failed, ["broken_syntax.rb"], "it is reported as the failure"
  end
end

puts "=" * 56
puts " RESULTS: #{$pass} passed, #{$fail} failed"
puts "=" * 56
exit($fail == 0 ? 0 : 1)
