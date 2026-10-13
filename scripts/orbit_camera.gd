extends Camera3D
## Builder camera.
## Right-drag rotate · middle-drag or WASD/arrows pan · Q/E rotate · wheel/pinch zoom.
## (Left mouse is reserved for building and selecting.)

@export var target := Vector3(0.3, 0.8, 0.3)
@export var start_position := Vector3(-9.5, 15.0, 15.5)
@export var min_distance := 9.0
@export var max_distance := 38.0
@export var pan_limit := 13.0
@export var key_pan_speed := 14.0

var _dist := 1.0
var _yaw := 0.0
var _pitch := 0.0

func _ready() -> void:
	var off := start_position - target
	_dist = off.length()
	_yaw = atan2(off.x, off.z)
	_pitch = asin(off.y / _dist)
	_apply()

func _process(delta: float) -> void:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): v.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): v.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): v.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): v.x += 1
	var rot := 0.0
	if Input.is_key_pressed(KEY_Q): rot += 1
	if Input.is_key_pressed(KEY_E): rot -= 1
	if v != Vector2.ZERO or rot != 0.0:
		_pan(v.normalized() * key_pan_speed * delta * (_dist / 20.0))
		_yaw += rot * 1.6 * delta
		_apply()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_yaw -= event.relative.x * 0.005
			_pitch = clamp(_pitch + event.relative.y * 0.004, 0.45, 1.35)
			_apply()
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			_pan(Vector2(-event.relative.x, -event.relative.y) * 0.0018 * _dist)
			_apply()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = max(min_distance, _dist * 0.9)
			_apply()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = min(max_distance, _dist * 1.1)
			_apply()
	elif event is InputEventMagnifyGesture:
		_dist = clamp(_dist / event.factor, min_distance, max_distance)
		_apply()
	elif event is InputEventPanGesture:
		_pan(event.delta * 0.02 * _dist)
		_apply()

## v.x = screen right, v.y = screen down (towards camera)
func _pan(v: Vector2) -> void:
	var right := Vector3(cos(_yaw), 0, -sin(_yaw))
	var back := Vector3(sin(_yaw), 0, cos(_yaw))
	target += right * v.x + back * v.y
	target.x = clamp(target.x, -pan_limit, pan_limit)
	target.z = clamp(target.z, -pan_limit, pan_limit)

func _apply() -> void:
	position = target + Vector3(cos(_pitch) * sin(_yaw), sin(_pitch), cos(_pitch) * cos(_yaw)) * _dist
	look_at(target, Vector3.UP)
