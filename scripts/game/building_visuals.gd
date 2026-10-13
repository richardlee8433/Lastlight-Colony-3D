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
static func create(type: String, seed_val: int) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new(); rng.seed = seed_val
	match type:
		"house": _house(root, rng)
		"woodcutter": _woodcutter(root, rng)
		"quarry": _quarry(root, rng)
		"farm": _farm(root, rng)
		"storehouse": _storehouse(root, rng)
	return root

static func _house(r: Node3D, rng: RandomNumberGenerator) -> void:
	var hut: Node3D = (load(HUT_SCENE) as PackedScene).instantiate()
	var s := rng.randf_range(0.5, 0.56)
	hut.scale = Vector3(s, s * rng.randf_range(0.95, 1.08), s)
	r.add_child(hut)

static func _woodcutter(r: Node3D, rng: RandomNumberGenerator) -> void:
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

static func _farm(r: Node3D, rng: RandomNumberGenerator) -> void:
	box(r, Vector3(3.7, 0.08, 3.7), Vector3(0, 0.03, 0), soil())
	var rows := 6
	for i in rows:
		var z := -1.5 + i * 0.6
		box(r, Vector3(3.3, 0.1, 0.22), Vector3(0, 0.1, z), soil())
		for k in 9:
			var x := -1.5 + k * 0.375 + rng.randf_range(-0.05, 0.05)
			var h := rng.randf_range(0.35, 0.55)
			var stem := cyl(r, 0.035, h, Vector3(x, 0.12 + h / 2, z), crop(), Vector3.ZERO, 5)
			stem.rotation = Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
			cyl(r, 0.06, 0.16, Vector3(x, 0.14 + h, z), wheat(), Vector3.ZERO, 5)
	# corner fence posts and a scarecrow
	for x in [-1.85, 1.85]:
		for z in [-1.85, 1.85]:
			cyl(r, 0.06, 0.7, Vector3(x, 0.35, z), wood())
	cyl(r, 0.05, 1.5, Vector3(1.3, 0.75, 1.3), wood_dark())
	cyl(r, 0.04, 0.9, Vector3(1.3, 1.15, 1.3), wood_dark(), Vector3(0, 0, PI / 2))
	var head := SphereMesh.new(); head.radius = 0.14; head.height = 0.28
	_add(r, head, wheat(), Vector3(1.3, 1.55, 1.3))
	var hat := CylinderMesh.new(); hat.top_radius = 0.05; hat.bottom_radius = 0.22; hat.height = 0.15
	_add(r, hat, thatch(), Vector3(1.3, 1.72, 1.3))

static func _storehouse(r: Node3D, rng: RandomNumberGenerator) -> void:
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

## Recursively applies a material override (used for the placement ghost).
static func override_all(n: Node, m: Material) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).material_override = m
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		override_all(c, m)
