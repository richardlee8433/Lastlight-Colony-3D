extends SceneTree
## The same colony as shot_village.gd at dusk and at night (needs a display / xvfb):
##   godot --path . --script res://tests/shot_night.gd
## Saves _dusk.png and _night.png in the project folder.

var f := 0
var game; var vm; var wear; var ctl; var cam

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")

func _process(_d: float) -> bool:
	if current_scene == null: return false
	f += 1
	if f == 3: _setup()
	if f == 5:
		cam.target = Vector3(0.0, 0.4, 8.0); cam._dist = 27.0; cam._apply()
		current_scene.get_node("DayNight").set_time(0.715)
	if f == 14:
		root.get_viewport().get_texture().get_image().save_png("res://_dusk.png")
		current_scene.get_node("DayNight").set_time(0.92)
	if f == 24:
		root.get_viewport().get_texture().get_image().save_png("res://_night.png")
		game.delete_save(); wear.clear()
		quit()
	return false

func _spot(type: String, near: Vector2, angle: float) -> Vector2:
	if Defs.BUILDINGS[type].get("on_deposit", false):     # quarries go on a free stone deposit
		var dep: int = current_scene.get_node("Deposits").free_near(near, 99.0)
		return Defs.DEPOSITS[dep]["pos"] if dep >= 0 else Vector2(999, 999)
	for r in range(0, 40):
		for k in 16:
			var p: Vector2 = near + Vector2(cos(k * TAU / 16), sin(k * TAU / 16)) * r * 0.5
			if ctl.can_place(type, p, angle): return p
	return near

func _setup() -> void:
	game = root.get_node("Game"); var s = current_scene
	vm = s.get_node("Villagers"); wear = s.get_node("PathWear"); ctl = s.get_node("BuildController"); cam = s.get_node("Camera")
	game._autosave = false; game.instant_build = true
	game.delete_save(); game.new_game(); game.speed = 0.0
	vm._first_sync()
	game.resources["wood"] = 400; game.resources["stone"] = 300; game.resources["food"] = 200
	for e in [["woodcutter", Vector2(-7.5, 8.0), 0.5], ["farm", Vector2(-1.0, 10.0), -0.15], ["quarry", Vector2(8.5, 6.5), 2.6],
			["storehouse", Vector2(4.8, 5.8), -0.8],
			["woodcutter", Vector2(-9.5, 1.0), -0.4], ["farm", Vector2(3.0, 14.0), 0.1]]:
		var p := _spot(e[0], e[1], e[2])
		ctl.try_place(e[0], p, e[2])
	# residential zones east and west of the south road
	var zones = s.get_node("Zones")
	for x in range(3, 11):
		for z in range(9, 15):
			zones.paint(Vector2(x, z), true)
	for x in range(-11, -4):
		for z in range(10, 15):
			zones.paint(Vector2(x, z), true)
	var minutes := 4.0
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: minutes = float(args[0])
	var t := 0.0
	while t < minutes * 60.0:
		game.step(0.1); vm.tick(0.1); wear.tick(0.1, 0.5); zones.tick(0.1)
		t += 0.1
	game.set_speed(0.0)
	ctl.select(-1)
