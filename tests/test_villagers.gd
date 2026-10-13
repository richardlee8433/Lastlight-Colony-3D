extends SceneTree
## Headless villager / road test:
##   godot --headless --path . --script res://tests/test_villagers.gd

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

func sim(game, vm, wear, seconds: float, step := 0.1) -> void:
	var t := 0.0
	while t < seconds:
		game.step(step)
		vm.tick(step)
		wear.tick(step, 0.5)
		t += step

func _run() -> void:
	var game = root.get_node("Game")
	var s = current_scene
	var ctl = s.get_node("BuildController")
	var nav = s.get_node("Nav")
	var wear = s.get_node("PathWear")
	var vm = s.get_node("Villagers")
	game._autosave = false
	game.delete_save()
	game.new_game()
	game.speed = 0.0                  # drive the simulation manually
	vm._first_sync()

	# --- navigation ---
	check(not nav.is_walkable(nav.cell_of(Vector3(0, 0, 0))), "cottage centre is blocked")
	var p: PackedVector3Array = nav.find_path(nav.on_ground(Defs.SPAWN_POINTS[0]), nav.on_ground(Defs.STORAGE_POINT))
	check(p.size() >= 2, "road from the south spawn reaches the cottage door (%d pts)" % p.size())
	var p2: PackedVector3Array = nav.find_path(nav.on_ground(Defs.SPAWN_POINTS[1]), nav.on_ground(Defs.STORAGE_POINT))
	check(p2.size() >= 2, "east spawn reaches the cottage door")
	check(nav.trees.size() > 10, "trees loaded (%d)" % nav.trees.size())

	# --- population ---
	check(vm.villagers.size() == 3, "3 villagers for population 3 (%d)" % vm.villagers.size())

	# --- jobs ---
	game.resources["wood"] += 200; game.resources["stone"] += 100
	var wc: int = ctl.try_place("woodcutter", Vector2i(-7, 6))
	var farm: int = ctl.try_place("farm", Vector2i(-1, 7))
	var q: int = ctl.try_place("quarry", Vector2i(6, 6))
	check(wc > 0 and farm > 0 and q > 0, "placed woodcutter, farm, quarry")
	var with_job := 0
	for v in vm.villagers:
		if v.job_id >= 0: with_job += 1
	check(with_job == 3, "all 3 villagers got a job (%d)" % with_job)
	check(not nav.is_walkable(nav.cell_of(Vector3(Defs.to_world(game.get_building(q), Vector2(-0.3, -0.6)).x, 0, Defs.to_world(game.get_building(q), Vector2(-0.3, -0.6)).y))), "quarry rocks block walking")

	var worked := {}; var delivered := 0
	var t := 0.0
	while t < 90.0:
		sim(game, vm, wear, 1.0)
		t += 1.0
		for v in vm.villagers:
			if v.state == v.S.WORK: worked[v.job_id] = true
	for v in vm.villagers: delivered += v.deliveries
	check(worked.has(wc) and worked.has(farm) and worked.has(q), "every worker reached the work spot (%s)" % str(worked.keys()))
	check(delivered >= 6, "goods were carried (%d deliveries)" % delivered)

	# --- roads ---
	check(wear.max_wear() > 0.5, "ground wears where villagers walk (max %.2f)" % wear.max_wear())
	sim(game, vm, wear, 120.0)
	check(s.get_node("Scatter").trampled_count() > 100, "grass trampled on roads (%d)" % s.get_node("Scatter").trampled_count())
	var worn_cell := Vector2i(-1, -1)
	for i in wear.wear.size():
		if wear.wear[i] > 0.8:
			worn_cell = Vector2i((i % wear.SIZE) / 2, (i / wear.SIZE) / 2); break
	check(worn_cell.x >= 0 and nav.astar.get_point_weight_scale(worn_cell) < 0.8, "worn road is cheaper for path-finding")

	# --- growth, houses, leaving ---
	var hc := Vector2i(999, 999)
	for z in range(4, 14):
		for x in range(-10, 10):
			if hc.x == 999 and ctl.can_place("house", Vector2i(x, z)): hc = Vector2i(x, z)
	var h: int = ctl.try_place("house", hc)
	check(h > 0, "placed a house")
	sim(game, vm, wear, Defs.DAY_LENGTH * 6)
	check(vm.villagers.size() == game.population and game.population > 3, "new villagers arrive (%d)" % vm.villagers.size())
	var homes_at_house := 0
	var door: Vector2 = Defs.to_world(game.get_building(h), Defs.BUILDINGS["house"]["door"])
	for v in vm.villagers:
		if v.home == door: homes_at_house += 1
	check(homes_at_house > 0, "some villagers live in the new house (%d)" % homes_at_house)
	var before: int = vm.villagers.size()
	game.demolish(h)
	vm._sync()
	check(vm.villagers.size() == game.population and vm.leaving.size() > 0, "villagers leave when housing shrinks (%d -> %d)" % [before, vm.villagers.size()])
	sim(game, vm, wear, 40.0)
	check(vm.leaving.is_empty(), "leavers walked off the map")

	# --- starvation stops work ---
	game.resources["food"] = 0
	game.demolish(farm)
	sim(game, vm, wear, Defs.DAY_LENGTH * 1.1)
	var jobs := 0
	for v in vm.villagers:
		if v.job_id >= 0: jobs += 1
	check(game.starving and jobs == 0, "hungry villagers stop working")
	game.delete_save()
	wear.clear()
	_done = true
