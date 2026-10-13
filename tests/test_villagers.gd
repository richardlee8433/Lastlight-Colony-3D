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

func find_spot(ctl, type: String, near: Vector2, angle := 0.0) -> Vector2:
	for r in range(0, 40):
		for k in 16:
			var p: Vector2 = near + Vector2(cos(k * TAU / 16), sin(k * TAU / 16)) * r * 0.5
			if ctl.can_place(type, p, angle): return p
	return Vector2(999, 999)

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
	var c: Vector2 = game.center()
	check(not nav.is_walkable(nav.cell_of(Vector3(c.x - 0.5, 0, c.y))), "the supply cart blocks walking")
	var camp: Vector3 = nav.on_ground(c + Vector2(0, 2))
	var p: PackedVector3Array = nav.find_path(nav.on_ground(Defs.SPAWN_POINTS[0]), camp)
	check(p.size() >= 2, "the south edge reaches the camp (%d pts)" % p.size())
	var p2: PackedVector3Array = nav.find_path(nav.on_ground(Defs.SPAWN_POINTS[1]), camp)
	check(p2.size() >= 2, "the east edge reaches the camp")
	var arriving := 0
	for v in vm.villagers:
		if v.state == v.S.ARRIVE: arriving += 1
	check(arriving == 3, "the first settlers walk in (%d)" % arriving)
	check(nav.trees.size() > 10, "trees loaded (%d)" % nav.trees.size())

	# --- population ---
	check(vm.villagers.size() == 3, "3 villagers for population 3 (%d)" % vm.villagers.size())

	# --- jobs ---
	game.resources["wood"] += 200; game.resources["stone"] += 100
	var wc: int = ctl.try_place("woodcutter", find_spot(ctl, "woodcutter", Vector2(-6, 7.5), 0.4), 0.4)
	var farm: int = ctl.try_place("farm", find_spot(ctl, "farm", Vector2(1, 9)))
	var q: int = ctl.try_place("quarry", find_spot(ctl, "quarry", Vector2(8, 7.5), PI), PI)
	check(wc > 0 and farm > 0 and q > 0, "placed woodcutter, farm, quarry (free positions and angles)")
	var with_job := 0
	for v in vm.villagers:
		if v.job_id >= 0: with_job += 1
	check(with_job == 3, "all 3 villagers got a job (%d)" % with_job)
	var rock: Vector2 = Defs.to_world(game.get_building(q), Vector2(-0.3, -0.6))
	check(not nav.is_walkable(nav.cell_of(Vector3(rock.x, 0, rock.y))), "rotated quarry rocks block walking")

	var stock0 := {"wood": game.resources["wood"], "stone": game.resources["stone"], "food": game.resources["food"]}
	var worked := {}; var delivered := 0
	var t := 0.0
	while t < 120.0:
		sim(game, vm, wear, 1.0)
		t += 1.0
		for v in vm.villagers:
			if v.state == v.S.WORK: worked[v.job_id] = true
	for v in vm.villagers: delivered += v.deliveries
	check(worked.has(wc) and worked.has(farm) and worked.has(q), "every worker reached the work spot (%s)" % str(worked.keys()))
	check(delivered >= 6, "goods were carried (%d deliveries)" % delivered)
	check(game.resources["wood"] > stock0["wood"] and game.resources["stone"] > stock0["stone"], "deliveries raised wood and stone")

	# --- a storehouse next to the quarry takes its deliveries ---
	var qb: Dictionary = game.get_building(q)
	var sh: int = ctl.try_place("storehouse", find_spot(ctl, "storehouse", qb["pos"] + Vector2(-1.5, -3.5)))
	check(sh > 0, "placed a storehouse near the quarry")
	var sh_drop: Vector2 = Defs.to_world(game.get_building(sh), Defs.BUILDINGS["storehouse"]["drop"])
	var used_storehouse := false
	t = 0.0
	while t < 60.0 and not used_storehouse:
		sim(game, vm, wear, 1.0)
		t += 1.0
		for v in vm.villagers:
			if v.job_id == q and not v.goods.is_empty() and v._drop_at.distance_to(sh_drop) < 0.1: used_storehouse = true
	check(used_storehouse, "the quarry worker now delivers to the nearer storehouse")

	# --- roads ---
	check(wear.max_wear() > 0.5, "ground wears where villagers walk (max %.2f)" % wear.max_wear())
	sim(game, vm, wear, 90.0)
	check(s.get_node("Scatter").trampled_count() > 100, "grass trampled on roads (%d)" % s.get_node("Scatter").trampled_count())
	var worn_cell := Vector2i(-1, -1)
	for i in wear.wear.size():
		if wear.wear[i] > 0.8:
			worn_cell = Vector2i((i % wear.SIZE) / 2, (i / wear.SIZE) / 2); break
	check(worn_cell.x >= 0 and nav.astar.get_point_weight_scale(worn_cell) < 0.8, "worn road is cheaper for path-finding")

	# --- growth, houses, leaving ---
	game.resources["food"] += 100
	var h: int = ctl.try_place("house", find_spot(ctl, "house", Vector2(-3, 12), 0.6), 0.6)
	check(h > 0, "placed a rotated house")
	sim(game, vm, wear, Defs.DAY_LENGTH * 5)
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

	# --- starvation: only farmers keep working ---
	game.resources["food"] = 0
	game._day_timer = Defs.DAY_LENGTH - 0.05     # the day ends with an empty pantry
	sim(game, vm, wear, 0.2)
	var job_types := {}
	for v in vm.villagers:
		if v.job_id >= 0: job_types[game.get_building(v.job_id)["type"]] = true
	check(game.starving and job_types.has("farm") and not job_types.has("woodcutter"), "hungry: farmer keeps working, others stop (%s)" % str(job_types.keys()))
	game.demolish(farm)
	vm._sync()
	var jobs := 0
	for v in vm.villagers:
		if v.job_id >= 0: jobs += 1
	check(jobs == 0, "no farm, no work while starving")
	game.delete_save()
	wear.clear()
	_done = true
