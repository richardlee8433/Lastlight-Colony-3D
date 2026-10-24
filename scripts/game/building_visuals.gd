class_name BuildingVisuals
## Builds the 3D look of each building type from primitives (plus the baked cottage for houses).
## Placeholder art in the same palette as the cottage; swap for baked Blender models later.

const HUT_SCENE := "res://models/hut.glb"

static var _mats := {}

static func mat(key: String, color: Color, rough := 0.9, noise_freq := 0.0) -> StandardMaterial3D:
	if _mats.has(key): return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if noise_freq > 0.0:
		var n := FastNoiseLite.new()
		n.frequency = noise_freq
		n.fractal_octaves = 4
		var t := NoiseTexture2D.new()
		t.noise = n; t.width = 256; t.height = 256; t.seamless = true
		var g := Gradient.new()
		g.set_color(0, Color(0.72, 0.72, 0.72)); g.set_color(1, Color(1.1, 1.1, 1.1))
		t.color_ramp = g
		m.albedo_texture = t
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(0.6, 0.6, 0.6)
	_mats[key] = m
	return m

static func thatch() -> StandardMaterial3D: return mat("thatch", Color(0.62, 0.46, 0.24), 0.95, 0.09)
static func wood() -> StandardMaterial3D: return mat("wood", Color(0.36, 0.24, 0.14), 0.85, 0.05)
static func wood_dark() -> StandardMaterial3D: return mat("wood_dark", Color(0.20, 0.13, 0.08), 0.85, 0.05)
static func stone() -> StandardMaterial3D: return mat("stone", Color(0.50, 0.49, 0.46), 0.9, 0.06)
static func soil() -> StandardMaterial3D: return mat("soil", Color(0.30, 0.20, 0.12), 0.95, 0.08)
static func crop() -> StandardMaterial3D: return mat("crop", Color(0.42, 0.55, 0.15), 0.85, 0.12)
static func wheat() -> StandardMaterial3D: return mat("wheat", Color(0.82, 0.66, 0.28), 0.85, 0.12)
static func plaster() -> StandardMaterial3D: return mat("plaster", Color(0.78, 0.70, 0.56), 0.95, 0.05)

static func _add(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi

static func box(p: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new(); b.size = size
	return _add(p, b, m, pos, rot)

static func cyl(p: Node3D, r: float, h: float, pos: Vector3, m: Material, rot := Vector3.ZERO, sides := 8) -> MeshInstance3D:
	var c := CylinderMesh.new(); c.top_radius = r; c.bottom_radius = r; c.height = h; c.radial_segments = sides; c.rings = 1
	return _add(p, c, m, pos, rot)

static func rock(p: Node3D, r: float, pos: Vector3, rng: RandomNumberGenerator) -> MeshInstance3D:
	var s := SphereMesh.new(); s.radius = r; s.height = r * 2; s.radial_segments = 7; s.rings = 4
	return _add(p, s, stone(), pos, Vector3(rng.randf() * 3, rng.randf() * 3, 0),
		Vector3(rng.randf_range(0.9, 1.4), rng.randf_range(0.55, 0.8), rng.randf_range(0.9, 1.3)))

static func roof(p: Node3D, w: float, d: float, h: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var pr := PrismMesh.new(); pr.size = Vector3(w, h, d)
	return _add(p, pr, m, pos)

## Returns a Node3D centred on the footprint, base at y=0.
static func create(type: String, seed_val: int, stage := 2) -> Node3D:
	if stage < 2:
		return construction(type, stage)
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new(); rng.seed = seed_val
	match type:
		"house": _house(root, rng)
		"woodcutter": _woodcutter(root, rng)
		"quarry": _quarry(root, rng)
		"farm": _farm(root, rng)
		"storehouse": _storehouse(root, rng)
		"cart": _cart(root, rng)
		"fishery": _fishery(root, rng)
	return root

const SITE_MODELS := ["res://models/site_0.glb", "res://models/site_1.glb"]

## A construction site (stage 0 foundation, 1 timber frame), built for 3 x 3 m and stretched to the footprint.
static func construction(type: String, stage: int) -> Node3D:
	var root := Node3D.new()
	var path: String = SITE_MODELS[clampi(stage, 0, 1)]
	var h := Defs.half_extents(type)
	if ResourceLoader.exists(path):
		var m: Node3D = (load(path) as PackedScene).instantiate()
		m.scale = Vector3(h.x / 1.5, minf(h.x, h.y) / 1.5, h.y / 1.5)
		root.add_child(m)
	else:
		box(root, Vector3(h.x * 2, 0.1, h.y * 2), Vector3(0, 0.05, 0), soil())
	return root

const HOUSE_VARIANTS := 6

static func _house(r: Node3D, rng: RandomNumberGenerator) -> void:
	# one of the baked variants (tools/house_variants.py), slightly resized
	var k := rng.randi() % HOUSE_VARIANTS
	var path := "res://models/houses/house_%d.glb" % k
	var house: Node3D
	if ResourceLoader.exists(path):
		house = (load(path) as PackedScene).instantiate()
		var s := rng.randf_range(0.95, 1.04)
		house.scale = Vector3(s * rng.randf_range(0.97, 1.03), s * rng.randf_range(0.96, 1.05), s)
	else:
		house = (load(HUT_SCENE) as PackedScene).instantiate()
		var s := rng.randf_range(0.5, 0.56)
		house.scale = Vector3(s, s, s)
	r.add_child(house)

static func _woodcutter(r: Node3D, rng: RandomNumberGenerator) -> void:
	# baked model (tools/buildings.py), same style as the village houses
	if _baked(r, "res://models/woodcutter.glb"): return
	_woodcutter_simple(r, rng)

## primitive fallback when the baked model is missing
static func _woodcutter_simple(r: Node3D, rng: RandomNumberGenerator) -> void:
	# open-sided shed with a thatched roof
	for x in [-0.9, 0.9]:
		for z in [-0.6, 0.6]:
			cyl(r, 0.07, 1.6, Vector3(x, 0.8, z), wood_dark())
	box(r, Vector3(2.0, 0.08, 1.4), Vector3(0, 0.04, 0), wood())
	box(r, Vector3(2.0, 1.0, 0.08), Vector3(0, 0.5, 0.62), plaster())
	roof(r, 2.5, 1.9, 0.9, Vector3(0, 2.05, 0), thatch())
	box(r, Vector3(2.2, 0.1, 0.12), Vector3(0, 1.62, -0.66), wood_dark())
	box(r, Vector3(2.2, 0.1, 0.12), Vector3(0, 1.62, 0.66), wood_dark())
	# log pile
	for row in 3:
		for i in 4 - row:
			cyl(r, 0.13, 1.1, Vector3(-0.2 + (i + row * 0.5) * 0.27 - 0.2, 0.13 + row * 0.22, -1.1), wood(), Vector3(0, 0, PI / 2))
	# chopping stump with a split log
	cyl(r, 0.25, 0.4, Vector3(1.05, 0.2, -1.0), wood_dark(), Vector3.ZERO, 10)
	cyl(r, 0.11, 0.45, Vector3(1.05, 0.55, -1.0), wood(), Vector3(0, 0, 0.2))

static func _quarry(r: Node3D, rng: RandomNumberGenerator) -> void:
	# baked quarry works (tools/buildings.py); the rock itself is the deposit (Deposits)
	if _baked(r, "res://models/quarry.glb"): return
	_quarry_simple(r, rng)

## primitive fallback when the baked model is missing
static func _quarry_simple(r: Node3D, rng: RandomNumberGenerator) -> void:
	# rock face
	for i in 9:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 0.9)
		rock(r, rng.randf_range(0.35, 0.7), Vector3(cos(a) * d - 0.2, 0.15, sin(a) * d * 0.7 - 0.4), rng)
	# cut blocks stacked
	for i in 5:
		var px := 0.7 + (i % 3) * 0.42
		var py := 0.18 + int(i / 3.0) * 0.34
		box(r, Vector3(0.38, 0.32, 0.38), Vector3(px, py, 0.8), stone(), Vector3(0, rng.randf_range(-0.2, 0.2), 0))
	# wooden hoist
	cyl(r, 0.06, 2.2, Vector3(-0.9, 1.1, 0.9), wood_dark())
	cyl(r, 0.05, 1.3, Vector3(-0.55, 2.05, 0.9), wood_dark(), Vector3(0, 0, -1.1))
	box(r, Vector3(0.3, 0.3, 0.3), Vector3(-0.15, 1.45, 0.9), stone())
	cyl(r, 0.01, 0.75, Vector3(-0.15, 1.85, 0.9), wood_dark())

const FARMHOUSE_SCENE := "res://models/farmhouse.glb"

static func _fishery(r: Node3D, _rng: RandomNumberGenerator) -> void:
	# baked fishing hut (tools/buildings.py); a plain shed as fallback
	if not _baked(r, "res://models/fishery.glb"):
		box(r, Vector3(2.0, 1.5, 1.3), Vector3(0, 0.75, -1.0), wood())

static func _baked(r: Node3D, path: String) -> bool:
	if not ResourceLoader.exists(path): return false
	r.add_child((load(path) as PackedScene).instantiate())
	return true

static func _farm(r: Node3D, rng: RandomNumberGenerator) -> void:
	# baked farmhouse (tools/farmhouse.py), same style as the village houses
	if ResourceLoader.exists(FARMHOUSE_SCENE):
		r.add_child((load(FARMHOUSE_SCENE) as PackedScene).instantiate())
		return
	_farm_simple(r, rng)

## primitive fallback when the baked model is missing
static func _farm_simple(r: Node3D, rng: RandomNumberGenerator) -> void:
	# farmhouse: a small timber-framed cottage with a thatched roof, a hay lean-to and
	# harvest sacks by the door. The field itself is painted on the ground (Fields).
	box(r, Vector3(2.35, 0.16, 1.55), Vector3(0, 0.08, -0.15), stone())
	box(r, Vector3(2.15, 1.25, 1.35), Vector3(-0.05, 0.78, -0.15), plaster())
	for x in [-1.1, 1.0]:
		for z in [-0.82, 0.52]:
			box(r, Vector3(0.12, 1.3, 0.12), Vector3(x, 0.8, z), wood_dark())
	box(r, Vector3(2.3, 0.1, 0.1), Vector3(-0.05, 1.42, 0.53), wood_dark())
	box(r, Vector3(2.3, 0.1, 0.1), Vector3(-0.05, 1.42, -0.83), wood_dark())
	box(r, Vector3(0.1, 0.9, 0.1), Vector3(-0.05, 0.85, 0.53), wood_dark(), Vector3(0, 0, 0.6))
	roof(r, 2.75, 2.05, 1.05, Vector3(-0.05, 1.98, -0.15), thatch())
	# door and a shuttered window facing the field (+z)
	box(r, Vector3(0.5, 0.85, 0.06), Vector3(0.45, 0.6, 0.55), wood())
	box(r, Vector3(0.36, 0.3, 0.06), Vector3(-0.55, 0.92, 0.55), wood_dark())
	box(r, Vector3(0.16, 0.32, 0.04), Vector3(-0.8, 0.92, 0.57), wood(), Vector3(0, 0.5, 0))
	# hay lean-to on the right
	for z in [-0.75, 0.45]:
		cyl(r, 0.05, 1.0, Vector3(1.38, 0.5, z), wood_dark())
	box(r, Vector3(0.55, 0.06, 1.45), Vector3(1.25, 1.02, -0.15), thatch(), Vector3(0, 0, -0.35))
	var hay := mat("hay", Color(0.80, 0.66, 0.30), 0.95, 0.15)
	for i in 2:
		cyl(r, 0.24, 0.42, Vector3(1.28, 0.24, -0.45 + i * 0.55), hay, Vector3(PI / 2, rng.randf_range(-0.2, 0.2), 0), 12)
	cyl(r, 0.22, 0.4, Vector3(1.28, 0.62, -0.18), hay, Vector3(PI / 2, 0.2, 0), 12)
	# harvest sacks and a hoe by the door
	for i in 3:
		var sack := SphereMesh.new(); sack.radius = 0.17; sack.height = 0.32
		_add(r, sack, wheat(), Vector3(-0.2 + i * 0.25 - (0.12 if i == 2 else 0.0), 0.17 + (0.24 if i == 2 else 0.0), 0.82),
			Vector3(0, rng.randf() * 3, 0), Vector3(1, 0.9, 0.85))
	cyl(r, 0.025, 1.2, Vector3(0.95, 0.58, 0.68), wood(), Vector3(0.25, 0, 0.12))
	box(r, Vector3(0.18, 0.05, 0.1), Vector3(0.88, 1.15, 0.53), stone())

static func soil_ridge() -> StandardMaterial3D: return mat("soil_ridge", Color(0.36, 0.25, 0.15), 0.95, 0.1)

static func _storehouse(r: Node3D, rng: RandomNumberGenerator) -> void:
	# baked model (tools/buildings.py), same style as the village houses
	if _baked(r, "res://models/storehouse.glb"): return
	_storehouse_simple(r, rng)

## primitive fallback when the baked model is missing
static func _storehouse_simple(r: Node3D, rng: RandomNumberGenerator) -> void:
	# open-fronted barn on a stone plinth, goods stacked inside, front = +z
	box(r, Vector3(2.7, 0.18, 2.3), Vector3(0, 0.09, -0.15), stone())
	for x in [-1.25, 0.0, 1.25]:
		for z in [-1.2, 0.9]:
			cyl(r, 0.08, 1.9, Vector3(x, 1.13, z), wood_dark())
	box(r, Vector3(2.6, 1.7, 0.08), Vector3(0, 1.03, -1.22), plaster())
	box(r, Vector3(0.08, 1.7, 2.1), Vector3(-1.27, 1.03, -0.15), plaster())
	box(r, Vector3(0.08, 1.7, 2.1), Vector3(1.27, 1.03, -0.15), plaster())
	box(r, Vector3(2.8, 0.12, 0.14), Vector3(0, 2.05, 0.92), wood_dark())
	box(r, Vector3(2.8, 0.12, 0.14), Vector3(0, 2.05, -1.22), wood_dark())
	roof(r, 3.2, 2.9, 1.1, Vector3(0, 2.62, -0.15), thatch())
	# goods: crates, sacks, barrels, a log stack
	for i in 3:
		box(r, Vector3(0.45, 0.4, 0.45), Vector3(-0.8 + i * 0.5, 0.38, -0.85), wood(), Vector3(0, rng.randf_range(-0.15, 0.15), 0))
	box(r, Vector3(0.42, 0.38, 0.42), Vector3(-0.55, 0.77, -0.85), wood(), Vector3(0, 0.3, 0))
	for i in 2:
		cyl(r, 0.22, 0.6, Vector3(0.85, 0.48, -0.75 + i * 0.5), wood_dark(), Vector3.ZERO, 12)
	for i in 3:
		var sack := SphereMesh.new(); sack.radius = 0.2; sack.height = 0.36
		_add(r, sack, wheat(), Vector3(-0.85 + i * 0.32, 0.36, -0.1), Vector3(0, rng.randf() * 3, 0), Vector3(1, 0.9, 0.8))
	for row in 2:
		for i in 3 - row:
			cyl(r, 0.1, 0.9, Vector3(0.45, 0.28 + row * 0.18, -0.2 + (i + row * 0.5) * 0.2), wood(), Vector3(PI / 2, 0, 0))
	# a sign
	cyl(r, 0.04, 1.1, Vector3(1.55, 0.55, 1.1), wood_dark())
	box(r, Vector3(0.5, 0.3, 0.05), Vector3(1.55, 1.0, 1.12), wood())

static func _cart(r: Node3D, rng: RandomNumberGenerator) -> void:
	# two-wheeled supply cart loaded with sacks, crates and barrels; a campfire with bedrolls beside it
	var cx := -0.5
	box(r, Vector3(1.7, 0.08, 1.0), Vector3(cx, 0.62, 0), wood())                     # bed
	for z in [-0.5, 0.5]:
		box(r, Vector3(1.7, 0.22, 0.06), Vector3(cx, 0.75, z), wood_dark())           # side boards
	box(r, Vector3(0.06, 0.22, 1.0), Vector3(cx - 0.85, 0.75, 0), wood_dark())
	for z in [-0.58, 0.58]:
		var wheel := cyl(r, 0.42, 0.08, Vector3(cx + 0.15, 0.42, z), wood_dark(), Vector3(PI / 2, 0, 0), 14)
		cyl(r, 0.1, 0.12, Vector3(cx + 0.15, 0.42, z), wood(), Vector3(PI / 2, 0, 0), 8)
		for k in 4:
			box(r, Vector3(0.05, 0.78, 0.03), Vector3(cx + 0.15, 0.42, z), wood(), Vector3(0, 0, k * PI / 4))
	cyl(r, 0.05, 1.2, Vector3(cx + 0.15, 0.42, 0), wood_dark(), Vector3(PI / 2, 0, 0))   # axle
	for z in [-0.3, 0.3]:                                                                # shafts resting on the ground
		cyl(r, 0.045, 1.1, Vector3(cx + 1.3, 0.34, z), wood(), Vector3(0, 0, 1.0))
	box(r, Vector3(0.5, 0.4, 0.45), Vector3(cx - 0.45, 0.9, -0.2), wood(), Vector3(0, 0.2, 0))
	box(r, Vector3(0.42, 0.35, 0.4), Vector3(cx - 0.4, 1.27, -0.15), wood(), Vector3(0, -0.15, 0))
	cyl(r, 0.2, 0.5, Vector3(cx + 0.35, 0.92, -0.22), wood_dark(), Vector3.ZERO, 12)
	for i in 3:
		var sack := SphereMesh.new(); sack.radius = 0.2; sack.height = 0.34
		_add(r, sack, mat("cart_sack", Color(0.72, 0.62, 0.42), 0.95), Vector3(cx - 0.3 + i * 0.32, 0.86, 0.25), Vector3(0, rng.randf() * 3, 0), Vector3(1, 0.85, 0.8))
	# a canvas tarp tied over part of the load
	var tarp := SphereMesh.new(); tarp.radius = 0.5; tarp.height = 1.0; tarp.radial_segments = 16; tarp.rings = 8
	_add(r, tarp, mat("canvas", Color(0.84, 0.80, 0.68), 0.9), Vector3(cx + 0.15, 0.7, -0.05), Vector3(0, 0.1, 0), Vector3(0.62, 0.42, 0.9))
	for k in 2:
		box(r, Vector3(0.03, 0.03, 1.02), Vector3(cx + 0.0 + k * 0.32, 0.98 - absf(k - 0.5) * 0.1, -0.05), mat("rope_c", Color(0.45, 0.35, 0.2), 0.9))
	# campfire: ring of stones, logs, glowing embers, a pot on a tripod
	var fx := 1.3; var fz := 1.0
	for k in 8:
		var a := k * TAU / 8
		rock(r, 0.09, Vector3(fx + cos(a) * 0.3, 0.05, fz + sin(a) * 0.3), rng)
	for k in 3:
		cyl(r, 0.05, 0.5, Vector3(fx, 0.08, fz), wood_dark(), Vector3(PI / 2, k * PI / 3, 0.15))
	var ember := SphereMesh.new(); ember.radius = 0.13; ember.height = 0.12
	var em := StandardMaterial3D.new(); em.albedo_color = Color(1.0, 0.45, 0.12); em.emission_enabled = true
	em.emission = Color(1.0, 0.4, 0.1); em.emission_energy_multiplier = 2.5
	_add(r, ember, em, Vector3(fx, 0.08, fz))
	var light := OmniLight3D.new(); light.light_color = Color(1.0, 0.6, 0.3); light.light_energy = 0.8; light.omni_range = 3.0
	light.position = Vector3(fx, 0.5, fz); r.add_child(light)
	for k in 3:
		var a := k * TAU / 3
		cyl(r, 0.02, 0.9, Vector3(fx + cos(a) * 0.18, 0.4, fz + sin(a) * 0.18), wood_dark(), Vector3(sin(a) * 0.35, 0, -cos(a) * 0.35))
	cyl(r, 0.12, 0.16, Vector3(fx, 0.55, fz), mat("pot", Color(0.12, 0.12, 0.12), 0.5), Vector3.ZERO, 10)
	# bedrolls around the fire
	for e in [[2.0, 1.6, 0.4], [0.55, 1.85, -0.3], [2.05, 0.35, 1.2]]:
		box(r, Vector3(0.55, 0.08, 0.95), Vector3(e[0], 0.04, e[1]), mat("bedroll", Color(0.48, 0.30, 0.22), 0.95), Vector3(0, e[2], 0))
		cyl(r, 0.09, 0.55, Vector3(e[0] + sin(e[2]) * 0.42, 0.09, e[1] + cos(e[2]) * 0.42), mat("bedroll2", Color(0.62, 0.52, 0.36), 0.95), Vector3(0, e[2], PI / 2))

## Recursively applies a material override (used for the placement ghost).
static func override_all(n: Node, m: Material) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).material_override = m
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		override_all(c, m)
