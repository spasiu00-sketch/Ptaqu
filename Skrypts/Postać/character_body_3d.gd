class_name Gracz
extends CharacterBody3D

signal health_changed(current: float, maximum: float)
signal died

const SPEED := 4.0
const SPRINT_SPEED := 7.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENS := 0.002
const MAX_LOOK_ANGLE := deg_to_rad(89)
const MIN_MOVE_SPEED := 0.5
const BOB_SPEED_FACTOR := 1.6
const IDLE_BREATH_AMOUNT := 0.002
const IDLE_BREATH_SPEED := 1.5
const CAPSULE_MIN_MARGIN := 0.01

# --- Poprawione ustawienia Head Bobbing (zmniejszona amplituda Y dla płynniejszego horyzontu) ---
const BOB_FREQ := 1.8
const BOB_AMP_Y := 0.012
const BOB_AMP_X := 0.015
const BOB_ROLL := 0.025
const BOB_SMOOTH := 10.0
const BOB_SPRINT_AMP := 1.2
const BOB_SPRINT_ROLL := 1.8
const BOB_CROUCH_AMP := 0.5

const SOUND_SILENT_DB := -60.0

const HERO_ANIMS := {
	"idle": "Hero_idle",
	"walk": "Hero_walking",
	"crouch_idle": "Hero_idle_crouch",
	"crouch_walk": "Hero_crouch_walk",
	"stand_up": "Hero_crouch_to_stand",
	"jump": "Hero_jump",
}
const HERO_ANIMS_LOOPED := ["idle", "walk", "crouch_idle", "crouch_walk"]
const HERO_LIB := "hero"

const FATIGUE_BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D ekran : hint_screen_texture, filter_linear_mipmap;
uniform float sila : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	float d = distance(uv, vec2(0.5));
	float lod = sila * 3.5 * (0.4 + d * 1.2);
	vec3 c = textureLod(ekran, uv, lod).rgb;
	float winieta = smoothstep(0.35, 0.9, d) * sila * 0.6;
	c *= 1.0 - winieta;
	COLOR = vec4(c, 1.0);
}
"""

const InventoryUIScript := preload("res://Skrypts/Ekwipunek/inventory_ui.gd")
const HealthOverlayScript := preload("res://Skrypts/Postać/zdrowie_ekran.gd")
const OczyScript := preload("res://Skrypts/Mechaniki strachu/oczy_zjawa.gd")
const EkranSmierciScript := preload("res://Skrypts/Postać/ekran_smierci.gd")
const AudioLoop := preload("res://Skrypts/MENU/audio_loop.gd")

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

@export_group("Ruch")
@export var acceleration: float = 60.0
@export var deceleration: float = 80.0

@export_group("Wytrzymałość")
@export var stamina_enabled: bool = true
@export var sprint_duration: float = 8.0
@export var stamina_regen_time: float = 12.0
@export_range(0.05, 1.0, 0.05) var stamina_recover_threshold: float = 0.35
@export_range(1.0, 6.0, 0.5) var fatigue_effect_power: float = 3.0
@export var fatigue_sway_amount: float = 0.05
@export var fatigue_roll_amount: float = 0.06
@export_range(0.0, 1.0, 0.05) var fatigue_blur_amount: float = 1.0
@export var exhausted_rest_time: float = 5.0

@export_group("Życie")
@export var max_health: float = 100.0
@export var regen_enabled: bool = true
@export var regen_delay: float = 8.0
@export var regen_speed: float = 1.5
@export_range(1.0, 100.0, 1.0) var darken_below_percent: float = 70.0
@export var debug_health_keys: bool = true   # F3 / F4, działa tylko w buildzie debug

@export_group("Życie - oddech i kaszel")
@export var low_health_breath_sound: AudioStream
@export var low_health_breath_min_db: float = -35.0
@export var low_health_breath_max_db: float = 0.0
@export var low_health_breath_pitch_min: float = 0.9
@export var low_health_breath_pitch_max: float = 1.15
@export var health_audio_smooth: float = 1.5
@export var cough_sounds: Array[AudioStream] = []
@export_range(0.0, 1.0, 0.05) var cough_start_intensity: float = 0.4
@export var cough_interval_max: float = 10.0
@export var cough_interval_min: float = 3.0
@export var cough_volume_db: float = -3.0

@export_group("Kucanie")
@export var crouch_toggle: bool = false
@export var crouch_speed: float = 2.0
@export_range(0.3, 0.9, 0.01) var crouch_height_ratio: float = 0.6
@export var crouch_transition_speed: float = 10.0
@export var crouch_footstep_db: float = -8.0

@export_group("Kroki")
@export var footstep_sounds: Array[AudioStream] = []
@export var step_distance: float = 2.0
@export var footstep_volume_db: float = 0.0
@export var debug_footsteps: bool = false

@export_group("Sprint - sapanie")
@export var breath_sound: AudioStream
@export var breath_volume_db: float = -4.0
@export var breath_min_volume_db: float = -46.0
@export var breath_pitch_min: float = 0.9
@export var breath_pitch_max: float = 1.3
@export var breath_start_delay: float = 0.0
@export var breath_recovery_time: float = 4.0

@export_group("Sprint - bicie serca")
@export var heartbeat_sound: AudioStream
@export var heartbeat_volume_db: float = -2.0
@export var heartbeat_min_volume_db: float = -40.0
@export var heartbeat_pitch_min: float = 0.85
@export var heartbeat_pitch_max: float = 1.3
@export var heartbeat_start_delay: float = 0.0
@export var heartbeat_recovery_time: float = 6.0

@export_group("Sprint - dźwięk ogólne")
@export var sound_fade_time: float = 0.5
@export var debug_sprint_audio: bool = false

@export_group("Latarka w ręku")
@export var bob_amount: float = 0.012
@export var sway_amount: float = 0.0015
@export var sway_max: float = 0.12
@export var sway_smooth: float = 10.0
@export var start_with_flashlight: bool = false
@export var held_root_name: String = "Cofanie"
@export var held_model_name: String = "Untitled_test animacji"

@export_group("Animacje postaci")
@export var anim_player: AnimationPlayer
@export var anim_folder: String = "res://animations/"
@export var anim_blend: float = 0.2
@export var sprint_anim_speed: float = 1.4
@export var anim_transition_speed: float = 1.0
@export var anim_spam_speed: float = 3.0
@export var debug_animations: bool = false

@export_group("Skok")
@export_range(0.0, 1.0, 0.05) var jump_launch_ratio: float = 1.0
@export var jump_blocks_movement: bool = true

@export_group("Czerwone oczy")
@export var oczy_wlaczone: bool = true
@export var oczy_min_przerwa: float = 25.0
@export var oczy_max_przerwa: float = 70.0
@export var oczy_klawisz_testowy: Key = KEY_F5

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var camera: Camera3D = $Camera3D
var camera_base_pos: Vector3 = Vector3.ZERO

var footstep_player: AudioStreamPlayer = null
var breath_player: AudioStreamPlayer = null
var heart_player: AudioStreamPlayer = null
var interact_ray: RayCast3D = null
var flashlight: Flashlight = null
var held_flashlight: Node3D = null
var held_root: Node3D = null
var prompt_label: Label
var inventory_ui = null
var oczy = null

var kontrola_zablokowana: bool = false
var kamera_zablokowana: bool = false

# Używane przez inne skrypty (jumpscare.gd, cien_gracza.gd):
var shake_offset: Vector2 = Vector2.ZERO          # chwilowy wstrząs kamery (h_offset / v_offset)
var camera_extra_offset: Vector3 = Vector3.ZERO   # dodatkowe przesunięcie kamery (lokalnie)

var health: float = 100.0
var health_overlay = null
var _since_damage: float = 0.0
var _dead: bool = false
var low_breath_player: AudioStreamPlayer = null
var cough_player: AudioStreamPlayer = null
var _health_audio_level: float = 0.0
var _cough_timer: float = -1.0

var stamina: float = 1.0
var _exhausted: bool = false
var _rest_left: float = 0.0
var _fatigue: float = 0.0
var _fatigue_time: float = 0.0
var _fatigue_blur_mat: ShaderMaterial = null
var _fatigue_blur_rect: ColorRect = null
var _fatigue_blur_copy: BackBufferCopy = null

var _h_speed: float = 0.0
var _moving: bool = false
var _sprinting: bool = false
var step_progress: float = 0.0

var _sprint_time: float = 0.0
var _breath_left: float = 0.0
var _heart_left: float = 0.0

var _crouching: bool = false
var _crouch_input: bool = false
var _col: CollisionShape3D = null
var _stand_h: float = 1.8
var _crouch_h: float = 1.1
var _stand_y: float = 0.0
var _cam_offset: float = 0.0

var _anim_current: String = ""
var _transition: String = ""
var _was_crouching: bool = false
var _jumped: bool = false
var _jump_pending: bool = false
var _jump_wait: float = 0.0

var bob_czas := 0.0
var _head_bob_offset := Vector3.ZERO
var _head_bob_roll: float = 0.0
var _applied_extra := Vector3.ZERO

var held_base_pos := Vector3.ZERO
var held_base_rot := Vector3.ZERO
var bob_time: float = 0.0
var _breath_time: float = 0.0
var bob_current := Vector3.ZERO
var sway_current := Vector3.ZERO
var mouse_input := Vector2.ZERO


func _ready() -> void:
	camera_base_pos = camera.position
	set_process(false)
	_setup_input_actions()
	_setup_footstep_player()
	_setup_sprint_audio()
	_create_prompt_label()
	_find_nodes()
	_setup_flashlight()
	_setup_held_item()
	_setup_crouch()
	_setup_animations()
	_setup_inventory()
	_setup_health()
	_setup_oczy()
	_setup_fatigue_blur()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _find_nodes() -> void:
	interact_ray = find_child("InteractRay", true, false)
	if interact_ray:
		interact_ray.add_exception(self)
	else:
		push_warning("Brak węzła InteractRay (RayCast3D) pod Camera3D")

	for light in find_children("*", "SpotLight3D", true, false):
		if light is Flashlight:
			flashlight = light
			break

	held_flashlight = _find_first_node([held_model_name, "HeldFlashlight"])
	if held_flashlight == null:
		held_flashlight = flashlight

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
	_disable_collisions(held_root)
	held_root.visible = start_with_flashlight and flashlight != null
	set_process(held_root.visible)


func _setup_inventory() -> void:
	inventory_ui = InventoryUIScript.new()
	inventory_ui.gracz = self
	add_child(inventory_ui)


func _setup_oczy() -> void:
	if not oczy_wlaczone:
		return
	oczy = OczyScript.new()
	oczy.gracz = self
	oczy.min_przerwa = oczy_min_przerwa
	oczy.max_przerwa = oczy_max_przerwa
	oczy.klawisz_testowy = oczy_klawisz_testowy
	oczy.tryb_testowy = OS.is_debug_build()
	add_child(oczy)


func _setup_animations() -> void:
	if anim_player == null:
		anim_player = find_child("AnimationPlayer2", true, false) as AnimationPlayer
	if anim_player == null:
		push_warning("Brak AnimationPlayera modelu bohatera - przypisz 'Anim Player' w Inspektorze gracza (grupa Animacje postaci)")
		return

	var lib := AnimationLibrary.new()
	for key in HERO_ANIMS:
		var path: String = anim_folder.path_join(str(HERO_ANIMS[key]) + ".res")
		var anim := load(path) as Animation
		if anim == null:
			push_warning("Nie wczytano animacji: " + path)
			continue
		anim.loop_mode = Animation.LOOP_LINEAR if key in HERO_ANIMS_LOOPED else Animation.LOOP_NONE
		lib.add_animation(key, anim)

	if anim_player.has_animation_library(HERO_LIB):
		anim_player.remove_animation_library(HERO_LIB)
	anim_player.add_animation_library(HERO_LIB, lib)
	_play_anim("idle")


func _play_anim(key: String) -> void:
	if key == _anim_current:
		return
	var full := HERO_LIB + "/" + key
	if not anim_player.has_animation(full):
		return
	_anim_current = key
	anim_player.play(full, anim_blend)
	if debug_animations:
		print("animacja: ", full)


func _start_transition(down: bool) -> void:
	var full := HERO_LIB + "/stand_up"
	if anim_player == null or not anim_player.has_animation(full):
		_transition = ""
		return
	var length := anim_player.get_animation(full).length
	var spam := _transition != ""
	var pos := anim_player.current_animation_position if spam else (length - 0.001 if down else 0.0)
	var speed := anim_transition_speed * (anim_spam_speed if spam else 1.0)

	_transition = "down" if down else "up"
	_anim_current = "stand_up"
	anim_player.speed_scale = 1.0
	anim_player.play(full, 0.0 if spam else anim_blend, -speed if down else speed)
	anim_player.seek(pos, true)
	if debug_animations:
		print("przejście: ", _transition, " (spam: ", spam, ", tempo: ", speed, ")")


func _transition_done() -> bool:
	if not anim_player.is_playing():
		return true
	var length := anim_player.get_animation(HERO_LIB + "/stand_up").length
	var pos := anim_player.current_animation_position
	return pos >= length - 0.03 if _transition == "up" else pos <= 0.03


func _update_animation() -> void:
	if anim_player == null:
		return

	if _crouching != _was_crouching:
		_was_crouching = _crouching
		if anim_player.has_animation(HERO_LIB + "/stand_up"):
			_start_transition(_crouching)

	if _transition != "":
		if not _transition_done():
			return
		_transition = ""

	if (_jump_pending or (_jumped and not is_on_floor())) and anim_player.has_animation(HERO_LIB + "/jump"):
		anim_player.speed_scale = 1.0
		_play_anim("jump")
		return

	var key: String
	var speed := 1.0
	if _crouching:
		key = "crouch_walk" if _moving else "crouch_idle"
	elif _moving:
		key = "walk"
		if _sprinting:
			speed = sprint_anim_speed
	else:
		key = "idle"

	anim_player.speed_scale = speed
	_play_anim(key)


func _setup_fatigue_blur() -> void:
	var warstwa := CanvasLayer.new()
	warstwa.name = "FatigueBlurLayer"
	warstwa.layer = 1
	add_child(warstwa)

	var shader := Shader.new()
	shader.code = FATIGUE_BLUR_SHADER
	_fatigue_blur_mat = ShaderMaterial.new()
	_fatigue_blur_mat.shader = shader

	_fatigue_blur_copy = BackBufferCopy.new()
	_fatigue_blur_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_fatigue_blur_copy.visible = false
	warstwa.add_child(_fatigue_blur_copy)

	_fatigue_blur_rect = ColorRect.new()
	_fatigue_blur_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fatigue_blur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fatigue_blur_rect.material = _fatigue_blur_mat
	_fatigue_blur_rect.visible = false
	warstwa.add_child(_fatigue_blur_rect)


func _update_stamina(delta: float) -> void:
	if not stamina_enabled:
		stamina = 1.0
		_exhausted = false
		_rest_left = 0.0
		_fatigue = 0.0
		_update_fatigue_blur()
		return

	if _sprinting:
		stamina -= delta / maxf(sprint_duration, 0.1)
	else:
		var mnoznik := 1.0 if _moving else 1.5
		stamina += delta / maxf(stamina_regen_time, 0.1) * mnoznik
	stamina = clampf(stamina, 0.0, 1.0)

	if stamina <= 0.0:
		if not _exhausted:
			_rest_left = exhausted_rest_time
		_exhausted = true
	elif _exhausted and stamina >= stamina_recover_threshold:
		_exhausted = false

	_rest_left = maxf(_rest_left - delta, 0.0)

	_fatigue = 1.0 - stamina
	_update_fatigue_blur()


func _update_fatigue_blur() -> void:
	if _fatigue_blur_rect == null or _fatigue_blur_mat == null:
		return
	var blisko := pow(_fatigue, fatigue_effect_power)
	var widoczne := blisko > 0.01
	if widoczne:
		_fatigue_blur_mat.set_shader_parameter("sila", clampf(blisko * fatigue_blur_amount, 0.0, 1.0))
	_fatigue_blur_rect.visible = widoczne
	_fatigue_blur_copy.visible = widoczne


func _can_sprint() -> bool:
	return not (stamina_enabled and _exhausted)


func is_exhausted() -> bool:
	return _exhausted


func is_resting() -> bool:
	return _rest_left > 0.0


func moze_sterowac() -> bool:
	return not _dead and not kontrola_zablokowana and not _inventory_open()


func _setup_health() -> void:
	health = max_health
	_since_damage = 0.0
	_dead = false
	health_overlay = HealthOverlayScript.new()
	add_child(health_overlay)
	_update_health_overlay(true)

	low_breath_player = AudioStreamPlayer.new()
	low_breath_player.name = "LowHealthBreathPlayer"
	low_breath_player.volume_db = low_health_breath_min_db
	add_child(low_breath_player)
	AudioLoop.zapetl(low_health_breath_sound)

	cough_player = AudioStreamPlayer.new()
	cough_player.name = "CoughPlayer"
	cough_player.volume_db = cough_volume_db
	add_child(cough_player)


func take_damage(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	_since_damage = 0.0
	if health_overlay:
		health_overlay.blysk_obrazen()
	_set_health(health - amount)


func heal(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	_set_health(health + amount)


func is_dead() -> bool:
	return _dead


func _set_health(value: float) -> void:
	health = clampf(value, 0.0, max_health)
	health_changed.emit(health, max_health)
	_update_health_overlay()
	if health <= 0.0 and not _dead:
		_die()


func _update_health_overlay(instant: bool = false) -> void:
	if health_overlay == null:
		return
	health_overlay.ustaw_natezenie(_health_intensity(), instant)


func _health_intensity() -> float:
	var percent := health / maxf(max_health, 0.001) * 100.0
	return clampf((darken_below_percent - percent) / maxf(darken_below_percent, 0.01), 0.0, 1.0)


func _update_health_audio(delta: float) -> void:
	var intensity := _health_intensity()
	_health_audio_level = lerpf(_health_audio_level, intensity, 1.0 - exp(-health_audio_smooth * delta))

	if low_breath_player != null and low_health_breath_sound != null:
		if _health_audio_level > 0.02:
			if not low_breath_player.playing:
				low_breath_player.stream = low_health_breath_sound
				low_breath_player.play()
			var k := pow(_health_audio_level, 1.5)
			low_breath_player.volume_db = lerpf(low_health_breath_min_db, low_health_breath_max_db, k)
			low_breath_player.pitch_scale = lerpf(
					low_health_breath_pitch_min, low_health_breath_pitch_max, _health_audio_level)
		elif low_breath_player.playing:
			low_breath_player.stop()

	if _dead or cough_player == null or cough_sounds.is_empty() or intensity < cough_start_intensity:
		_cough_timer = -1.0
		return
	if _cough_timer < 0.0:
		_cough_timer = _next_cough_interval(intensity)
	_cough_timer -= delta
	if _cough_timer <= 0.0:
		if not cough_player.playing:
			cough_player.stream = cough_sounds.pick_random()
			cough_player.volume_db = cough_volume_db
			cough_player.pitch_scale = randf_range(0.92, 1.08)
			cough_player.play()
		_cough_timer = _next_cough_interval(intensity)


func _next_cough_interval(intensity: float) -> float:
	var t := clampf((intensity - cough_start_intensity) / maxf(1.0 - cough_start_intensity, 0.01), 0.0, 1.0)
	var avg := lerpf(cough_interval_max, cough_interval_min, t)
	return randf_range(avg * 0.7, avg * 1.3)


func _update_health(delta: float) -> void:
	if _dead:
		return
	_since_damage += delta
	if regen_enabled and health < max_health and _since_damage >= regen_delay:
		_set_health(health + regen_speed * delta)


func _die() -> void:
	kamera_zablokowana = false
	if _dead:
		return
	_dead = true
	died.emit()
	if oczy != null:
		oczy.wlaczony = false
	if _inventory_open():
		_toggle_inventory()
	if prompt_label:
		prompt_label.visible = false
	if health_overlay:
		health_overlay.smierc()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var ekran := EkranSmierciScript.new()
	add_child(ekran)
	ekran.pokaz()


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

	_col.shape = _col.shape.duplicate() as Shape3D
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


func _can_stand() -> bool:
	if _col == null:
		return true
	var standing_shape := _col.shape.duplicate() as Shape3D
	_set_shape_height(standing_shape, _stand_h)
	var standing_transform := _col.global_transform
	standing_transform.origin += Vector3.UP * (_stand_h - _crouch_h) * 0.5
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = standing_shape
	query.transform = standing_transform
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _set_crouching(state: bool) -> void:
	_crouching = state
	if _col != null:
		var height := _crouch_h if state else _stand_h
		_set_shape_height(_col.shape, height)
		_col.position.y = _stand_y - (_stand_h - height) * 0.5
	set_process(true)


# --- Poprawiona obsługa pozycji kamery przy kucaniu ---
func _update_crouch_camera(delta: float) -> bool:
	var target := -(_stand_h - _crouch_h) if _crouching else 0.0
	if _cam_offset == target:
		return false
	var new_offset := lerpf(_cam_offset, target, 1.0 - exp(-crouch_transition_speed * delta))
	if absf(new_offset - target) < 0.001:
		new_offset = target
	_cam_offset = new_offset

	camera.position = camera_base_pos + Vector3(0.0, _cam_offset, 0.0) + _head_bob_offset + _applied_extra
	return new_offset != target


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
	if debug_health_keys and OS.is_debug_build() \
			and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F3:
			take_damage(10.0)
		elif event.physical_keycode == KEY_F4:
			heal(10.0)

	if _dead:
		return

	if event.is_action_pressed("inventory") and not event.is_echo():
		if not kontrola_zablokowana:
			_toggle_inventory()
		get_viewport().set_input_as_handled()
		return

	if _inventory_open():
		if event.is_action_pressed("ui_cancel"):
			_toggle_inventory()
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and not kontrola_zablokowana and not kamera_zablokowana:
		_look(event.relative)

	if event.is_action_pressed("interact") and not event.is_echo() and not kontrola_zablokowana:
		_try_interact()

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and not kontrola_zablokowana:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _look(relative: Vector2) -> void:
	rotate_y(-relative.x * MOUSE_SENS)
	camera.rotation.x = clampf(camera.rotation.x - relative.y * MOUSE_SENS, -MAX_LOOK_ANGLE, MAX_LOOK_ANGLE)
	mouse_input += relative


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


func give_flashlight() -> void:
	if flashlight:
		flashlight.pick_up()
	if held_root:
		held_root.visible = true
		mouse_input = Vector2.ZERO
		set_process(true)


func schowaj_latarke() -> void:
	if flashlight:
		flashlight.zabierz()
	if held_root:
		held_root.visible = false
	mouse_input = Vector2.ZERO


func _create_prompt_label() -> void:
	var hud := CanvasLayer.new()
	hud.layer = 2
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
	prompt_label.visible = target != null and not _inventory_open() and not kontrola_zablokowana
	if target:
		var text = target.get("prompt_text")
		var prefix = target.get("prompt_prefix")   # drzwi/szuflady podają "[LPM] ", reszta zostaje na "[E] "
		prompt_label.text = (str(prefix) if prefix != null else "[E] ") + (str(text) if text != null else "Użyj")


func _setup_footstep_player() -> void:
	footstep_player = find_child("FootstepPlayer", true, false) as AudioStreamPlayer
	if footstep_player == null:
		footstep_player = AudioStreamPlayer.new()
		footstep_player.name = "FootstepPlayer"
		add_child(footstep_player)
	footstep_player.volume_db = footstep_volume_db
	footstep_player.max_polyphony = 3


func _handle_footsteps(delta: float) -> void:
	if _moving:
		step_progress += _h_speed * delta
		var interval := maxf(step_distance, 0.1)
		if step_progress >= interval:
			step_progress = fmod(step_progress, interval)
			_play_step()
	else:
		step_progress = maxf(step_distance, 0.1)


func _play_step() -> void:
	if not footstep_sounds.is_empty():
		footstep_player.stream = footstep_sounds.pick_random()
	if footstep_player.stream == null:
		return
	footstep_player.pitch_scale = randf_range(0.9, 1.1)
	footstep_player.volume_db = footstep_volume_db + (crouch_footstep_db if _crouching else 0.0)
	footstep_player.play()
	if debug_footsteps:
		print("krok")


func _setup_sprint_audio() -> void:
	breath_player = _make_loop_player("BreathPlayer", breath_volume_db)
	heart_player = _make_loop_player("HeartPlayer", heartbeat_volume_db)
	AudioLoop.zapetl(breath_sound)
	AudioLoop.zapetl(heartbeat_sound)
	if breath_sound == null:
		push_warning("Brak dźwięku sapania: uzupełnij 'Breath Sound' w Inspektorze gracza (grupa Sprint - sapanie)")
	if heartbeat_sound == null:
		push_warning("Brak dźwięku serca: uzupełnij 'Heartbeat Sound' w Inspektorze gracza (grupa Sprint - bicie serca)")


func _make_loop_player(player_name: String, volume_db: float) -> AudioStreamPlayer:
	var p := find_child(player_name, true, false) as AudioStreamPlayer
	if p == null:
		p = AudioStreamPlayer.new()
		p.name = player_name
		add_child(p)
	p.volume_db = volume_db
	return p


func _update_sprint_audio(delta: float) -> void:
	if _sprinting:
		_sprint_time += delta
	else:
		_sprint_time = 0.0

	_breath_left = _tick_sound_timer(_breath_left, breath_start_delay, breath_recovery_time, delta)
	_heart_left = _tick_sound_timer(_heart_left, heartbeat_start_delay, heartbeat_recovery_time, delta)

	var breath_active := _breath_left > 0.0
	var breath_target_db := breath_volume_db
	if stamina_enabled:
		breath_active = breath_active or _fatigue > 0.02
		breath_target_db = lerpf(breath_min_volume_db, breath_volume_db, pow(_fatigue, 1.3))
		if breath_player != null:
			breath_player.pitch_scale = lerpf(breath_pitch_min, breath_pitch_max, _fatigue)

	_drive_loop(breath_player, breath_sound, breath_target_db, breath_active, delta)
	var heart_active := _heart_left > 0.0
	var heart_target_db := heartbeat_volume_db
	if stamina_enabled:
		heart_active = heart_active or _fatigue > 0.1
		heart_target_db = lerpf(heartbeat_min_volume_db, heartbeat_volume_db, pow(_fatigue, 1.3))
		if heart_player != null:
			heart_player.pitch_scale = lerpf(heartbeat_pitch_min, heartbeat_pitch_max, _fatigue)

	_drive_loop(heart_player, heartbeat_sound, heart_target_db, heart_active, delta)


func _tick_sound_timer(left: float, start_delay: float, recovery: float, delta: float) -> float:
	if _sprinting:
		if _sprint_time >= start_delay:
			return maxf(recovery, 0.01)
		return left
	return maxf(left - delta, 0.0)


func _drive_loop(player: AudioStreamPlayer, stream: AudioStream, base_db: float, active: bool, delta: float) -> void:
	if player == null or stream == null:
		return

	var fade_speed := absf(base_db - SOUND_SILENT_DB) / maxf(sound_fade_time, 0.05)

	if active:
		if not player.playing:
			var same_stream := player.stream == stream
			player.stream = stream
			if not same_stream or player.volume_db <= SOUND_SILENT_DB:
				player.volume_db = SOUND_SILENT_DB
			player.play()
			if debug_sprint_audio:
				print("start dźwięku: ", player.name)
		player.volume_db = move_toward(player.volume_db, base_db, fade_speed * delta)
	elif player.playing:
		player.volume_db -= fade_speed * delta
		if player.volume_db <= SOUND_SILENT_DB:
			player.stop()
			if debug_sprint_audio:
				print("koniec dźwięku: ", player.name)


func _process(delta: float) -> void:
	var camera_busy := _update_crouch_camera(delta)
	var held_active := held_root != null and held_flashlight != null and held_root.visible

	if held_active:
		_update_held_flashlight(delta)
	else:
		mouse_input = Vector2.ZERO

	if not camera_busy and not held_active:
		set_process(false)


func _update_held_flashlight(delta: float) -> void:
	var smooth := 1.0 - exp(-sway_smooth * delta)
	bob_current = bob_current.lerp(_calc_target_bob(delta), smooth)
	sway_current = sway_current.lerp(_calc_target_sway(), smooth)
	mouse_input = Vector2.ZERO

	held_flashlight.position = held_base_pos + bob_current
	held_flashlight.rotation = held_base_rot + sway_current


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


func _calc_target_sway() -> Vector3:
	return Vector3(
		clampf(mouse_input.y * sway_amount, -sway_max, sway_max),
		clampf(mouse_input.x * sway_amount, -sway_max, sway_max),
		0.0
	)


func _physics_process(delta: float) -> void:
	if _dead:
		_physics_dead(delta)
		return

	_update_crouch()
	_apply_gravity_and_jump(delta)
	_apply_movement(delta)
	move_and_slide()

	_h_speed = Vector2(velocity.x, velocity.z).length()
	_moving = is_on_floor() and _h_speed > MIN_MOVE_SPEED
	_sprinting = _moving and not _crouching and not _inventory_open() \
			and not kontrola_zablokowana and Input.is_action_pressed("sprint") and _can_sprint()

	_update_stamina(delta)
	_update_head_bob(delta)
	_update_animation()
	_update_sprint_audio(delta)
	_handle_footsteps(delta)
	_update_health(delta)
	_update_health_audio(delta)
	_update_prompt()


func _physics_dead(delta: float) -> void:
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(Vector2.ZERO, deceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()

	_h_speed = 0.0
	_moving = false
	_sprinting = false
	_update_stamina(delta)
	_update_head_bob(delta)
	_update_animation()
	_update_sprint_audio(delta)
	_update_health_audio(delta)


func _apply_gravity_and_jump(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
		_jump_pending = false
		return

	if _jump_pending:
		_jump_wait -= delta
		if _jump_wait <= 0.0:
			_launch_jump()
		return

	_jumped = false
	if not _crouching and not _inventory_open() and not kontrola_zablokowana and not is_resting() \
			and Input.is_action_just_pressed("jump"):
		_start_jump()


func _start_jump() -> void:
	var full := HERO_LIB + "/jump"
	if anim_player != null and anim_player.has_animation(full):
		_jump_pending = true
		_jump_wait = anim_player.get_animation(full).length * jump_launch_ratio
		_anim_current = ""
	else:
		_launch_jump()


func _launch_jump() -> void:
	_jump_pending = false
	_jumped = true
	velocity.y = JUMP_VELOCITY


func _apply_movement(delta: float) -> void:
	var input_dir := Vector2.ZERO
	var skok_blokuje := _jump_pending and jump_blocks_movement
	if not _inventory_open() and not kontrola_zablokowana and not is_resting() and not skok_blokuje:
		input_dir = Input.get_vector("left", "right", "forward", "back")
	var direction := (basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var speed := SPEED
	if _crouching:
		speed = crouch_speed
	elif input_dir != Vector2.ZERO and Input.is_action_pressed("sprint") and _can_sprint() \
			and not kontrola_zablokowana and not is_resting():
		speed = SPRINT_SPEED

	var rate := acceleration if direction != Vector3.ZERO else deceleration
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(
			Vector2(direction.x, direction.z) * speed, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y


# --- Bezpieczne obliczanie Head Bobbing względem pozycji bazowej (bez accumulowania '+=') ---
func _update_head_bob(delta: float) -> void:
	var cel_poz := Vector3.ZERO
	var cel_roll := 0.0

	if _moving:
		var amp := 1.0
		var roll_amp := 1.0
		if _sprinting:
			amp = BOB_SPRINT_AMP
			roll_amp = BOB_SPRINT_ROLL
		elif _crouching:
			amp = BOB_CROUCH_AMP
			roll_amp = BOB_CROUCH_AMP

		bob_czas += delta * _h_speed * BOB_FREQ * 0.5
		cel_poz = Vector3(
			cos(bob_czas) * BOB_AMP_X * amp,
			sin(bob_czas * 2.0) * BOB_AMP_Y * amp,
			0.0
		)
		cel_roll = cos(bob_czas) * BOB_ROLL * roll_amp

	var smooth := 1.0 - exp(-BOB_SMOOTH * delta)

	_head_bob_offset = _head_bob_offset.lerp(cel_poz, smooth)
	_applied_extra = _applied_extra.lerp(camera_extra_offset, smooth)
	_head_bob_roll = lerpf(_head_bob_roll, cel_roll, smooth)

	var blisko := pow(_fatigue, fatigue_effect_power)
	_fatigue_time += delta * (1.0 + blisko * 1.5)
	camera.h_offset = sin(_fatigue_time * 1.3) * fatigue_sway_amount * blisko + shake_offset.x
	camera.v_offset = sin(_fatigue_time * 2.1) * fatigue_sway_amount * 0.6 * blisko + shake_offset.y
	var fatigue_roll := sin(_fatigue_time * 0.9) * fatigue_roll_amount * blisko

	camera.rotation.z = _head_bob_roll + fatigue_roll
	camera.position = camera_base_pos + Vector3(0.0, _cam_offset, 0.0) + _head_bob_offset + _applied_extra


func _disable_collisions(node: Node) -> void:
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	for child in node.get_children():
		_disable_collisions(child)
