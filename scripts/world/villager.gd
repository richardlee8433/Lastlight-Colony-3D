class_name Villager
extends Node3D
## One villager: a puppet model animated in code plus a small state machine.
## The VillagerManager decides home and job; the villager walks, works, carries and rests.

const MODEL := preload("res://models/villager.glb")

const SKIN := [Color(0.95, 0.78, 0.64), Color(0.88, 0.67, 0.52), Color(0.74, 0.54, 0.40), Color(0.56, 0.39, 0.28)]
## colony jumpsuits: survey orange, hull white, slate, olive, ochre, teal (the legs match the suit)
## pressure suits: mostly white and pale grey, some in survey orange; the trims carry a crew colour
const TUNIC := [Color(0.88, 0.88, 0.85), Color(0.92, 0.91, 0.88), Color(0.80, 0.81, 0.80), Color(0.72, 0.73, 0.74),
	Color(0.88, 0.48, 0.18), Color(0.86, 0.86, 0.80)]
const CREW := [Color(0.86, 0.42, 0.14), Color(0.20, 0.46, 0.60), Color(0.78, 0.62, 0.22), Color(0.20, 0.50, 0.46),
	Color(0.62, 0.22, 0.22), Color(0.36, 0.30, 0.56)]
const PANTS := [Color(0.22, 0.23, 0.25), Color(0.30, 0.31, 0.33)]
const HAIR := [Color(0.20, 0.12, 0.06), Color(0.36, 0.22, 0.10), Color(0.09, 0.07, 0.06), Color(0.66, 0.50, 0.25), Color(0.55, 0.24, 0.10)]
const HOODS := [Color(0.88, 0.88, 0.85), Color(0.90, 0.62, 0.12), Color(0.86, 0.40, 0.12)]
const SKIRTS := [Color(0.36, 0.26, 0.32), Color(0.30, 0.34, 0.46), Color(0.46, 0.34, 0.22), Color(0.30, 0.38, 0.28), Color(0.55, 0.26, 0.22)]
const APRONS := [Color(0.20, 0.21, 0.23), Color(0.85, 0.85, 0.82), Color(0.30, 0.32, 0.34)]   # chest rigs
const VESTS := [Color(0.22, 0.24, 0.27), Color(0.32, 0.34, 0.30), Color(0.18, 0.20, 0.24)]
const KERCHIEFS := [Color(0.12, 0.12, 0.13), Color(0.22, 0.23, 0.25)]          # comm headsets
## every optional piece of the model (shown per look / job)
const OPTIONAL := ["Hair0", "Hair1", "Hair2", "Hair3", "Hair4", "Hair5", "Hair6", "Beard0", "Beard1",
	"Hem", "HemTrim", "Skirt", "SkirtTrim", "Apron", "Vest", "Satchel", "Kerchief",
	"HatStraw", "HatCap", "Hood", "Axe", "Pick", "Hoe", "Rod", "CarryLog", "CarryStone", "CarrySack", "CarryFish"]
const NAMES_EN := ["Ade", "Mira", "Kenji", "Sofia", "Ravi", "Lena", "Tomas", "Yara", "Idris", "Noor", "Felix", "Aiko",
	"Mateo", "Zara", "Oskar", "Priya", "Jonah", "Hana", "Leif", "Amara"]
const NAMES_ZH := ["艾德", "米拉", "健司", "蘇菲", "拉維", "莉娜", "托馬", "雅拉", "伊德", "努爾", "菲力", "愛子",
	"馬提", "莎拉", "奧斯", "普莉", "約拿", "花子", "雷夫", "阿瑪"]

enum S { IDLE, WANDER, ARRIVE, TO_WORK, WORK, TO_DROP, DROP, TO_HOME, REST, LEAVE }

var vid := 0
var vname: String:                 # display name in the current language
	get: return (NAMES_ZH if Loc.lang == "zh" else NAMES_EN)[(vid - 1) % NAMES_EN.size()]
var state := S.IDLE
var home := Vector2.ZERO
var job_id := -1                  # building id, -1 = no job
var deliveries := 0
var carrying := ""                # node name of the carried item, "" = none
var goods := {}                   # what is being carried, e.g. {"wood": 6}
var _drop_at := Vector2.ZERO      # storage point of the current delivery
var manager: Node                 # VillagerManager
var nav: NavGrid
var wear: PathWear

var _path := PackedVector3Array()
var _path_i := 0
var _dest := Vector3.ZERO
var _look := Vector3.ZERO         # where to face while working / idling
var _timer := 0.0
var _anim := "idle"
var _phase := 0.0
var _lane := 0.0
var _yaw := 0.0
var _head_yaw_target := 0.0
var _head_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _fail := 0

# parts
var _model: Node3D
var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _toggles := {}                # name -> Node3D (tools, hats, hair, carry items)
var _eyes: Array[Node3D] = []
var _blink := 0.0                 # seconds until the next blink
var _skirt := false
var _kerchief := false

func setup(id: int, mgr: Node, nav_grid: NavGrid, path_wear: PathWear) -> void:
	vid = id; manager = mgr; nav = nav_grid; wear = path_wear
	_rng.seed = id * 92821 + 17
	_lane = _rng.randf_range(-0.16, 0.16)
	_build_model()

func _build_model() -> void:
	_model = MODEL.instantiate()
	add_child(_model)
	_torso = _model.find_child("Torso", true, false)
	_head = _model.find_child("Head", true, false)
	_arm_l = _model.find_child("ArmL", true, false)
	_arm_r = _model.find_child("ArmR", true, false)
	_leg_l = _model.find_child("LegL", true, false)
	_leg_r = _model.find_child("LegR", true, false)
	for n in OPTIONAL:
		var node := _model.find_child(n, true, false)
		if node:
			_toggles[n] = node
			node.visible = false
	for n in ["EyeL", "EyeR"]:
		var e := _model.find_child(n, true, false)
		if e: _eyes.append(e)
	_blink = _rng.randf_range(0.5, 4.0)
	_pick_look()

## A look per villager: hair, beard, skirt or tunic, apron / vest / satchel, kerchief, colours, build.
func _pick_look() -> void:
	var hair_i: int = [0, 0, 1, 5, 5, 6][_rng.randi() % 6]     # styles that fit inside the helmet
	var hair := "Hair%d" % hair_i
	_show(hair); _toggles["_hair"] = _toggles.get(hair)
	if hair_i != 1 and _rng.randf() < 0.3: _show("Beard1")    # moustaches only: full beards fill the visor
	_skirt = false                     # jumpsuits all round
	if _skirt: _show("Skirt"); _show("SkirtTrim")
	else: _show("Hem"); _show("HemTrim")
	var layer := _rng.randf()
	if layer < 0.32: _show("Apron")
	elif layer < 0.58: _show("Vest")
	_show("Satchel")                                  # everyone carries a life-support pack
	_kerchief = _rng.randf() < 0.5                   # comm antenna on the helmet
	if _kerchief: _show("Kerchief")
	var skin: Color = SKIN[_rng.randi() % SKIN.size()]
	var tunic: Color = TUNIC[_rng.randi() % TUNIC.size()]
	var pants: Color = tunic.darkened(0.08)
	var hair_c: Color = HAIR[_rng.randi() % HAIR.size()]
	if hair_i == 6 or _rng.randf() < 0.1: hair_c = Color(0.62, 0.60, 0.57)        # some grey-haired elders
	var hood_c: Color = HOODS[_rng.randi() % HOODS.size()]
	var trim: Color = CREW[_rng.randi() % CREW.size()]
	_tint(["Head", "Neck", "Nose", "EarL", "EarR"], skin)
	_tint(["HandL", "HandR"], Color(0.30, 0.31, 0.33))               # gloves
	_tint(["Helmet"], tunic.lerp(Color(0.95, 0.95, 0.93), 0.6))
	_glass(["HelmetGlass"], Color(0.55, 0.75, 0.85, 0.16), 0.2)
	_glass(["Hood"], Color(0.85, 0.62, 0.22, 0.92), 0.9)              # gold sun visor (harvesters)
	_tint(["Torso", "ArmL", "ArmR", "Hem"], tunic, true)
	_tint(["Satchel"], Color(0.82, 0.83, 0.80))
	_tint(["HemTrim", "SkirtTrim", "Collar", "CuffL", "CuffR"], trim, true)
	_tint(["LegL", "LegR"], pants, true)
	_tint(["Hair0", "Hair1", "Hair2", "Hair3", "Hair4", "Hair5", "Hair6", "Beard0", "Beard1", "BrowL", "BrowR"], hair_c)
	_tint(["HatCap"], hood_c, true)
	_tint(["Skirt"], SKIRTS[_rng.randi() % SKIRTS.size()], true)
	_tint(["Apron"], APRONS[_rng.randi() % APRONS.size()], true)
	_tint(["Vest"], VESTS[_rng.randi() % VESTS.size()], true)
	_tint(["Kerchief"], KERCHIEFS[_rng.randi() % KERCHIEFS.size()], true)
	_tint(["CheekL", "CheekR"], skin.lerp(Color(0.95, 0.45, 0.42), 0.55))
	# build: a little taller or shorter, slimmer or stockier
	var h := _rng.randf_range(0.92, 1.07)
	var w := h * _rng.randf_range(0.92, 1.1)
	_model.scale = Vector3(w, h, w)

## glossy see-through material for helmet glass / sun visors
func _glass(names: Array, c: Color, metal: float) -> void:
	var key := "glass" + c.to_html()
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.metallic = metal; m.roughness = 0.05; m.metallic_specular = 0.9
		m.cull_mode = BaseMaterial3D.CULL_BACK
		_mat_cache[key] = m
	for n in names:
		var mi := _model.find_child(n, true, false) as MeshInstance3D
		if mi:
			mi.material_override = _mat_cache[key]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _show(n: String) -> void:
	if _toggles.has(n): (_toggles[n] as Node3D).visible = true

static var _mat_cache := {}
static var _fabric: Texture2D
## a soft woven-cloth texture shared by all clothing (triplanar, so no UVs needed)
static func fabric() -> Texture2D:
	if _fabric == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.frequency = 0.09; n.seed = 5
		var g := Gradient.new()
		g.set_color(0, Color(0.88, 0.88, 0.88)); g.set_color(1, Color(1, 1, 1))
		var t := NoiseTexture2D.new()
		t.noise = n; t.color_ramp = g; t.seamless = true; t.width = 128; t.height = 128
		_fabric = t
	return _fabric

func _tint(names: Array, c: Color, cloth := false) -> void:
	var key := c.to_html() + ("c" if cloth else "")
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9 if cloth else 0.7
		if cloth:
			m.albedo_texture = fabric()
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(9, 9, 9)
		_mat_cache[key] = m
	for n in names:
		var mi := _model.find_child(n, true, false) as MeshInstance3D
		if mi: mi.material_override = _mat_cache[key]

# ---------------- outfit ----------------

func set_outfit(job: Dictionary) -> void:
	for n in ["HatStraw", "HatCap", "Hood", "Axe", "Pick", "Hoe", "Rod"]:
		_toggles[n].visible = false
	var hat: String = job.get("hat", "")
	if _toggles.has("Kerchief"): (_toggles["Kerchief"] as Node3D).visible = _kerchief
	if hat != "": _toggles[hat].visible = true

func _show_tool(on: bool) -> void:
	var job: Dictionary = manager.job_of(self) if manager else {}
	for n in ["Axe", "Pick", "Hoe", "Rod"]:
		_toggles[n].visible = on and job.get("tool", "") == n

func _set_carry(item: String) -> void:
	carrying = item
	for n in ["CarryLog", "CarryStone", "CarrySack", "CarryFish"]:
		_toggles[n].visible = (n == item)

# ---------------- commands from the manager ----------------

func place_at(p: Vector2) -> void:
	var q := nav.walkable_point(p)
	position = nav.on_ground(q)

func arrive_from(spawn: Vector2) -> void:
	place_at(spawn)
	_go(nav.on_ground(Game.center() + Vector2(_rng.randf_range(-1.5, 1.5), 2.0)), S.ARRIVE)

func leave(exit: Vector2) -> void:
	job_id = -1
	_set_carry(""); _show_tool(false); set_outfit({})
	_go(nav.on_ground(exit), S.LEAVE)

func assign_job(id: int) -> void:
	job_id = id
	deliveries = 0
	_set_carry("")
	set_outfit(manager.job_of(self))
	_start_work_trip()

func clear_job() -> void:
	job_id = -1
	_show_tool(false); set_outfit({})
	if not goods.is_empty() and state in [S.TO_DROP, S.DROP]:
		return                    # finish the delivery first, then wander
	goods = {}
	_set_carry("")
	_start_wander(0.5)

func repath() -> void:
	if _is_walking():
		_go(_dest, state)

# ---------------- state machine ----------------

func tick(dt: float) -> void:
	match state:
		S.IDLE, S.REST, S.DROP, S.WORK:
			_timer -= dt
			if _timer <= 0.0: _on_timer()
		_:
			_walk(dt)
	_animate(dt)

func _is_walking() -> bool:
	return state in [S.WANDER, S.ARRIVE, S.TO_WORK, S.TO_DROP, S.TO_HOME, S.LEAVE]

func _go(target: Vector3, s: S) -> void:
	state = s
	_dest = target
	_path = nav.find_path(position, target, _lane)
	_path_i = 1
	if _path.size() < 2:
		_fail += 1
		if _fail > 2:
			# give up on this target: snap to a walkable spot and idle a moment
			_fail = 0
			place_at(Vector2(position.x, position.z))
			_path = PackedVector3Array()
			_arrived()
		else:
			_path = PackedVector3Array([position, target]) if position.distance_to(target) < 0.8 else PackedVector3Array()
			if _path.is_empty():
				state = S.IDLE; _timer = 0.6; _retry_state = s
	else:
		_fail = 0

var _retry_state := S.IDLE

func _walk(dt: float) -> void:
	if _path.size() < 2 or _path_i >= _path.size():
		_arrived()
		return
	var speed: float = Defs.VILLAGER["speed"] * (0.75 if state == S.WANDER else 1.0) * (0.9 if carrying != "" else 1.0)
	var remaining := speed * dt
	while remaining > 0.0 and _path_i < _path.size():
		var target := _path[_path_i]
		var to := Vector2(target.x - position.x, target.z - position.z)
		var d := to.length()
		if d <= remaining:
			position = Vector3(target.x, 0, target.z)
			remaining -= d
			_path_i += 1
		else:
			var step := to / d * remaining
			position += Vector3(step.x, 0, step.y)
			remaining = 0.0
			_face(atan2(-to.x, -to.y), dt)
	position.y = nav.height_at(position.x, position.z)
	if wear:
		var k := 0.45 if state == S.WANDER else 1.0
		wear.deposit(position, float(Defs.PATHS["deposit"]) * dt * k)
	_anim = "carry" if carrying != "" else "walk"
	if _path_i >= _path.size():
		_arrived()

func _face(target_yaw: float, dt: float) -> void:
	_yaw = lerp_angle(_yaw, target_yaw, clampf(dt * 9.0, 0.0, 1.0))
	rotation.y = _yaw

func _face_point(p: Vector3, dt: float) -> void:
	var d := Vector2(p.x - position.x, p.z - position.z)
	if d.length() > 0.05:
		_face(atan2(-d.x, -d.y), dt)

func _arrived() -> void:
	match state:
		S.ARRIVE:
			_start_wander(1.0)
		S.WANDER:
			state = S.IDLE
			_timer = _rng.randf_range(2.0, 6.0)
			_anim = "idle"
		S.TO_WORK:
			state = S.WORK
			_timer = Defs.VILLAGER["work_time"] * _rng.randf_range(0.85, 1.2)
			_anim = manager.job_of(self).get("anim", "idle")
			_show_tool(true)
		S.TO_DROP:
			state = S.DROP
			_timer = Defs.VILLAGER["drop_time"]
			_anim = "drop"
		S.TO_HOME:
			state = S.REST
			_timer = Defs.VILLAGER["rest_time"]
			_anim = "idle"
			_look = position + (position - nav.on_ground(home)).normalized()
		S.LEAVE:
			manager.villager_left(self)
		_:
			state = S.IDLE; _timer = 1.0; _anim = "idle"

func _on_timer() -> void:
	match state:
		S.IDLE:
			if _retry_state != S.IDLE:
				var s := _retry_state; _retry_state = S.IDLE
				_go(_dest, s)
			elif job_id >= 0:
				_start_work_trip()
			else:
				_start_wander(0.0)
		S.WORK:
			_show_tool(false)
			var job: Dictionary = manager.job_of(self)
			_set_carry(job.get("carry", ""))
			goods = manager.yield_of(self)
			if goods.is_empty():
				# nothing came of it (tree already gone, field erased...): look for other work
				_set_carry("")
				_start_work_trip()
				return
			var st: Dictionary = manager.nearest_storage(Vector2(position.x, position.z))
			_drop_at = st["drop"]
			_look = nav.on_ground(st["look"])
			_go(nav.on_ground(_drop_at), S.TO_DROP)
		S.DROP:
			for r in goods:
				Game.deliver(r, int(goods[r]), _drop_at)
			goods = {}
			_set_carry("")
			deliveries += 1
			if job_id < 0:
				_start_wander(0.0)
			elif deliveries % int(Defs.VILLAGER["rest_every"]) == 0:
				_go(nav.on_ground(home), S.TO_HOME)
			else:
				_start_work_trip()
		S.REST:
			if job_id >= 0: _start_work_trip()
			else: _start_wander(0.0)

func _start_work_trip() -> void:
	if job_id < 0:
		_start_wander(0.0); return
	var t: Dictionary = manager.work_target(self)
	if t.is_empty():
		state = S.IDLE; _timer = 2.0; _anim = "idle"; return
	_look = t["look"]
	_go(t["pos"], S.TO_WORK)

func _start_wander(delay: float) -> void:
	if delay > 0.0:
		state = S.IDLE; _timer = delay; _anim = "idle"; return
	if _rng.randf() < 0.18:
		# now and then a stroll down to the water to look at it for a while
		var spot := Fishing.shore_near(nav, home, 16.0, _rng)
		if not spot.is_empty():
			_look = nav.on_ground(spot["look"])
			_go(nav.on_ground(spot["pos"]), S.WANDER)
			return
	var center := home if _rng.randf() < 0.7 else Game.center()
	var p := center + Vector2(_rng.randf_range(-4.5, 4.5), _rng.randf_range(-4.5, 4.5))
	var bb: Rect2 = Defs.BUILD_BOUNDS
	p = Vector2(clampf(p.x, bb.position.x, bb.end.x), clampf(p.y, bb.position.y, bb.end.y))
	_look = Vector3.ZERO
	_go(nav.on_ground(nav.walkable_point(p)), S.WANDER)

# ---------------- animation ----------------

var _t := 0.0
func _animate(dt: float) -> void:
	_t += dt
	var la := 0.0; var ra := 0.0; var lz := 0.0; var rz := 0.0
	var ll := 0.0; var rl := 0.0; var lean := 0.0; var bob := 0.0; var head_x := 0.0
	var k := clampf(dt * 14.0, 0.0, 1.0)
	match _anim:
		"walk", "carry":
			var f := 1.75 if _anim == "walk" else 1.55
			_phase += dt * TAU * f * (0.8 if state == S.WANDER else 1.0)
			var s := sin(_phase)
			ll = 0.55 * s; rl = -0.55 * s
			bob = 0.028 * absf(cos(_phase))
			lean = 0.07
			if _anim == "walk":
				la = -0.42 * s; ra = 0.42 * s
				lz = 0.06; rz = -0.06
			else:
				la = 1.05; ra = 1.05; lz = -0.22; rz = 0.22
				ll *= 0.8; rl *= 0.8
			k = clampf(dt * 22.0, 0.0, 1.0)
		"chop", "mine":
			var period := 1.25 if _anim == "chop" else 1.05
			var u := fmod(_t, period) / period
			var raise := 0.0
			if u < 0.55: raise = ease(u / 0.55, 0.6)                  # wind up
			elif u < 0.68: raise = 1.0 - ease((u - 0.55) / 0.13, 2.4)  # strike
			else: raise = 0.0
			var top := 3.0 if _anim == "chop" else 2.7
			la = lerpf(0.55, top, raise); ra = la
			lz = -0.32; rz = 0.32
			lean = lerpf(0.42 if _anim == "mine" else 0.3, -0.12, raise)
			ll = 0.25; rl = -0.18
			head_x = lerpf(0.25, -0.15, raise)
			k = clampf(dt * 30.0, 0.0, 1.0)
			if _look != Vector3.ZERO: _face_point(_look, dt)
		"hoe":
			var u := fmod(_t, 1.4) / 1.4
			var raise := 0.0
			if u < 0.5: raise = ease(u / 0.5, 0.7)
			elif u < 0.7: raise = 1.0 - ease((u - 0.5) / 0.2, 2.0)
			la = lerpf(0.35, 1.7, raise); ra = la
			lz = -0.3; rz = 0.3
			lean = lerpf(0.38, 0.12, raise)
			ll = 0.3; rl = -0.2
			head_x = 0.2
			k = clampf(dt * 24.0, 0.0, 1.0)
			if _look != Vector3.ZERO: _face_point(_look, dt)
		"fish":
			# rod held out over the water; now and then a tug and a little lift
			var u := fmod(_t + float(vid) * 0.7, 5.0)
			var tug := 0.0
			if u > 4.2: tug = sin((u - 4.2) / 0.8 * PI)
			ra = 0.95 + 0.04 * sin(_t * 1.3) + tug * 0.45
			la = 0.75 + tug * 0.35
			lz = -0.18; rz = 0.12
			lean = 0.05 - tug * 0.08
			head_x = 0.25
			bob = 0.004 * sin(_t * 2.0)
			k = clampf(dt * 10.0, 0.0, 1.0)
			if _look != Vector3.ZERO: _face_point(_look, dt)
		"drop":
			lean = 0.45; la = 0.9; ra = 0.9; lz = -0.2; rz = 0.2; head_x = 0.3
			if _look != Vector3.ZERO: _face_point(_look, dt)
		_:
			# idle: breathe, look around
			bob = 0.006 * sin(_t * 2.2)
			la = 0.04; ra = 0.04; lz = 0.07; rz = -0.07
			_head_timer -= dt
			if _head_timer <= 0.0:
				_head_timer = _rng.randf_range(1.5, 4.0)
				_head_yaw_target = _rng.randf_range(-0.7, 0.7)
			if _look != Vector3.ZERO and (state == S.REST or state == S.IDLE): _face_point(_look, dt)
	if _skirt: ll *= 0.75; rl *= 0.75                 # shorter steps in a long skirt
	# blink now and then
	_blink -= dt
	var lid := 1.0
	if _blink < 0.0:
		lid = 0.12
		if _blink < -0.11: _blink = _rng.randf_range(2.0, 5.5)
	for e in _eyes: e.scale.y = lerpf(e.scale.y, lid, clampf(dt * 40.0, 0.0, 1.0))
	_arm_l.rotation.x = lerpf(_arm_l.rotation.x, la, k)
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, ra, k)
	_arm_l.rotation.z = lerpf(_arm_l.rotation.z, lz, k)
	_arm_r.rotation.z = lerpf(_arm_r.rotation.z, rz, k)
	_leg_l.rotation.x = lerpf(_leg_l.rotation.x, ll, k)
	_leg_r.rotation.x = lerpf(_leg_r.rotation.x, rl, k)
	# torso and head point up, so a forward lean is a negative X rotation
	_torso.rotation.x = lerpf(_torso.rotation.x, -lean, k)
	_head.rotation.x = lerpf(_head.rotation.x, -head_x, k)
	var hy := _head_yaw_target if _anim == "idle" else 0.0
	_head.rotation.y = lerpf(_head.rotation.y, hy, clampf(dt * 3.0, 0.0, 1.0))
	_model.position.y = lerpf(_model.position.y, bob, k)

func status_text() -> String:
	match state:
		S.TO_WORK: return Loc.t("Going to work")
		S.WORK:
			match _anim:
				"chop": return Loc.t("Cutting fibre")
				"mine": return Loc.t("Drilling")
				"hoe": return Loc.t("Tending crops")
				"fish": return Loc.t("Netting")
			return Loc.t("Working")
		S.TO_DROP, S.DROP: return Loc.t("Hauling")
		S.TO_HOME, S.REST: return Loc.t("Resting at home")
		S.ARRIVE: return Loc.t("Just arrived")
		S.LEAVE: return Loc.t("Leaving the colony")
	return Loc.t("Strolling")
