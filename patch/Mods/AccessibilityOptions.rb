# =============================================================================
# AccessibilityOptions.rb - puts the accessibility settings in the game's own
# Options screen, where they belong.
#
# Everything the mods do that you might reasonably want to turn off is here:
#
#   Speech               the screen reader output itself
#   Speaker Names        saying who is talking before their line
#   Event Names          working out names for EV027-style events
#   Tile Sounds          footsteps that tell you what you are walking on
#   Tile Sound Volume    how loud those are
#   Directional Beacon   whether Shift+B does anything
#   Spoken Directions    whether the beacon also says left / right / up / down
#   Battle Speech        battle messages, menus, moves, targets
#   Spoken Damage        exact damage numbers after every hit
#
# They sit at the end of the list, after the game's own settings, and the menus
# mod reads them out like any other option.
#
# HOW THEY ARE STORED
# -------------------
# In ONE new field on $Settings - a Hash, not six separate ivars - which keeps
# the footprint to a single ivar and makes an old Settings.dat simply come back
# with nothing there, falling through to the defaults below.
#
# $Settings lives in Settings.dat, which is SEPARATE from your save games. If it
# ever went bad the game deletes it and rebuilds (ClientData.rb:44), losing your
# options and nothing else. That is why adding to it is safe in a way that
# adding to the save file would not be.
#
# The game's own pbEndScene applies every option when you leave the screen but
# never writes them to disk, so these save themselves when they change.
#
# ADDING TO OptionList IS THE GAME'S OWN IDIOM: Options.rb:419 pushes the Unreal
# Time options on at runtime in exactly this way, guarded against double-adding.
# =============================================================================

module A11ySettings
  ON  = 0
  OFF = 1

  DEFAULTS = {
    :speech        => ON,
    :speaker_names => ON,
    :event_names   => ON,
    :tile_sounds   => ON,
    :step_volume   => 70,     # what STEP_VOLUME was before this existed
    :beacon        => ON,
    # 0 = only when Steam Audio could not start, 1 = always, 2 = never.
    # Not an On/Off, because "speak as well as the 3D sound" and "speak only
    # when there is no 3D sound" are genuinely different things to want.
    :spoken_directions => 0,
    :battle_speech => ON,
    :spoken_damage => ON
  }

  class << self
    def store
      return nil unless defined?($Settings) && $Settings
      unless $Settings.respond_to?(:a11y)
        return nil
      end
      $Settings.a11y = {} if $Settings.a11y.nil?
      $Settings.a11y
    rescue Exception
      nil
    end

    def get(key)
      s = store
      return DEFAULTS[key] if s.nil?
      v = s[key]
      v.nil? ? DEFAULTS[key] : v
    rescue Exception
      DEFAULTS[key]
    end

    def set(key, value)
      s = store
      return if s.nil?
      return if s[key] == value
      s[key] = value
      apply(key, value)
      saveSettings if defined?(saveSettings)
    rescue Exception
      nil
    end

    # 0 is On for every enum here, matching the option lists below.
    def on?(key)
      get(key) == ON
    end

    def step_volume
      v = get(:step_volume).to_i
      v < 0 ? 0 : (v > 100 ? 100 : v)
    end

    # Settings that another mod holds as its own state need pushing across.
    def apply(key, value)
      case key
      when :speech
        if defined?(AccessibilitySpeech)
          AccessibilitySpeech.enabled = (value == ON)
        end
      end
    rescue Exception
      nil
    end

    # Called once at load so a stored setting takes effect before you touch
    # anything.
    def apply_all
      DEFAULTS.each_key { |k| apply(k, get(k)) }
    rescue Exception
      nil
    end
  end
end

# One extra field. An old Settings.dat has no @a11y, so it reads back nil and
# every setting falls through to its default.
class PokemonOptions
  attr_accessor :a11y
end

# ---------------------------------------------------------------------------
# The options themselves.
# ---------------------------------------------------------------------------
if defined?(PokemonOptionScene) && defined?(EnumOption) && defined?(NumberOption)
  begin
    list = PokemonOptionScene::OptionList

    on_off = proc do |title, key, help|
      EnumOption.new(_INTL(title), [_INTL("On"), _INTL("Off")],
        proc { A11ySettings.get(key) },
        proc { |value| A11ySettings.set(key, value) },
        help)
    end

    to_add = []
    to_add << on_off.call("Speech", :speech,
      "Reads menus, dialogue and the world out loud. F2 toggles this too.")
    to_add << on_off.call("Speaker Names", :speaker_names,
      "Says who is talking before their line, when the writing does not.")
    to_add << on_off.call("Event Names", :event_names,
      "Works out a real name for things the game left called EV027.")
    to_add << on_off.call("Tile Sounds", :tile_sounds,
      "Footsteps that tell you what you are walking on.")
    to_add << NumberOption.new(_INTL("Tile Sound Volume"), _INTL("Type %d"), 0, 100,
      proc { A11ySettings.get(:step_volume) },
      proc { |value| A11ySettings.set(:step_volume, value) },
      "How loud the footsteps are, on top of the game's SE volume.")
    to_add << on_off.call("Directional Beacon", :beacon,
      "Lets Shift+B guide you to the selected target with a 3D sound.")
    to_add << on_off.call("Battle Speech", :battle_speech,
      "Reads battle messages, menus, moves and targets out loud.")
    to_add << on_off.call("Spoken Damage", :spoken_damage,
      "Says exact damage dealt and remaining HP after every hit.")
    to_add << EnumOption.new(_INTL("Spoken Directions"),
      [_INTL("If no 3D sound"), _INTL("Always"), _INTL("Never")],
      proc { A11ySettings.get(:spoken_directions) },
      proc { |value| A11ySettings.set(:spoken_directions, value) },
      "Whether the beacon also says left, right, up or down as you follow it.")

    # Same guard the game uses for its own runtime additions, so a soft reset
    # does not stack a second copy of every row.
    to_add.each do |opt|
      next if list.any? { |o| o.respond_to?(:name) && o.name == opt.name }
      list.push(opt)
    end
  rescue Exception => e
    if defined?(AccessibilitySpeech)
      AccessibilitySpeech.log("Could not add accessibility options: #{e.class}: #{e.message}")
    end
  end
end

A11ySettings.apply_all
