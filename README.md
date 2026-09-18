# Pokémon Desolation Accessibility Pack

Screen-reader accessibility mods for [Pokémon Desolation](https://desolation.fandom.com/), a fan game built on Pokémon Essentials. With this pack installed, a blind player can play the game start to finish with **NVDA**: every menu, battle, quest, item and Pokémon speaks, footsteps tell you what you are walking on, and a 3D audio beacon guides you to doors, people and items.

Thirteen mods, all loaded from a `patch` folder that never touches the game's own files. **This pack contains no game files** — you need your own copy of Pokémon Desolation.

## Requirements

- **Pokémon Desolation**, installed and able to start. Built and tested on version **6.0.13**; nearby versions should work.
- **NVDA** running. All speech goes through NVDA.
- Windows.

## Installation

1. Download the pack: go to the [latest release](https://github.com/mohammedtahadev/pokemon-desolation-accessibility/releases/latest) and download the `Pokemon-Desolation-Accessibility` zip, then extract it. (Downloading the repository itself with the Code button works too.)
2. Open your Pokémon Desolation game folder — the folder that contains `Game.exe`.
3. Copy these two folders from the extracted download into the game folder, merging when Windows asks:
   - `Data` — contains one file, the bootstrap loader.
   - `patch` — everything else: the mods, the beacon's audio engine, the sounds, the biology database.
4. Start NVDA if it is not running, then start the game. You should hear **"Accessibility speech enabled"** almost immediately. If you hear that, you are done.

If the game stays silent, look in the game folder for a file called `ACCESSIBILITY_NOT_LOADED.txt` — if it exists, the `patch` folder did not get copied, and the file says exactly what to do.

To **uninstall**: delete `Data\Mods\AccessibilityLoader.rb` and the `patch\Mods` folder. The game itself was never modified.

## What speaks

- **Every menu and screen** — the pause menu, options, shops, the party, the PC, dialogue with speaker names, choices.
- **Battles** — every message, the command and fight menus, targeting in doubles, exact damage after every hit, and inspect keys for both sides of the field.
- **The Accessible Summary** — a fully spoken summary of any Pokémon: stats with IVs and EVs, base stats, abilities, moves with descriptions, biology, and a team export. Ported from Lorenzo's Reborn mod (see credits).
- **The bag** — pockets announce themselves, every item reads its description, and a TM tells you who in your party can learn it.
- **The quest log** — tabs, full quest pages that never spoil unreached objectives, and spoken "Quest added / completed" updates on the map.
- **The Pokédex** — entries read themselves, and a key reads the species' long biology description.
- **The world** — footstep sounds that say what surface you are on, a where-am-I key, an event scanner that finds doors, people and items, pathfinding that walks you to them, and a Steam Audio 3D beacon that pauses itself during battles.

## The most important keys

| Key | What it does |
| --- | --- |
| F1 | Repeat the last thing spoken |
| F2 | Speech on or off |
| V | Where am I: map name, coordinates, surface underfoot |
| J and L | Select the previous or next thing on the map (doors, people, items); K says it again; P walks you to it |
| Shift+B | 3D sound beacon guiding you to the selected thing; press again to stop |
| K | On the party screen or in the PC: the Accessible Summary of that Pokémon — also the last entry of its action menu, after Cancel |
| N | In the bag: the item's description. In a Pokédex entry: the species' biology |
| K (in battle) | Quick status of every Pokémon on the field |
| Shift+K (in battle) | Weather, field effect, screens and hazards |
| Q / W (in battle) | Your side / the enemy side in full: types, stat changes, ability, item, moves with exact PP |
| Z (fight menu) | The focused move's full description |

The full key list, every feature in detail, and the design notes are in [MANUAL.txt](MANUAL.txt) — written to be read top to bottom with a screen reader.

All the accessibility switches live at the **end of the game's own Options menu**.

## If something goes wrong

Logs in the game folder say more than a description can:

- `ACCESSIBILITY_NOT_LOADED.txt` — only exists if the `patch` folder is missing.
- `patch\Mods\load_log.txt` — which mods loaded, which failed, and why. A broken mod is skipped and named here instead of crashing the game.
- `beacon_error.txt` — why the 3D beacon did or did not start.

If the game crashes with an error window, the text of that window is the single most useful thing to put in an issue report.

## For developers

- The mods are in `patch/Mods`, one feature per file, heavily commented. The one file outside `patch` is `Data/Mods/AccessibilityLoader.rb`, because Desolation's engine only loads mods from `Data/Mods` — that bootstrap is what teaches it to load the patch folder, each mod crash-isolated.
- `accessibility_tests/` holds twelve standalone test harnesses, over 600 checks total, runnable with plain Ruby and no game: `ruby test_summary.rb ../patch/Mods/AccessibilitySummary.rb` and so on. Run all of them after any edit.
- `tools/` holds helper scripts, including `build_biology.rb`, which regenerates `patch/biology.dat` from Lorenzo's `pokemon_biology.json`.
- Landmines worth knowing before editing are documented in MANUAL.txt — among them: Desolation's stat arrays put **Speed last**, not third as standard Essentials does, and the game's embedded Ruby ships **no standard library**.

## Credits

This project would not exist without **Lorenzo ([fclorenzo](https://github.com/fclorenzo))** and his [pkreborn-access](https://github.com/fclorenzo/pkreborn-access) project for Pokémon Reborn. Three pillars of this pack are ports or direct adaptations of his work:

- **The Accessible Summary** — modeled on his pra-accessible-summary mod, including its menu structure, the stats/IV/EV details view, the base stat view, and the team export.
- **Pathfinding and auto-walk** — his event scanner, pathfinder and auto-walk, ported to Desolation's maps.
- **The biology database** — the Pokémon biology descriptions (1,020 species) come from his `pokemon_biology.json`, shipped here pre-converted.

Also thanks to the **Pokémon Reborn team**, whose built-in Blindstep accessibility support was the model for the battle speech, the inspect keys, and several other features, and to the **Pokémon Desolation team** for the game itself.

The 3D beacon is built on [Steam Audio](https://valvesoftware.github.io/steam-audio/) by Valve and [miniaudio](https://miniaud.io/). Speech reaches the screen reader through the NVDA controller client library (`patch\nvdaControllerClient.dll`) by [NV Access](https://www.nvaccess.org/), distributed under the GNU LGPL.

This is a fan-made accessibility project. It is not affiliated with the Pokémon Desolation team, Nintendo, Game Freak or The Pokémon Company. No copyrighted game assets are included.
