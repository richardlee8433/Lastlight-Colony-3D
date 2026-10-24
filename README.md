# Cozy Village Builder

A small cozy village-building game in Godot 4.5+. The art is generated with code in Blender, and the gameplay is written in GDScript.

## Run
Open Godot, choose **Import**, and select `project.godot`. Wait for the first asset import to finish, then press **F5**.

## Controls
| Action | Input |
|---|---|
| Residential zones | Click "住宅區" in the bottom menu (or press `4`), then left-drag to paint a zone |
| Forest areas | Place a woodcutter (`1`); a starter area is painted over the nearest trees and the forest brush opens. Later: select the lodge → "Edit forest area" |
| Farm fields | Place a farmhouse ("農舍", `2`); a starter field is painted and the field brush opens. Left-drag to grow the field (within 10 m of the farmhouse). Later: select the farmhouse → "編輯田地" |
| Erasing areas | In either brush: toggle "擦除" in the brush toolbar or press `X`, or hold `Shift` while dragging. "清空田地" / "全部清除" wipes the whole field / all zones (built houses stay). "完成", right-click or `Esc` ends the brush |
| Build | Click a button in the bottom menu, or press `1`–`6`. Buildings can be placed anywhere at any angle (no grid). Left-click to place; `R` / `Shift+R` or `Shift` + mouse wheel rotates in 15° steps; right-click or `Esc` cancels |
| Select / demolish | Left-click a building, then use the side panel or press `Delete` |
| Camera | Right-drag to rotate, `Q`/`E` to rotate, `WASD` or middle-drag to pan, mouse wheel or pinch to zoom |
| Speed | Pause / 1x / 2x / 4x buttons in the top-right corner |
| Language | English by default; the "中文" / "English" button in the top-right switches (remembered in `user://settings.cfg`) |

## Gameplay (MVP)
- **Opening**: the map starts as open meadow. Three settlers walk in from the south road to the **supply cart**. The cart is the temporary storage (holding the starting wood 60, stone 20, food 40), and the campfire beside it has 4 sleeping spots. The cart can't be demolished. Saves from before this change get a supply cart automatically.
- **Resources**: wood, stone, food. **Resources only count once a villager carries them into a storage.** After each work session the worker carries one load (woodcutter 8 wood, farm 5 food, quarry 6 stone) to the **nearest storage**, so the farther the trip, the less gets produced. The resource bar shows how much was brought into storage yesterday.
- **Map**: 68 x 68 m with groves, single trees, rocks and bushes; a border forest surrounds it (instanced from the tree models, positions in `world.json`). Grass and flowers are grown by the game in 8 m chunks, nearest the camera first, so the bigger map starts quickly; the meadow colour of the ground covers the distance.
- **Trees and light**: crowns are made of textured leaf cards (broadleaf clusters, drooping pine tiers) with crown-shaped normals, sway in the wind and get a slight colour variation per tree (`scripts/world/foliage.gdshader`). Warmer sun, aerial haze and colour grading in `main.tscn`.
- **Lived-in props**: finished buildings get props around them — gardens, fences, laundry lines, firewood, flower boxes and benches at houses; crates, barrels and sacks at the storehouse; hay bales at farms (`scripts/world/clutter.gd`, models from `tools/props.py`). Spots on paths, doorsteps, fields or other buildings are skipped; larger props block walking; a new building clears props in its way.
- **Water**: a stream crosses the east side of the map and a pond lies south-west of the village (`Defs.WATER`, `scripts/world/water.gd`). The same carve profile lowers the ground mesh (shader) and the walk-grid heights; water blocks walking, two wooden footbridges cross the stream (the east road uses one). The water shader traces its own screen-space reflections (trees, houses and bridges show in the water, the sky where nothing is hit), colours by depth, refracts the bed, sparkles with sun glints and foams wherever something breaks the surface — the banks and the stones in the stream — streaked along the flow. No trees, grass, buildings or zones in the water.
- **Villagers' looks**: each villager gets a look — 7 hairstyles (short, bun, braids, long, ponytail, curls, balding), beards or moustaches, tunic or long skirt, apron / vest / satchel, a kerchief, trims in a matching colour, grey hair for some elders, a slightly different height and build. Faces have brows, cheeks and a smile; eyes blink. Clothes share a soft woven texture.
- **Fishing huts** (`6`): built on the shore of the pond or the stream — the ghost snaps to the nearest water and turns to face it, the jetty reaches out over the water. The fisher casts from a spot on the bank and carries fish home. Each water body (the pond, stretches of the stream) has a fish stock: every catch uses some up, catches shrink as it drops, below 20 % the fisher waits, and the fish come back over a few days; at most 2 huts per water body (`Defs.FISHING`, `scripts/world/fishing.gd`).
- **Pond life**: reeds and cattails along the banks, lily pads with flowers on the pond, fish that jump now and then with a splash, and villagers who sometimes stroll down to the water and look at it for a while.
- **Construction**: a placed building is a construction site. A villager builds it in two visible stages (staked foundation with material piles, then a timber frame with scaffolding) before it is finished; only finished buildings give beds, jobs or storage. Sites get their builders before workplaces, so production can pause while something is built. Cancelling a site refunds everything. Houses grown in zones are built the same way.
- **Roads**: every new building gets a dirt path from its door to the nearest road (or the village centre); after that, paths grow and fade with use.
- **Stone deposits**: six rock outcrops on the map (four 13–19 m from the village, two further out). A quarry can only be built on a free deposit (one quarry each): while placing one, the deposits get a glowing ring and the quarry snaps onto the nearest; any rotation works. The mason works the rock face and hauls stone to the nearest storage, so a storehouse next to the quarry pays off.
- **Woodcutters (Foundation-style)**: a woodcutter's lodge plus a painted forest area. Every tree inside the map is a separate model; only trees inside an area are felled. A grown tree gives 3 trips of wood, falls and leaves a stump; the stump sprouts after a day and grows back in about three days, and empty spots in the area fill with saplings (up to one tree per 5 m²). Trees outside areas are scenery and are never cut. While painting, trees inside the area are tinted green.
- **Farms (Foundation-style)**: a farm is a farmhouse plus a field you paint. The field turns into furrowed soil with wheat rows, grass is cleared, and the farmer works anywhere in it. The wheat grows from freshly tilled soil to young green plants to ripe gold (~1.25 days); a ripe field is harvested over 5 trips (rows disappear as they are cut) and then tilled again. Food per harvest trip = field size / 3 m² (min 2 m² to produce, max 8 food at 24 m²). Fields can't overlap other fields, zones, buildings or trees; nothing can be built on a field.
- **Buildings**: woodcutter, farmhouse, quarry, storehouse (a delivery point: build one near your production to cut down hauling)
- **Residential zones**: houses are not placed by hand. The player paints residential zones, and when free beds run out (at most 1 left), food is sufficient, and wood and stone can cover the cost, villagers build a house (+4 population cap) on their own in the best open spot within the zone. Houses line up with their neighbors to form rows, with the front door facing the nearest path (or the village center). The zone shows on the ground as a light yellow outline.
- **House variants**: 6 baked houses (golden / weathered / mossy thatch, different wall colors, chimneys, windows, side sheds, and flower boxes). Each one gets a slight random size adjustment.
- **Villagers**: every producing building needs one worker. Each villager eats 1 food per day (one day = 30 seconds of game time). When there is free housing and enough food, one new villager arrives each day. When food runs out, only farmers keep working, so the village can recover on its own.
- **Quests**: 8 quests that guide the player step by step, each with a reward
- **Autosave**: the game saves at the end of every in-game day and when the window closes (`user://save.json`)

- **Villagers**: every villager is a little figure on the map. Workers walk to their workplace, work (chopping trees, quarrying, hoeing the fields), carry what they produce to the storage at the starting cottage, and go home every few trips to rest. Unemployed villagers wander around the village. New villagers walk in along the roads, and villagers who lose their housing walk away.
- **Organic roads**: there are no roads to build. Wherever villagers walk often, the grass is gradually worn away and a dirt path appears. Villagers prefer to walk on paths, so frequently used routes become main roads, and paths that are no longer used slowly grow back into grass. Paths are saved along with the game.

## Languages
The code is written in English; `Loc.t("...")` looks up the Traditional Chinese text in `scripts/game/loc.gd` (building, resource and quest names in `defs.gd` are translated where they are shown). The UI font is Noto Sans TC (SIL OFL, `fonts/OFL.txt`) cut down to the characters the game uses, so text renders the same on every platform, including web builds. After adding Chinese text, rebuild the font: `python3 tools/subset_font.py <NotoSansTC[wght].ttf>`. `tests/test_i18n.gd` fails if a string has no translation or a glyph is missing.

All balance values (costs, output, day length, quests, villager speed, how fast paths wear and fade) are in `scripts/game/defs.gd`.

## Project layout
```
scripts/game/defs.gd             game data and balance values
scripts/game/game_state.gd       simulation core (autoload: Game) — resources (added via deliveries), population, quests, saving (v2; old grid saves are converted automatically)
scripts/game/build_controller.gd free placement (overlap / obstacle / no-build-zone checks), placement preview, rotation, selection, delivery popups
scripts/game/building_visuals.gd building models (temporary placeholders; the house uses the baked cottage)
scripts/ui/hud.gd                all UI (rebuilt when the language changes)
scripts/game/loc.gd              English -> Traditional Chinese table, language setting
scripts/world/nav_grid.gd        walkable grid (0.5 m) + A* pathfinding; buildings block cells, worn paths lower the cost
scripts/world/deposits.gd        stone deposits: outcrop models, quarry placement queries, highlight rings
scripts/world/forest.gd          trees in the map (growth, felling, stumps, saplings) and woodcutter forest areas
scripts/world/fields.gd          farm fields: painted cells per farmhouse, soil/wheat visuals, yield per trip
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
godot --headless --path . --script res://tests/test_i18n.gd       # every UI string translated, font covers all glyphs, runtime switching
godot --headless --path . --script res://tests/test_fishing.gd     # fishing huts: shore placement, catches, fish stocks, pond life
godot --headless --path . --script res://tests/test_water.gd       # stream, pond, bridges: blocking, carving, crossing
godot --headless --path . --script res://tests/test_clutter.gd     # props around buildings: placement rules, blocking, removal
godot --headless --path . --script res://tests/test_construction.gd # construction sites, builders, stages, refunds, saving, auto paths
godot --headless --path . --script res://tests/test_deposits.gd   # stone deposits: quarry placement rules, snapping, mason at work
godot --headless --path . --script res://tests/test_forest.gd     # forest areas: felling, stumps, regrowth, saplings, saving
godot --headless --path . --script res://tests/test_fields.gd     # farm fields: starter field, painting rules, erase / clear, yield, saving
godot --headless --path . --script res://tests/sim_balance.gd     # follow a fixed build order for 30 days and print each day's economy (for checking balance)
godot --path . --script res://tests/shot_village.gd -- 6          # render a screenshot after 6 minutes of time-lapse (needs a display)
godot --path . --script res://tests/shot_opening.gd               # render the opening screenshots (needs a display)
godot --path . --script res://tests/shot_ui.gd                    # render the UI in English and Chinese (needs a display)
godot --path . --script res://tests/shot_stages.gd                # render construction stages and wheat stages (needs a display)
godot --path . --script res://tests/shot_quarry.gd                # render deposits while placing, then a working quarry (needs a display)
godot --path . --script res://tests/shot_forest.gd                # render a woodcutter with its forest area (needs a display)
godot --path . --script res://tests/shot_fields.gd                # render a farmhouse + painted field (needs a display)
```

Screenshots render with the software Vulkan driver (lavapipe) in Forward+, like the game on a desktop:
`VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a godot --path . --rendering-driver vulkan --rendering-method forward_plus --script res://tests/shot_water.gd`

## Regenerating the art (requires `pip install bpy`)
```
python3 tools/bake_export.py <output folder> empty   # build the 68 m map (empty meadow), bake ground + scenery (add nature_only for scenery only)
python3 tools/repack_glb.py <output folder>/models/*.glb   # convert embedded textures to JPEG to shrink files
python3 tools/export_world_data.py data/world.json empty   # walkable grid, ground heights, map trees, border forest
python3 tools/villager.py models                           # villager model (add "preview" to also render a preview image)
python3 tools/house_variants.py models 6 preview           # 6 house variants → models/houses/
python3 tools/farmhouse.py models                          # farmhouse → models/farmhouse.glb
python3 tools/buildings.py models                          # woodcutter's lodge, storehouse, quarry, stone deposits, construction stages, bridge, fishing hut → models/*.glb
python3 tools/props.py models                              # lived-in props (crates, fences, laundry...) → models/props/
python3 tools/leaf_textures.py models/trees                 # leaf / needle textures for the tree crowns
python3 tools/trees.py models                              # leaf-card tree variants (add "stumps" to rebuild stumps) → models/trees/
python3 tools/bake_export.py <output folder> empty nature_only   # only re-export nature.glb (rocks and bushes; trees are drawn by the game)
```
