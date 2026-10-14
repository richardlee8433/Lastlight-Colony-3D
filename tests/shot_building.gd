extends SceneTree
## Renders one building type up close and from the normal game distance (needs a display / xvfb):
##   godot --path . --script res://tests/shot_building.gd -- farm
## Saves _building_close.png and _building_game.png.

var f := 0
var game; var ctl; var cam
var type := "farm"
var pos := Vector2(0.5, 8.5)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: type = args[0]
	change_scene_to_file("res://main.tscn")

func _process(_d: float) -> bool:
	if current_scene == null: return false
	f += 1
	if f == 3:
		game = root.get_node("Game"); ctl = current_scene.get_node("BuildController"); cam = current_scene.get_node("Camera")
		game._autosave = false; game.instant_build = true; game.delete_save(); game.new_game()
		game.resources["wood"] = 500; game.resources["stone"] = 500
		ctl.try_place(type, pos, 0.25)
		cam.target = Vector3(pos.x, 0.3, pos.y); cam._dist = 6.5; cam._pitch = 0.55; cam._yaw = -0.5; cam._apply()
	if f == 12:
		root.get_viewport().get_texture().get_image().save_png("res://_building_close.png")
		cam._dist = 18.0; cam._pitch = 0.85; cam._yaw = -0.55; cam._apply()
	if f == 20:
		root.get_viewport().get_texture().get_image().save_png("res://_building_game.png")
		game.delete_save()
		quit()
	return false
