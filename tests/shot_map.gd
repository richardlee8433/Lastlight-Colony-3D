extends SceneTree
## Renders the whole map from high above and the village close-up — needs a display / xvfb:
##   godot --path . --script res://tests/shot_map.gd
## Saves _map_overview.png and _map_village.png.

var f := 0
var game; var cam; var sc

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")

func _process(_d: float) -> bool:
	if current_scene == null: return false
	f += 1
	if f == 3:
		game = root.get_node("Game"); cam = current_scene.get_node("Camera"); sc = current_scene.get_node("Scatter")
		game._autosave = false; game.delete_save(); game.new_game(); game.speed = 0.0
		sc.grow_around(Vector2.ZERO, 100.0)
		cam.target = Vector3(0, 0, 2); cam._dist = 60.0; cam._pitch = 1.0; cam._yaw = 0.0; cam._apply()
	if f == 12:
		root.get_viewport().get_texture().get_image().save_png("res://_map_overview.png")
		cam.target = Vector3(0, 0.3, 3); cam._dist = 22.0; cam._pitch = 0.7; cam._yaw = -0.5; cam._apply()
	if f == 22:
		root.get_viewport().get_texture().get_image().save_png("res://_map_village.png")
		game.delete_save()
		quit()
	return false
