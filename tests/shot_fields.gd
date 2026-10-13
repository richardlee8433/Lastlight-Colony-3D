extends SceneTree
## Renders a farmhouse with a painted wheat field — needs a display / xvfb:
##   godot --path . --script res://tests/shot_fields.gd
## Saves _fields_edit.png (field brush active) and _fields.png.

var f := 0
var game; var vm; var wear; var cam; var ctl; var fields
var spot := Vector2(-5.5, -4.5)

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
		cam = current_scene.get_node("Camera"); ctl = current_scene.get_node("BuildController"); fields = current_scene.get_node("Fields")
		game._autosave = false; game.delete_save(); game.new_game(); game.speed = 0.0
		game.resources["wood"] = 300; game.resources["stone"] = 300
		vm._first_sync()
		var id: int = ctl.try_place("farm", spot, 0.35)
		if id < 0:
			for k in 30:
				spot += Vector2(0.5, 0.3)
				id = ctl.try_place("farm", spot, 0.35)
				if id >= 0: break
		ctl.begin_field(id)
		for k in 7:
			ctl.brush_at(spot + Vector2(-1.5 + k * 0.6, 4.6).rotated(-0.35), true)
		_sim(25.0)
		cam.target = Vector3(spot.x + 0.8, 0.3, spot.y + 2.5); cam._dist = 11.0; cam._pitch = 0.75; cam._yaw = -0.35; cam._apply()
	if f == 12:
		root.get_viewport().get_texture().get_image().save_png("res://_fields_edit.png")
		ctl.cancel_place()
		cam._dist = 9.0; cam._pitch = 0.55; cam._yaw = 0.3; cam._apply()
	if f == 22:
		root.get_viewport().get_texture().get_image().save_png("res://_fields.png")
		game.delete_save(); wear.clear()
		quit()
	return false
