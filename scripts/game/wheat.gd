class_name Wheat
## Procedural wheat for farms: one clump mesh (a few stalks with nodding ears and leaves),
## instanced in rows with a MultiMesh and swayed by a small wind shader.

const WIND_SHADER := preload("res://scripts/game/wheat_wind.gdshader")

const STEM_LO := Color(0.50, 0.50, 0.18)
const STEM_HI := Color(0.90, 0.72, 0.30)
const EAR := Color(0.98, 0.74, 0.26)
const EAR_TIP := Color(1.0, 0.86, 0.46)
const LEAF := Color(0.46, 0.50, 0.18)

static var _mesh: ArrayMesh
static var _mat: ShaderMaterial

## Wheat clump mesh (shared by every farm).
static func clump_mesh() -> ArrayMesh:
	if _mesh: return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new(); rng.seed = 1234
	for s in 5:
		var base := Vector3(rng.randf_range(-0.06, 0.06), 0, rng.randf_range(-0.06, 0.06))
		var h := rng.randf_range(0.5, 0.68)
		var lean := Vector3(rng.randf_range(-0.05, 0.09), 0, rng.randf_range(-0.05, 0.05))
		_stalk(st, base, h, lean, rng)
	st.generate_normals()
	_mesh = st.commit()
	return _mesh

## Curved point along a stalk: t 0..1
static func _along(base: Vector3, h: float, lean: Vector3, t: float) -> Vector3:
	return base + Vector3(0, h * t, 0) + lean * (t * t)

static func _stalk(st: SurfaceTool, base: Vector3, h: float, lean: Vector3, rng: RandomNumberGenerator) -> void:
	var segs := 3
	var w := 0.011
	# two crossed ribbons so the stalk reads from every angle
	for side: Vector3 in [Vector3(w, 0, 0), Vector3(0, 0, w)]:
		for i in segs:
			var t0 := float(i) / segs; var t1 := float(i + 1) / segs
			var a := _along(base, h, lean, t0); var b := _along(base, h, lean, t1)
			var c0 := STEM_LO.lerp(STEM_HI, t0); var c1 := STEM_LO.lerp(STEM_HI, t1)
			_quad(st, a - side, a + side, b + side * 0.7, b - side * 0.7, c0, c0, c1, c1)
	# ear: a 4-sided spindle that nods a little past the top of the stalk
	var top := _along(base, h, lean, 1.0)
	var dir := (_along(base, h, lean, 1.0) - _along(base, h, lean, 0.85)).normalized()
	dir = (dir + Vector3(lean.x, -0.15, lean.z) * 2.0).normalized()
	var length := rng.randf_range(0.10, 0.13)
	var up := dir.cross(Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.FORWARD).normalized()
	var right := dir.cross(up).normalized()
	var ring_t: Array[float] = [0.0, 0.3, 0.7, 1.0]
	var ring_r: Array[float] = [0.006, 0.020, 0.018, 0.0]
	var ring_pts: Array[PackedVector3Array] = []
	for ri in ring_t.size():
		var c: Vector3 = top + dir * length * ring_t[ri]
		var pts := PackedVector3Array()
		for k in 4:
			var ang := TAU * k / 4.0 + PI / 4.0
			pts.append(c + (up * cos(ang) + right * sin(ang)) * ring_r[ri])
		ring_pts.append(pts)
	for i in ring_t.size() - 1:
		var ca: Color = EAR.lerp(EAR_TIP, ring_t[i]); var cb: Color = EAR.lerp(EAR_TIP, ring_t[i + 1])
		for k in 4:
			var j := (k + 1) % 4
			_quad(st, ring_pts[i][k], ring_pts[i][j], ring_pts[i + 1][j], ring_pts[i + 1][k], ca, ca, cb, cb)
	# awns: a thin whisker plane past the tip
	var tip := top + dir * length
	_quad(st, tip - right * 0.004, tip + right * 0.004, tip + dir * 0.07 + right * 0.012, tip + dir * 0.07 - right * 0.012,
		EAR_TIP, EAR_TIP, EAR_TIP, EAR_TIP)
	# one leaf curling out from the lower stalk
	var lb := _along(base, h, lean, 0.18)
	var ld := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
	var lw := ld.cross(Vector3.UP) * 0.012
	var lm := lb + ld * 0.07 + Vector3(0, 0.08, 0)
	var le := lb + ld * 0.15 + Vector3(0, 0.05, 0)
	_quad(st, lb - lw, lb + lw, lm + lw, lm - lw, LEAF, LEAF, LEAF, LEAF)
	_tri(st, lm - lw, lm + lw, le, LEAF)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	st.set_color(ca); st.add_vertex(a)
	st.set_color(cb); st.add_vertex(b)
	st.set_color(cc); st.add_vertex(c)
	st.set_color(ca); st.add_vertex(a)
	st.set_color(cc); st.add_vertex(c)
	st.set_color(cd); st.add_vertex(d)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	st.set_color(col); st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)

static func material() -> ShaderMaterial:
	if _mat: return _mat
	_mat = ShaderMaterial.new()
	_mat.shader = WIND_SHADER
	return _mat

## Fills rows of a field. rows: z positions (local), x_range: half length of each row.
static func field(parent: Node3D, row_z: Array, half_len: float, y: float, rng: RandomNumberGenerator) -> MultiMeshInstance3D:
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	for zz in row_z:
		var z: float = zz
		var x := -half_len
		while x <= half_len:
			for lane: float in [-0.07, 0.07]:
				var p := Vector3(x + rng.randf_range(-0.03, 0.03), y, z + lane + rng.randf_range(-0.025, 0.025))
				var s := rng.randf_range(0.85, 1.15)
				var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.1), s))
				xfs.append(Transform3D(b, p))
				# mostly ripe gold with the odd greener clump
				var g := rng.randf()
				cols.append(Color(1, 1, 1).lerp(Color(0.85, 0.95, 0.7), g * g * 0.6).darkened(rng.randf_range(0.0, 0.1)))
			x += 0.17
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = clump_mesh()
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material()
	parent.add_child(mmi)
	return mmi
