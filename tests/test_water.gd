extends SceneTree
## Headless test of the stream, pond and bridges:
##   godot --headless --path . --script res://tests/test_water.gd

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
	var nav = s.get_node("Nav")
	var ctl = s.get_node("BuildController")
	var water = s.get_node("Water")
	game._autosave = false; game.instant_build = true
	game.delete_save(); game.new_game(); game.speed = 0.0
	var pts: PackedVector2Array = Water.river_samples()
	check(pts.size() > 50, "stream centre line (%d samples)" % pts.size())
	# water blocks walking, except on the bridges
	var i3: int = pts.size() / 3
	while i3 < pts.size() - 2:
		var far := true
		for bp in Defs.WATER["bridges"]:
			if pts[i3].distance_to(bp) < 5.0: far = false
		if far and absf(pts[i3].x) < 30 and absf(pts[i3].y) < 30: break
		i3 += 1
	var mid: Vector2 = pts[i3]
	check(Water.is_water(mid) and not nav.is_walkable(nav.cell_of(Vector3(mid.x, 0, mid.y))), "the stream blocks walking")
	var pc: Vector2 = Defs.WATER["pond"]["pos"]
	check(Water.is_water(pc) and not nav.is_walkable(nav.cell_of(Vector3(pc.x, 0, pc.y))), "so does the pond")
	check(Water.bridges.size() == Defs.WATER["bridges"].size(), "%d bridges" % Water.bridges.size())
	for b in Water.bridges:
		var bp: Vector2 = b["pos"]
		check(nav.is_walkable(nav.cell_of(Vector3(bp.x, 0, bp.y))), "bridge deck at %s is walkable" % bp)
		check(nav.height_at(bp.x, bp.y) >= b["deck_y"] - 0.01, "and at deck height")
	# the east road crosses on the bridge
	var east: Vector2 = Defs.SPAWN_POINTS[1]
	var p: PackedVector3Array = nav.find_path(nav.on_ground(nav.walkable_point(east)), nav.on_ground(nav.walkable_point(game.center() + Vector2(0, 2))))
	check(p.size() >= 2, "settlers from the east reach the village")
	var crossed := false
	for q in p:
		for b in Water.bridges:
			if Vector2(q.x, q.z).distance_to(b["pos"]) < 2.5: crossed = true
	check(crossed, "over a bridge")
	# the ground is carved lower in the stream than on its banks
	var tangent: Vector2 = (pts[i3 + 1] - pts[i3 - 1]).normalized()
	var bank: Vector2 = mid + Vector2(-tangent.y, tangent.x) * (Defs.WATER["river_width"] + 3.0)
	check(Water.sample(bank).x == 0.0 and nav.height_at(mid.x, mid.y) < nav.height_at(bank.x, bank.y) - 0.3, "the stream bed is lower than the meadow (%.2f vs %.2f)" % [nav.height_at(mid.x, mid.y), nav.height_at(bank.x, bank.y)])
	# nothing grows or gets built in the water
	var wet_trees := 0
	for t in game.trees:
		if Water.is_water(t["pos"]): wet_trees += 1
	check(wet_trees == 0, "no trees standing in the water")
	check(ctl.place_problem("house", pc, 0.0) != "", "can't build in the pond")
	var zones = s.get_node("Zones")
	check(zones.paint(pc, true, 1.0) == 0, "can't zone the pond")
	check(water.get_node_or_null("Stream") != null and water.get_node_or_null("Pond") != null, "water surfaces built")
	game.delete_save()
	_done = true
