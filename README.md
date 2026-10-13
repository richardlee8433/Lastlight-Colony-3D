# Cozy Village Builder

A small cozy village-building game in Godot 4.5+. The art is generated with code in Blender, and the gameplay is written in GDScript.

## Run
Open Godot, choose **Import**, and select `project.godot`. Wait for the first asset import to finish, then press **F5**.

## Controls
| Action | Input |
|---|---|
| Build | Click a button in the bottom menu, or press `1`–`4`. Left-click to place, `R` to rotate, right-click or `Esc` to cancel |
| Select / demolish | Left-click a building, then use the side panel or press `Delete` |
| Camera | Right-drag to rotate, `Q`/`E` to rotate, `WASD` or middle-drag to pan, mouse wheel or pinch to zoom |
| Speed | Pause / 1x / 2x / 4x buttons in the top-right corner |

## Gameplay (MVP)
- **Resources**: wood, stone, food
- **Buildings**: woodcutter (wood), farm (food), quarry (stone), house (+4 population cap)
- **Villagers**: every producing building needs one worker. Each villager eats 1 food per day. When there is free housing and enough food, one new villager arrives each day. When food runs out, every building stops producing.
- **Quests**: 8 quests that guide the player step by step, each with a reward
- **Autosave**: the game saves at the end of every in-game day and when the window closes (`user://save.json`)

All balance values (costs, output, day length, quests) are in `scripts/game/defs.gd`.

## Project layout
```
scripts/game/defs.gd             game data and balance values
scripts/game/game_state.gd       simulation core (autoload: Game) — resources, population, quests, saving
scripts/game/build_controller.gd grid, placement preview, selection, building nodes
scripts/game/building_visuals.gd building models (temporary placeholders; the house uses the baked cottage)
scripts/ui/hud.gd                all UI
scripts/scatter.gd               grass and flowers (MultiMesh)
models/  data/                   models and placement data baked from Blender
tools/                           Blender generation and baking scripts
tests/test_gameplay.gd           automated tests
```

## Tests
```
godot --headless --path . --script res://tests/test_gameplay.gd
```

## Regenerating the art (requires `pip install bpy`)
```
python3 tools/bake_export.py <output folder>     # build scene → bake textures → export GLB + scatter.json
python3 tools/repack_glb.py <output folder>/models/*.glb   # convert embedded textures to JPEG to shrink files
```
