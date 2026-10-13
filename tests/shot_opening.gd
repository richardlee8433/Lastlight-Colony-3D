extends SceneTree
## Renders the opening (settlers walking in with the supply cart) — needs a display / xvfb:
##   godot --path . --script res://tests/shot_opening.gd
## Saves _opening_arrive.png and _opening_camp.png.

var f := 0
var game; var vm; var wear; var cam

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")

func _sim(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		game.step(0.1); vm.tick(0.1); wear.tick(0.1, 0.5)
		t += 0.1

func _process(_d: float) -> bool:
	if current_scene == null: return false
	f += 1
	if f == 3:
		game = root.get_node("Game"); vm = current_scene.get_node("Villagers"); wear = current_scene.get_node("PathWear")
		cam = current_scene.get_node("Camera")
		game._autosave = false; game.delete_save(); game.new_game(); game.speed = 0.0
		vm._first_sync()
		_sim(6.0)
		cam.target = Vector3(0.0, 0.3, 5.0); cam._dist = 19.0; cam._pitch = 0.75; cam._yaw = -0.3; cam._apply()
	if f == 12:
		root.get_viewport().get_texture().get_image().save_png("res://_opening_arrive.png")
		_sim(14.0)
		cam.target = Vector3(0.3, 0.3, 1.6); cam._dist = 8.5; cam._pitch = 0.6; cam._yaw = -0.6; cam._apply()
	if f == 22:
		root.get_viewport().get_texture().get_image().save_png("res://_opening_camp.png")
		game.delete_save(); wear.clear()
		quit()
	return false
