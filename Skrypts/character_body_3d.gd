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
const EXACT_NAME_BONUS := 1_000_000  # dokładna nazwa animacji zawsze wygrywa z auto-wykrywaniem
const CAPSULE_MIN_MARGIN := 0.01     # kapsuła nie może być niższa niż 2 * promień

const INPUT_KEYS := {
	"forward": KEY_W,
	"back": KEY_S,
	"left": KEY_A,
	"right": KEY_D,
	"jump": KEY_SPACE,
	"sprint": KEY_SHIFT,
	"crouch": KEY_C,
	"interact": KEY_E,
}

enum BodyState { UNSET, NONE, IDLE, WALK, CROUCH_IDLE, CROUCH_WALK }

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
@export var procedural_crouch: bool = true              # brak klipów kucania = generuj je z idle/walk (rig Mixamo)
@export_range(0.1, 0.7, 0.01) var procedural_crouch_depth: float = 0.4   # o ile ugiąć nogi (ułamek długości nogi)
@export_range(0.0, 0.8, 0.01) var procedural_crouch_lean: float = 0.3    # pochylenie tułowia do przodu (radiany)
@export var procedural_crouch_flip: bool = false        # włącz, jeśli nogi uginają się w złą stronę (do tyłu)
@export var crouch_idle_animation: StringName = &"crouch_idle_main_hero"   # animacja stania w kucki (brak = auto: nazwa zawiera "crouch" i "idle")
@export var crouch_walk_animation: StringName = &"crouch_walk_main_hero"   # animacja chodzenia w kucki (brak = auto: "crouch" i "walk"); bez żadnej = zwykłe idle/walk

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

@export_group("Model postaci (cień)")
@export var body_node_name: String = "cien_gracza"            # węzeł z modelem postaci (instancja character.tscn)
@export var walk_animation: StringName = &"walk_main_hero"    # dokładna nazwa animacji chodzenia (puste/nie znaleziono = auto: nazwa zawiera "walk")
@export var idle_animation: StringName = &"idle_main_hero"    # dokładna nazwa animacji stania (puste/nie znaleziono = auto: nazwa zawiera "idle")
@export var lock_idle_root_motion: bool = true                # blokuje przesuwanie się modelu podczas idle (root motion)
@export var lock_root_axes: Vector3 = Vector3(1, 0, 1)        # osie kości Hips do zablokowania (1 = blokuj); Y zostaje (oddychanie)
@export var anim_blend_time: float = 0.2                      # płynne przejście między animacjami (sekundy)
@export var debug_body_animation: bool = false                # true = wypisuje w Output animacje i dopasowanie tracków

# ---------- Stan ----------

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var camera: Camera3D = $Camera3D

var footstep_player = null          # AudioStreamPlayer lub AudioStreamPlayer3D
var interact_ray: RayCast3D = null
var flashlight: Flashlight = null
var held_flashlight: Node3D = null  # węzeł kołysany przy chodzeniu (model latarki)
var held_root: Node3D = null        # węzeł ukrywany/pokazywany (Cofanie)
var prompt_label: Label

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

# animacje modelu
var _slots := {}                           # BodyState -> {"player": AnimationPlayer, "name": StringName}
var _body_state: BodyState = BodyState.UNSET
var _root_ref = null                       # Vector3: pozycja Hips z chodzenia (odniesienie dla idle)
var _bone_map_cache := {}                  # Skeleton3D -> {znormalizowana nazwa: prawdziwa nazwa kości}


# ---------- Inicjalizacja ----------

func _ready() -> void:
	set_process(false)   # _process tylko gdy trzeba (latarka w ręku / ruch kamery przy kucaniu)
	_setup_input_actions()
	_setup_footstep_player()
	_create_prompt_label()
	_find_nodes()
	_setup_flashlight()
	_setup_held_item()
	_setup_body_animation()
	_setup_crouch()
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


# ---------- Animacja modelu: konfiguracja ----------

# Szuka AnimationPlayerów TYLKO w modelu postaci, nie rusza animacji latarki.
# Każda animacja (walk, idle, kucanie) może leżeć w innym AnimationPlayerze.
func _setup_body_animation() -> void:
	var body := find_child(body_node_name, true, false)
	if body == null:
		push_warning("Brak węzła modelu postaci '%s'" % body_node_name)
		return

	var players := body.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		push_warning("Model '%s' nie ma AnimationPlayera" % body_node_name)
		return

	if debug_body_animation:
		for node in players:
			var p := node as AnimationPlayer
			print("AnimationPlayer: ", p.get_path(), " | animacje: ", p.get_animation_list())
			for anim_name in p.get_animation_list():
				print("   ", anim_name, " -> pasujących tracków kości: ", _match_score(p, p.get_animation(anim_name)))

	# [stan, dokładna nazwa, słowa kluczowe auto-wykrywania ("-słowo" = wyklucz), blokada root motion]
	# kolejność ma znaczenie: walk idzie pierwszy i zapamiętuje pozycję Hips
	var specs := [
		[BodyState.WALK, walk_animation, "walk -crouch", false],
		[BodyState.IDLE, idle_animation, "idle -crouch", lock_idle_root_motion],
		[BodyState.CROUCH_WALK, crouch_walk_animation, "crouch walk", false],
		[BodyState.CROUCH_IDLE, crouch_idle_animation, "crouch idle", lock_idle_root_motion],
	]
	for spec in specs:
		var found := _pick_animation(players, spec[1], spec[2])
		if found.player != null:
			_slots[spec[0]] = {"player": found.player, "name": found.name}

	if _slots.is_empty():
		push_warning("Żaden AnimationPlayer modelu nie ma animacji walk/idle. Włącz debug_body_animation, żeby zobaczyć listę.")
		return

	for spec in specs:
		if _slots.has(spec[0]):
			var slot: Dictionary = _slots[spec[0]]
			_prepare_animation(slot.player, slot.name, spec[3])

	if procedural_crouch:   # brak własnych klipów kucania -> tworzymy je z gotowych idle / walk
		_make_procedural_crouch(BodyState.IDLE, BodyState.CROUCH_IDLE)
		_make_procedural_crouch(BodyState.WALK, BodyState.CROUCH_WALK)

	var summary := []
	for state in _slots:
		summary.append("%s='%s' (%s)" % [BodyState.keys()[state], _slots[state].name, _slots[state].player.name])
	print("Animacje postaci: ", ", ".join(summary))


# ---------- Kucanie proceduralne (gdy nie ma klipów crouch) ----------

# Tworzy kopię animacji idle/walk z ugiętymi nogami, obniżonymi biodrami i pochylonym tułowiem.
# Działa na rigu Mixamo (hips, upleg, leg, foot, spine, head); kierunki liczy z pozy spoczynkowej szkieletu.
func _make_procedural_crouch(source: BodyState, target: BodyState) -> void:
	if _slots.has(target) or not _slots.has(source):
		return
	var slot: Dictionary = _slots[source]
	var player: AnimationPlayer = slot.player
	var src := player.get_animation(slot.name)
	var root := player.get_node_or_null(player.root_node)
	if root == null:
		return
	var best := _best_skeleton(root, src)
	var skeleton := best.skeleton as Skeleton3D
	if skeleton == null or best.matches == 0:
		return

	var pose := _calc_crouch_pose(skeleton)
	if pose.is_empty():
		push_warning("Kucanie proceduralne: brak kości Mixamo (hips, upleg, leg, foot, head) - pomijam")
		return

	var map := _get_bone_map(skeleton)
	var skeleton_path := String(root.get_path_to(skeleton))
	var anim := src.duplicate(true) as Animation   # kopia już naprawionej animacji (ścieżki, root motion)
	anim.loop_mode = Animation.LOOP_LINEAR

	# 1) obrót kości wokół osi zginania (w przestrzeni lokalnej kości)
	for key in pose.angles:
		var real: String = map[key]
		var bone := skeleton.find_bone(real)
		var parent_basis := _parent_rest_basis(skeleton, bone).orthonormalized()
		var delta := Quaternion((parent_basis.inverse() * pose.axis).normalized(), pose.angles[key])
		var node_path := NodePath("%s:%s" % [skeleton_path, real])
		var track := anim.find_track(node_path, Animation.TYPE_ROTATION_3D)
		if track == -1:   # kość nie była animowana: dodajemy track ze stałą pozą spoczynkową
			track = anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(track, node_path)
			anim.rotation_track_insert_key(track, 0.0, skeleton.get_bone_rest(bone).basis.get_rotation_quaternion())
		for k in anim.track_get_key_count(track):
			var q: Quaternion = anim.track_get_key_value(track, k)
			anim.track_set_key_value(track, k, delta * q)

	# 2) obniżenie bioder
	var hips := skeleton.find_bone(map["hips"])
	var hips_track := anim.find_track(NodePath("%s:%s" % [skeleton_path, map["hips"]]), Animation.TYPE_POSITION_3D)
	if hips_track != -1:
		var local_drop: Vector3 = _parent_rest_basis(skeleton, hips).inverse() * (-pose.up * pose.drop)
		for k in anim.track_get_key_count(hips_track):
			var v: Vector3 = anim.track_get_key_value(hips_track, k)
			anim.track_set_key_value(hips_track, k, v + local_drop)

	# 3) rejestracja nowej animacji w bibliotece playera
	var lib_name := player.find_animation_library(src)
	var lib := player.get_animation_library(lib_name)
	var short_name := "proc_crouch_idle" if target == BodyState.CROUCH_IDLE else "proc_crouch_walk"
	lib.add_animation(short_name, anim)
	_slots[target] = {"player": player, "name": StringName(short_name if lib_name == &"" else "%s/%s" % [lib_name, short_name])}
	player.clear_caches()


func _parent_rest_basis(skeleton: Skeleton3D, bone: int) -> Basis:
	var parent := skeleton.get_bone_parent(bone)
	return Basis.IDENTITY if parent == -1 else skeleton.get_bone_global_rest(parent).basis


# Liczy kąty zginania z pozy spoczynkowej: {axis, up, drop, angles{znormalizowana nazwa kości: kąt}}
func _calc_crouch_pose(skeleton: Skeleton3D) -> Dictionary:
	var map := _get_bone_map(skeleton)
	for key in ["hips", "head", "leftupleg", "rightupleg", "leftleg", "leftfoot"]:
		if not map.has(key):
			return {}

	var hips_pos := _rest_pos(skeleton, map["hips"])
	var up := (_rest_pos(skeleton, map["head"]) - hips_pos).normalized()
	var left := _rest_pos(skeleton, map["leftupleg"]) - _rest_pos(skeleton, map["rightupleg"])
	left = (left - up * left.dot(up)).normalized()
	var axis := -left   # obrót wokół tej osi o dodatni kąt = ruch do przodu (przód postaci = left x up)
	if procedural_crouch_flip:
		axis = -axis

	var upleg_pos := _rest_pos(skeleton, map["leftupleg"])
	var leg_pos := _rest_pos(skeleton, map["leftleg"])
	var foot_pos := _rest_pos(skeleton, map["leftfoot"])
	var l1 := upleg_pos.distance_to(leg_pos)
	var l2 := leg_pos.distance_to(foot_pos)
	if l1 < 0.0001 or l2 < 0.0001:
		return {}

	# dwuczłonowa noga: biodro schodzi o 'depth' długości nogi, stopa zostaje na ziemi
	var straight := l1 + l2
	var h := clampf(straight * (1.0 - procedural_crouch_depth), absf(l1 - l2) + straight * 0.02, straight)
	var knee_flex := PI - acos(clampf((l1 * l1 + l2 * l2 - h * h) / (2.0 * l1 * l2), -1.0, 1.0))
	var hip_flex := acos(clampf((l1 * l1 + h * h - l2 * l2) / (2.0 * l1 * h), -1.0, 1.0))

	var angles := {
		"leftupleg": hip_flex, "rightupleg": hip_flex,
		"leftleg": -knee_flex, "rightleg": -knee_flex,
		"leftfoot": knee_flex - hip_flex, "rightfoot": knee_flex - hip_flex,
		"spine": -procedural_crouch_lean * 0.5,   # kość w górę: obrót "do przodu" nogi daje tu pochylenie do tyłu, stąd minus
		"spine1": -procedural_crouch_lean * 0.3,
		"spine2": -procedural_crouch_lean * 0.2,
		"neck": procedural_crouch_lean * 0.5,     # szyja i głowa prostują spojrzenie
		"head": procedural_crouch_lean * 0.5,
	}
	for key in angles.keys():
		if not map.has(key):
			angles.erase(key)
	return {"axis": axis, "up": up, "drop": straight - h, "angles": angles}


func _rest_pos(skeleton: Skeleton3D, bone_name: String) -> Vector3:
	return skeleton.get_bone_global_rest(skeleton.find_bone(bone_name)).origin


# Wybiera najlepszą animację spośród wszystkich playerów: {player, name, score}
func _pick_animation(players: Array[Node], exact: StringName, keyword: String) -> Dictionary:
	var best := {"player": null, "name": &"", "score": -1}
	for node in players:
		var player := node as AnimationPlayer
		var found := _find_best_animation(player, exact, keyword)
		if found.name != &"" and found.score > best.score:
			best = {"player": player, "name": found.name, "score": found.score}
	return best


# {name, score}: dokładna nazwa (jeśli istnieje) albo animacja ze słowem kluczowym,
# która najlepiej pasuje do kości szkieletu
func _find_best_animation(player: AnimationPlayer, exact: StringName, keyword: String) -> Dictionary:
	if exact != &"" and player.has_animation(exact):
		return {"name": exact, "score": EXACT_NAME_BONUS}
	var best := {"name": &"", "score": -1}
	var tokens := keyword.to_lower().split(" ", false)
	if tokens.is_empty():
		return best
	for anim_name in player.get_animation_list():
		if _name_matches(String(anim_name).to_lower(), tokens):
			var score := _match_score(player, player.get_animation(anim_name))
			if score > best.score:
				best = {"name": anim_name, "score": score}
	return best


# Nazwa musi zawierać wszystkie słowa i żadnego z wykluczonych (z "-" na początku)
func _name_matches(anim_name: String, tokens: PackedStringArray) -> bool:
	for token in tokens:
		if token.begins_with("-"):
			if anim_name.contains(token.substr(1)):
				return false
		elif not anim_name.contains(token):
			return false
	return true


func _prepare_animation(player: AnimationPlayer, anim_name: StringName, lock_root: bool) -> void:
	var anim := player.get_animation(anim_name)
	anim.loop_mode = Animation.LOOP_LINEAR   # animacje z .glb / .fbx domyślnie się nie zapętlają
	_fix_animation_paths(player, anim, lock_root)
	player.active = true
	player.stop()
	player.clear_caches()   # odrzuca stare, błędne ścieżki zapamiętane np. przez Autoplay


# Dopasowuje tracki animacji do kości faktycznego szkieletu w modelu.
# Naprawia błąd "couldn't resolve track ...", gdy szkielet nazywa się inaczej lub leży pod inną ścieżką.
func _fix_animation_paths(player: AnimationPlayer, anim: Animation, lock_root: bool) -> void:
	var root := player.get_node_or_null(player.root_node)
	if root == null:
		push_warning("Root Node AnimationPlayera modelu nie wskazuje na żaden węzeł")
		return

	var best := _best_skeleton(root, anim)
	var skeleton := best.skeleton as Skeleton3D
	if skeleton == null:
		push_warning("Model nie ma Skeleton3D pod Root Node AnimationPlayera")
		return
	if best.matches == 0:
		push_warning("Animacja '%s': żaden track nie pasuje do kości szkieletu - nie zmieniam ścieżek" % anim.resource_name)
		return

	var bones := _get_bone_map(skeleton)
	var skeleton_path := String(root.get_path_to(skeleton))
	print("Animacja '%s': pasuje %d tracków kości do szkieletu %s (%d kości)" % [
		anim.resource_name, best.matches, skeleton_path, skeleton.get_bone_count()])

	var removed := 0
	for i in range(anim.get_track_count() - 1, -1, -1):
		if not _is_bone_track(anim, i):
			continue
		var path := anim.track_get_path(i)
		if path.get_subname_count() == 0:
			continue
		var key := _normalize_bone_name(String(path.get_subname(0)))
		if not bones.has(key):
			anim.remove_track(i)   # kość nie istnieje w modelu, track i tak by nie działał
			removed += 1
			continue
		anim.track_set_path(i, NodePath("%s:%s" % [skeleton_path, bones[key]]))

	if removed > 0:
		push_warning("Animacja '%s': usunięto %d tracków bez pasującej kości" % [anim.resource_name, removed])

	_handle_root_motion(anim, skeleton, skeleton_path, lock_root)


# Pierwsza przetworzona animacja (walk) zapamiętuje pozycję Hips. Animacje z lock_root
# dostają X/Z (osie z lock_root_axes) równe tej pozycji, więc model nie ucieka na bok.
func _handle_root_motion(anim: Animation, skeleton: Skeleton3D, skeleton_path: String, lock_root: bool) -> void:
	var root_bone := _get_root_bone(skeleton)
	if root_bone == "":
		return
	var track := anim.find_track(NodePath("%s:%s" % [skeleton_path, root_bone]), Animation.TYPE_POSITION_3D)
	if track == -1 or anim.track_get_key_count(track) == 0:
		return

	if _root_ref == null:
		_root_ref = anim.track_get_key_value(track, 0)
	if not lock_root:
		return

	var ref: Vector3 = _root_ref
	for k in anim.track_get_key_count(track):
		var v: Vector3 = anim.track_get_key_value(track, k)
		anim.track_set_key_value(track, k, Vector3(
			ref.x if lock_root_axes.x > 0.5 else v.x,
			ref.y if lock_root_axes.y > 0.5 else v.y,
			ref.z if lock_root_axes.z > 0.5 else v.z))
	print("Zablokowano root motion animacji '%s' (kość %s, osie %s)" % [anim.resource_name, root_bone, lock_root_axes])


func _get_root_bone(skeleton: Skeleton3D) -> String:
	var bones := _get_bone_map(skeleton)
	if bones.has("hips"):
		return bones["hips"]
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_parent(i) == -1:
			return skeleton.get_bone_name(i)
	return ""


# Szkielet pod rootem, do którego pasuje najwięcej tracków animacji: {skeleton, matches}
func _best_skeleton(root: Node, anim: Animation) -> Dictionary:
	var best := {"skeleton": null, "matches": 0}
	for node in root.find_children("*", "Skeleton3D", true, false):
		var sk := node as Skeleton3D
		var matches := _count_matching_tracks(anim, _get_bone_map(sk))
		if best.skeleton == null or matches > best.matches:
			best = {"skeleton": sk, "matches": matches}
	return best


func _match_score(player: AnimationPlayer, anim: Animation) -> int:
	var root := player.get_node_or_null(player.root_node)
	return 0 if root == null else _best_skeleton(root, anim).matches


# Mapa znormalizowana nazwa -> prawdziwa nazwa kości (liczona raz na szkielet)
func _get_bone_map(skeleton: Skeleton3D) -> Dictionary:
	if _bone_map_cache.has(skeleton):
		return _bone_map_cache[skeleton]
	var map := {}
	for i in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(i)
		map[_normalize_bone_name(bone_name)] = bone_name
	_bone_map_cache[skeleton] = map
	return map


func _count_matching_tracks(anim: Animation, bones: Dictionary) -> int:
	var count := 0
	for i in anim.get_track_count():
		if not _is_bone_track(anim, i):
			continue
		var path := anim.track_get_path(i)
		if path.get_subname_count() > 0 and bones.has(_normalize_bone_name(String(path.get_subname(0)))):
			count += 1
	return count


func _is_bone_track(anim: Animation, idx: int) -> bool:
	var t := anim.track_get_type(idx)
	return t == Animation.TYPE_POSITION_3D or t == Animation.TYPE_ROTATION_3D or t == Animation.TYPE_SCALE_3D


# "mixamorig_Hips" == "mixamorig:Hips" == "Hips"
func _normalize_bone_name(bone: String) -> String:
	return bone.to_lower().replace("mixamorig", "").replace(":", "").replace("_", "").replace(" ", "")


# ---------- Animacja modelu: odtwarzanie ----------

# Maszyna stanów: animację przełączamy tylko przy zmianie stanu, nie co klatkę
func _update_body_animation() -> void:
	if _slots.is_empty():
		return

	var target := _pick_body_state()
	if target != _body_state:
		_set_body_state(target)
	if target == BodyState.WALK or target == BodyState.CROUCH_WALK:
		var ref_speed := crouch_speed if target == BodyState.CROUCH_WALK else SPEED
		_slots[target].player.speed_scale = _h_speed / ref_speed   # szybszy ruch = szybsza animacja


# Pierwszy dostępny stan z listy kandydatów (kucanie wraca do zwykłych animacji, gdy nie ma własnych)
func _pick_body_state() -> BodyState:
	var candidates: Array
	if _moving:
		candidates = [BodyState.CROUCH_WALK, BodyState.WALK, BodyState.CROUCH_IDLE, BodyState.IDLE] \
				if _crouching else [BodyState.WALK, BodyState.IDLE]
	else:
		candidates = [BodyState.CROUCH_IDLE, BodyState.IDLE] if _crouching else [BodyState.IDLE]
	for state in candidates:
		if _slots.has(state):
			return state
	return BodyState.NONE


func _set_body_state(state: BodyState) -> void:
	_body_state = state
	if state == BodyState.NONE:
		for s in _slots.values():
			s.player.pause()
		return

	var slot: Dictionary = _slots[state]
	var active: AnimationPlayer = slot.player
	for s in _slots.values():   # inne playery stop, żeby nie walczyły o ten sam szkielet
		if s.player != active and s.player.is_playing():
			s.player.stop(true)
	active.speed_scale = 1.0
	active.play(slot.name, anim_blend_time)


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
	_update_body_animation()
	_update_prompt()


func _apply_gravity_and_jump(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif not _crouching and Input.is_action_just_pressed("jump"):   # w kucki nie skaczemy
		velocity.y = JUMP_VELOCITY


func _apply_movement(delta: float) -> void:
	var input_dir := Input.get_vector("left", "right", "forward", "back")
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
