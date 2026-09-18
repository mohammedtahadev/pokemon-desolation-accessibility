# =============================================================================
# AccessibilityLoader.rb - the one file that has to live in Data\Mods.
#
# Everything else - all the accessibility mods, and any mods of your own -
# lives in patch\Mods, the same layout Reborn and Rejuvenation use.
#
# WHY THIS FILE CANNOT MOVE TOO
# -----------------------------
# Desolation has no native patch\Mods support. The only place its engine ever
# loads mods from is Data\Mods (ClientData.rb runs Dir["./Data/Mods/*.rb"] at
# startup - that line IS the game's whole mod system). So one bootstrap must
# sit here to teach it the Reborn layout; delete this file and patch\Mods goes
# completely dead.
#
# WHAT IT DOES, IN ORDER
# ----------------------
#   1. Loads patch\Mods\Accessibility*.rb, alphabetically - the accessibility
#      system itself.
#   2. Loads every other patch\Mods\*.rb, alphabetically - your own mods, which
#      therefore always load AFTER the accessibility mods they might build on.
#      (Load position does not depend on what your files are named.)
#   3. Applies the stored accessibility settings. This must happen after ALL
#      mods exist: the Options mod loads at "O", before Speech at "S", so a
#      stored "speech off" could not take effect at its own load time and
#      would otherwise be forgotten on every restart.
#
# EVERY FILE LOADS IN ITS OWN GUARD. Desolation's native loader is unguarded -
# one broken mod takes the whole game down with a crash dialog that does not
# even name the file. Here a mod that fails is skipped and named in
# patch\Mods\load_log.txt while everything else still runs. Mods written for
# Reborn reach for classes Desolation does not have, so failing IS the normal
# case for a straight drop-in; it should cost a log line, not your session.
# =============================================================================

module A11yPatchMods
  DIR = "patch/Mods"
  LOG = "patch/Mods/load_log.txt"

  class << self
    attr_reader :loaded, :failed

    def log(lines)
      return if lines.empty?
      File.open(LOG, "w") do |f|
        f.puts "# Written by Data/Mods/AccessibilityLoader.rb every time the game starts."
        f.puts "# Delete it freely; it is regenerated."
        f.puts "# #{Time.now}"
        f.puts
        lines.each { |l| f.puts l }
      end
    rescue Exception
      nil
    end

    def load_one(file, lines)
      load file
      @loaded << File.basename(file)
      lines << "OK      #{File.basename(file)}"
    rescue Exception => e
      @failed << File.basename(file)
      lines << "FAILED  #{File.basename(file)}"
      lines << "        #{e.class}: #{e.message}"
      Array(e.backtrace).first(4).each { |b| lines << "        #{b}" }
    end

    def run
      @loaded = []
      @failed = []
      lines = []
      unless File.directory?(DIR)
        # No patch folder means no accessibility system AT ALL. The usual log
        # lives inside that folder, so the warning has to go somewhere that
        # still exists - the game root, where it cannot be missed.
        begin
          File.open("ACCESSIBILITY_NOT_LOADED.txt", "w") do |f|
            f.puts "patch\\Mods does not exist, so NO accessibility mods were loaded."
            f.puts "The game will run, silently. Re-copy the patch folder from the pack"
            f.puts "into the game folder, next to Game.exe, and start the game again."
            f.puts "(#{Time.now})"
          end
        rescue Exception
        end
        return
      end
      # A leftover warning from a previous bad start is stale the moment this
      # loader gets further than that check.
      begin
        File.delete("ACCESSIBILITY_NOT_LOADED.txt") if File.exist?("ACCESSIBILITY_NOT_LOADED.txt")
      rescue Exception
      end
      all = Dir[File.join(DIR, "*.rb")].sort
      core   = all.select { |f| File.basename(f).start_with?("Accessibility") }
      extras = all - core
      if all.empty?
        log(["patch/Mods exists but holds no .rb files."])
        return
      end
      core.each   { |f| load_one(f, lines) }
      lines << "" unless extras.empty?
      extras.each { |f| load_one(f, lines) }
      lines << ""
      lines << "#{@loaded.length} loaded, #{@failed.length} failed."
      log(lines)
    rescue Exception
      nil
    end
  end
end

A11yPatchMods.run

# Push the stored settings into the mods that keep their own state, now that
# every mod exists. See WHAT IT DOES above for why this cannot happen earlier.
A11ySettings.apply_all if defined?(A11ySettings)
