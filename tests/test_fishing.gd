extends SceneTree
## Headless test of fishing huts and fish stocks:
##   godot --headless --path . --script res://tests/test_fishing.gd

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
	var vm = s.get_node("Villagers")
	var nav = s.get_node("Nav")
	var wear = s.get_node("PathWear")
	var fishing = s.get_node("Fishing")
	var water = s.get_node("Water")
	game._autosave = false; game.instant_build = true
	game.delete_save(); game.new_game(); game.speed = 0.0
	game.resources["wood"] = 300; game.resources["food"] = 100
	var pond: Vector2 = Defs.WATER["pond"]["pos"]
	var pr: float = Defs.WATER["pond"]["radius"]

	# --- placement ---
	check(ctl.place_problem("fishery", Vector2(0, 8), 0.0) != "", "no fishing hut away from the water")
	var near: Vector2 = pond + Vector2(pr + 4.0, 0.0)
	var sn: Dictionary = fishing.snap("fishery", near)
	check(not sn.is_empty(), "the ghost snaps to the pond shore")
	var front: Vector2 = Defs.to_world({"pos": sn["pos"], "angle": sn["angle"], "type": "fishery"}, Vector2(0, 2.0))
	check(front.distance_to(pond) < sn["pos"].distance_to(pond), "and faces the water")
	var id: int = ctl.try_place("fishery", sn["pos"], sn["angle"])
	check(id >= 0, "fishing hut built on the shore (%s)" % ctl.place_problem("fishery", sn["pos"], sn["angle"]))
	var b: Dictionary = game.get_building(id)
	check(fishing.body_of(b) == 0, "it fishes the pond")

	# --- the fisher ---
	vm._sync()
	var fisher = null
	for v in vm.villagers:
		if v.job_id == id: fisher = v
	check(fisher != null, "the hut has a fisher")
	var t: Dictionary = vm.work_target(fisher)
	check(not t.is_empty() and nav.is_walkable(nav.cell_of(t["pos"])), "fishes from a walkable spot on the bank")
	var food0: int = game.resources["food"]
	var fished := false
	var tt := 0.0
	while tt < 120.0:
		game.step(0.1); vm.tick(0.1); wear.tick(0.1, 0.5)
		tt += 0.1
		if fisher.state == fisher.S.WORK and fisher._anim == "fish": fished = true
	check(fished, "the fisher sits on the bank with a rod")
	check(game.resources["food"] > food0 - game.population * 4, "fish carried to storage")
	check(fishing.stock(0) < 1.0, "the pond's fish stock went down (%.2f)" % fishing.stock(0))

	# --- scarcity and recovery ---
	game.fish["0"] = 0.1
	check(fishing.catch_fish(b) == 0 and vm.work_target(fisher).is_empty(), "no catch when fish are scarce")
	fishing.tick(Defs.DAY_LENGTH * 2.0)
	check(fishing.stock(0) > 0.45, "fish come back over time (%.2f)" % fishing.stock(0))
	check(fishing.catch_fish(b) >= 1, "and can be caught again")

	# --- limit per water body ---
	var placed := 1
	for k in 12:
		var a := k / 12.0 * TAU
		var sp: Dictionary = fishing.snap("fishery", pond + Vector2(cos(a), sin(a)) * (pr + 4.0))
		if sp.is_empty(): continue
		if ctl.try_place("fishery", sp["pos"], sp["angle"]) >= 0: placed += 1
	check(placed == Defs.FISHING["huts_per_body"], "at most %d huts on the pond (%d)" % [Defs.FISHING["huts_per_body"], placed])

	# --- saving ---
	game.fish["0"] = 0.37
	game.save_game(); game.load_game()
	check(absf(fishing.stock(0) - 0.37) < 0.01, "fish stocks are saved")

	# --- pond life ---
	check(water.get_node_or_null("Reeds") != null and water.get_node("Reeds").multimesh.instance_count > 30, "reeds along the banks")
	check(water.get_node_or_null("LilyPads") != null, "lily pads on the pond")
	var n0: int = water.get_child_count()
	water.jump_fish(Vector3(pond.x, 0, pond.y), 0.5)
	check(water.get_child_count() > n0, "a fish jumps")
	check(fishing.shore_spots(nav).size() > 50, "bank spots for strolling villagers (%d)" % fishing.shore_spots(nav).size())
	game.delete_save()
	_done = true
