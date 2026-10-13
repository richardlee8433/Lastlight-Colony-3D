extends SceneTree
## Renders a time-lapse of a small village (needs a display / xvfb):
##   godot --path . --script res://tests/shot_village.gd -- <minutes>
## Saves _village_wide.png and _village_close.png in the project folder.

var f := 0
var game; var vm; var wear; var ctl; var cam

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")

func _process(_d: float) -> bool:
	if current_scene == null: return false
	f += 1
	if f == 3: _setup()
	if f == 14:
		root.get_viewport().get_texture().get_image().save_png("res://_village_wide.png")
		cam.target = Vector3(-3.5, 0.4, 6.5); cam._dist = 11.0; cam._pitch = 0.62; cam._yaw = -0.35; cam._apply()
	if f == 24:
		root.get_viewport().get_texture().get_image().save_png("res://_village_close.png")
		game.delete_save(); wear.clear()
		quit()
	return false

func _setup() -> void:
	game = root.get_node("Game"); var s = current_scene
	vm = s.get_node("Villagers"); wear = s.get_node("PathWear"); ctl = s.get_node("BuildController"); cam = s.get_node("Camera")
	game._autosave = false
	game.delete_save(); game.new_game(); game.speed = 0.0
	vm._first_sync()
	game.resources["wood"] = 400; game.resources["stone"] = 300; game.resources["food"] = 200
	ctl.try_place("woodcutter", Vector2i(-8, 5), 0)
	ctl.try_place("farm", Vector2i(-3, 8), 0)
	ctl.try_place("quarry", Vector2i(7, 5), 2)
	ctl.try_place("house", Vector2i(3, 9), 0)
	ctl.try_place("house", Vector2i(-7, 10), 1)
	ctl.try_place("woodcutter", Vector2i(8, -8), 0)
	ctl.try_place("farm", Vector2i(3, 13), 0)
	var minutes := 6.0
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: minutes = float(args[0])
	var t := 0.0
	while t < minutes * 60.0:
		game.step(0.1); vm.tick(0.1); wear.tick(0.1, 0.5)
		t += 0.1
	game.speed = 1.0
	ctl.select(-1)
