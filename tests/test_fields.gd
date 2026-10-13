extends SceneTree
## Headless farm-field test:
##   godot --headless --path . --script res://tests/test_fields.gd

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
	if Defs.BUILDINGS[type].get("on_deposit", false):     # quarries go on a free stone deposit
		var dep: int = current_scene.get_node("Deposits").free_near(near, 99.0)
		return Defs.DEPOSITS[dep]["pos"] if dep >= 0 else Vector2(999, 999)
	for r in range(0, 40):
		for k in 16:
			var p: Vector2 = near + Vector2(cos(k * TAU / 16.0), sin(k * TAU / 16.0)) * r * 0.5
			if ctl.can_place(type, p, ang): return p
	return Vector2.INF

func _run() -> void:
	var game = root.get_node("Game")
	var s = current_scene
	var fields = s.get_node("Fields")
	var ctl = s.get_node("BuildController")
	var zones = s.get_node("Zones")
	var vm = s.get_node("Villagers")
	var scatter = s.get_node("Scatter")
	var wear = s.get_node("PathWear")
	game._autosave = false
	game.delete_save(); game.new_game(); game.speed = 0.0
	game.resources["wood"] = 500; game.resources["stone"] = 500; game.resources["food"] = 200

	check(wear._ground_mats.size() > 0 and wear._ground_mats[0].get_shader_parameter("field_tex") != null, "field soil hooked into the ground shader")

	# --- a farmhouse gets a starter field ---
	var spot: Vector2 = find_spot(ctl, "farm", Vector2(-6, -4))
	var id: int = ctl.try_place("farm", spot, 0.0)
	check(id >= 0, "farmhouse placed at %s" % spot)
	var n0: int = fields.field_of(id).size()
	check(n0 >= Defs.FIELD["min_cells"], "starter field painted (%d cells = %.0f m²)" % [n0, n0 * 0.25])
	check(fields.yield_for(id) >= 1, "starter field produces (%d food/trip)" % fields.yield_for(id))
	check(fields.wheat_count(id) > 20, "wheat grows on the field (%d clumps)" % fields.wheat_count(id))
	var c0: Vector2 = fields.cell_center(fields.field_of(id)[0])
	check(fields.is_field(c0), "field cells are marked")
	# (the headless renderer doesn't keep MultiMesh transforms, so check scatter's own state)
	check(scatter._field.has(fields.cell_of(c0)), "grass cleared on the field")

	# --- painting rules ---
	ctl.begin_field(id)
	check(ctl.placing == "field" and ctl.area_owner == id and fields.editing == id, "field brush mode")
	var far: int = fields.paint(id, spot + Vector2(Defs.FIELD["range"] + 3.0, 0), true)
	check(far == 0, "can't paint far from the farmhouse")
	var tree: Vector3 = s.get_node("Nav").trees[0]
	check(fields.cell_problem(game.get_building(id), fields.cell_of(Vector2(tree.x, tree.z))) != "", "can't farm a tree trunk")
	var y0: int = fields.yield_for(id)
	for k in 6:
		ctl.brush_at(spot + Vector2(-2.0 + k * 0.8, 4.5), true)
	var n1: int = fields.field_of(id).size()
	check(n1 > n0, "dragging the brush grows the field (%d -> %d)" % [n0, n1])
	check(fields.yield_for(id) >= y0, "bigger field, same or more food per trip (%d)" % fields.yield_for(id))
	for k in 40:
		fields.paint(id, spot + Vector2(-4.0 + (k % 8), -4.0 + int(k / 8.0) * 2.0), true)
	check(fields.field_of(id).size() <= Defs.FIELD["max_cells"], "field size is capped (%d)" % fields.field_of(id).size())
	check(fields.yield_for(id) <= Defs.FIELD["max_yield"], "yield capped")

	# --- erasing ---
	ctl.set_erase(true)
	check(ctl.erasing(), "erase toggle")
	var before: int = fields.field_of(id).size()
	var cc: Vector2 = fields.cell_center(fields.field_of(id)[0])
	ctl.brush_at(cc, false)
	check(fields.field_of(id).size() < before and not fields.is_field(cc), "erase brush removes field cells")
	ctl.set_erase(false)
	ctl.clear_brush_area()
	check(fields.field_of(id).is_empty() and fields.yield_for(id) == 0 and fields.wheat_count(id) == 0, "clear the whole field")
	check(not scatter._field.has(fields.cell_of(cc)), "grass returns after erasing")
	ctl.cancel_place()
	check(ctl.placing == "" and fields.editing == -1, "leave field brush")

	# --- no field: farmer idles, no food ---
	vm._sync()
	var farmer = null
	for v in vm.villagers:
		if v.job_id == id: farmer = v
	check(farmer != null, "farm has a farmer")
	if farmer:
		check(vm.work_target(farmer).is_empty() and vm.yield_of(farmer).is_empty(), "no field -> nothing to do")

	# --- repaint and work ---
	fields.auto_field(game.get_building(id))
	check(fields.yield_for(id) > 0, "re-paint a field")
	if farmer:
		var t: Dictionary = vm.work_target(farmer)
		check(not t.is_empty() and fields.is_field(Vector2(t["pos"].x, t["pos"].z)) or Vector2(t["pos"].x, t["pos"].z).distance_to(spot) < Defs.FIELD["range"] + 1.0, "farmer works in the field")
		check(vm.yield_of(farmer).get("food", 0) == fields.yield_for(id), "harvest per trip follows the field")

	# --- other things respect fields ---
	var fc: Vector2 = fields.cell_center(fields.field_of(id)[fields.field_of(id).size() / 2])
	check(ctl.place_problem("storehouse", fc, 0.0) != "", "can't build on a field")
	check(zones.paint(fc, true, 0.3) == 0, "can't zone over a field")
	ctl.begin_place("zone")
	ctl.set_erase(true)
	game.set_zone(fields.cell_of(spot + Vector2(0, -8)), true)
	var zc: int = game.zone_count()
	ctl.brush_at(spot + Vector2(0, -8), false)
	check(game.zone_count() < zc, "zone brush erases too")
	ctl.cancel_place()

	# --- second farm can't steal cells ---
	var spot2: Vector2 = find_spot(ctl, "farm", spot + Vector2(5, 0), 0.6)
	var id2: int = ctl.try_place("farm", spot2, 0.6)
	check(id2 >= 0, "second farmhouse")
	if id2 >= 0:
		check(fields.paint(id2, fc, true, 0.3) == 0, "a farm can't paint over another farm's field")
		var overlap := false
		for i in fields.field_of(id2):
			if fields.field_of(id).has(i): overlap = true
		check(not overlap, "fields don't overlap")

	# --- saving ---
	var cells: Array = fields.field_of(id).duplicate()
	fields.paint(id, fields.cell_center(cells[0]), false, 0.6)      # an erased bit must stay erased after loading
	cells = fields.field_of(id).duplicate()
	game.save_game()
	game.load_game()
	fields._init_existing()
	var fb: Dictionary = {}
	for b in game.buildings:
		if b["type"] == "farm" and b["pos"].distance_to(spot) < 0.01: fb = b
	var same: bool = not fb.is_empty() and fb.has("field") and fb["field"].size() == cells.size()
	if same:
		for i in cells:
			if not fb["field"].has(i): same = false
	check(same, "the painted field itself is saved (%d cells)" % cells.size())

	# --- demolish frees the field ---
	if not fb.is_empty():
		game.demolish(fb["id"])
		check(not fields.is_field(fc), "demolishing the farmhouse frees its field")
	game.delete_save()
	_done = true
