extends SceneTree
## Headless gameplay smoke test (economy, placement rules, quests, saving):
##   godot --headless --path . --script res://tests/test_gameplay.gd

var _frame := 0
var _fails := 0
var _done := false
var game: Node
var ctl: Node

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")

func _process(_d: float) -> bool:
	if current_scene == null: return false
	_frame += 1
	if _frame == 5:
		_run()
		var ok := _fails == 0 and _done
		print("RESULT: ", "PASS" if ok else "FAIL (%d%s)" % [_fails, "" if _done else ", crashed"])
		quit(0 if ok else 1)
	return false

func check(cond: bool, msg: String) -> void:
	if cond: print("  ok   ", msg)
	else:
		print("  FAIL ", msg); _fails += 1

## first free spot on a spiral around `near`
func find_spot(type: String, near := Vector2(0, 7), angle := 0.0) -> Vector2:
	for r in range(0, 40):
		for k in 16:
			var p: Vector2 = near + Vector2(cos(k * TAU / 16), sin(k * TAU / 16)) * r * 0.5
			if ctl.can_place(type, p, angle): return p
	return Vector2(999, 999)

func _run() -> void:
	game = root.get_node("Game")
	ctl = current_scene.get_node("BuildController")
	game._autosave = false
	game.delete_save()
	game.new_game()
	game.speed = 0.0
	check(game.resources["wood"] == 60 and game.population == 3, "new game start state")
	check(game.count_of("cart") == 1 and game.buildings.size() == 1, "the only building at the start is the supply cart")
	check(game.housing() == 4, "the camp has 4 beds")

	# --- placement rules ---
	check(not ctl.can_place("house", Defs.CART_SPOT), "cannot build on the supply cart")
	var cart_id: int = game.buildings[0]["id"]
	game.demolish(cart_id)
	check(game.count_of("cart") == 1, "the supply cart can't be demolished")
	check(ctl.place_problem("house", Vector2(20, 0), 0.0) != "", "cannot build outside the map")
	var p := find_spot("woodcutter", Vector2(-6, 8), 0.3)
	var id: int = ctl.try_place("woodcutter", p, 0.3)
	check(id > 0, "place woodcutter at %s, rotated 0.3 rad" % p)
	check(is_equal_approx(game.get_building(id)["angle"], 0.3), "any rotation is kept")
	check(game.resources["wood"] == 45, "woodcutter cost paid")
	check(game.quest_index == 1 and game.resources["food"] == 50, "quest 1 done + reward")
	check(ctl.try_place("woodcutter", p + Vector2(1.0, 0.5), 0.0) == -1, "cannot overlap another building")
	var near := p + Defs.rot2(Vector2(3.4, 0), 0.3)
	game.resources["wood"] += 15
	check(ctl.can_place("woodcutter", near, 0.3), "can build right next to it (free placement, no grid)")
	check(ctl.building_at_point(Vector3(p.x, 0, p.y)) == id, "click selects the rotated building")

	# --- economy: only deliveries count ---
	var w0: int = game.resources["wood"]
	game.step(10.0)
	check(game.resources["wood"] == w0, "no production without a delivery")
	game.deliver("wood", 6, Vector2(0, 2.75))
	check(game.resources["wood"] == w0 + 6, "delivery adds to stock")
	game.step(Defs.DAY_LENGTH)
	check(game.day == 2 and game.income_per_day("wood") == 6, "yesterday's income is tracked (%d)" % game.income_per_day("wood"))

	game.resources["wood"] += 200; game.resources["stone"] += 100
	check(ctl.try_place("farm", find_spot("farm", Vector2(2, 8))) > 0, "place farm")
	check(ctl.try_place("house", find_spot("house", Vector2(6, 2))) > 0, "place house")
	check(ctl.try_place("quarry", find_spot("quarry", Vector2(8, 7))) > 0, "place quarry")
	check(ctl.try_place("storehouse", find_spot("storehouse", Vector2(-4, 6))) > 0, "place storehouse")
	check(game.quest_index == 5, "first five quests done (%d)" % game.quest_index)
	check(game.housing() == 8, "housing 8")
	check(game.workers_needed() == 3 and game.workers_used() == 3, "all 3 producers staffed")

	game.resources["food"] = 100
	game.step(Defs.DAY_LENGTH * 6)
	check(game.population == 8, "population grew to housing cap (%d)" % game.population)

	# starving: only food jobs keep working
	game.resources["food"] = 0
	game.step(Defs.DAY_LENGTH)
	check(game.starving, "starving with no food")
	var active := {}
	for b in game.buildings:
		if game.is_active(b): active[b["type"]] = true
	check(active.has("farm") and not active.has("woodcutter") and not active.has("quarry"), "only farmers work while starving")

	# --- save / load round trip ---
	var n: int = game.buildings.size()
	var wood: int = game.resources["wood"]
	var first_pos: Vector2 = game.buildings[0]["pos"]
	game.save_game()
	game.resources["wood"] = 0
	check(game.load_game(), "load save")
	check(game.buildings.size() == n and game.resources["wood"] == wood and game.buildings[0]["pos"].distance_to(first_pos) < 0.01,
		"save round trip (%d buildings)" % n)

	# --- old grid saves still load ---
	var f := FileAccess.open(game.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "resources": {"wood": 5, "stone": 6, "food": 7}, "population": 3, "day": 4,
		"quest_index": 2, "buildings": [{"type": "house", "x": 4, "y": 4, "rot": 1, "progress": 0.0}]}))
	f.close()
	check(game.load_game(), "load a v1 (grid) save")
	var b0: Dictionary = game.buildings[0]
	check(b0["pos"] == Vector2(5.5, 5.5) and is_equal_approx(b0["angle"], PI / 2), "grid cell + quarter turn converted to position + angle")
	check(game.count_of("cart") == 1, "old saves get a supply cart")

	# --- UI ---
	var hud := current_scene.get_node("HUD")
	check(hud._build_buttons.size() == 5, "5 build buttons")
	ctl.begin_place("house")
	check(ctl.placing == "house" and ctl._ghost != null, "ghost preview")
	ctl._rotate_ghost(1)
	check(is_equal_approx(ctl.ghost_angle, PI / 12), "R rotates the ghost by 15°")
	ctl.cancel_place()
	check(ctl.placing == "", "cancel placement")
	game.delete_save()
	_done = true
