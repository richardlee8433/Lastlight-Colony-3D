extends Node3D
## Rebuilds the grass and flower scatter from Blender as MultiMeshes (one draw call each).
## Instances can be hidden under buildings and flattened where villagers wear a road.

const KINDS := {
	"tuft": {"model": "res://models/tuft.glb", "tint": true},
	"flower_petal_v": {"model": "res://models/flower_petal_v.glb", "tint": false},
	"flower_petal_w": {"model": "res://models/flower_petal_w.glb", "tint": false},
}
## bucket size for trampling (matches NavGrid / PathWear cells)
const BUCKET := 0.5
const ORIGIN := Vector2(-17, -17)
const BW := 68

## per kind: {"mm": MultiMesh, "xf": Array[Transform3D], "hidden": PackedByteArray}
var _sets := {}
## bucket index -> Array of [kind, instance index]
var _buckets := {}
## bucket index -> 0..1 grass scale (1 = untouched)
var _trample := {}

func _ready() -> void:
	var f := FileAccess.open("res://data/scatter.json", FileAccess.READ)
	if f == null:
		push_warning("scatter.json missing")
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for kind in KINDS:
		if data.has(kind):
			_build(kind, data[kind], KINDS[kind], rng)

func _find_mesh(n: Node) -> Mesh:
	if n is MeshInstance3D:
		return (n as MeshInstance3D).mesh
	for c in n.get_children():
		var m := _find_mesh(c)
		if m:
			return m
	return null

func _bucket_of(x: float, z: float) -> int:
	var i := floori((x - ORIGIN.x) / BUCKET); var j := floori((z - ORIGIN.y) / BUCKET)
	if i < 0 or j < 0 or i >= BW or j >= BW: return -1
	return j * BW + i

func _build(kind: String, rows: Array, cfg: Dictionary, rng: RandomNumberGenerator) -> void:
	var src: Node = (load(cfg["model"]) as PackedScene).instantiate()
	var mesh := _find_mesh(src)
	src.queue_free()
	if mesh == null:
		push_warning("no mesh in " + cfg["model"])
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = cfg["tint"]
	mm.mesh = mesh
	mm.instance_count = rows.size()
	var xfs: Array[Transform3D] = []
	xfs.resize(rows.size())
	for i in rows.size():
		var a: Array = rows[i]
		var b := Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8]))
		xfs[i] = Transform3D(b, Vector3(a[9], a[10], a[11]))
		mm.set_instance_transform(i, xfs[i])
		var bi := _bucket_of(a[9], a[11])
		if bi >= 0:
			if not _buckets.has(bi): _buckets[bi] = []
			_buckets[bi].append([kind, i])
		if cfg["tint"]:
			# olive-to-yellow green, like the Blender blade material
			var t := rng.randf()
			var c := Color(0.20, 0.33, 0.06).lerp(Color(0.52, 0.55, 0.16), t * t)
			mm.set_instance_color(i, c.darkened(rng.randf_range(0.0, 0.35)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = kind
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind == "tuft" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if cfg["tint"]:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color.WHITE
		m.roughness = 0.9
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mmi.material_override = m
	add_child(mmi)
	var hidden := PackedByteArray(); hidden.resize(rows.size())
	_sets[kind] = {"mm": mm, "xf": xfs, "hidden": hidden}

func _apply(kind: String, i: int) -> void:
	var s: Dictionary = _sets[kind]
	var base: Transform3D = s["xf"][i]
	var k := 0.0
	if not s["hidden"][i]:
		var bi := _bucket_of(base.origin.x, base.origin.z)
		k = float(_trample.get(bi, 1.0))
		if kind != "tuft": k = 0.0 if k < 0.7 else k   # flowers vanish early on a path
	(s["mm"] as MultiMesh).set_instance_transform(i, Transform3D(base.basis.scaled(Vector3(1, k, 1) if k > 0.0 else Vector3.ZERO), base.origin))

## Hides grass/flowers under a building footprint (centre, half extents, rotation), e.g. a new building.
func clear_area(center: Vector2, half: Vector2, angle: float) -> void:
	_apply_area(center, half, angle, true)

## Restores them (after demolishing).
func restore_area(center: Vector2, half: Vector2, angle: float) -> void:
	_apply_area(center, half, angle, false)

func _apply_area(center: Vector2, half: Vector2, angle: float, hide: bool) -> void:
	var r := half.length()
	for kind in _sets:
		var xfs: Array[Transform3D] = _sets[kind]["xf"]
		var hidden: PackedByteArray = _sets[kind]["hidden"]
		for i in xfs.size():
			var o := xfs[i].origin
			var d := Vector2(o.x, o.z) - center
			if absf(d.x) > r or absf(d.y) > r: continue
			var l := Defs.rot2(d, -angle)
			if absf(l.x) <= half.x and absf(l.y) <= half.y:
				hidden[i] = 1 if hide else 0
				_apply(kind, i)

## Flattens grass in one bucket. f: 1 = untouched, 0 = gone.
func set_trample(bucket: int, f: float) -> void:
	if is_equal_approx(float(_trample.get(bucket, 1.0)), f): return
	if f >= 0.999: _trample.erase(bucket)
	else: _trample[bucket] = f
	for e in _buckets.get(bucket, []):
		_apply(e[0], e[1])

func trampled_count() -> int:
	var n := 0
	for b in _trample:
		if _trample[b] < 0.5: n += _buckets.get(b, []).size()
	return n
