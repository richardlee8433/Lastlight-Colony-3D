extends Node3D
## Rebuilds the grass and flower scatter from Blender as MultiMeshes (one draw call each).

const KINDS := {
	"tuft": {"model": "res://models/tuft.glb", "tint": true},
	"flower_petal_v": {"model": "res://models/flower_petal_v.glb", "tint": false},
	"flower_petal_w": {"model": "res://models/flower_petal_w.glb", "tint": false},
}

## per kind: {"mm": MultiMesh, "xf": Array[Transform3D]} so instances can be hidden under buildings
var _sets := {}

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
	_sets[kind] = {"mm": mm, "xf": xfs}

## Hides grass/flowers inside an XZ rectangle (world units), e.g. under a new building.
func clear_rect(r: Rect2) -> void:
	_apply_rect(r, true)

## Restores them (after demolishing).
func restore_rect(r: Rect2) -> void:
	_apply_rect(r, false)

func _apply_rect(r: Rect2, hide: bool) -> void:
	var hidden := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for kind in _sets:
		var mm: MultiMesh = _sets[kind]["mm"]
		var xfs: Array[Transform3D] = _sets[kind]["xf"]
		for i in xfs.size():
			var o := xfs[i].origin
			if r.has_point(Vector2(o.x, o.z)):
				mm.set_instance_transform(i, Transform3D(hidden.basis, o) if hide else xfs[i])
