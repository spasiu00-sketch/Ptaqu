extends CharacterBody3D

# ---------- Sygnały ----------

signal health_changed(current: float, maximum: float)
signal died

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

# head bob (kołysanie kamery przy chodzeniu)
const BOB_FREQ := 2.4                # szybkość kołysania
const BOB_AMP_Y := 0.04              # góra-dół (małe)
const BOB_AMP_X := 0.05              # na boki
const BOB_ROLL := 0.025              # przechył kamery (w radianach)
const BOB_SMOOTH := 10.0             # płynność włączania/wyłączania efektu
const BOB_SPRINT_AMP := 1.6          # mnożnik siły kołysania przy sprincie
const BOB_SPRINT_ROLL := 1.8         # mnożnik przechyłu przy sprincie
const BOB_CROUCH_AMP := 0.5          # mnożnik siły kołysania w kucki

# dźwięki sprintu (sapanie, serce)
const SOUND_SILENT_DB := -40.0       # tyle uznajemy za ciszę przy wyciszaniu / wzmacnianiu

# rozmazanie ekranu przy zmęczeniu (shader czyta obraz ekranu i rozmywa go mipmapami)
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

# preload zamiast class_name: działa nawet, gdy Godot nie odświeżył listy klas
const InventoryUIScript := preload("res://Skrypts/inventory_ui.gd")
const GlitchScript := preload("res://Skrypts/glitch_kamery.gd")
const HealthOverlayScript := preload("res://Skrypts/zdrowie_ekran.gd")
const OczyScript := preload("res://Skrypts/oczy_zjawa.gd")

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

@export_group("Wytrzymałość")
@export var stamina_enabled: bool = true
@export var sprint_duration: float = 8.0               # ile sekund ciągłego sprintu do pełnego wyczerpania
@export var stamina_regen_time: float = 12.0           # ile sekund odpoczynku do pełnej wytrzymałości
@export_range(0.05, 1.0, 0.05) var stamina_recover_threshold: float = 0.35   # po wyczerpaniu sprint wraca dopiero po tym poziomie
@export_range(1.0, 6.0, 0.5) var fatigue_effect_power: float = 3.0           # im więcej, tym później (bliżej limitu) wchodzą kołysanie i rozmazanie
@export var fatigue_sway_amount: float = 0.05          # kołysanie kamery na boki / góra-dół (przesunięcie)
@export var fatigue_roll_amount: float = 0.06          # przechył kamery (radiany)
@export_range(0.0, 1.0, 0.05) var fatigue_blur_amount: float = 1.0           # siła rozmazania ekranu

@export_group("Życie")
@export var max_health: float = 100.0
@export var regen_enabled: bool = true                 # true = życie samo wraca (jak w CoD)
@export var regen_delay: float = 8.0                   # ile sekund bez obrażeń, zanim życie zacznie wracać
@export var regen_speed: float = 1.5                   # punktów życia na sekundę (1.5 = pełne życie w ok. minutę)
@export_range(1.0, 100.0, 1.0) var darken_below_percent: float = 70.0   # poniżej tego % życia ekran zaczyna ciemnieć
@export var restart_on_death: bool = true              # po śmierci wczytaj scenę od nowa
@export var death_delay: float = 3.0                   # ile sekund po śmierci do restartu
@export var debug_health_keys: bool = true             # F3 = -10 życia, F4 = +10 życia (do testów, wyłącz w wersji końcowej)

@export_group("Życie - oddech i kaszel")
@export var low_health_breath_sound: AudioStream       # ciężki oddech, gra w kółko; im mniej życia, tym głośniej i szybciej
@export var low_health_breath_min_db: float = -35.0    # głośność tuż po przekroczeniu progu (ledwo słyszalny)
@export var low_health_breath_max_db: float = 0.0      # głośność przy prawie zerowym życiu
@export var low_health_breath_pitch_min: float = 0.9   # wysokość dźwięku na początku
@export var low_health_breath_pitch_max: float = 1.15  # wysokość dźwięku przy bardzo niskim życiu
@export var health_audio_smooth: float = 1.5           # płynność zmiany głośności (mniej = wolniej)
@export var cough_sounds: Array[AudioStream] = []      # dźwięki kaszlu / krztuszenia (losowe, opcjonalne)
@export_range(0.0, 1.0, 0.05) var cough_start_intensity: float = 0.4   # od jakiego stopnia osłabienia zaczyna się kaszel
@export var cough_interval_max: float = 10.0           # średnia przerwa między kaszlnięciami na początku (s)
@export var cough_interval_min: float = 3.0            # średnia przerwa przy bardzo niskim życiu (s)
@export var cough_volume_db: float = -3.0

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

@export_group("Sprint - sapanie")
@export var breath_sound: AudioStream                  # dźwięk sapania (gra w kółko podczas sprintu)
@export var breath_volume_db: float = -4.0             # głośność sapania przy pełnym zmęczeniu (maksimum)
@export var breath_min_volume_db: float = -32.0        # głośność sapania na początku sprintu (przy pełnej wytrzymałości)
@export var breath_pitch_min: float = 0.9              # wysokość dźwięku przy pełnej wytrzymałości
@export var breath_pitch_max: float = 1.2              # wysokość dźwięku przy pełnym zmęczeniu
@export var breath_start_delay: float = 0.0            # ile sekund sprintu, zanim zacznie sapać
@export var breath_recovery_time: float = 4.0          # ile sekund sapie po przestaniu biegu (minimum)

@export_group("Sprint - bicie serca")
@export var heartbeat_sound: AudioStream               # dźwięk bicia serca (gra w kółko podczas sprintu)
@export var heartbeat_volume_db: float = -2.0
@export var heartbeat_start_delay: float = 0.0         # ile sekund sprintu, zanim serce zacznie bić
@export var heartbeat_recovery_time: float = 6.0       # ile sekund bije po przestaniu biegu

@export_group("Sprint - dźwięk ogólne")
@export var sound_fade_time: float = 0.5               # czas płynnego włączania / wyciszania dźwięków
@export var debug_sprint_audio: bool = false           # true = wypisuje w Output, kiedy dźwięki startują

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

@export_group("Czerwone oczy")
@export var oczy_wlaczone: bool = true     # losowe zdarzenie z oczami (oczy_zjawa.gd)
@export var oczy_min_przerwa: float = 25.0 # minimalny czas między zdarzeniami (s)
@export var oczy_max_przerwa: float = 70.0 # maksymalny czas między zdarzeniami (s)
@export var oczy_klawisz_testowy: Key = KEY_F5   # F3 / F4 zajęte przez testy życia

# ---------- Stan ----------

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var camera: Camera3D = $Camera3D

var footstep_player = null          # AudioStreamPlayer lub AudioStreamPlayer3D
var breath_player: AudioStreamPlayer = null
var heart_player: AudioStreamPlayer = null
var interact_ray: RayCast3D = null
var flashlight: Flashlight = null
var held_flashlight: Node3D = null  # węzeł kołysany przy chodzeniu (model latarki)
var held_root: Node3D = null        # węzeł ukrywany/pokazywany (Cofanie)
var prompt_label: Label
var inventory_ui = null            # instancja inventory_ui.gd
var glitch = null                  # instancja glitch_kamery.gd
var oczy = null                    # instancja oczy_zjawa.gd

# true = zdarzenie (np. czerwone oczy) przejęło kamerę: blokuje myszkę i ruch gracza
var kontrola_zablokowana: bool = false

# życie
var health: float = 100.0
var health_overlay = null          # instancja zdrowie_ekran.gd
var _since_damage: float = 0.0     # ile sekund minęło od ostatnich obrażeń
var _dead: bool = false
var low_breath_player: AudioStreamPlayer = null   # oddech przy niskim życiu
var cough_player: AudioStreamPlayer = null
var _health_audio_level: float = 0.0   # wygładzone natężenie osłabienia (0..1) dla dźwięku
var _cough_timer: float = -1.0

# wytrzymałość
var stamina: float = 1.0            # 1.0 = pełna, 0.0 = wyczerpany
var _exhausted: bool = false        # true = nie można sprintować, dopóki wytrzymałość nie wróci do progu
var _fatigue: float = 0.0           # 1.0 - stamina (0 = wypoczęty, 1 = na limicie)
var _fatigue_time: float = 0.0      # czas do kołysania kamery przy zmęczeniu
var _fatigue_blur_mat: ShaderMaterial = null
var _fatigue_blur_rect: ColorRect = null

# ruch (liczone raz na klatkę fizyki)
var _h_speed: float = 0.0
var _moving: bool = false
var _sprinting: bool = false
var step_progress: float = 0.0

# dźwięki sprintu
var _sprint_time: float = 0.0     # ile sekund z rzędu gracz sprintuje
var _breath_left: float = 0.0     # ile jeszcze sekund ma grać sapanie
var _heart_left: float = 0.0      # ile jeszcze sekund ma grać serce

# kucanie
var _crouching: bool = false
var _crouch_input: bool = false
var _col: CollisionShape3D = null
var _stand_h: float = 1.8     # nadpisywane wysokością z kształtu kolizji
var _crouch_h: float = 1.1
var _stand_y: float = 0.0     # pozycja Y węzła kolizji w staniu
var _cam_offset: float = 0.0  # aktualne przesunięcie kamery w dół (<= 0)

# head bob kamery
var bob_czas := 0.0
var _head_bob_offset := Vector3.ZERO   # aktualne przesunięcie kamery od bobu
var _head_bob_roll: float = 0.0        # aktualny przechył kamery od bobu

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
	_setup_sprint_audio()
	_create_prompt_label()
	_find_nodes()
	_setup_flashlight()
	_setup_held_item()
	_setup_crouch()
	_setup_inventory()
	_setup_health()
	_setup_glitch()
	_setup_oczy()
	_setup_fatigue_blur()
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


# Losowe zdarzenie: kamera odwraca się w stronę czerwonych oczu (oczy_zjawa.gd).
# Na czas zdarzenia skrypt ustawia kontrola_zablokowana = true.
func _setup_oczy() -> void:
	if not oczy_wlaczone:
		return
	oczy = OczyScript.new()
	oczy.gracz = self
	oczy.min_przerwa = oczy_min_przerwa
	oczy.max_przerwa = oczy_max_przerwa
	oczy.klawisz_testowy = oczy_klawisz_testowy
	add_child(oczy)


# ---------- Wytrzymałość ----------

# Warstwa z rozmazaniem ekranu (layer 1, więc napis [E] i ekwipunek zostają ostre)
func _setup_fatigue_blur() -> void:
	var warstwa := CanvasLayer.new()
	warstwa.name = "FatigueBlurLayer"
	warstwa.layer = 1
	add_child(warstwa)

	var shader := Shader.new()
	shader.code = FATIGUE_BLUR_SHADER
	_fatigue_blur_mat = ShaderMaterial.new()
	_fatigue_blur_mat.shader = shader

	_fatigue_blur_rect = ColorRect.new()
	_fatigue_blur_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fatigue_blur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fatigue_blur_rect.material = _fatigue_blur_mat
	_fatigue_blur_rect.visible = false
	warstwa.add_child(_fatigue_blur_rect)


# Sprint zużywa wytrzymałość, odpoczynek ją odnawia (w bezruchu szybciej).
# Po dojściu do zera sprint jest zablokowany, dopóki wytrzymałość nie wróci do progu.
func _update_stamina(delta: float) -> void:
	if not stamina_enabled:
		stamina = 1.0
		_exhausted = false
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
		_exhausted = true
	elif _exhausted and stamina >= stamina_recover_threshold:
		_exhausted = false

	_fatigue = 1.0 - stamina
	_update_fatigue_blur()


func _update_fatigue_blur() -> void:
	if _fatigue_blur_rect == null:
		return
	var blisko := pow(_fatigue, fatigue_effect_power)
	_fatigue_blur_mat.set_shader_parameter("sila", clampf(blisko * fatigue_blur_amount, 0.0, 1.0))
	_fatigue_blur_rect.visible = blisko > 0.01


func _can_sprint() -> bool:
	return not (stamina_enabled and _exhausted)


func is_exhausted() -> bool:
	return _exhausted


# ---------- Życie ----------

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
	_prepare_loop(low_health_breath_sound)

	cough_player = AudioStreamPlayer.new()
	cough_player.name = "CoughPlayer"
	cough_player.volume_db = cough_volume_db
	add_child(cough_player)


# Zadaj obrażenia graczowi (wywołuj np. z przeciwnika: gracz.take_damage(20.0))
func take_damage(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	_since_damage = 0.0   # regeneracja zaczyna odliczanie od nowa
	if health_overlay:
		health_overlay.blysk_obrazen()
	_set_health(health - amount)


# Ulecz gracza (apteczka itp.)
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


# Przelicza % życia na natężenie ciemnienia ekranu (0 = brak, 1 = maksimum)
func _update_health_overlay(instant: bool = false) -> void:
	if health_overlay == null:
		return
	health_overlay.ustaw_natezenie(_health_intensity(), instant)


# 0.0 = zdrowy (powyżej progu), 1.0 = prawie martwy. Steruje ciemnieniem, rozmazaniem i dźwiękiem
func _health_intensity() -> float:
	var percent := health / maxf(max_health, 0.001) * 100.0
	return clampf((darken_below_percent - percent) / maxf(darken_below_percent, 0.01), 0.0, 1.0)


# Oddech cichutko zaczyna być słyszalny przy progu i narasta; od pewnego momentu dochodzi kaszel
func _update_health_audio(delta: float) -> void:
	var intensity := _health_intensity()
	_health_audio_level = lerpf(_health_audio_level, intensity, 1.0 - exp(-health_audio_smooth * delta))

	if low_breath_player != null and low_health_breath_sound != null:
		if _health_audio_level > 0.02:
			if not low_breath_player.playing:
				low_breath_player.stream = low_health_breath_sound
				low_breath_player.play()
			var k := pow(_health_audio_level, 1.5)   # wolny start, mocniejszy przy końcu
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


# Im gorzej z graczem, tym częściej kaszle
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
	_dead = true
	died.emit()
	if oczy != null:
		oczy.wlaczony = false   # po śmierci nie startują nowe zdarzenia z oczami
	if _inventory_open():
		_toggle_inventory()
	if prompt_label:
		prompt_label.visible = false
	if health_overlay:
		health_overlay.smierc()
	if restart_on_death:
		await get_tree().create_timer(death_delay).timeout
		get_tree().reload_current_scene()


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
	# klawisze testowe życia: F3 = obrażenia, F4 = leczenie
	if debug_health_keys and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F3:
			take_damage(10.0)
		elif event.physical_keycode == KEY_F4:
			heal(10.0)

	# martwy gracz nie steruje postacią
	if _dead:
		return

	if event.is_action_pressed("inventory"):
		if not kontrola_zablokowana:   # w trakcie zdarzenia nie otwieramy ekwipunku
			_toggle_inventory()
		return

	# przy otwartym ekwipunku: tylko Esc zamyka, reszta wejścia idzie do UI
	if _inventory_open():
		if event.is_action_pressed("ui_cancel"):
			_toggle_inventory()
		return

	# w trakcie zdarzenia kamerą steruje skrypt zdarzenia, myszka jest ignorowana
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and not kontrola_zablokowana:
		_look(event.relative)

	if event.is_action_pressed("interact") and not kontrola_zablokowana:
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
	prompt_label.visible = target != null and not _inventory_open() and not kontrola_zablokowana
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


# ---------- Dźwięki sprintu: sapanie + bicie serca ----------

func _setup_sprint_audio() -> void:
	breath_player = _make_loop_player("BreathPlayer", breath_volume_db)
	heart_player = _make_loop_player("HeartPlayer", heartbeat_volume_db)
	_prepare_loop(breath_sound)
	_prepare_loop(heartbeat_sound)
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


# MP3 / OGG zapętlamy w kodzie (bez płynnych przerw). WAV nie jest ruszany,
# bo ciągłość zapewnia ponowne odpalenie dźwięku zaraz po jego końcu (patrz _drive_loop).
func _prepare_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true


func _update_sprint_audio(delta: float) -> void:
	if _sprinting:
		_sprint_time += delta
	else:
		_sprint_time = 0.0

	_breath_left = _tick_sound_timer(_breath_left, breath_start_delay, breath_recovery_time, delta)
	_heart_left = _tick_sound_timer(_heart_left, heartbeat_start_delay, heartbeat_recovery_time, delta)

	# sapanie: głośność i wysokość zależą od zmęczenia, gra też dopóki gracz się nie uspokoi
	var breath_active := _breath_left > 0.0
	var breath_target_db := breath_volume_db
	if stamina_enabled:
		breath_active = breath_active or _fatigue > 0.02
		breath_target_db = lerpf(breath_min_volume_db, breath_volume_db, pow(_fatigue, 0.8))
		if breath_player != null:
			breath_player.pitch_scale = lerpf(breath_pitch_min, breath_pitch_max, _fatigue)

	_drive_loop(breath_player, breath_sound, breath_target_db, breath_active, delta)
	_drive_loop(heart_player, heartbeat_sound, heartbeat_volume_db, _heart_left > 0.0, delta)


# Podczas sprintu (po opóźnieniu startu) licznik jest zawsze pełny.
# Po zakończeniu sprintu odlicza do zera, a dźwięk gra do tego czasu.
func _tick_sound_timer(left: float, start_delay: float, recovery: float, delta: float) -> float:
	if _sprinting:
		if _sprint_time >= start_delay:
			return maxf(recovery, 0.01)
		return left
	return maxf(left - delta, 0.0)


# Gra dźwięk w kółko, dopóki 'active' jest true. Włącza i wyłącza go płynnie.
func _drive_loop(player: AudioStreamPlayer, stream: AudioStream, base_db: float, active: bool, delta: float) -> void:
	if player == null or stream == null:
		return

	var fade_speed := absf(base_db - SOUND_SILENT_DB) / maxf(sound_fade_time, 0.05)

	if active:
		if not player.playing:
			player.stream = stream
			player.volume_db = SOUND_SILENT_DB   # start od ciszy, potem płynnie głośniej
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
	_update_sprint_audio(delta)
	_handle_footsteps(delta)
	_update_health(delta)
	_update_health_audio(delta)
	_update_prompt()


# Po śmierci: postać hamuje, opada na ziemię, dźwięki sprintu cichną
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
	_update_sprint_audio(delta)
	_update_health_audio(delta)


func _apply_gravity_and_jump(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif not _crouching and not _inventory_open() and not kontrola_zablokowana \
			and Input.is_action_just_pressed("jump"):   # w kucki, z ekwipunkiem i w trakcie zdarzenia nie skaczemy
		velocity.y = JUMP_VELOCITY


func _apply_movement(delta: float) -> void:
	var input_dir := Vector2.ZERO
	if not _inventory_open() and not kontrola_zablokowana:
		input_dir = Input.get_vector("left", "right", "forward", "back")
	var direction := (basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var speed := SPEED
	if _crouching:
		speed = crouch_speed   # w kucki nie ma sprintu
	elif Input.is_action_pressed("sprint") and _can_sprint() and not kontrola_zablokowana:
		speed = SPRINT_SPEED

	var rate := acceleration if direction != Vector3.ZERO else deceleration
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(
			Vector2(direction.x, direction.z) * speed, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y


# ---------- Head bob kamery ----------

# Kamera kołysze się góra-dół, na boki i przechyla (roll). Przy sprincie efekt jest mocniejszy
# i szybszy (tempo zależy od prędkości), w kucki słabszy. Pozycja liczona jako różnica (offset),
# więc nie gryzie się z kucaniem. Roll ustawiamy bezpośrednio, bo _look() zmienia tylko rotation.x.
# Na to dochodzi kołysanie ze zmęczenia (h_offset / v_offset kamery + dodatkowy przechył),
# które rośnie dopiero blisko limitu wytrzymałości.
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

		bob_czas += delta * _h_speed * BOB_FREQ * 0.5   # szybszy ruch = szybsze kroki
		cel_poz = Vector3(
			cos(bob_czas) * BOB_AMP_X * amp,             # na boki
			sin(bob_czas * 2.0) * BOB_AMP_Y * amp,       # góra-dół (dwa razy częściej niż boki)
			0.0
		)
		cel_roll = cos(bob_czas) * BOB_ROLL * roll_amp   # przechył w rytm kroków

	var smooth := 1.0 - exp(-BOB_SMOOTH * delta)

	var nowy_poz := _head_bob_offset.lerp(cel_poz, smooth)
	camera.position += nowy_poz - _head_bob_offset
	_head_bob_offset = nowy_poz

	_head_bob_roll = lerpf(_head_bob_roll, cel_roll, smooth)

	# zmęczenie: im bliżej limitu, tym mocniejsze (i szybsze) kołysanie postacią
	var blisko := pow(_fatigue, fatigue_effect_power)
	_fatigue_time += delta * (1.0 + blisko * 1.5)
	camera.h_offset = sin(_fatigue_time * 1.3) * fatigue_sway_amount * blisko
	camera.v_offset = sin(_fatigue_time * 2.1) * fatigue_sway_amount * 0.6 * blisko
	var fatigue_roll := sin(_fatigue_time * 0.9) * fatigue_roll_amount * blisko

	camera.rotation.z = _head_bob_roll + fatigue_roll


# ---------- Pomocnicze ----------

func _disable_collisions(node: Node) -> void:
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	for child in node.get_children():
		_disable_collisions(child)
