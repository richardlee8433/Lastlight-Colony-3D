class_name Backdrop
extends MeshInstance3D
## The land beyond the colony: low rolling dunes rising into eroded ridges and flat-topped mesas,
## built once as a height-field ring around the (flat) playable ground. Only scenery — nothing walks
## or builds out here. Shaded by backdrop.gdshader (regolith, strata on the slopes, dust in the hollows).

const HALF := 280.0          # metres from the centre to the edge of the backdrop
const STEP := 3.0            # grid spacing
const FLAT := 52.0           # inside this square half-size the backdrop stays below the ground
const RISE := 170.0          # distance over which the hills grow to full height

var _n1 := FastNoiseLite.new()
var _n2 := FastNoiseLite.new()
var _n3 := FastNoiseLite.new()

func _ready() -> void:
	_n1.seed = 71; _n1.frequency = 0.008; _n1.fractal_octaves = 4
	_n2.seed = 13; _n2.frequency = 0.03; _n2.fractal_octaves = 3
	_n3.seed = 5; _n3.frequency = 0.004; _n3.noise_type = FastNoiseLite.TYPE_CELLULAR
	_n3.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
	mesh = _build()
	var m := ShaderMaterial.new()
	m.shader = preload("res://scripts/world/backdrop.gdshader")
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func height(x: float, z: float) -> float:
	var d := maxf(absf(x), absf(z))
	var t := smoothstep(FLAT, FLAT + RISE, d)
	if d < FLAT: return -2.0
	# dunes near the colony, ridges further out, and mesas: terraced, flat-topped plateaus
	var dunes := (_n2.get_noise_2d(x, z) * 0.5 + 0.5) * 1.8
	var ridge := 1.0 - absf(_n1.get_noise_2d(x, z))
	ridge = ridge * ridge * 9.0
	var mesa_mask := smoothstep(0.55, 0.62, 1.0 - _n3.get_noise_2d(x, z))
	var mesa := mesa_mask * 12.0
	var h := dunes * smoothstep(FLAT, FLAT + 25.0, d) + (ridge + mesa) * t
	# a far mountain range on the horizon
	h += smoothstep(170.0, 260.0, d) * (1.0 - absf(_n1.get_noise_2d(x * 0.6 + 300.0, z * 0.6))) * 38.0
	# terraces (erosion steps) on the high ground
	var step_h := 2.5
	var terr := floorf(h / step_h) * step_h + smoothstep(0.75, 1.0, fmod(h, step_h) / step_h) * step_h
	h = lerpf(h, terr, smoothstep(5.0, 11.0, h) * 0.7)
	return h - 0.35

func _build() -> ArrayMesh:
	var n := int(HALF * 2.0 / STEP) + 1
	var verts := PackedVector3Array(); verts.resize(n * n)
	for j in n:
		for i in n:
			var x := -HALF + i * STEP; var z := -HALF + j * STEP
			verts[j * n + i] = Vector3(x, height(x, z), z)
	var idx := PackedInt32Array()
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i; var b := a + 1; var c := a + n; var d := c + 1
			# skip quads that are entirely under the playable ground
			if verts[a].y < -1.0 and verts[b].y < -1.0 and verts[c].y < -1.0 and verts[d].y < -1.0: continue
			idx.append_array([a, b, c, b, d, c])
	var st := SurfaceTool.new()
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts; arr[Mesh.ARRAY_INDEX] = idx
	st.create_from_arrays(arr)
	st.generate_normals()
	return st.commit()
