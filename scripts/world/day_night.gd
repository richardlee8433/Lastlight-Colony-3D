class_name DayNight
extends Node
## Day and night over the colony. One sol (a full day-night cycle) lasts SOL_DAYS in-game days, so the
## light changes slowly while the economy keeps its 30-second days. Moves the sun across the sky, warms
## it at dawn and dusk, swaps to dim blue moonlight at night, darkens the sky and the fog, and switches on
## the colony's lights: glowing windows, lamps and grow lights (surfaces named "glow_*" in the baked
## models, tools/scifi.py) plus one small light per building. Shaders read the global uniform `night`.

const SOL_DAYS := 4.0
const NOON_ELEV := deg_to_rad(56.0)
const BASE_AZ := deg_to_rad(35.0)            # where the sun stands at noon (matches the old fixed sun)

@export var sun_path: NodePath = ^"../Sun"
@export var env_path: NodePath = ^"../WorldEnvironment"

static var night := 0.0                      # 0 = full day, 1 = deep night
static var time_of_day := 0.42               # 0..1: 0.25 sunrise, 0.5 noon, 0.75 sunset
static var _mats := {}                       # glow kind -> StandardMaterial3D
static var _lights: Array[OmniLight3D] = []

const GLOW := {
	# kind: [day albedo, night emission colour, emission strength]
	"glow_window": [Color(0.10, 0.13, 0.16), Color(1.0, 0.80, 0.52), 3.2],
	"glow_lamp": [Color(0.80, 0.82, 0.84), Color(0.85, 0.93, 1.0), 5.0],
	"glow_grow": [Color(0.36, 0.62, 0.52), Color(0.95, 0.45, 0.95), 1.6],
}

var _sun: DirectionalLight3D
var _env: Environment
var _fog_day: Color

func _ready() -> void:
	_sun = get_node_or_null(sun_path)
	var we := get_node_or_null(env_path) as WorldEnvironment
	if we: _env = we.environment
	if _env: _fog_day = _env.fog_light_color
	_lights.clear()
	apply()

func _process(delta: float) -> void:
	if Game.speed <= 0.0: return
	time_of_day = fposmod(time_of_day + delta * Game.speed / (Defs.DAY_LENGTH * SOL_DAYS), 1.0)
	apply()

## Jump to a time of day (tests, screenshots).
func set_time(t: float) -> void:
	time_of_day = fposmod(t, 1.0)
	apply()

static func sun_elevation(t: float) -> float:
	return NOON_ELEV * sin((t - 0.25) * TAU)

func apply() -> void:
	var el := sun_elevation(time_of_day)
	var az := BASE_AZ + (time_of_day - 0.5) * PI
	var day := smoothstep(-0.06, 0.3, sin(el))
	night = 1.0 - smoothstep(-0.14, 0.08, sin(el))
	if _sun:
		var dir: Vector3
		var col: Color
		var energy: float
		if el > -0.06:
			dir = Vector3(cos(az) * cos(el), sin(maxf(el, 0.02)), sin(az) * cos(el)).normalized()
			# low sun: warm and weak; high sun: white and harsh
			var high := smoothstep(0.0, 0.5, sin(el))
			col = Color(1.0, 0.62, 0.38).lerp(Color(1.0, 0.95, 0.88), high)
			energy = lerpf(0.0, 2.5, smoothstep(-0.06, 0.35, sin(el)))
		else:
			# moonlight from the other side of the sky, faint and cool
			var maz := az + PI
			dir = Vector3(cos(maz) * 0.6, 0.75, sin(maz) * 0.6).normalized()
			col = Color(0.55, 0.66, 0.95)
			energy = 0.45 * smoothstep(0.0, 0.25, night)
		_sun.global_transform.basis = Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
		_sun.light_color = col
		_sun.light_energy = energy
	if _env:
		_env.ambient_light_energy = lerpf(0.16, 0.42, day)
		_env.fog_light_color = _fog_day.lerp(Color(0.10, 0.12, 0.2), night * 0.9)
		_env.background_energy_multiplier = lerpf(0.35, 1.0, day)
		if _env.sky and _env.sky.sky_material is ShaderMaterial:
			(_env.sky.sky_material as ShaderMaterial).set_shader_parameter("day", day)
	RenderingServer.global_shader_parameter_set("night", night)
	for kind in _mats:
		var m: StandardMaterial3D = _mats[kind]
		m.emission_energy_multiplier = GLOW[kind][2] * night
	_lights = _lights.filter(func(x): return is_instance_valid(x))
	for l in _lights:
		if true:
			l.visible = night > 0.05
			l.light_energy = night * float(l.get_meta("energy", 0.8))

## Shared material for one kind of glowing surface.
static func material(kind: String) -> StandardMaterial3D:
	if not _mats.has(kind):
		var g: Array = GLOW[kind]
		var m := StandardMaterial3D.new()
		m.albedo_color = g[0]
		m.roughness = 0.25 if kind == "glow_window" else 0.5
		m.emission_enabled = true
		m.emission = g[1]
		m.emission_energy_multiplier = g[2] * night
		_mats[kind] = m
	return _mats[kind]

## Give a freshly built model its night lights: glow surfaces get the shared materials.
static func dress(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var sm := mi.mesh.surface_get_material(i)
				if sm == null: continue
				for kind in GLOW:
					if sm.resource_name.begins_with(kind):
						mi.set_surface_override_material(i, material(kind))
	for c in n.get_children(): dress(c)

## A small warm light that only shines at night (one per building, at its front).
static func add_light(parent: Node3D, pos: Vector3, energy := 0.8, rng := 4.0, color := Color(1.0, 0.78, 0.5)) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.omni_range = rng
	l.position = pos
	l.shadow_enabled = false
	l.set_meta("energy", energy)
	l.light_energy = energy * night
	l.visible = night > 0.05
	parent.add_child(l)
	_lights.append(l)
	return l
