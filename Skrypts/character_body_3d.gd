extends CharacterBody3D

# ---------- Stałe ----------

const SPEED := 4.0
const SPRINT_SPEED := 7.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENS := 0.002
const MAX_LOOK_ANGLE := deg_to_rad(89)
const MIN_MOVE_SPEED := 0.5          # poniżej tej prędkości gracz "stoi"
const BOB_SPEED_FACTOR := 1.6
const IDLE_BREATH_AMOUNT := 0.002

const INPUT_KEYS := {
	"forward": KEY_W,
	"back": KEY_S,
	"left": KEY_A,
	"right": KEY_D,
	"jump": KEY_SPACE,
	"sprint": KEY_SHIFT,
	"interact": KEY_E,
}

# ---------- Ustawienia w Inspektorze ----------

@export_group("Kroki")
@export var footstep_sounds: Array[AudioStream] = []   # przeciągnij tu pliki dźwięków kroków
@export var step_distance: float = 2.0                 # co ile metrów jeden krok
@export var footstep_volume_db: float = 0.0
@export var debug_footsteps: bool = false              # true = wypisuje "krok" w Output

@export_group("Latarka w ręku")
@export var bob_amount: float = 0.012     # siła kołysania przy chodzeniu
@export var sway_amount: float = 0.0015   # siła opóźnienia przy obracaniu myszką
@export var sway_max: float = 0.12        # maksymalny wychył (radiany)
@export var sway_smooth: float = 10.0     # im większe, tym szybciej latarka "dogania" kamerę
@export var start_with_flashlight: bool = false   # false = gracz dostaje latarkę dopiero po podniesieniu
@export var held_root_name: String = "Cofanie"                   # węzeł ukrywany do czasu podniesienia latarki
@export var held_model_name: String = "Untitled_test animacji"   # model, który kołysze się przy chodzeniu

# ---------- Stan ----------

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var step_progress: float = 0.0

var camera: Camera3D
var footstep_player = null          # AudioStreamPlayer lub AudioStreamPlayer3D
var interact_ray: RayCast3D = null
var flashlight: Flashlight = null
var held_flashlight: Node3D = null  # węzeł kołysany przy chodzeniu (model latarki)
var held_root: Node3D = null        # węzeł ukrywany/pokazywany (Cofanie)
var prompt_label: Label

var held_base_pos := Vector3.ZERO
var held_base_rot := Vector3.ZERO
var bob_time: float = 0.0
var bob_current := Vector3.ZERO
var sway_current := Vector3.ZERO
var mouse_input := Vector2.ZERO


# ---------- Inicjalizacja ----------

func _ready() -> void:
	camera = $Camera3D
	_setup_input_actions()
	_setup_footstep_player()
	_create_prompt_label()
	_find_nodes()
	_setup_flashlight()
	_setup_held_item()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _find_nodes() -> void:
	interact_ray = find_child("InteractRay", true, false)
	if interact_ray:
		interact_ray.add_exception(self)   # promień ignoruje kapsułę gracza
	else:
		push_warning("Brak węzła InteractRay (RayCast3D) pod Camera3D")

	# światło szukamy po typie, nazwa węzła nie ma znaczenia
	for light in find_children("*", "SpotLight3D", true, false):
		if light is Flashlight:
			flashlight = light
			break

	# węzeł do kołysania: model latarki -> HeldFlashlight -> samo światło
	held_flashlight = _find_first_node([held_model_name, "HeldFlashlight"])
	if held_flashlight == null:
		held_flashlight = flashlight

	# węzeł do ukrywania: Cofanie (model + światło razem), a jeśli go nie ma, to samo co wyżej
	held_root = _find_first_node([held_root_name])
	if held_root == null:
		held_root = held_flashlight


func _find_first_node(node_names: Array[String]) -> Node3D:
	for node_name in node_names:
		var found := find_child(node_name, true, false) as Node3D
		if found:
			return found
	return null


func _setup_flashlight() -> void:
	if flashlight == null:
		push_warning("Nie znaleziono węzła ze skryptem Flashlight pod Camera3D")
		return
	flashlight.unlocked = start_with_flashlight
	if not start_with_flashlight:
		flashlight._set_light(false)


func _setup_held_item() -> void:
	if held_root == null or held_flashlight == null:
		push_warning("Brak latarki w ręku (Cofanie / model / HeldFlashlight)")
		return
	held_base_pos = held_flashlight.position
	held_base_rot = held_flashlight.rotation
	_disable_collisions(held_root)   # model w ręku nie może mieć kolizji
	held_root.visible = start_with_flashlight and flashlight != null


# ---------- Ustawienia wejścia ----------

func _setup_input_actions() -> void:
	for action in INPUT_KEYS:
		_add_key_action(action, INPUT_KEYS[action])


func _add_key_action(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if InputMap.action_get_events(action).is_empty():
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative)

	if event.is_action_pressed("interact"):
		_try_interact()

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _look(relative: Vector2) -> void:
	rotate_y(-relative.x * MOUSE_SENS)
	camera.rotate_x(-relative.y * MOUSE_SENS)
	camera.rotation.x = clamp(camera.rotation.x, -MAX_LOOK_ANGLE, MAX_LOOK_ANGLE)
	mouse_input += relative   # używane do opóźnienia latarki


# ---------- Interakcja ----------

# Zwraca obiekt, na który patrzy gracz, jeśli da się z nim wejść w interakcję
func _get_interact_target() -> Object:
	if interact_ray == null or not interact_ray.is_colliding():
		return null
	var target := interact_ray.get_collider()
	if is_instance_valid(target) and target.has_method("interact"):
		return target
	return null


func _try_interact() -> void:
	var target := _get_interact_target()
	if target:
		target.interact(self)


# Wywoływane przez przedmiot na ziemi
func give_flashlight() -> void:
	if flashlight:
		flashlight.pick_up()
	if held_root:
		held_root.visible = true


# ---------- Napis "[E] ..." ----------

func _create_prompt_label() -> void:
	var hud := CanvasLayer.new()
	hud.layer = 2   # nad efektem post-process (Layer 1)
	add_child(hud)

	prompt_label = Label.new()
	prompt_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	prompt_label.offset_top = 120.0
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_label.add_theme_font_size_override("font_size", 26)
	prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	prompt_label.add_theme_constant_override("outline_size", 8)
	prompt_label.visible = false
	hud.add_child(prompt_label)


func _update_prompt() -> void:
	var target := _get_interact_target()
	prompt_label.visible = target != null
	if target:
		var text = target.get("prompt_text")
		prompt_label.text = "[E] " + (str(text) if text != null else "Użyj")


# ---------- Dźwięk kroków ----------

func _setup_footstep_player() -> void:
	footstep_player = find_child("FootstepPlayer", true, false)
	if footstep_player == null:
		footstep_player = AudioStreamPlayer.new()
		footstep_player.name = "FootstepPlayer"
		add_child(footstep_player)
		print("Utworzono FootstepPlayer w kodzie")
	footstep_player.volume_db = footstep_volume_db
	footstep_player.max_polyphony = 3   # pozwala, by kroki nakładały się bez ucinania


func _handle_footsteps(delta: float) -> void:
	if _is_walking():
		step_progress += _get_horizontal_speed() * delta
		if step_progress >= step_distance:
			step_progress = 0.0
			_play_step()
	else:
		step_progress = step_distance   # pierwszy krok zagra od razu po ruszeniu


func _play_step() -> void:
	if not footstep_sounds.is_empty():
		footstep_player.stream = footstep_sounds.pick_random()
	if footstep_player.stream == null:
		push_warning("Brak dźwięku kroków: uzupełnij 'Footstep Sounds' w Inspektorze gracza")
		return
	footstep_player.pitch_scale = randf_range(0.9, 1.1)
	footstep_player.volume_db = footstep_volume_db
	footstep_player.play()
	if debug_footsteps:
		print("krok")


# ---------- Latarka w ręku: kołysanie i opóźnienie ----------

func _process(delta: float) -> void:
	_update_held_flashlight(delta)


func _update_held_flashlight(delta: float) -> void:
	if held_root == null or held_flashlight == null or not held_root.visible:
		mouse_input = Vector2.ZERO
		return

	var smooth := 1.0 - exp(-sway_smooth * delta)
	bob_current = bob_current.lerp(_calc_target_bob(delta), smooth)
	sway_current = sway_current.lerp(_calc_target_sway(), smooth)
	mouse_input = Vector2.ZERO

	held_flashlight.position = held_base_pos + bob_current
	held_flashlight.rotation = held_base_rot + sway_current


# Kołysanie przy chodzeniu / oddychanie w bezruchu
func _calc_target_bob(delta: float) -> Vector3:
	if _is_walking():
		bob_time += delta * _get_horizontal_speed() * BOB_SPEED_FACTOR
		return Vector3(
			cos(bob_time) * bob_amount,
			sin(bob_time * 2.0) * bob_amount * 0.7,
			0.0
		)
	return Vector3(0.0, sin(Time.get_ticks_msec() * 0.0015) * IDLE_BREATH_AMOUNT, 0.0)


# Opóźnienie latarki przy obracaniu myszką
func _calc_target_sway() -> Vector3:
	return Vector3(
		clamp(mouse_input.y * sway_amount, -sway_max, sway_max),
		clamp(mouse_input.x * sway_amount, -sway_max, sway_max),
		0.0
	)


# ---------- Ruch ----------

func _physics_process(delta: float) -> void:
	_apply_gravity_and_jump(delta)
	_apply_movement()
	move_and_slide()
	_handle_footsteps(delta)
	_update_prompt()


func _apply_gravity_and_jump(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY


func _apply_movement() -> void:
	var input_dir := Input.get_vector("left", "right", "forward", "back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var current_speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else SPEED

	if direction != Vector3.ZERO:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, current_speed)
		velocity.z = move_toward(velocity.z, 0.0, current_speed)


# ---------- Pomocnicze ----------

func _get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _is_walking() -> bool:
	return is_on_floor() and _get_horizontal_speed() > MIN_MOVE_SPEED


func _disable_collisions(node: Node) -> void:
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	for child in node.get_children():
		_disable_collisions(child)
