extends Camera3D
## Walk / free-fly camera: WASD or arrows move, mouse looks (click to capture the mouse), Shift is faster,
## F switches walk / fly, E and Q (or Space and C) go up and down while flying, Esc frees the mouse.
## Movement keys are physical, so they sit in the same place on any keyboard layout.

@export var walk_speed := 2.2
@export var fly_speed := 4.0
@export var fast_multiplier := 3.0
@export var mouse_sensitivity := 0.0025
@export var eye_height := 1.6
@export var flying := false
## The camera stays inside this box (the room).
@export var bounds_min := Vector3(-1000, 0.2, -1000)
@export var bounds_max := Vector3(1000, 100, 1000)

var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	_yaw = rotation.y
	_pitch = rotation.x


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	var motion := event as InputEventMouseMotion
	var key := event as InputEventKey
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(motion.relative)
	elif key != null and key.pressed and not key.echo:
		if key.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif key.keycode == KEY_F:
			flying = not flying
		else:
			return
		get_viewport().set_input_as_handled()


## Turns the view by a mouse movement in pixels.
func look(relative: Vector2) -> void:
	_yaw -= relative.x * mouse_sensitivity
	_pitch = clampf(_pitch - relative.y * mouse_sensitivity, deg_to_rad(-88.0), deg_to_rad(88.0))
	rotation = Vector3(_pitch, _yaw, 0.0)


func _key(a: Key, b: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(a) or Input.is_physical_key_pressed(b) else 0.0


func _process(delta: float) -> void:
	var dir := Vector3(_key(KEY_D, KEY_RIGHT) - _key(KEY_A, KEY_LEFT), 0.0, _key(KEY_S, KEY_DOWN) - _key(KEY_W, KEY_UP))
	var speed := fly_speed if flying else walk_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= fast_multiplier
	var move: Vector3
	if flying:
		move = global_transform.basis * dir
		move.y += _key(KEY_E, KEY_SPACE) - _key(KEY_Q, KEY_C)
	else:
		move = Basis(Vector3.UP, _yaw) * dir
	if move.length() > 1.0:
		move = move.normalized()
	var p := position + move * speed * delta
	if not flying:
		p.y = lerpf(p.y, eye_height, 1.0 - exp(-10.0 * delta))
	position = p.clamp(bounds_min, bounds_max)
