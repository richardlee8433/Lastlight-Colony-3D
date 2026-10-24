extends SceneTree
## Renders a low view towards the horizon (sky, gas giant, distant terrain) — needs a display:
##   godot --path . --script res://tests/shot_horizon.gd
## Saves _horizon.png.
var f := 0
func _initialize() -> void:
	change_scene_to_file("res://main.tscn")
func _process(_d: float) -> bool:
	if current_scene == null: return false
	f += 1
	if f == 3:
		var game = root.get_node("Game"); var cam = current_scene.get_node("Camera")
		game._autosave = false; game.delete_save(); game.new_game(); game.speed = 0.0
		current_scene.get_node("Scatter").grow_around(Vector2.ZERO, 40.0)
		cam.target = Vector3(-6.0, 9.0, -8.0); cam._dist = 16.0; cam._pitch = 0.05; cam._yaw = 0.63; cam._apply()
	if f == 12:
		root.get_viewport().get_texture().get_image().save_png("res://_horizon.png")
		root.get_node("Game").delete_save()
		quit()
	return false
