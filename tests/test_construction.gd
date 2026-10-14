extends SceneTree
## Headless construction-site / auto-road test:
##   godot --headless --path . --script res://tests/test_construction.gd

var _frame := 0
var _fails := 0
var _done := false

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

func find_spot(ctl, type: String, near: Vector2, ang := 0.0) -> Vector2:
	if Defs.BUILDINGS[type].get("on_deposit", false):
		var dep: int = current_scene.get_node("Deposits").free_near(near, 99.0)
		return Defs.DEPOSITS[dep]["pos"] if dep >= 0 else Vector2(999, 999)
	for r in range(0, 50):
		for k in 16:
			var p: Vector2 = near + Vector2(cos(k * TAU / 16.0), sin(k * TAU / 16.0)) * r * 0.5
			if ctl.can_place(type, p, ang): return p
	return Vector2.INF

func _run() -> void:
	var game = root.get_node("Game")
	var s = current_scene
	var ctl = s.get_node("BuildController")
	var vm = s.get_node("Villagers")
	var wear = s.get_node("PathWear")
	var fields = s.get_node("Fields")
	game._autosave = false; game.instant_build = false
	game.delete_save(); game.new_game(); game.speed = 0.0
	vm._first_sync()
	game.resources["wood"] = 400; game.resources["stone"] = 200; game.resources["food"] = 200

	# --- placing makes a construction site ---
	var id: int = ctl.try_place("woodcutter", find_spot(ctl, "woodcutter", Vector2(-5, 6)), 0.3)
	var b: Dictionary = game.get_building(id)
	check(id >= 0 and not game.is_built(b) and game.build_stage(b) == 0, "placing a building starts a construction site")
	check(game.count_of("woodcutter") == 0 and game.quest_index == 0, "a site doesn't count as built yet")
	var node: Node3D = ctl._nodes[id]
	check(int(node.get_meta("stage")) == 0, "stage 1 model: foundation")
	vm._sync()
	var builder = null
	for v in vm.villagers:
		if v.job_id == id: builder = v
	check(builder != null and vm.job_of(builder).get("target", "") == "site", "a villager becomes the builder")

	# --- the builder works it through both stages ---
	var stages := {}
	var t := 0.0
	while t < 200.0 and not game.is_built(b):
		game.step(0.1); vm.tick(0.1); wear.tick(0.1, 0.5)
		t += 0.1
		stages[int(node.get_meta("stage"))] = true
	check(stages.has(1), "stage 2 model: timber frame")
	check(game.is_built(b) and int(node.get_meta("stage")) == 2, "the site is finished (%.0f s)" % t)
	check(game.count_of("woodcutter") == 1 and game.quest_index == 1, "now it counts (quest done)")
	vm._sync()
	check(builder.job_id == id and vm.job_of(builder).get("target", "") == "tree", "the builder becomes its woodcutter")

	# --- builders come before workplaces ---
	var f1: int = ctl.try_place("farm", find_spot(ctl, "farm", Vector2(3, 8)), 0.0)
	var h1: int = ctl.try_place("house", find_spot(ctl, "house", Vector2(-3, 12)), 0.0)
	var q1: int = ctl.try_place("quarry", find_spot(ctl, "quarry", Vector2(8, 5)), 0.0)
	check(f1 >= 0 and h1 >= 0 and q1 >= 0, "three more sites")
	game.population = 3; game._assign_workers()
	check(game.sites() == 3 and game.get_building(f1)["staffed"] and game.get_building(h1)["staffed"] and game.get_building(q1)["staffed"], "every site gets a builder")
	check(not game.get_building(id)["staffed"], "the woodcutter pauses while all villagers build")
	check(game.housing() == 4 and game.housing(true) == 8, "a house only gives beds once it's finished")
	check(not fields.is_field(Vector2(999, 999)) and fields.crop_stage(f1) == "tilled", "a farm site's field stays bare")

	# --- cancelling a site refunds everything ---
	var wood0: int = game.resources["wood"]; var stone0: int = game.resources["stone"]
	game.demolish(q1)
	check(game.resources["wood"] == wood0 + 25 and game.resources["stone"] == stone0, "cancelling a site refunds the full cost")

	# --- progress is saved ---
	game.add_build_progress(h1, 0.6)
	game.save_game(); game.load_game()
	var hb: Dictionary = game.get_building(h1)
	check(not hb.is_empty() and not game.is_built(hb) and absf(game.build_progress(hb) - 0.6) < 0.01, "construction progress is saved")
	game.finish_all_construction()
	check(game.sites() == 0 and game.housing() == 8, "finish_all_construction")

	# --- new buildings get a path to the road ---
	var ssp: Vector2 = find_spot(ctl, "storehouse", Vector2(7, -3), 0.5)
	var sh: int = ctl.try_place("storehouse", ssp, 0.5)
	var sb: Dictionary = game.get_building(sh)
	var entrance: Vector2 = Defs.to_world(sb, Defs.BUILDINGS["storehouse"]["drop"])
	wear.clear()
	var laid: int = 0
	wear.connect_building(sb)
	var on_path := 0; var samples := 0
	var target: Vector2 = game.center() + Vector2(0, 1.6)
	for k in range(2, 9):
		var p: Vector2 = entrance.lerp(target, k / 10.0)
		samples += 1
		var best := 0.0
		for dx in range(-6, 7):
			for dz in range(-6, 7):
				best = maxf(best, wear.wear_at(Vector3(p.x + dx * 0.25, 0, p.y + dz * 0.25)))
		if best > 0.4: on_path += 1
	check(wear.wear_at(Vector3(entrance.x, 0, entrance.y)) > 0.3 or on_path >= samples - 2, "a dirt path leads from the new storehouse")
	check(on_path >= samples - 2, "all the way to the village (%d/%d)" % [on_path, samples])
	game.delete_save()
	_done = true
