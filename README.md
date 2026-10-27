# Lastlight Colony

A hard sci-fi colony builder in Godot 4.5+. A handful of survivors crash-land on Lastlight, a rust-red moon under a ringed gas giant, and build a colony from what the alien land gives them. The gameplay is a Foundation-style organic builder (painted areas, walking workers, roads that wear in by use); the art is generated with code in Blender, the gameplay is written in GDScript.

This project started as a reskin of [cozy-village-builder](https://github.com/richardlee8433/cozy-village-builder): same core gameplay, new setting.

## Run
Open Godot, choose **Import**, and select `project.godot`. Wait for the first asset import to finish, then press **F5**.

## Controls
| Action | Input |
|---|---|
| Habitat zones | Click "Habitat zone" in the bottom menu (or press `4`), then left-drag to paint a zone |
| Harvest areas | Place a fibre harvester (`1`); a starter area is painted over the nearest alien flora and the brush opens. Later: select the harvester → "Edit harvest area" |
| Crop fields | Place an agri station (`2`); a starter field is painted and the field brush opens. Left-drag to grow it (within 10 m of the station) |
| Erasing areas | In any brush: toggle "Erase" or press `X`, or hold `Shift` while dragging. "Clear" wipes the whole area. "Done", right-click or `Esc` ends the brush |
| Build | Bottom menu or `1`–`5`. Free placement at any angle. Left-click to place; `R` / `Shift+R` or `Shift` + wheel rotates; right-click or `Esc` cancels |
| Select / demolish | Left-click a building, then use the side panel or press `Delete` |
| Camera | Right-drag or `Q`/`E` to rotate, `WASD` or middle-drag to pan, wheel or pinch to zoom |
| Speed | Pause / 1x / 2x / 4x in the top-right corner |
| Language | English by default; "中文" / "English" in the top-right switches (remembered in `user://settings.cfg`) |

## Setting
- **The world**: barren rust regolith with lichen only in scattered patches, basalt boulders, glowing cyan and violet crystal clusters, and alien flora (`tools/flora.py`, `scripts/world/alien_flora.gdshader`): umbrella fungi with glowing spore bulbs, tube clusters, frond stalks, twisted spires and disc stacks. A thin, dark sky with daytime stars, thin sun-lit cloud streaks, a small cratered moon and a banded, ringed gas giant over the dusty horizon (`scripts/world/alien_sky.gdshader`). Beyond the colony the land rises into dunes, terraced mesas with dark caprock and striped strata, and a far mountain range (`scripts/world/backdrop.gd`). Loose stones and half-buried boulders lie everywhere (`scripts/world/rock.gdshader`).
- **Opening**: three survivors stand by their **crashed escape pod** — scorched crater, parachute, supply cases, an antenna mast with a blinking beacon, a solar array, and a portable heater with four thermal blankets. The pod is temporary storage (Fibre 60, Ore 20, Food 40) and sleeps 4; it can't be demolished.
- **Colonists**: everyone wears a pressure suit — white, pale grey or survey orange with crew-colour trims, gloves, boots, a life-support pack and a helmet with a glass visor (some carry a comm antenna). Job gear: gold sun visor + cutter (harvester), sun-shade peak + soil probe (agronomist), helmet lamps + drill (miner). The colonists are modelled with adult proportions in an EVA-style suit (hard upper torso, joint bearings, chest display, PLSS backpack, EVA boots) — `tools/colonist.py`.

## Day and night
One sol (a full day-night cycle) lasts four in-game days (`scripts/world/day_night.gd`). The sun crosses the sky, turns warm and long-shadowed at dawn and dusk, and gives way to faint blue moonlight; the sky darkens and the stars come out. At night the colony lights up: windows glow warm, lamp posts and floodlights come on, the depot hangar is lit from inside and the greenhouses glow with pink grow lights. Baked models keep their glowing parts as `glow_*` surfaces (`finish_glow()` in `tools/scifi.py`); shaders read the global uniform `night`.

## Gameplay
- **Resources**: fibre, ore, food. **Resources only count once a colonist carries them into storage.** After each work session the worker carries one load (fibre bale, ore chunk, food case) to the **nearest storage**, so distance matters. The resource bar shows yesterday's deliveries.
- **Fibre harvester**: a prefab workshop plus a painted harvest area. Grown alien plants inside the area are cut (3 trips each), leave a stump, regrow in a few days, and new shoots sprout in empty spots. Plants outside areas are scenery.
- **Agri station**: a greenhouse tunnel plus a painted crop field of engineered grain, growing from tilled regolith to ripe (~1.25 days) and harvested over 5 trips. Food per trip grows with field size.
- **Mining rig**: built on one of six ore deposits (basalt outcrops with copper-green veins). A drill derrick works the rock; the miner hauls ore to storage.
- **The lake and the stream**: cold water with pale alien reeds, float pads and gas bubbling up from the bed. Nothing in it is edible, so there is no fishing; idle colonists sometimes walk down to the bank and look at it.
- **Supply depot**: a quonset storage hangar; build one near production to shorten hauling.
- **Habitat zones**: habs aren't placed by hand. Paint zones, and when beds run low, food suffices and fibre and ore cover the cost, colonists assemble a **hab** (+4 beds) in the best spot: cylinder modules on cradles or regolith-bermed domes, six variants.
- **Construction**: every building goes up in two stages — a staked pad with survey tripod and panel bundles, then a steel frame with a jib crane — before it is finished. Cancelling refunds everything.
- **Roads**: none to build. Where colonists walk often the lichen wears away into paths; unused paths grow back.
- **Colony life**: weather masts, hydroponic planters, gas cylinders, cargo cases and fibre bales appear around finished buildings (`scripts/world/clutter.gd`).
- **Population**: each colonist eats 1 food per day (a day is 30 s). With free beds and enough food a new colonist arrives each day. When food runs out only agronomists keep working.
- **Quests** guide the first hour; the game autosaves every in-game day (`user://save.json`).

All balance values are in `scripts/game/defs.gd`. Internally the resources are still keyed `wood` / `stone` / `food` and the building types `woodcutter` / `farm` / `quarry` / `house` / `storehouse` / `cart`, so saves and tests carry over (aqua harvesters from old saves are dropped on load).

## Languages
The code is written in English; `Loc.t("...")` looks up Traditional Chinese in `scripts/game/loc.gd`. The UI font is Noto Sans TC (SIL OFL, `fonts/OFL.txt`) cut down to the characters the game uses. After adding Chinese text: `python3 tools/subset_font.py <NotoSansTC[wght].ttf>`. `tests/test_i18n.gd` fails if a string has no translation or a glyph is missing.

## Tests
```
godot --headless --path . --script res://tests/test_gameplay.gd     # economy, quests, saving
godot --headless --path . --script res://tests/test_villagers.gd    # pathfinding, jobs, paths, arrivals and departures
godot --headless --path . --script res://tests/test_zones.gd        # habitat zones and auto-built habs
godot --headless --path . --script res://tests/test_i18n.gd         # translations, font coverage, language switching
godot --headless --path . --script res://tests/test_water.gd        # stream, lake, bridges, lake life, bank spots
godot --headless --path . --script res://tests/test_clutter.gd      # props around buildings
godot --headless --path . --script res://tests/test_construction.gd # construction sites and stages
godot --headless --path . --script res://tests/test_deposits.gd     # ore deposits and mining rigs
godot --headless --path . --script res://tests/test_forest.gd       # harvest areas, cutting, regrowth
godot --headless --path . --script res://tests/test_fields.gd       # crop fields
```
Screenshot scripts (`tests/shot_*.gd`) need a display; headless servers can use lavapipe:
`VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a godot --path . --rendering-driver vulkan --rendering-method forward_plus --script res://tests/shot_horizon.gd`

## Regenerating the art (requires `pip install bpy`)
```
python3 tools/scifi.py models                 # crashed escape pod camp
python3 tools/scifi_buildings.py models       # habs (models/houses/), depot, harvester, agri station, mining rig,
                                              # construction stages, ore deposits, truss bridge
python3 tools/scifi_props.py models           # colony props → models/props/
python3 tools/crystals.py models              # crystal clusters
python3 tools/colonist.py models              # colonist in a pressure suit → models/villager.glb (add "preview")
python3 tools/flora.py models                 # alien flora → models/trees/ (add "preview" for preview images)
```
Add `preview` to the Blender scripts to render a preview image of each model. Buildings, the pod and props get a weathering layer before baking (`weather()` in `tools/scifi.py`): dust settling low and on upward faces, rust streaks running down, scratched bright edges, grime in the creases.
