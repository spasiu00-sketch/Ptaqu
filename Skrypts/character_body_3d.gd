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
const IDLE_BREATH_SPEED := 1.5       # rad/s
const CAPSULE_MIN_MARGIN := 0.01     # kapsuła nie może być niższa niż 2 * promień

# preload zamiast class_name: działa nawet, gdy Godot nie odświeżył listy klas
const InventoryUIScript := preload("res://Skrypts/inventory_ui.gd")
const GlitchScript := preload("res://Skrypts/glitch_kamery.gd")

const INPUT_KEYS := {
	"forward": KEY_W,
	"back": KEY_S,
	"left": KEY_A,
	"right": KEY_D,
	"jump": KEY_SPACE,
	"sprint": KEY_SHIFT,
	"crouch": KEY_C,
	"interact": KEY_E,
	"inventory": KEY_TAB,
}

# ---------- Ustawienia w Inspektorze ----------

@export_group("Ruch")
@export var acceleration: float = 60.0    # m/s² przy rozpędzaniu (duża wartość = natychmiastowy start)
@export var deceleration: float = 80.0    # m/s² przy hamowaniu

@export_group("Kucanie")
@export var crouch_toggle: bool = false                 # false = kucasz, dopóki trzymasz klawisz; true = przełączanie
@export var crouch_speed: float = 2.0                   # prędkość chodzenia w kucki
@export_range(0.3, 0.9, 0.01) var crouch_height_ratio: float = 0.6   # wysokość kolizji w kucki (ułamek normalnej)
@export var crouch_transition_speed: float = 10.0       # płynność opuszczania/podnoszenia kamery
@export var crouch_footstep_db: float = -8.0            # o ile ciszej brzmią kroki w kucki

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

@export_group("Efekty")
@export var glitch_wlaczony: bool = true   # losowy glitch obrazu (glitch_kamery.gd)

# ---------- Stan ----------

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var camera: Camera3D = $Camera3D

var footstep_player = null          # AudioStreamPlayer lub AudioStreamPlayer3D
var interact_ray: RayCast3D = null
var flashlight: Flashlight = null
var held_flashlight: Node3D = null  # węzeł kołysany przy chodzeniu (model latarki)
var held_root: Node3D = null        # węzeł ukrywany/pokazywany (Cofanie)
var prompt_label: Label
var inventory_ui = null            # instancja inventory_ui.gd
var glitch = null                  # instancja glitch_kamery.gd

# ruch (liczone raz na klatkę fizyki)
var _h_speed: float = 0.0
var _moving: bool = false
var step_progress: float = 0.0

# kucanie
var _crouching: bool = false
var _crouch_input: bool = false
var _col: CollisionShape3D = null
var _stand_h: float = 1.8     # nadpisywane wysokością z kształtu kolizji
var _crouch_h: float = 1.1
var _stand_y: float = 0.0     # pozycja Y węzła kolizji w staniu
var _cam_offset: float = 0.0  # aktualne przesunięcie kamery w dół (<= 0)

# latarka
var held_base_pos := Vector3.ZERO
var held_base_rot := Vector3.ZERO
var bob_time: float = 0.0
var _breath_time: float = 0.0
var bob_current := Vector3.ZERO
var sway_current := Vector3.ZERO
var mouse_input := Vector2.ZERO


# ---------- Inicjalizacja ----------

func _ready() -> void:
	set_process(false)   # _process tylko gdy trzeba (latarka w ręku / ruch kamery przy kucaniu)
	_setup_input_actions()
	_setup_footstep_player()
	_create_prompt_label()
	_find_nodes()
	_setup_flashlight()
	_setup_held_item()
	_setup_crouch()
	_setup_inventory()
	_setup_glitch()
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
	set_process(held_root.visible)


func _setup_inventory() -> void:
	inventory_ui = InventoryUIScript.new()
	inventory_ui.gracz = self
	add_child(inventory_ui)


func _setup_glitch() -> void:
	if not glitch_wlaczony:
		return
	glitch = GlitchScript.new()
	add_child(glitch)


# ---------- Ekwipunek ----------

func _inventory_open() -> bool:
	return inventory_ui != null and inventory_ui.otwarty


func _toggle_inventory() -> void:
	if inventory_ui == null:
		return
	if inventory_ui.otwarty:
		inventory_ui.zamknij()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		inventory_ui.otworz()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	mouse_input = Vector2.ZERO


# ---------- Kucanie ----------

# Szuka kształtu kolizji gracza (bezpośrednie dziecko) i liczy wysokości stania / kucania
func _setup_crouch() -> void:
	for child in get_children():
		if child is CollisionShape3D and child.shape != null:
			_col = child as CollisionShape3D
			break
	if _col == null:
		push_warning("Brak CollisionShape3D pod graczem - kucanie zmieni tylko kamerę")
		return

	var height := _get_shape_height(_col.shape)
	if height <= 0.0:
		push_warning("Kucanie obsługuje kolizję typu Capsule / Cylinder / Box - zmieni tylko kamerę")
		_col = null
		return

	_col.shape = _col.shape.duplicate() as Shape3D   # unikamy zmiany współdzielonego zasobu
	_stand_h = height
	_stand_y = _col.position.y
	var min_height := 0.0
	if _col.shape is CapsuleShape3D:
		min_height = (_col.shape as CapsuleShape3D).radius * 2.0 + CAPSULE_MIN_MARGIN
	_crouch_h = minf(maxf(_stand_h * crouch_height_ratio, min_height), _stand_h)


func _get_shape_height(shape: Shape3D) -> float:
	if shape is CapsuleShape3D:
		return (shape as CapsuleShape3D).height
	if shape is CylinderShape3D:
		return (shape as CylinderShape3D).height
	if shape is BoxShape3D:
		return (shape as BoxShape3D).size.y
	return 0.0


func _set_shape_height(shape: Shape3D, height: float) -> void:
	if shape is CapsuleShape3D:
		(shape as CapsuleShape3D).height = height
	elif shape is CylinderShape3D:
		(shape as CylinderShape3D).height = height
	elif shape is BoxShape3D:
		var box := shape as BoxShape3D
		box.size = Vector3(box.size.x, height, box.size.z)


func _update_crouch() -> void:
	if crouch_toggle:
		if Input.is_action_just_pressed("crouch"):
			_crouch_input = not _crouch_input
	else:
		_crouch_input = Input.is_action_pressed("crouch")

	if _crouch_input == _crouching:
		return
	if _crouch_input:
		_set_crouching(true)
	elif _can_stand():
		_set_crouching(false)


# Sprawdza, czy nad głową jest miejsce na wstanie (sufit)
func _can_stand() -> bool:
	return not test_move(global_transform, Vector3.UP * (_stand_h - _crouch_h))


# Kolizja zmienia się od razu (stopy zostają w miejscu), kamera płynnie w _process
func _set_crouching(state: bool) -> void:
	_crouching = state
	if _col != null:
		var height := _crouch_h if state else _stand_h
		_set_shape_height(_col.shape, height)
		_col.position.y = _stand_y - (_stand_h - height) * 0.5
	set_process(true)


# Zwraca true, dopóki kamera jeszcze się przesuwa
func _update_crouch_camera(delta: float) -> bool:
	var target := -(_stand_h - _crouch_h) if _crouching else 0.0
	if _cam_offset == target:
		return false
	var new_offset := lerpf(_cam_offset, target, 1.0 - exp(-crouch_transition_speed * delta))
	if absf(new_offset - target) < 0.001:
		new_offset = target
	camera.position.y += new_offset - _cam_offset   # różnica, więc nie psuje innych przesunięć kamery
	_cam_offset = new_offset
	return new_offset != target


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
	if event.is_action_pressed("inventory"):
		_toggle_inventory()
		return

	# przy otwartym ekwipunku: tylko Esc zamyka, reszta wejścia idzie do UI
	if _inventory_open():
		if event.is_action_pressed("ui_cancel"):
			_toggle_inventory()
		return

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
	camera.rotation.x = clampf(camera.rotation.x - relative.y * MOUSE_SENS, -MAX_LOOK_ANGLE, MAX_LOOK_ANGLE)
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
		mouse_input = Vector2.ZERO
		set_process(true)


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
	prompt_label.visible = target != null and not _inventory_open()
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
	if _moving:
		step_progress += _h_speed * delta
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
	footstep_player.volume_db = footstep_volume_db + (crouch_footstep_db if _crouching else 0.0)
	footstep_player.play()
	if debug_footsteps:
		print("krok")


# ---------- _process: kamera przy kucaniu + latarka w ręku ----------

func _process(delta: float) -> void:
	var camera_busy := _update_crouch_camera(delta)
	var held_active := held_root != null and held_flashlight != null and held_root.visible

	if held_active:
		_update_held_flashlight(delta)
	else:
		mouse_input = Vector2.ZERO

	if not camera_busy and not held_active:
		set_process(false)   # nic więcej do roboty, oszczędzamy klatki


func _update_held_flashlight(delta: float) -> void:
	var smooth := 1.0 - exp(-sway_smooth * delta)
	bob_current = bob_current.lerp(_calc_target_bob(delta), smooth)
	sway_current = sway_current.lerp(_calc_target_sway(), smooth)
	mouse_input = Vector2.ZERO

	held_flashlight.position = held_base_pos + bob_current
	held_flashlight.rotation = held_base_rot + sway_current


# Kołysanie przy chodzeniu / oddychanie w bezruchu
func _calc_target_bob(delta: float) -> Vector3:
	if _moving:
		bob_time += delta * _h_speed * BOB_SPEED_FACTOR
		return Vector3(
			cos(bob_time) * bob_amount,
			sin(bob_time * 2.0) * bob_amount * 0.7,
			0.0
		)
	_breath_time += delta
	return Vector3(0.0, sin(_breath_time * IDLE_BREATH_SPEED) * IDLE_BREATH_AMOUNT, 0.0)


# Opóźnienie latarki przy obracaniu myszką
func _calc_target_sway() -> Vector3:
	return Vector3(
		clampf(mouse_input.y * sway_amount, -sway_max, sway_max),
		clampf(mouse_input.x * sway_amount, -sway_max, sway_max),
		0.0
	)


# ---------- Ruch ----------

func _physics_process(delta: float) -> void:
	_update_crouch()
	_apply_gravity_and_jump(delta)
	_apply_movement(delta)
	move_and_slide()

	_h_speed = Vector2(velocity.x, velocity.z).length()
	_moving = is_on_floor() and _h_speed > MIN_MOVE_SPEED

	_handle_footsteps(delta)
	_update_prompt()


func _apply_gravity_and_jump(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif not _crouching and not _inventory_open() and Input.is_action_just_pressed("jump"):   # w kucki i z ekwipunkiem nie skaczemy
		velocity.y = JUMP_VELOCITY


func _apply_movement(delta: float) -> void:
	var input_dir := Vector2.ZERO
	if not _inventory_open():
		input_dir = Input.get_vector("left", "right", "forward", "back")
	var direction := (basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var speed := SPEED
	if _crouching:
		speed = crouch_speed   # w kucki nie ma sprintu
	elif Input.is_action_pressed("sprint"):
		speed = SPRINT_SPEED

	var rate := acceleration if direction != Vector3.ZERO else deceleration
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(
			Vector2(direction.x, direction.z) * speed, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y


# ---------- Pomocnicze ----------

func _disable_collisions(node: Node) -> void:
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	for child in node.get_children():
		_disable_collisions(child)
