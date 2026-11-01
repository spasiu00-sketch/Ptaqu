extends Node
# Białe oczy w polu widzenia kamery (w powietrzu albo na ścianie).
# - stoją cały czas, maksymalnie `maks_oczu` naraz
# - nowe pojawia się co min_przerwa..max_przerwa; gdy limit przekroczony, NAJSTARSZE zanika
# - gdy gracz spojrzy na oko (środek ekranu), oko znika NATYCHMIAST (ta sama klatka)
# - bez światła, tylko świecący (unshaded) biały mesh
# Tworzy je gracz (character_body_3d.gd). Ręcznie: wymus() albo klawisz testowy.

@export var wlaczony: bool = true
@export var min_przerwa: float = 4.0       # minimalny czas między pojawieniem się kolejnych oczu (s)
@export var max_przerwa: float = 10.0      # maksymalny czas między pojawieniem się kolejnych oczu (s)
@export var maks_oczu: int = 3             # ile par oczu naraz

@export_group("Miejsce w kadrze")
@export var max_kat_poziomy: float = 30.0  # o ile stopni w lewo/prawo od środka ekranu mogą się pojawić
@export var min_kat_pionowy: float = -8.0  # kąt w pionie (min), ujemny = w dół
@export var max_kat_pionowy: float = 14.0  # kąt w pionie (max), dodatni = w górę
@export var odleglosc: float = 7.0         # maksymalna odległość oczu od kamery (m)
@export var min_odleglosc: float = 2.0     # bliżej niż to nie stawiamy oczu
@export var min_odstep_miedzy_oczami: float = 1.2   # minimalny dystans między parami oczu (m)
@export_flags_3d_physics var maska_kolizji: int = 1

@export_group("Patrzenie")
@export var kat_patrzenia: float = 4.0     # w jakim stożku (stopnie od środka ekranu) oko uznajemy za "najechane" i znika

@export_group("Oczy")
@export var kolor: Color = Color(1.0, 1.0, 1.0)
@export var rozstaw: float = 0.32          # odległość między oczami (m)
@export var rozmiar: float = 0.07          # wielkość oka (m)
@export var czas_otwierania: float = 0.5
@export var czas_zanikania: float = 0.8    # zanikanie najstarszych oczu po przekroczeniu limitu
@export var dzwiek: AudioStream            # opcjonalny dźwięk przy pojawieniu się oczu
@export var glosnosc_db: float = 0.0

@export_group("Test")
@export var tryb_testowy: bool = true      # false = klawisz testowy nic nie robi (na wersję końcową)
@export var klawisz_testowy: Key = KEY_F3

const OKO_ZAMKNIETE := Vector3(1.6, 0.03, 0.35)   # spłaszczone, pionowa szczelina
const OKO_OTWARTE := Vector3(1.6, 1.0, 0.35)

var gracz: CharacterBody3D

var _kamera: Camera3D
var _audio: AudioStreamPlayer
var _do_nastepnego: float = 0.0
var _licznik: int = 0                       # numer kolejnego zdarzenia (do ustalenia, które oczy są najstarsze)

var _material: StandardMaterial3D
var _mesh: SphereMesh
var _sloty: Array[Dictionary] = []          # {"root","oczy","aktywny","zanika","otwarcie","nr","poz"}
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
	for i in maxi(maks_oczu, 1) + 2:   # zapas na oczy, które akurat zanikają
		_sloty.append(_zrob_slot())
	_losuj_przerwe()


func _losuj_przerwe() -> void:
	_do_nastepnego = randf_range(min_przerwa, maxf(max_przerwa, min_przerwa))


# Wymusza pojawienie się nowych oczu od razu
func wymus() -> void:
	_pojaw()


func _unhandled_input(event: InputEvent) -> void:
	if not tryb_testowy:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == klawisz_testowy:
		wymus()


func _process(delta: float) -> void:
	# --- pojawianie nowych ---
	if wlaczony:
		_do_nastepnego -= delta
		if _do_nastepnego <= 0.0:
			if _pojaw():
				_losuj_przerwe()
			else:
				_do_nastepnego = 1.5   # nie wyszło (np. ściana tuż przed twarzą), próbujemy za chwilę
	else:
		# wyłączone (np. po śmierci): wszystkie oczy zanikają
		for s in _sloty:
			if s["aktywny"]:
				s["zanika"] = true

	# --- aktualizacja istniejących ---
	var kam_poz := _kamera.global_position
	var przod := -_kamera.global_transform.basis.z.normalized()

	for s in _sloty:
		if not s["aktywny"]:
			continue

		# spojrzenie na oko = znika natychmiast (w tej klatce)
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


# ---------- Pojawianie ----------

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

	# limit: jeśli po dodaniu byłoby ponad maks, najstarsze (niezanikające) zaczyna zanikać
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
		root.look_at(_kamera.global_position, up)   # oczy "patrzą" na gracza
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


# ---------- Wybór miejsca (w kadrze kamery) ----------

# Zwraca Vector3 albo null
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
			cel = punkt + normalna * 0.05   # lekko przed ścianą, żeby oczy w niej nie zniknęły

		if not _kamera.is_position_in_frustum(cel):
			continue

		# nie stawiamy oczu na sobie
		var za_blisko := false
		for s in _sloty:
			if s["aktywny"] and (s["poz"] as Vector3).distance_to(cel) < min_odstep_miedzy_oczami:
				za_blisko = true
				break
		if za_blisko:
			continue

		return cel
	return null


# ---------- Oczy ----------

func _zbuduj_zasoby() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = kolor
	# bez emisji i bez światła: unshaded wystarczy, żeby oczy były białe w ciemności

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


# 0 = zamknięte (niewidoczne), 1 = w pełni otwarte
func _ustaw_otwarcie(s: Dictionary, otwarcie: float) -> void:
	for oko: MeshInstance3D in s["oczy"]:
		oko.visible = otwarcie > 0.02
		oko.scale = OKO_ZAMKNIETE.lerp(OKO_OTWARTE, otwarcie)
