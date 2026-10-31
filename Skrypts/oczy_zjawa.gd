extends Node
# Losowe zdarzenie: kamera sama obraca się w losowe miejsce i przybliża, tam otwierają się
# czerwone, świecące oczy i zamykają, po czym kamera wraca do normalnego widoku.
# Tworzy je gracz (character_body_3d.gd). Ręcznie: wymus() albo klawisz F3 w trybie testowym.

@export var wlaczony: bool = true
@export var min_przerwa: float = 25.0      # minimalny czas między zdarzeniami (s)
@export var max_przerwa: float = 70.0      # maksymalny czas między zdarzeniami (s)

@export_group("Spojrzenie")
@export var min_kat: float = 50.0          # o ile stopni w bok od kierunku patrzenia (min)
@export var max_kat: float = 150.0         # o ile stopni w bok od kierunku patrzenia (max)
@export var min_wysokosc_kat: float = -5.0 # kąt w pionie (min), ujemny = w dół
@export var max_wysokosc_kat: float = 18.0 # kąt w pionie (max), dodatni = w górę
@export var odleglosc: float = 7.0         # jak daleko pojawiają się oczy (m)
@export var min_odleglosc: float = 2.0     # bliżej niż to nie stawiamy oczu (ściana tuż przed twarzą)
@export var czas_obrotu: float = 0.45      # jak szybko kamera odwraca się w stronę oczu (s)
@export var czas_powrotu: float = 0.7      # jak wolno kamera wraca do normalnego widoku (s)
@export var zoom_fov: float = 45.0         # FOV przy przybliżeniu (normalnie ok. 75)
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

enum Stan { SPOKOJ, OBROT, OTWIERANIE, PATRZY, ZAMYKANIE, POWROT }

var gracz: CharacterBody3D

var _stan: Stan = Stan.SPOKOJ
var _t: float = 0.0
var _do_nastepnego: float = 0.0
var _kamera: Camera3D
var _audio: AudioStreamPlayer

var _oczy: Node3D
var _oczy_mesh: Array[MeshInstance3D] = []
var _swiatlo: OmniLight3D
var _cel_poz := Vector3.ZERO
var _pozostale_mrugniecia: int = 0

var _start_yaw: float = 0.0
var _start_pitch: float = 0.0
var _start_fov: float = 75.0
var _ostatni_yaw: float = 0.0
var _ostatni_pitch: float = 0.0
var _od_yaw: float = 0.0
var _od_pitch: float = 0.0


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

	_losuj_przerwe()


func _exit_tree() -> void:
	if _stan != Stan.SPOKOJ and gracz != null:
		gracz.set("kontrola_zablokowana", false)
	_usun_oczy()


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

		Stan.OBROT:
			_t += delta / maxf(czas_obrotu, 0.01)
			var s := smoothstep(0.0, 1.0, minf(_t, 1.0))
			_patrz(s)
			_kamera.fov = lerpf(_start_fov, zoom_fov, s)
			if _t >= 1.0:
				_przejdz(Stan.OTWIERANIE)

		Stan.OTWIERANIE:
			_patrz(1.0)
			_t += delta / maxf(czas_otwierania, 0.01)
			_ustaw_otwarcie(minf(_t, 1.0))
			if _t >= 1.0:
				_przejdz(Stan.PATRZY)

		Stan.PATRZY:
			_patrz(1.0)
			_t += delta
			if _t >= czas_otwartych:
				_przejdz(Stan.ZAMYKANIE)

		Stan.ZAMYKANIE:
			_patrz(1.0)
			_t += delta / maxf(czas_zamykania, 0.01)
			_ustaw_otwarcie(1.0 - minf(_t, 1.0))
			if _t >= 1.0:
				if _pozostale_mrugniecia > 0:
					_pozostale_mrugniecia -= 1
					_przejdz(Stan.OTWIERANIE)
				else:
					_usun_oczy()
					_od_yaw = _ostatni_yaw
					_od_pitch = _ostatni_pitch
					_przejdz(Stan.POWROT)

		Stan.POWROT:
			_t += delta / maxf(czas_powrotu, 0.01)
			var s := smoothstep(0.0, 1.0, minf(_t, 1.0))
			gracz.rotation.y = lerp_angle(_od_yaw, _start_yaw, s)
			_kamera.rotation.x = lerpf(_od_pitch, _start_pitch, s)
			_kamera.fov = lerpf(zoom_fov, _start_fov, s)
			if _t >= 1.0:
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

	_start_yaw = gracz.rotation.y
	_start_pitch = _kamera.rotation.x
	_start_fov = _kamera.fov
	_ostatni_yaw = _start_yaw
	_ostatni_pitch = _start_pitch
	_pozostale_mrugniecia = maxi(liczba_mrugniec - 1, 0)

	gracz.set("kontrola_zablokowana", true)
	_przejdz(Stan.OBROT)
	return true


func _zakoncz() -> void:
	gracz.rotation.y = _start_yaw
	_kamera.rotation.x = _start_pitch
	_kamera.fov = _start_fov
	gracz.set("kontrola_zablokowana", false)
	_stan = Stan.SPOKOJ
	_t = 0.0
	_losuj_przerwe()


# ---------- Wybór miejsca ----------

# Losuje kierunek w bok od patrzenia gracza i stawia oczy w powietrzu albo na ścianie.
# Próbuje kilka razy, bo wylosowany kierunek może kończyć się ścianą tuż przed twarzą.
func _znajdz_miejsce() -> bool:
	var od := _kamera.global_position
	var przod: Vector3 = -gracz.global_transform.basis.z
	var przestrzen := gracz.get_world_3d().direct_space_state

	for i in 8:
		var kat := deg_to_rad(randf_range(min_kat, max_kat)) * (1.0 if randf() < 0.5 else -1.0)
		var kierunek := przod.rotated(Vector3.UP, kat)
		var os := kierunek.cross(Vector3.UP).normalized()
		kierunek = kierunek.rotated(os, deg_to_rad(randf_range(min_wysokosc_kat, max_wysokosc_kat)))

		var koniec := od + kierunek * odleglosc
		var zapytanie := PhysicsRayQueryParameters3D.create(od, koniec, maska_kolizji, [gracz.get_rid()])
		var trafienie := przestrzen.intersect_ray(zapytanie)

		if trafienie.is_empty():
			_cel_poz = koniec
		else:
			var punkt: Vector3 = trafienie["position"]
			if od.distance_to(punkt) < min_odleglosc:
				continue
			var normalna: Vector3 = trafienie["normal"]
			_cel_poz = punkt + normalna * 0.05   # lekko przed ścianą, żeby oczy w niej nie zniknęły

		_stworz_oczy(od)
		return true
	return false


# ---------- Kamera ----------

# waga 0 = widok z początku zdarzenia, 1 = patrzy prosto na oczy
func _patrz(waga: float) -> void:
	var d := _cel_poz - _kamera.global_position
	var poziomo := Vector2(d.x, d.z).length()
	var cel_yaw := atan2(-d.x, -d.z)
	var cel_pitch := atan2(d.y, poziomo)

	_ostatni_yaw = lerp_angle(_start_yaw, cel_yaw, waga)
	_ostatni_pitch = lerpf(_start_pitch, cel_pitch, waga)

	gracz.rotation.y = _ostatni_yaw
	_kamera.rotation.x = clampf(_ostatni_pitch, -1.55, 1.55)


# ---------- Oczy ----------

func _stworz_oczy(patrzy_na: Vector3) -> void:
	_usun_oczy()

	var scena := get_tree().current_scene
	if scena == null:
		return

	_oczy = Node3D.new()
	scena.add_child(_oczy)
	_oczy.global_position = _cel_poz
	if not _cel_poz.is_equal_approx(patrzy_na):
		_oczy.look_at(patrzy_na, Vector3.UP)   # oczy "patrzą" na gracza

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = kolor
	mat.emission_enabled = true
	mat.emission = kolor
	mat.emission_energy_multiplier = 3.0

	var kula := SphereMesh.new()
	kula.radius = rozmiar
	kula.height = rozmiar * 2.0
	kula.radial_segments = 12
	kula.rings = 6

	for strona in [-1.0, 1.0]:
		var oko := MeshInstance3D.new()
		oko.mesh = kula
		oko.material_override = mat
		oko.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		oko.position = Vector3(strona * rozstaw * 0.5, 0.0, 0.0)
		oko.scale = Vector3(1.6, 0.03, 0.35)   # spłaszczone, pionowa szczelina (zamknięte)
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


# 0 = zamknięte (niewidoczne), 1 = w pełni otwarte
func _ustaw_otwarcie(otwarcie: float) -> void:
	if _oczy == null:
		return
	for oko in _oczy_mesh:
		oko.visible = otwarcie > 0.02
		oko.scale.y = lerpf(0.03, 1.0, otwarcie)
	if _swiatlo != null:
		_swiatlo.light_energy = swiatlo_energia * otwarcie


func _usun_oczy() -> void:
	if _oczy != null and is_instance_valid(_oczy):
		_oczy.queue_free()
	_oczy = null
	_swiatlo = null
	_oczy_mesh.clear()
