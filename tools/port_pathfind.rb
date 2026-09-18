# Regenerates Desolation's AccessibilityPathfind.rb from the NEWER Reborn mods
# in E:/Guide. Deterministic: run it again any time the upstream mods change.

SRC  = "E:/Guide/Reborn-19.5.0-windows/patch/Mods"
DEST = "E:/Pokemon Desolation/Pokemon Desolation/patch/Mods/AccessibilityPathfind.rb"

pathfind = File.read(File.join(SRC, "pra-pathfind.rb"))
walk     = File.read(File.join(SRC, "pra-walk.rb"))

changes = []

# --- 1. Guard the alias lines so an F12 soft reset cannot chain an alias onto
#        itself and recurse. Upstream leaves them bare because Reborn's mods are
#        loaded once; Desolation reloads Data/Mods on every soft reset.
def guard_alias(text, new_name, log)
  pattern = /^([ \t]*)alias_method :#{Regexp.escape(new_name)}, :(\w+)[ \t]*$/
  raise "alias #{new_name} not found" unless text =~ pattern
  text.sub(pattern) do
    indent, old = $1, $2
    log << "guarded alias #{new_name}"
    "#{indent}unless method_defined?(:#{new_name})\n" \
    "#{indent}  alias_method :#{new_name}, :#{old}\n" \
    "#{indent}end"
  end
end

pathfind = guard_alias(pathfind, "access_mod_original_update",     changes)
pathfind = guard_alias(pathfind, "access_mod_original_initialize", changes)
pathfind = guard_alias(pathfind, "access_mod_original_main",       changes)
walk     = guard_alias(walk,     "access_mod_walk_original_update", changes)

# --- 2. Guard the constant, same reason (Ruby warns and the value is re-frozen
#        on every reload otherwise).
const_line = 'CUSTOM_NAMES_FILE = "pra-custom-names.txt"'
raise "constant not found" unless pathfind.include?(const_line)
pathfind = pathfind.sub(const_line, const_line + " unless defined?(CUSTOM_NAMES_FILE)")
changes << "guarded CUSTOM_NAMES_FILE"

# --- 3. Self-heal the mod's settings on a loaded save.
#        Desolation restores $game_player straight out of the save file with
#        Marshal (Scripts/Load.rb:679), and Marshal never calls initialize. Any
#        save made before this mod existed therefore comes back with the mod's
#        settings nil, which silently disables auto-refresh and distance
#        sorting for good. Upstream already guards @hm_toggle_modes this way
#        inside cycle_hm_toggle; this extends the same idea to the rest.
anchor = [
  "  def update",
  "    # First, call the original update method",
  "    access_mod_original_update"
].join("\n")
raise "update anchor not found" unless pathfind.include?(anchor)
replacement = [
  "  def update",
  "    # PORT FIX: on Continue, Desolation hands back a Marshal'd Game_Player,",
  "    # so initialize never ran and these are all nil. Restore them once.",
  "    if @hm_toggle_modes.nil?",
  "      @hm_toggle_modes = [:off, :surf_only, :surf_and_waterfall]",
  "      @hm_toggle_index = 0",
  "      @sort_by_distance = true",
  "      @auto_refresh_map_list = true",
  "      @last_map_id = -1",
  "      PraSession.reset!",
  "    end",
  "",
  "    # First, call the original update method",
  "    access_mod_original_update"
].join("\n")
pathfind = pathfind.sub(anchor, replacement)
changes << "added the loaded-save self-heal to Game_Player#update"

# --- 4. Everything else stays byte-identical, including all ~200 tts() call
#        sites. tts() itself does not exist in Desolation, so it is shimmed onto
#        this game's speech engine below.
shim = <<~'RUBY'
  # =============================================================================
  # AccessibilityPathfind.rb
  #
  # A port of the Pokemon Reborn accessibility mods pra-pathfind.rb and
  # pra-walk.rb (github.com/fclorenzo/pkreborn-access), taken from the newer
  # copy in E:/Guide/Reborn-19.5.0-windows/patch/Mods.
  #
  # WHAT WAS CHANGED, AND NOTHING ELSE
  # ----------------------------------
  #   1. tts() is defined below and forwards to this game's speech engine.
  #      Reborn provides tts(); Desolation does not. Every one of the mod's
  #      announcement call sites is therefore left exactly as written upstream.
  #   2. The four alias_method lines and the CUSTOM_NAMES_FILE constant are
  #      wrapped in re-entry guards. Desolation reloads Data/Mods on an F12 soft
  #      reset, and an unguarded alias would chain onto itself and recurse.
  #   3. Game_Player#update restores the mod's own settings if it finds them
  #      nil. Desolation loads a save by handing back a Marshal'd Game_Player
  #      (Scripts/Load.rb:679), and Marshal does not call initialize, so on any
  #      save made before this mod the auto-refresh and distance sorting would
  #      never switch on. Upstream guards @hm_toggle_modes the same way inside
  #      cycle_hm_toggle; this covers the rest of them.
  #
  # No pathfinding, key binding, filter or announcement was altered.
  #
  # Regenerate with tools/port_pathfind.rb after any upstream change.
  # =============================================================================

  # Reborn's speech function. Desolation speaks through AccessibilitySpeech, and
  # this file loads before it alphabetically, so the call is resolved lazily.
  unless defined?(tts)
    def tts(text, interrupt = false)
      return unless defined?(AccessibilitySpeech)
      AccessibilitySpeech.speak(text.to_s, true)
    rescue Exception
      nil
    end
  end

RUBY

out = shim + pathfind + "\n\n" +
      "# =============================================================================\n" \
      "# pra-walk.rb - the auto-walk half. Upstream keeps it in a separate file; it is\n" \
      "# appended here so the alias chain order (walk wraps pathfind wraps the game)\n" \
      "# is fixed rather than depending on load order.\n" \
      "# =============================================================================\n\n" +
      walk + "\n"

File.write(DEST, out)

puts changes.map { |c| "  " + c }
puts
puts "wrote #{DEST}"
puts "  #{out.lines.size} lines, #{out.bytesize} bytes"
