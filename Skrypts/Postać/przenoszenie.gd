class_name PrzenoszeniePrzedmiotow
extends Node
# Przenoszenie fizycznych obiektów (RigidBody3D) jak w Garry's Mod.
# Tworzy go gracz (character_body_3d.gd), osobny węzeł nie jest potrzebny.
#
# PPM (przytrzymaj)  = chwyć obiekt, którego dotyczy celownik; puszczenie PPM = upuść
# LPM podczas trzymania = rzuć
# KÓŁKO podczas trzymania = przybliż / oddal obiekt
#
# Obiekt musi być RigidBody3D, nie zamrożony, i lżejszy niż 'maks_masa'.

signal chwycono(cialo: RigidBody3D)
signal puszczono(cialo: RigidBody3D)

@export var gracz: CharacterBody3D
@export var wlaczone: bool = true

@export_group("Chwytanie")
@export var zasieg: float = 3.0                 # jak daleko od kamery da się chwycić
@export_flags_3d_physics var maska_kolizji: int = 1
@export var maks_masa: float = 30.0             # cięższe obiekty nie dadzą się podnieść
@export var min_dystans: float = 0.9
@export var maks_dystans: float = 3.0
@export var krok_kolka: float = 0.25

@export_group("Ruch")
@export var sila: float = 14.0                  # jak szybko obiekt goni punkt przed kamerą
@export var maks_predkosc: float = 14.0
@export var tlumienie_obrotu: float = 8.0
@export var odleglosc_zerwania: float = 1.8     # obiekt zablokowany dalej niż to od celu = upada
@export var sila_rzutu: float = 9.0

var _cialo: RigidBody3D = null
var _dystans: float = 1.8
var _stara_grawitacja: float = 1.0
var _kamera: Camera3D


func _ready() -> void:
	if gracz == null:
		gracz = get_parent() as CharacterBody3D
	if gracz == null:
		push_warning("przenoszenie: brak gracza (CharacterBody3D)")
		set_process_input(false)
		set_physics_process(false)
		return
	_kamera = gracz.get("camera") as Camera3D
	if _kamera == null:
		push_warning("przenoszenie: gracz nie ma kamery")
		set_process_input(false)
		set_physics_process(false)


func trzyma() -> bool:
	return _cialo != null and is_instance_valid(_cialo)


func _moze_sterowac() -> bool:
	if not wlaczone or gracz == null:
		return false
	if gracz.has_method("moze_sterowac"):
		return bool(gracz.call("moze_sterowac"))
	return true


# ---------- Wejście ----------
# _input (nie _unhandled_input), żeby LPM i kółko nie trafiały jednocześnie do ręki z przedmiotem

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return

	if trzyma():
		if not event.pressed:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				puszcz()
			return
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				rzuc()
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_UP:
				_dystans = clampf(_dystans + krok_kolka, min_dystans, maks_dystans)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				_dystans = clampf(_dystans - krok_kolka, min_dystans, maks_dystans)
				get_viewport().set_input_as_handled()
		return

	if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _moze_sterowac():
		_chwyc()


# ---------- Chwytanie / puszczanie ----------

func _chwyc() -> void:
	var od := _kamera.global_position
	var kierunek := -_kamera.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(od, od + kierunek * zasieg, maska_kolizji, [gracz.get_rid()])
	var trafienie := gracz.get_world_3d().direct_space_state.intersect_ray(q)
	if trafienie.is_empty():
		return

	var cialo := trafienie["collider"] as RigidBody3D
	if cialo == null or cialo.freeze or cialo.mass > maks_masa:
		return

	_cialo = cialo
	_dystans = clampf(od.distance_to(trafienie["position"]), min_dystans, maks_dystans)
	_stara_grawitacja = _cialo.gravity_scale
	_cialo.gravity_scale = 0.0
	_cialo.sleeping = false
	_cialo.add_collision_exception_with(gracz)   # obiekt nie wypycha gracza
	gracz.add_collision_exception_with(_cialo)
	chwycono.emit(_cialo)


func puszcz() -> void:
	if _cialo == null:
		return
	var cialo := _cialo
	_cialo = null
	if is_instance_valid(cialo):
		cialo.gravity_scale = _stara_grawitacja
		cialo.remove_collision_exception_with(gracz)
		if is_instance_valid(gracz):
			gracz.remove_collision_exception_with(cialo)
		puszczono.emit(cialo)


func rzuc() -> void:
	if not trzyma():
		puszcz()
		return
	var cialo := _cialo
	puszcz()
	var kierunek := -_kamera.global_transform.basis.z
	cialo.sleeping = false
	cialo.linear_velocity = kierunek * sila_rzutu
	cialo.angular_velocity = Vector3(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))


# ---------- Fizyka ----------

func _physics_process(delta: float) -> void:
	if _cialo == null:
		return
	if not is_instance_valid(_cialo) or not _moze_sterowac() \
			or not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		puszcz()
		return

	var cel := _kamera.global_position - _kamera.global_transform.basis.z * _dystans
	var do_celu := cel - _cialo.global_position

	# zablokowany za ścianą / przygnieciony = upuszczamy
	if do_celu.length() > odleglosc_zerwania:
		puszcz()
		return

	_cialo.sleeping = false
	_cialo.linear_velocity = (do_celu * sila).limit_length(maks_predkosc)
	_cialo.angular_velocity = _cialo.angular_velocity.lerp(
			Vector3.ZERO, 1.0 - exp(-tlumienie_obrotu * delta))
