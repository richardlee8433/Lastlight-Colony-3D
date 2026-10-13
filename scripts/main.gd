extends Node3D
## Aims the sun to match the Blender render.

func _ready() -> void:
	var f := FileAccess.open("res://data/scene.json", FileAccess.READ)
	if f == null:
		return
	var info: Dictionary = JSON.parse_string(f.get_as_text())
	var d: Array = info.get("sun_dir", [0.3, -0.7, 0.4])
	var dir := Vector3(d[0], d[1], d[2]).normalized()
	var sun := $Sun as DirectionalLight3D
	sun.look_at_from_position(-dir * 30.0, Vector3.ZERO, Vector3.UP)
	_use_vertex_colors($Nature)

## Foliage colours are baked into vertex colours; make sure the material uses them.
func _use_vertex_colors(n: Node) -> void:
	if n is MeshInstance3D:
		_boost_colors(n as MeshInstance3D)
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.85
		(n as MeshInstance3D).material_override = m
	for c in n.get_children():
		_use_vertex_colors(c)

## Baked foliage colours are quite dark in linear space; lift and saturate them a bit.
func _boost_colors(mi: MeshInstance3D) -> void:
	var src := mi.mesh as ArrayMesh
	if src == null:
		return
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for i in cols.size():
			var c := cols[i]
			var l := (c.r + c.g + c.b) / 3.0
			c = Color(l + (c.r - l) * 1.35, l + (c.g - l) * 1.35, l + (c.b - l) * 1.35) * 1.7
			cols[i] = c
		arrays[Mesh.ARRAY_COLOR] = cols
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), arrays)
	mi.mesh = out
