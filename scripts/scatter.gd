extends Node3D
## Grass tufts and flower clumps, grown procedurally in square chunks — nearest to the camera
## first, a few per frame — so a big map costs little up front. Each chunk is one MultiMesh per
## kind that fades out with distance (far away the meadow colour of the ground takes over).
## Instances are hidden under buildings / fields and flattened where villagers wear a road.

const KINDS := {
	"tuft": {"model": "res://models/tuft.glb", "tint": true, "per_m2": 40.0, "scale": Vector2(0.5, 1.15)},
	"flower_petal_v": {"model": "res://models/flower_petal_v.glb", "tint": false, "per_m2": 3.2, "scale": Vector2(0.8, 1.4)},
	"flower_petal_w": {"model": "res://models/flower_petal_w.glb", "tint": false, "per_m2": 1.6, "scale": Vector2(0.8, 1.3)},
}
const TUFT_SHADER := preload("res://scripts/world/grass_tuft.gdshader")
const CHUNK := 8.0                       # metres
const GROUND_HALF := 40.0                # grass grows out under the border forest too
const BUCKET := 0.5                      # trample / field buckets: the zone grid
const VIEW_RANGE := 90.0                 # chunks fade out beyond this distance (past the camera's max zoom)
const BUILD_BUDGET_MS := 6.0             # chunk generation per frame

@export var nav_path: NodePath = ^"../Nav"

var _meshes := {}                        # kind -> Mesh
var _chunks := {}                        # Vector2i -> {kind: {"mmi", "xf": Array[Transform3D], "bucket": PackedInt32Array, "hidden": PackedByteArray}}
var _queue: Array[Vector2i] = []         # chunks still to grow
var _buckets := {}                       # bucket -> Array of [chunk key, kind, index]
var _trample := {}                       # bucket -> 0..1 grass scale (1 = untouched)
var _field := {}                         # buckets covered by farm fields (grass removed)
var _areas: Array = []                   # [centre, half, angle] footprints with no grass
var _flower_noise := FastNoiseLite.new()
var _nav: Node
var _bw := 0
var _origin := Vector2.ZERO

func _ready() -> void:
	for kind in KINDS:
		var src: Node = (load(KINDS[kind]["model"]) as PackedScene).instantiate()
		_meshes[kind] = _find_mesh(src)
		src.queue_free()
	_flower_noise.seed = 11
	_flower_noise.frequency = 0.09
	_bw = Defs.ZONE["w"]; _origin = Defs.ZONE["origin"]
	var n := ceili(2.0 * GROUND_HALF / CHUNK)
	for j in n:
		for i in n:
			_queue.append(Vector2i(i, j))
	call_deferred("_start")

func _start() -> void:
	_nav = get_node_or_null(nav_path)
	# grow the village area right away; the rest follows a few chunks per frame
	grow_around(Defs.CART_SPOT, 22.0)

func _find_mesh(n: Node) -> Mesh:
	if n is MeshInstance3D:
		return (n as MeshInstance3D).mesh
	for c in n.get_children():
		var m := _find_mesh(c)
		if m: return m
	return null

func _process(_d: float) -> void:
	if _queue.is_empty() or _nav == null: return
	var focus := Vector2.ZERO
	var cam := get_viewport().get_camera_3d()
	if cam:
		var t = cam.get("target")
		focus = Vector2(t.x, t.z) if t is Vector3 else Vector2(cam.global_position.x, cam.global_position.z)
	_queue.sort_custom(func(a, b): return _chunk_center(a).distance_squared_to(focus) < _chunk_center(b).distance_squared_to(focus))
	var t0 := Time.get_ticks_usec()
	while not _queue.is_empty() and (Time.get_ticks_usec() - t0) < BUILD_BUDGET_MS * 1000.0:
		_grow_chunk(_queue.pop_front())

## Grow every chunk within `radius` of p now (startup, tests).
func grow_around(p: Vector2, radius: float) -> void:
	if _nav == null: _nav = get_node_or_null(nav_path)
	for key in _queue.duplicate():
		if _chunk_center(key).distance_to(p) <= radius + CHUNK * 0.71:
			_queue.erase(key)
			_grow_chunk(key)

func chunks_grown() -> int:
	return _chunks.size()

func _chunk_center(key: Vector2i) -> Vector2:
	return Vector2(-GROUND_HALF + (key.x + 0.5) * CHUNK, -GROUND_HALF + (key.y + 0.5) * CHUNK)

func _bucket_of(x: float, z: float) -> int:
	var i := floori((x - _origin.x) / BUCKET); var j := floori((z - _origin.y) / BUCKET)
	if i < 0 or j < 0 or i >= _bw or j >= _bw: return -1
	return j * _bw + i

# ---------------- growing ----------------

func _grow_chunk(key: Vector2i) -> void:
	if _chunks.has(key): return
	var rng := RandomNumberGenerator.new()
	rng.seed = key.x * 92821 + key.y * 68917 + 7
	var x0 := -GROUND_HALF + key.x * CHUNK; var z0 := -GROUND_HALF + key.y * CHUNK
	var map_half: float = Defs.MAP_HALF
	var entry := {}
	for kind in KINDS:
		var cfg: Dictionary = KINDS[kind]
		var flower: bool = not cfg["tint"]
		var count := int(cfg["per_m2"] * CHUNK * CHUNK * (1.0 if flower else 1.0))
		var xfs: Array[Transform3D] = []
		var cols: Array[Color] = []
		var buckets := PackedInt32Array()
		for n in count:
			var x := x0 + rng.randf() * CHUNK
			var z := z0 + rng.randf() * CHUNK
			var outside := absf(x) > map_half or absf(z) > map_half
			if outside and rng.randf() < 0.5: continue          # thinner under the border forest
			if flower:
				# flowers grow in patches
				var m := _flower_noise.get_noise_2d(x, z)
				if m < 0.12 or rng.randf() > (m - 0.12) * 2.4: continue
			if _nav and _nav.scenery_at(Vector2(x, z)) and not outside: continue
			if Water.sample(Vector2(x, z)).y > 0.35: continue                   # no grass in the water or on wet banks
			var y: float = _nav.height_at(clampf(x, -map_half + 0.1, map_half - 0.1), clampf(z, -map_half + 0.1, map_half - 0.1)) if _nav else 0.0
			var lush := Meadow.sample(x, z)
			var s := rng.randf_range(cfg["scale"].x, cfg["scale"].y)
			var b := Basis(Vector3.UP, rng.randf() * TAU)
			b = Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.08)) * b
			if cfg["tint"]:
				b = b.scaled(Vector3(s, s * lerpf(0.7, 1.45, lush), s))
				var c := Meadow.grass_color(clampf(lush + rng.randf_range(-0.12, 0.12), 0.0, 1.0))
				cols.append(c.darkened(rng.randf_range(0.0, 0.15)).lightened(rng.randf_range(0.0, 0.08)))
			else:
				b = b.scaled(Vector3(s, s, s))
			xfs.append(Transform3D(b, Vector3(x, y, z)))
			buckets.append(_bucket_of(x, z))
		if xfs.is_empty(): continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = cfg["tint"]
		mm.mesh = _meshes[kind]
		mm.instance_count = xfs.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d_%d" % [kind, key.x, key.y]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind == "tuft" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mmi.visibility_range_end = VIEW_RANGE
		mmi.visibility_range_end_margin = 10.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if cfg["tint"]:
			var mat := ShaderMaterial.new()
			mat.shader = TUFT_SHADER
			mmi.material_override = mat
		add_child(mmi)
		var hidden := PackedByteArray(); hidden.resize(xfs.size())
		var e := {"mmi": mmi, "xf": xfs, "bucket": buckets, "hidden": hidden}
		entry[kind] = e
		for i in xfs.size():
			if cfg["tint"]: mm.set_instance_color(i, cols[i])
			var o := xfs[i].origin
			for a in _areas:
				if _in_area(Vector2(o.x, o.z), a): hidden[i] = 1
			if buckets[i] >= 0:
				if not _buckets.has(buckets[i]): _buckets[buckets[i]] = []
				_buckets[buckets[i]].append([key, kind, i])
	_chunks[key] = entry
	for kind in entry:
		for i in (entry[kind]["xf"] as Array).size():
			_apply_e(entry[kind], kind, i)

# ---------------- per-instance state ----------------

func _apply(key: Vector2i, kind: String, i: int) -> void:
	_apply_e(_chunks[key][kind], kind, i)

func _apply_e(e: Dictionary, kind: String, i: int) -> void:
	var base: Transform3D = e["xf"][i]
	var bi: int = e["bucket"][i]
	var k := 0.0
	if not e["hidden"][i] and not _field.has(bi):
		k = float(_trample.get(bi, 1.0))
		if kind != "tuft": k = 0.0 if k < 0.7 else k   # flowers vanish early on a path
	(e["mmi"].multimesh as MultiMesh).set_instance_transform(i, Transform3D(base.basis.scaled(Vector3(1, k, 1)) if k > 0.0 else Basis().scaled(Vector3.ZERO), base.origin))

func _in_area(p: Vector2, a: Array) -> bool:
	var d: Vector2 = p - a[0]
	var r: float = (a[1] as Vector2).length()
	if absf(d.x) > r or absf(d.y) > r: return false
	var l := Defs.rot2(d, -a[2])
	return absf(l.x) <= a[1].x and absf(l.y) <= a[1].y

## Hides grass/flowers under a building footprint (centre, half extents, rotation).
func clear_area(center: Vector2, half: Vector2, angle: float) -> void:
	var a := [center, half, angle]
	_areas.append(a)
	_update_area(a)

## Restores them (after demolishing).
func restore_area(center: Vector2, half: Vector2, angle: float) -> void:
	for a in _areas.duplicate():
		if (a[0] as Vector2).is_equal_approx(center) and (a[1] as Vector2).is_equal_approx(half) and is_equal_approx(a[2], angle):
			_areas.erase(a)
			_update_area(a)
			return

func _update_area(a: Array) -> void:
	var r: float = (a[1] as Vector2).length()
	for key in _chunks:
		var c := _chunk_center(key)
		if absf(c.x - a[0].x) > r + CHUNK or absf(c.y - a[0].y) > r + CHUNK: continue
		for kind in _chunks[key]:
			var e: Dictionary = _chunks[key][kind]
			var xfs: Array = e["xf"]
			for i in xfs.size():
				var o: Vector3 = xfs[i].origin
				var p := Vector2(o.x, o.z)
				if not _in_area(p, a): continue
				var h := 0
				for other in _areas:
					if _in_area(p, other): h = 1
				if e["hidden"][i] != h:
					e["hidden"][i] = h
					_apply_e(e, kind, i)

## Flattens grass in one bucket. f: 1 = untouched, 0 = gone.
func set_trample(bucket: int, f: float) -> void:
	if is_equal_approx(float(_trample.get(bucket, 1.0)), f): return
	if f >= 0.999: _trample.erase(bucket)
	else: _trample[bucket] = f
	for e in _buckets.get(bucket, []):
		_apply(e[0], e[1], e[2])

## Farm fields: grass is cleared on every bucket in `on` (bucket index -> true).
func set_field_buckets(on: Dictionary) -> void:
	var touched := {}
	for b in on:
		if not _field.has(b): touched[b] = true
	for b in _field:
		if not on.has(b): touched[b] = true
	_field = on.duplicate()
	for b in touched:
		for e in _buckets.get(b, []):
			_apply(e[0], e[1], e[2])

func trampled_count() -> int:
	var n := 0
	for b in _trample:
		if _trample[b] < 0.5: n += _buckets.get(b, []).size()
	return n
