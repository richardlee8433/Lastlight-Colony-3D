extends SceneTree
## Headless stone-deposit / quarry test:
##   godot --headless --path . --script res://tests/test_deposits.gd

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

func _run() -> void:
	var game = root.get_node("Game")
	var s = current_scene
	var ctl = s.get_node("BuildController")
	var nav = s.get_node("Nav")
	var vm = s.get_node("Villagers")
	var deps = s.get_node("Deposits")
	var wear = s.get_node("PathWear")
	game._autosave = false; game.instant_build = true
	game.delete_save(); game.new_game(); game.speed = 0.0
	game.resources["wood"] = 500; game.resources["stone"] = 100; game.resources["food"] = 200

	# --- deposits on the map ---
	check(deps._rocks.size() == Defs.DEPOSITS.size() and Defs.DEPOSITS.size() >= 3, "%d stone deposits on the map" % deps._rocks.size())
	var d0: Vector2 = Defs.DEPOSITS[0]["pos"]
	check(not nav.is_walkable(nav.cell_of(Vector3(d0.x, 0, d0.y))), "deposit rock blocks walking")
	var reach: PackedVector3Array = nav.find_path(nav.on_ground(game.center()), nav.on_ground(d0 + Vector2(0, 1.8)))
	var all_reach := true
	for d in Defs.DEPOSITS:
		var p: PackedVector3Array = nav.find_path(nav.on_ground(nav.walkable_point(game.center() + Vector2(0, 2))), nav.on_ground(nav.walkable_point((d["pos"] as Vector2) + Vector2(0, 1.9))))
		if p.size() < 2: all_reach = false
	check(all_reach, "every deposit can be reached on foot")
	check(deps.free_count() == Defs.DEPOSITS.size(), "all deposits start free")

	# --- placement rules ---
	check(ctl.place_problem("quarry", Vector2(0, 8), 0.0) != "", "no quarry away from a deposit")
	check(ctl.place_problem("storehouse", d0, 0.0) != "", "nothing else can be built on the rock")
	check(deps.free_near(d0 + Vector2(3, 2), Defs.DEPOSIT["snap"]) == 0, "the placement ghost snaps to a nearby deposit")
	check(deps.free_near(Vector2(0, 1), 2.0) == -1, "no snapping when no deposit is close")
	ctl.begin_place("quarry")
	var lit := 0
	for r in deps._rings:
		if r.visible: lit += 1
	check(lit == Defs.DEPOSITS.size(), "deposits light up while placing a quarry")
	ctl.cancel_place()
	var dark := true
	for r in deps._rings:
		if r.visible: dark = false
	check(dark, "and stop when placing ends")

	var q: int = ctl.try_place("quarry", d0, 0.9)
	check(q >= 0, "quarry built on a deposit (any rotation)")
	check(deps.quarry_on(0) == q and deps.free_count() == Defs.DEPOSITS.size() - 1, "the deposit is taken")
	check(ctl.place_problem("quarry", d0, 0.0) != "", "one quarry per deposit")
	check(is_equal_approx(deps._rocks[0].rotation.y, 0.9), "the quarried face turns towards the quarry")
	var q2: int = ctl.try_place("quarry", Defs.DEPOSITS[1]["pos"], 0.0)
	check(q2 >= 0, "a second quarry on another deposit")

	# --- the mason works the rock ---
	vm._sync()
	var mason = null
	for v in vm.villagers:
		if v.job_id == q: mason = v
	check(mason != null, "the quarry has a mason")
	var stone0: int = game.resources["stone"]
	var worked := false
	var t := 0.0
	while t < 120.0:
		game.step(0.1); vm.tick(0.1); wear.tick(0.1, 0.5)
		t += 0.1
		if mason and mason.state == mason.S.WORK:
			worked = true
	check(worked, "the mason reached the rock face")
	check(game.resources["stone"] > stone0, "stone carried to storage (+%d)" % (game.resources["stone"] - stone0))

	# --- demolishing frees the deposit ---
	game.demolish(q)
	check(deps.quarry_on(0) == -1 and ctl.place_problem("quarry", d0, 0.0) == "", "demolishing frees the deposit")
	game.delete_save()
	_done = true
