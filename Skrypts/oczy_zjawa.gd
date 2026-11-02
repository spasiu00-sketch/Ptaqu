class_name OczyZjawa
extends Node

@export var wlaczony: bool = true
@export var min_przerwa: float = 4.0
@export var max_przerwa: float = 10.0
@export var maks_oczu: int = 3

@export_group("Miejsce w kadrze")
@export var max_kat_poziomy: float = 30.0
@export var min_kat_pionowy: float = -8.0
@export var max_kat_pionowy: float = 14.0
@export var odleglosc: float = 7.0
@export var min_odleglosc: float = 2.0
@export var min_odstep_miedzy_oczami: float = 1.2
@export_flags_3d_physics var maska_kolizji: int = 1

@export_group("Patrzenie")
@export var kat_patrzenia: float = 4.0

@export_group("Oczy")
@export var kolor: Color = Color(1.0, 1.0, 1.0)
@export var rozstaw: float = 0.32
@export var rozmiar: float = 0.07
@export var czas_otwierania: float = 0.5
@export var czas_zanikania: float = 0.8
@export var dzwiek: AudioStream
@export var glosnosc_db: float = 0.0

@export_group("Test")
@export var tryb_testowy: bool = true
@export var klawisz_testowy: Key = KEY_F3

const OKO_ZAMKNIETE := Vector3(1.6, 0.03, 0.35)
const OKO_OTWARTE := Vector3(1.6, 1.0, 0.35)

var gracz: CharacterBody3D

var _kamera: Camera3D
var _audio: AudioStreamPlayer
var _do_nastepnego: float = 0.0
var _licznik: int = 0

var _material: StandardMaterial3D
var _mesh: SphereMesh
var _sloty: Array[Dictionary] = []
var _cos_patrzenia: float = 1.0


func _ready() -> void:
	if gracz == null:
		gracz = get_parent() as CharacterBody3D
	if gracz == null:
		push_warning("oczy_zjawa: brak gracza (CharacterBody3D)")
		set_process(false)
		return
	_kamera = gracz.get("camera") as Camera3D
	if _kamera == null:
		push_warning("oczy_zjawa: gracz nie ma kamery")
		set_process(false)
		return

	if dzwiek != null:
		_audio = AudioStreamPlayer.new()
		_audio.stream = dzwiek
		_audio.volume_db = glosnosc_db
		add_child(_audio)

	_cos_patrzenia = cos(deg_to_rad(kat_patrzenia))
	_zbuduj_zasoby()
	for i in maxi(maks_oczu, 1) + 2:
		_sloty.append(_zrob_slot())
	_losuj_przerwe()


func _losuj_przerwe() -> void:
	_do_nastepnego = randf_range(min_przerwa, maxf(max_przerwa, min_przerwa))


func wymus() -> void:
	_pojaw()


func _unhandled_input(event: InputEvent) -> void:
	if not tryb_testowy:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == klawisz_testowy:
		wymus()


func _process(delta: float) -> void:
	if wlaczony:
		_do_nastepnego -= delta
		if _do_nastepnego <= 0.0:
			if _pojaw():
				_losuj_przerwe()
			else:
				_do_nastepnego = 1.5
	else:
		for s in _sloty:
			if s["aktywny"]:
				s["zanika"] = true

	var kam_poz := _kamera.global_position
	var przod := -_kamera.global_transform.basis.z.normalized()

	for s in _sloty:
		if not s["aktywny"]:
			continue

		var kierunek: Vector3 = (s["poz"] - kam_poz).normalized()
		if kierunek.dot(przod) >= _cos_patrzenia:
			_zwolnij(s)
			continue

		var o: float = s["otwarcie"]
		if s["zanika"]:
			o -= delta / maxf(czas_zanikania, 0.01)
			if o <= 0.0:
				_zwolnij(s)
				continue
		else:
			o = minf(o + delta / maxf(czas_otwierania, 0.01), 1.0)
		s["otwarcie"] = o
		_ustaw_otwarcie(s, o)


func _pojaw() -> bool:
	if gracz == null or _kamera == null:
		return false
	if gracz.call("_inventory_open"):
		return false

	var slot = _wolny_slot()
	if slot == null:
		return false

	var poz = _znajdz_miejsce()
	if poz == null:
		return false

	var zywe: Array[Dictionary] = []
	for s in _sloty:
		if s["aktywny"] and not s["zanika"]:
			zywe.append(s)
	zywe.sort_custom(func(a, b): return a["nr"] < b["nr"])
	while zywe.size() >= maks_oczu and not zywe.is_empty():
		var najstarsze: Dictionary = zywe.pop_front()
		najstarsze["zanika"] = true

	_licznik += 1
	slot["aktywny"] = true
	slot["zanika"] = false
	slot["otwarcie"] = 0.0
	slot["nr"] = _licznik
	slot["poz"] = poz

	var root: Node3D = slot["root"]
	root.global_position = poz
	var up := Vector3.UP
	var do_gracza: Vector3 = (_kamera.global_position - poz).normalized()
	if absf(do_gracza.dot(Vector3.UP)) > 0.99:
		up = Vector3.RIGHT
	if not poz.is_equal_approx(_kamera.global_position):
		root.look_at(_kamera.global_position, up)
	_ustaw_otwarcie(slot, 0.0)
	root.visible = true

	if _audio != null:
		_audio.play()
	return true


func _wolny_slot():
	for s in _sloty:
		if not s["aktywny"]:
			return s
	return null


func _zwolnij(s: Dictionary) -> void:
	s["aktywny"] = false
	s["zanika"] = false
	s["otwarcie"] = 0.0
	(s["root"] as Node3D).visible = false


func _znajdz_miejsce():
	var od := _kamera.global_position
	var baza := _kamera.global_transform.basis.orthonormalized()
	var przestrzen := gracz.get_world_3d().direct_space_state

	for i in 12:
		var yaw := deg_to_rad(randf_range(-max_kat_poziomy, max_kat_poziomy))
		var pitch := deg_to_rad(randf_range(min_kat_pionowy, max_kat_pionowy))
		var lokalny := Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3.FORWARD
		var kierunek := baza * lokalny

		var koniec := od + kierunek * odleglosc
		var zapytanie := PhysicsRayQueryParameters3D.create(od, koniec, maska_kolizji, [gracz.get_rid()])
		var trafienie := przestrzen.intersect_ray(zapytanie)

		var cel: Vector3
		if trafienie.is_empty():
			cel = koniec
		else:
			var punkt: Vector3 = trafienie["position"]
			if od.distance_to(punkt) < min_odleglosc:
				continue
			var normalna: Vector3 = trafienie["normal"]
			cel = punkt + normalna * 0.05

		if not _kamera.is_position_in_frustum(cel):
			continue

		var za_blisko := false
		for s in _sloty:
			if s["aktywny"] and (s["poz"] as Vector3).distance_to(cel) < min_odstep_miedzy_oczami:
				za_blisko = true
				break
		if za_blisko:
			continue

		return cel
	return null


func _zbuduj_zasoby() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = kolor

	_mesh = SphereMesh.new()
	_mesh.radius = rozmiar
	_mesh.height = rozmiar * 2.0
	_mesh.radial_segments = 12
	_mesh.rings = 6


func _zrob_slot() -> Dictionary:
	var root := Node3D.new()
	root.name = "BialeOczy"
	root.top_level = true
	root.visible = false
	add_child(root)

	var oczy: Array[MeshInstance3D] = []
	for strona in [-1.0, 1.0]:
		var oko := MeshInstance3D.new()
		oko.mesh = _mesh
		oko.material_override = _material
		oko.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		oko.position = Vector3(strona * rozstaw * 0.5, 0.0, 0.0)
		oko.scale = OKO_ZAMKNIETE
		oko.visible = false
		root.add_child(oko)
		oczy.append(oko)

	return {
		"root": root, "oczy": oczy, "aktywny": false, "zanika": false,
		"otwarcie": 0.0, "nr": 0, "poz": Vector3.ZERO,
	}


func _ustaw_otwarcie(s: Dictionary, otwarcie: float) -> void:
	for oko: MeshInstance3D in s["oczy"]:
		oko.visible = otwarcie > 0.02
		oko.scale = OKO_ZAMKNIETE.lerp(OKO_OTWARTE, otwarcie)
