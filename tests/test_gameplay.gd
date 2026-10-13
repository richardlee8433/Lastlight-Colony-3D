extends SceneTree
## Headless gameplay smoke test:
##   godot --headless --path . --script res://tests/test_gameplay.gd

var _frame := 0
var _fails := 0
var _done := false
var game: Node
var ctl: Node

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")

func _process(_d: float) -> bool:
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

func find_cell(type: String) -> Vector2i:
	for r in range(0, 14):
		for x in range(-r, r + 1):
			for z in range(-r, r + 1):
				if abs(x) != r and abs(z) != r: continue
				var c := Vector2i(x, z)
				if ctl.can_place(type, c): return c
	return Vector2i(999, 999)

func _run() -> void:
	game = root.get_node("Game")
	ctl = current_scene.get_node("BuildController")
	game._autosave = false
	game.delete_save()
	game.new_game()
	check(game.resources["wood"] == 40 and game.population == 3, "new game start state")
	check(ctl._blocked.size() > 50, "scenery blocks cells (%d)" % ctl._blocked.size())
	check(not ctl.can_place("house", Vector2i(-1, -1)), "cannot build on the cottage")

	var c := find_cell("woodcutter")
	var id: int = ctl.try_place("woodcutter", c)
	check(id > 0, "place woodcutter at %s" % c)
	check(game.resources["wood"] == 25, "woodcutter cost paid")
	check(game.quest_index == 1 and game.resources["food"] == 40, "quest 1 done + reward")
	check(ctl.try_place("woodcutter", c) == -1, "cannot overlap")

	var w0: int = game.resources["wood"]
	game.step(8.0)
	check(game.resources["wood"] == w0 + 6, "woodcutter produced 6 wood in 8s (%d)" % (game.resources["wood"] - w0))
	check(game.day == 2, "a day passed")

	game.resources["wood"] += 100; game.resources["stone"] += 50
	check(ctl.try_place("farm", find_cell("farm")) > 0, "place farm")
	check(ctl.try_place("house", find_cell("house")) > 0, "place house")
	check(ctl.try_place("quarry", find_cell("quarry")) > 0, "place quarry")
	check(game.quest_index == 4, "first four quests done (%d)" % game.quest_index)
	check(game.housing() == 8, "housing 8")
	check(game.workers_needed() == 3 and game.workers_used() == 3, "all 3 producers staffed")

	game.step(Defs.DAY_LENGTH * 12)
	check(game.population == 8, "population grew to housing cap (%d)" % game.population)
	check(not game.starving, "not starving with a farm")

	# starvation path
	game.resources["food"] = 0
	var removed_farm := -1
	for b in game.buildings:
		if b["type"] == "farm": removed_farm = b["id"]
	game.demolish(removed_farm)
	game.step(Defs.DAY_LENGTH)
	check(game.starving, "starving with no food")
	var s0: int = game.resources["stone"]
	game.step(10.0)
	check(game.resources["stone"] == s0, "production halts while starving")

	# save / load round trip
	var n: int = game.buildings.size()
	var wood: int = game.resources["wood"]
	game.save_game()
	game.resources["wood"] = 0
	check(game.load_game(), "load save")
	check(game.buildings.size() == n and game.resources["wood"] == wood, "save round trip (%d buildings)" % n)

	# UI exists
	var hud := current_scene.get_node("HUD")
	check(hud._build_buttons.size() == 4, "4 build buttons")
	ctl.begin_place("house")
	check(ctl.placing == "house" and ctl._ghost != null, "ghost preview")
	ctl.cancel_place()
	check(ctl.placing == "", "cancel placement")
	game.delete_save()
	_done = true
