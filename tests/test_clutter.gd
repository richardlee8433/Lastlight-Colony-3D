extends SceneTree
## Headless test of the lived-in props around buildings:
##   godot --headless --path . --script res://tests/test_clutter.gd

var _frame := 0
var _fails := 0
var _done := false
var _stage := 0
var game; var ctl; var clutter; var nav; var wear
var ids: Array = []

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")

func check(cond: bool, msg: String) -> void:
	if cond: print("  ok   ", msg)
	else:
		print("  FAIL ", msg); _fails += 1

func find_spot(type: String, near: Vector2, ang := 0.0) -> Vector2:
	for r in range(0, 50):
		for k in 16:
			var p: Vector2 = near + Vector2(cos(k * TAU / 16.0), sin(k * TAU / 16.0)) * r * 0.5
			if ctl.can_place(type, p, ang): return p
	return Vector2.INF

func _process(_d: float) -> bool:
	if current_scene == null: return false
	_frame += 1
	if _frame == 5:
		game = root.get_node("Game"); var s = current_scene
		ctl = s.get_node("BuildController"); clutter = s.get_node("Clutter"); nav = s.get_node("Nav"); wear = s.get_node("PathWear")
		game._autosave = false; game.instant_build = true
		game.delete_save(); game.new_game(); game.speed = 0.0
		game.resources["wood"] = 900; game.resources["stone"] = 600
		for i in 4:
			ids.append(ctl.try_place("house", find_spot("house", Vector2(-9.0 + i * 5.5, 9.0)), 0.0))
		ids.append(ctl.try_place("storehouse", find_spot("storehouse", Vector2(8, -4)), 0.4))
		ids.append(ctl.try_place("farm", find_spot("farm", Vector2(-10, -6)), 0.0))
	if _frame == 8:          # props are placed deferred (after the auto paths)
		_run()
		var ok := _fails == 0 and _done
		print("RESULT: ", "PASS" if ok else "FAIL (%d%s)" % [_fails, "" if _done else ", crashed"])
		quit(0 if ok else 1)
	return false

func _run() -> void:
	var houses := 0
	for i in 4:
		if clutter.prop_count(ids[i]) > 0: houses += 1
	check(houses >= 3, "houses get props (%d of 4)" % houses)
	check(clutter.prop_count(ids[4]) >= 2, "the storehouse gets crates and barrels (%d)" % clutter.prop_count(ids[4]))
	check(clutter.prop_count() >= 10, "%d props in the village" % clutter.prop_count())
	# nothing on paths, doorsteps or inside buildings
	var bad := 0; var blocking := 0
	for id in clutter._props:
		for p in clutter._props[id]:
			var pos: Vector2 = p["pos"]
			if wear.wear_at(Vector3(pos.x, 0, pos.y)) > 0.3: bad += 1
			for b in game.buildings:
				var l := Defs.to_local(b, pos)
				var h := Defs.half_extents(b["type"])
				if absf(l.x) < h.x and absf(l.y) < h.y: bad += 1
			if p["key"] != null:
				blocking += 1
				if nav.is_walkable(nav.cell_of(Vector3(pos.x, 0, pos.y))): bad += 1
	check(bad == 0, "no props on paths, inside buildings, and big ones block walking (%d blocking)" % blocking)
	for b in game.buildings:
		if b["type"] != "house": continue
		var door: Vector2 = Defs.to_world(b, Vector2(0, 1.9))
		var p: PackedVector3Array = nav.find_path(nav.on_ground(nav.walkable_point(door)), nav.on_ground(nav.walkable_point(game.center() + Vector2(0, 2))))
		check(p.size() >= 2, "house %d door still reachable" % b["id"])
	# removing a building removes its props and frees their cells
	var hid: int = ids[0]
	var keys: Array = []
	for p in clutter._props.get(hid, []):
		if p["key"] != null: keys.append(p["pos"])
	game.demolish(hid)
	var freed := true
	for pos in keys:
		if not nav.is_walkable(nav.cell_of(Vector3(pos.x, 0, pos.y))) and not nav.scenery_at(pos): freed = false
	check(clutter.prop_count(hid) == 0 and freed, "demolishing removes the props")
	# a new building clears props in its way
	var victim: Dictionary = {}
	for id in clutter._props:
		if not clutter._props[id].is_empty(): victim = clutter._props[id][0]; break
	if not victim.is_empty():
		var n0: int = clutter.prop_count()
		game.add_building("storehouse", victim["pos"], 0.0, false)
		check(clutter.prop_count() < n0, "a new building clears props under it")
	game.new_game()
	check(clutter.prop_count() == 0, "new game: no props")
	game.delete_save()
	_done = true
