# Cozy Village Builder

A small cozy village-building game in Godot 4.5+. The art is generated with code in Blender, and the gameplay is written in GDScript.

## Run
Open Godot, choose **Import**, and select `project.godot`. Wait for the first asset import to finish, then press **F5**.

## Controls
| Action | Input |
|---|---|
| Residential zones | Click "住宅區" in the bottom menu (or press `4`), then left-drag to paint a zone; hold `Shift` and drag to erase |
| Build | Click a button in the bottom menu, or press `1`–`5`. Buildings can be placed anywhere at any angle (no grid). Left-click to place; `R` / `Shift+R` or `Shift` + mouse wheel rotates in 15° steps; right-click or `Esc` cancels |
| Select / demolish | Left-click a building, then use the side panel or press `Delete` |
| Camera | Right-drag to rotate, `Q`/`E` to rotate, `WASD` or middle-drag to pan, mouse wheel or pinch to zoom |
| Speed | Pause / 1x / 2x / 4x buttons in the top-right corner |

## Gameplay (MVP)
- **Resources**: wood, stone, food. **Resources only count once a villager carries them into a storage.** After each work session the worker carries one load (woodcutter 8 wood, farm 5 food, quarry 6 stone) to the **nearest storage**, so the farther the trip, the less gets produced. The resource bar shows how much was brought into storage yesterday.
- **Buildings**: woodcutter, farm (wheat field), quarry, storehouse (a delivery point: build one near your production to cut down hauling)
- **Residential zones**: houses are not placed by hand. The player paints residential zones, and when free beds run out (at most 1 left), food is sufficient, and wood and stone can cover the cost, villagers build a house (+4 population cap) on their own in the best open spot within the zone. Houses line up with their neighbors to form rows, with the front door facing the nearest path (or the village center). The zone shows on the ground as a light yellow outline.
- **House variants**: 6 baked houses (golden / weathered / mossy thatch, different wall colors, chimneys, windows, side sheds, and flower boxes). Each one gets a slight random size adjustment.
- **Villagers**: every producing building needs one worker. Each villager eats 1 food per day (one day = 30 seconds of game time). When there is free housing and enough food, one new villager arrives each day. When food runs out, only farmers keep working, so the village can recover on its own.
- **Quests**: 8 quests that guide the player step by step, each with a reward
- **Autosave**: the game saves at the end of every in-game day and when the window closes (`user://save.json`)

- **Villagers**: every villager is a little figure on the map. Workers walk to their workplace, work (chopping trees, quarrying, hoeing the fields), carry what they produce to the storage at the starting cottage, and go home every few trips to rest. Unemployed villagers wander around the village. New villagers walk in along the roads, and villagers who lose their housing walk away.
- **Organic roads**: there are no roads to build. Wherever villagers walk often, the grass is gradually worn away and a dirt path appears. Villagers prefer to walk on paths, so frequently used routes become main roads, and paths that are no longer used slowly grow back into grass. Paths are saved along with the game.

All balance values (costs, output, day length, quests, villager speed, how fast paths wear and fade) are in `scripts/game/defs.gd`.

## Project layout
```
scripts/game/defs.gd             game data and balance values
scripts/game/game_state.gd       simulation core (autoload: Game) — resources (added via deliveries), population, quests, saving (v2; old grid saves are converted automatically)
scripts/game/build_controller.gd free placement (overlap / obstacle / no-build-zone checks), placement preview, rotation, selection, delivery popups
scripts/game/building_visuals.gd building models (temporary placeholders; the house uses the baked cottage)
scripts/ui/hud.gd                all UI
scripts/world/nav_grid.gd        walkable grid (0.5 m) + A* pathfinding; buildings block cells, worn paths lower the cost
scripts/world/path_wear.gd       wear map, path decay, trampled grass, path saving
scripts/world/ground_path.gdshader  ground shader (grass ↔ dirt paths)
scripts/world/villager.gd        villager: model, state machine (work / carry / rest / wander / arrive / leave), procedural animation
scripts/world/villager_manager.gd  syncs villagers with population, assigns homes and jobs
scripts/world/zones.gd           residential zones: brush, overlay, automatic house building (spot choice, alignment, door direction)
scripts/world/meadow.gd          grassland zones (lush / normal / dry), shared by the ground and grass tufts
scripts/game/wheat.gd            procedural wheat + wind shader
scripts/scatter.gd               grass and flowers (MultiMesh)
models/  data/                   models baked from Blender (including villager.glb), grass placement, world.json (walkable cells / heights / tree positions)
tools/                           Blender generation and baking scripts
tests/test_gameplay.gd           automated tests
```

## Tests
```
godot --headless --path . --script res://tests/test_gameplay.gd    # economy, quests, saving
godot --headless --path . --script res://tests/test_villagers.gd   # pathfinding, jobs, paths, moving in and out
godot --headless --path . --script res://tests/test_zones.gd      # residential zones: painting, erasing, auto-built houses, saving
godot --headless --path . --script res://tests/sim_balance.gd     # follow a fixed build order for 30 days and print each day's economy (for checking balance)
godot --path . --script res://tests/shot_village.gd -- 6          # render a screenshot after 6 minutes of time-lapse (needs a display)
```

## Regenerating the art (requires `pip install bpy`)
```
python3 tools/bake_export.py <output folder>     # build scene → bake textures → export GLB + scatter.json
python3 tools/repack_glb.py <output folder>/models/*.glb   # convert embedded textures to JPEG to shrink files
python3 tools/export_world_data.py data/world.json         # walkable grid, ground heights, tree positions
python3 tools/villager.py models                           # villager model (add "preview" to also render a preview image)
python3 tools/house_variants.py models 6 preview           # 6 house variants → models/houses/
```
