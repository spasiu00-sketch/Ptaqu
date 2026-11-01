extends Node
# Losowe zdarzenie: w polu widzenia kamery (przed graczem, w powietrzu albo na ścianie)
# otwierają się czerwone, świecące oczy, patrzą przez chwilę i zamykają się.
# Kamera NIE jest ruszana, gracz steruje normalnie i sam decyduje, czy je zauważy.
# Tworzy je gracz (character_body_3d.gd). Ręcznie: wymus() albo klawisz testowy.
#
# Oczy (mesh, materiał, światło) tworzone są RAZ w _ready() i tylko pokazywane / chowane.

@export var wlaczony: bool = true
@export var min_przerwa: float = 25.0      # minimalny czas między zdarzeniami (s)
@export var max_przerwa: float = 70.0      # maksymalny czas między zdarzeniami (s)

@export_group("Miejsce w kadrze")
@export var max_kat_poziomy: float = 30.0  # o ile stopni w lewo/prawo od środka ekranu mogą się pojawić
@export var min_kat_pionowy: float = -8.0  # kąt w pionie względem środka ekranu (min), ujemny = w dół
@export var max_kat_pionowy: float = 14.0  # kąt w pionie względem środka ekranu (max), dodatni = w górę
@export var odleglosc: float = 7.0         # maksymalna odległość oczu od kamery (m)
@export var min_odleglosc: float = 2.0     # bliżej niż to nie stawiamy oczu (ściana tuż przed twarzą)
@export_flags_3d_physics var maska_kolizji: int = 1

@export_group("Oczy")
@export var kolor: Color = Color(1.0, 0.05, 0.03)
@export var rozstaw: float = 0.32          # odległość między oczami (m)
@export var rozmiar: float = 0.07          # wielkość oka (m)
@export var czas_otwierania: float = 0.5
@export var czas_otwartych: float = 1.6
@export var czas_zamykania: float = 0.35
@export var liczba_mrugniec: int = 1       # ile razy oczy się otwierają i zamykają
@export var swiatlo_energia: float = 1.5   # siła czerwonej poświaty wokół oczu
@export var dzwiek: AudioStream            # opcjonalny dźwięk przy otwarciu oczu
@export var glosnosc_db: float = 0.0

@export_group("Test")
@export var tryb_testowy: bool = true      # false = klawisz testowy nic nie robi (na wersję końcową)
@export var klawisz_testowy: Key = KEY_F3

enum Stan { SPOKOJ, OTWIERANIE, PATRZY, ZAMYKANIE }

const OKO_ZAMKNIETE := Vector3(1.6, 0.03, 0.35)   # spłaszczone, pionowa szczelina
const OKO_OTWARTE := Vector3(1.6, 1.0, 0.35)

var gracz: CharacterBody3D

var _stan: Stan = Stan.SPOKOJ
var _t: float = 0.0
var _do_nastepnego: float = 0.0
var _kamera: Camera3D
var _audio: AudioStreamPlayer

# zasoby tworzone raz
var _material: StandardMaterial3D
var _mesh: SphereMesh
var _oczy: Node3D
var _oczy_mesh: Array[MeshInstance3D] = []
var _swiatlo: OmniLight3D

var _cel_poz := Vector3.ZERO
var _pozostale_mrugniecia: int = 0


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

	_zbuduj_oczy()
	_losuj_przerwe()


func _losuj_przerwe() -> void:
	_do_nastepnego = randf_range(min_przerwa, maxf(max_przerwa, min_przerwa))


# Wymusza zdarzenie od razu (np. z innego skryptu albo z jumpscare)
func wymus() -> void:
	if _stan == Stan.SPOKOJ:
		_start()


func _unhandled_input(event: InputEvent) -> void:
	if not tryb_testowy:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == klawisz_testowy:
		wymus()


func _process(delta: float) -> void:
	match _stan:
		Stan.SPOKOJ:
			if not wlaczony:
				return
			_do_nastepnego -= delta
			if _do_nastepnego <= 0.0:
				if not _start():
					_do_nastepnego = 2.0   # nie wyszło (np. ściana tuż przed twarzą), próbujemy za chwilę

		Stan.OTWIERANIE:
			_t += delta / maxf(czas_otwierania, 0.01)
			_ustaw_otwarcie(minf(_t, 1.0))
			if _t >= 1.0:
				_przejdz(Stan.PATRZY)

		Stan.PATRZY:
			_t += delta
			if _t >= czas_otwartych:
				_przejdz(Stan.ZAMYKANIE)

		Stan.ZAMYKANIE:
			_t += delta / maxf(czas_zamykania, 0.01)
			_ustaw_otwarcie(1.0 - minf(_t, 1.0))
			if _t >= 1.0:
				if _pozostale_mrugniecia > 0:
					_pozostale_mrugniecia -= 1
					_przejdz(Stan.OTWIERANIE)
				else:
					_zakoncz()


func _przejdz(nowy: Stan) -> void:
	_stan = nowy
	_t = 0.0
	if nowy == Stan.OTWIERANIE and _audio != null:
		_audio.play()


# ---------- Start / koniec ----------

func _start() -> bool:
	if gracz == null or _kamera == null or _stan != Stan.SPOKOJ:
		return false
	if gracz.call("_inventory_open"):
		return false
	if not _znajdz_miejsce():
		return false

	_pozostale_mrugniecia = maxi(liczba_mrugniec - 1, 0)
	_pokaz_oczy()
	_przejdz(Stan.OTWIERANIE)
	return true


func _zakoncz() -> void:
	_ukryj_oczy()
	_stan = Stan.SPOKOJ
	_t = 0.0
	_losuj_przerwe()


# ---------- Wybór miejsca (zawsze w kadrze kamery) ----------

# Losuje kierunek w obrębie widoku kamery i stawia oczy w powietrzu albo na ścianie.
# Próbuje kilka razy, bo wylosowany kierunek może kończyć się ścianą tuż przed twarzą
# albo punktem poza kadrem.
func _znajdz_miejsce() -> bool:
	var od := _kamera.global_position
	var baza := _kamera.global_transform.basis.orthonormalized()
	var przestrzen := gracz.get_world_3d().direct_space_state

	for i in 10:
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

		# pewność, że gracz je zobaczy: punkt musi mieścić się w kadrze
		if not _kamera.is_position_in_frustum(cel):
			continue

		_cel_poz = cel
		return true
	return false


# ---------- Oczy ----------

# Tworzone raz. Węzeł jest top_level, więc współrzędne są światowe (nie zależą od gracza).
func _zbuduj_oczy() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = kolor
	_material.emission_enabled = true
	_material.emission = kolor
	_material.emission_energy_multiplier = 3.0

	_mesh = SphereMesh.new()
	_mesh.radius = rozmiar
	_mesh.height = rozmiar * 2.0
	_mesh.radial_segments = 12
	_mesh.rings = 6

	_oczy = Node3D.new()
	_oczy.name = "CzerwoneOczy"
	_oczy.top_level = true
	_oczy.visible = false
	add_child(_oczy)

	for strona in [-1.0, 1.0]:
		var oko := MeshInstance3D.new()
		oko.mesh = _mesh
		oko.material_override = _material
		oko.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		oko.position = Vector3(strona * rozstaw * 0.5, 0.0, 0.0)
		oko.scale = OKO_ZAMKNIETE
		oko.visible = false
		_oczy.add_child(oko)
		_oczy_mesh.append(oko)

	_swiatlo = OmniLight3D.new()
	_swiatlo.light_color = kolor
	_swiatlo.omni_range = 3.5
	_swiatlo.light_energy = 0.0
	_swiatlo.shadow_enabled = false
	_swiatlo.position = Vector3(0.0, 0.0, -0.3)   # lekko przed oczami, w stronę gracza
	_oczy.add_child(_swiatlo)


func _pokaz_oczy() -> void:
	_oczy.global_position = _cel_poz
	var patrzy_na := _kamera.global_position
	if not _cel_poz.is_equal_approx(patrzy_na):
		_oczy.look_at(patrzy_na, Vector3.UP)   # oczy "patrzą" na gracza
	_ustaw_otwarcie(0.0)
	_oczy.visible = true


func _ukryj_oczy() -> void:
	_ustaw_otwarcie(0.0)
	_oczy.visible = false


# 0 = zamknięte (niewidoczne), 1 = w pełni otwarte
func _ustaw_otwarcie(otwarcie: float) -> void:
	for oko in _oczy_mesh:
		oko.visible = otwarcie > 0.02
		oko.scale = OKO_ZAMKNIETE.lerp(OKO_OTWARTE, otwarcie)
	_swiatlo.light_energy = swiatlo_energia * otwarcie
