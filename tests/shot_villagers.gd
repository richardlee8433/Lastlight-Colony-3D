extends SceneTree
## Renders a lineup of villagers close up (different looks and jobs) — needs a display / xvfb:
##   godot --path . --script res://tests/shot_villagers.gd
## Saves _villagers.png.

var f := 0
var game; var vm; var cam

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")

func _process(_d: float) -> bool:
	if current_scene == null: return false
	f += 1
	if f == 3:
		game = root.get_node("Game"); vm = current_scene.get_node("Villagers"); cam = current_scene.get_node("Camera")
		game._autosave = false; game.instant_build = true
		game.delete_save(); game.new_game(); game.speed = 0.0
		game.fresh_start = false
		game.population = 11
		vm._sync()
		var jobs := [{}, {"hat": "HatStraw", "tool": "Hoe"}, {}, {"hat": "Hood", "tool": "Axe"}, {},
			{"hat": "HatCap", "tool": "Pick"}, {}, {}, {}, {}, {}]
		var anims := ["idle", "hoe", "walk", "chop", "idle", "mine", "carry", "idle", "walk", "idle", "idle"]
		for i in vm.villagers.size():
			var v = vm.villagers[i]
			v.state = v.S.IDLE; v._timer = 999.0
			v.position = Vector3(-4.0 + i * 0.8, 0.0, 6.0)
			v.position.y = v.nav.height_at(v.position.x, v.position.z)
			v.rotation.y = PI + (0.35 if i % 2 == 0 else -0.3)
			v.set_outfit(jobs[i])
			if jobs[i].has("tool"): v._toggles[jobs[i]["tool"]].visible = true
			if anims[i] == "carry": v._set_carry("CarrySack")
			v._anim = anims[i]; v._look = Vector3.ZERO
			v._t = 0.3 + i * 0.37; v._phase = i * 0.9
			for k in 12: v._animate(0.05)
		current_scene.get_node("Scatter").clear_area(Vector2(0, 6.4), Vector2(4.5, 1.6), 0.0)
		cam.target = Vector3(0.0, 0.5, 6.0); cam._dist = 6.8; cam._pitch = 0.32; cam._yaw = 0.0; cam._apply()
	if f == 12:
		root.get_viewport().get_texture().get_image().save_png("res://_villagers.png")
		game.delete_save()
		quit()
	return false
