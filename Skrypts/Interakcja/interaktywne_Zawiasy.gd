class_name InteraktywnyZawias
extends AnimatableBody3D
# Obiekt otwierany jak w Phasmophobii: celujesz, przytrzymujesz LPM i ruszasz kamerą.
# Punkt chwytu podąża za środkiem ekranu (kamera + ruch gracza), żadna oś nie jest blokowana.
# Po puszczeniu LPM obiekt dalej się rusza z bezwładnością (można trzasnąć drzwiami).
#
# USTAWIENIE:
#  - węzeł AnimatableBody3D z tym skryptem stoi DOKŁADNIE w miejscu zawiasu
#    (jego pozycja = oś obrotu). Model i CollisionShape3D są jego dziećmi, przesuniętymi od zawiasu.
#  - scena w pozycji ZAMKNIĘTEJ (q = 0)
#  - ZAWIAS: obraca wokół 'Os Lokalna' (domyślnie Y), SZUFLADA: przesuwa wzdłuż 'Os Lokalna'
#  - 'Kat Otwarcia' / 'Przesuw Otwarcia' ze znakiem minus = otwiera się w drugą stronę

enum Typ { ZAWIAS, SZUFLADA }

@export var typ: Typ = Typ.ZAWIAS
@export var os_lokalna: Vector3 = Vector3.UP
@export var kat_otwarcia: float = 90.0
@export var przesuw_otwarcia: float = 0.4
@export_range(0.0, 1.0, 0.01) var start_otwarcie: float = 0.0

@export_group("Przeciąganie")
@export var przycisk: MouseButton = MOUSE_BUTTON_LEFT
@export var maks_dystans: float = 3.0                # dalej od kamery = puszcza
@export var maks_odchylenie: float = 1.5             # gdy punkt chwytu ucieknie tak daleko od celownika = puszcza
@export_range(0.05, 1.0, 0.05) var sledzenie: float = 1.0   # 1 = sztywno za celownikiem, mniej = bardziej "ciężko"
@export var maks_krok_kat: float = 0.35              # maks. obrót na klatkę fizyki (rad), zabezpieczenie przed skokami
@export var maks_krok_przesuw: float = 0.2           # maks. przesuw na klatkę (m)

@export_group("Fizyka")
@export var tlumienie: float = 2.5
@export_range(0.0, 1.0, 0.05) var odbicie: float = 0.2
@export var zatrzask: float = 0.05
@export var zablokowane: bool = false
@export var klucz: Item
@export var zuzyj_klucz: bool = false

@export_group("Napisy")
@export var prompt_otworz: String = "Otwórz (przytrzymaj i ruszaj kamerą)"
@export var prompt_zamknij: String = "Zamknij (przytrzymaj i ruszaj kamerą)"
@export var prompt_zablokowane: String = "Zamknięte"

@export_group("Dźwięki")
@export var dzwiek_otwarcie: AudioStream
@export var dzwiek_zamkniecie: AudioStream
@export var dzwiek_skrzyp: AudioStream
@export var dzwiek_zamkniete: AudioStream
@export var dzwiek_odblokowanie: AudioStream
@export var glosnosc_db: float = 0.0

# odczytywane przez gracza (prefiks + tekst)
var prompt_prefix: String = "[LPM] "
var prompt_text: String = ""

var q: float = 0.0
var omega: float = 0.0

var _lo: float = 0.0
var _hi: float = 0.0
var _eps: float = 0.0
var _v_stop: float = 0.0
var _v_ref: float = 1.0
var _os: Vector3 = Vector3.UP
var _baza_basis: Basis
var _baza_poz: Vector3

var _trzyma: bool = false
var _gracz: Node3D
var _chwyt_lok: Vector3 = Vector3.ZERO   # punkt chwytu w układzie obiektu
var _chwyt_dyst: float = 1.0             # odległość kamera -> punkt chwytu w chwili złapania
var _byl_otwarty: bool = false

var _sfx: AudioStreamPlayer3D
var _sfx_skrzyp: AudioStreamPlayer3D


func _ready() -> void:
	sync_to_physics = true
	_baza_basis = basis
	_baza_poz = position
	_os = os_lokalna.normalized() if os_lokalna.length() > 0.001 else Vector3.UP

	var otw: float
	if typ == Typ.ZAWIAS:
		otw = deg_to_rad(kat_otwarcia)
		_eps = deg_to_rad(0.5)
		_v_stop = 0.03
		_v_ref = 2.0
	else:
		otw = przesuw_otwarcia
		_eps = 0.004
		_v_stop = 0.015
		_v_ref = 1.0
	_lo = minf(0.0, otw)
	_hi = maxf(0.0, otw)
	q = otw * start_otwarcie
	_byl_otwarty = absf(q) > _eps

	_sfx = _zrob_sfx()
	_sfx_skrzyp = _zrob_sfx()
	_sfx_skrzyp.stream = dzwiek_skrzyp

	_zastosuj()
	_odswiez_prompt()
	set_physics_process(false)


func _zrob_sfx() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.unit_size = 6.0
	add_child(p)
	return p


# E już nic nie robi (metoda zostaje, bo gracz po niej rozpoznaje obiekt i pokazuje napis)
func interact(_gracz_arg = null) -> void:
	pass


# ---------- Wejście: LPM ----------

func _input(event: InputEvent) -> void:
	if _trzyma:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == przycisk):
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	var gracz := _znajdz_gracza()
	if gracz == null:
		return
	if gracz.has_method("is_dead") and gracz.call("is_dead"):
		return
	if gracz.has_method("_inventory_open") and gracz.call("_inventory_open"):
		return
	if gracz.get("kontrola_zablokowana"):
		return

	var ray := gracz.get("interact_ray") as RayCast3D
	if ray == null or not ray.is_colliding() or ray.get_collider() != self:
		return

	get_viewport().set_input_as_handled()   # klik nie leci dalej (np. do przedmiotu w ręku)

	if zablokowane and not _odblokuj():
		_zagraj(dzwiek_zamkniete)
		return

	var cam := gracz.get("camera") as Camera3D
	if cam == null:
		return
	var pkt := ray.get_collision_point()
	_gracz = gracz
	_chwyt_lok = to_local(pkt)
	_chwyt_dyst = cam.global_position.distance_to(pkt)
	_trzyma = true
	set_physics_process(true)


func _znajdz_gracza() -> Node3D:
	if _gracz != null and is_instance_valid(_gracz):
		return _gracz
	var cam := get_viewport().get_camera_3d()
	var n: Node = cam
	while n != null:
		if n is CharacterBody3D:
			_gracz = n as Node3D
			return _gracz
		n = n.get_parent()
	return null


func _odblokuj() -> bool:
	if klucz == null:
		return false
	var inv := get_node_or_null("/root/Inventory")
	if inv == null or not inv.ma(klucz):
		return false
	if zuzyj_klucz:
		inv.usun_item(klucz, 1)
	zablokowane = false
	_zagraj(dzwiek_odblokowanie)
	_odswiez_prompt()
	return true


func odblokuj_na_sile() -> void:
	zablokowane = false
	_odswiez_prompt()


func _pusc() -> void:
	_trzyma = false
	_odswiez_prompt()


func _cel_celownika(cam: Camera3D) -> Vector3:
	return cam.global_position - cam.global_transform.basis.z * _chwyt_dyst


func _powinien_puscic(cam: Camera3D) -> bool:
	if _gracz == null or not is_instance_valid(_gracz) or cam == null:
		return true
	if not Input.is_mouse_button_pressed(przycisk) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return true
	if _gracz.has_method("is_dead") and _gracz.call("is_dead"):
		return true
	if _gracz.has_method("_inventory_open") and _gracz.call("_inventory_open"):
		return true
	var chwyt := to_global(_chwyt_lok)
	if cam.global_position.distance_to(chwyt) > maks_dystans:
		return true
	if chwyt.distance_to(_cel_celownika(cam)) > maks_odchylenie:
		return true
	return false


# ---------- Fizyka ----------

func _physics_process(delta: float) -> void:
	if _trzyma:
		var cam: Camera3D = null
		if _gracz != null and is_instance_valid(_gracz):
			cam = _gracz.get("camera") as Camera3D
		if _powinien_puscic(cam):
			_pusc()
		else:
			var dq := _blad_do_celownika(cam) * sledzenie
			var limit := maks_krok_kat if typ == Typ.ZAWIAS else maks_krok_przesuw
			dq = clampf(dq, -limit, limit)
			var nowe := clampf(q + dq, _lo, _hi)
			omega = lerpf(omega, (nowe - q) / maxf(delta, 0.0001), 0.5)
			q = nowe
	else:
		omega *= exp(-tlumienie * delta)
		q += omega * delta
		if q < _lo:
			q = _lo
			omega = absf(omega) * odbicie
		elif q > _hi:
			q = _hi
			omega = -absf(omega) * odbicie

		var zakres := maxf(_hi - _lo, 0.0001)
		if absf(q) < zakres * zatrzask and absf(omega) < _v_stop * 4.0:
			q = 0.0
			omega = 0.0

	_zastosuj()
	_dzwieki()

	if not _trzyma and absf(omega) < _v_stop:
		omega = 0.0
		_odswiez_prompt()
		set_physics_process(false)


# Ile trzeba zmienić q (rad albo m), żeby punkt chwytu dogonił punkt przed kamerą.
# Działa dla każdego ruchu kamery (obrót w dowolną stronę, chodzenie), bez wybierania osi ekranu.
func _blad_do_celownika(cam: Camera3D) -> float:
	var os_w := (global_transform.basis * _os).normalized()
	var chwyt := to_global(_chwyt_lok)
	var cel := _cel_celownika(cam)

	if typ == Typ.SZUFLADA:
		return (cel - chwyt).dot(os_w)

	var g := chwyt - global_position
	var t := cel - global_position
	g -= os_w * g.dot(os_w)
	t -= os_w * t.dot(os_w)
	if g.length() < 0.05 or t.length() < 0.05:
		return 0.0
	return g.signed_angle_to(t, os_w)


func _zastosuj() -> void:
	if typ == Typ.ZAWIAS:
		basis = _baza_basis * Basis(_os, q)
	else:
		position = _baza_poz + _baza_basis * (_os * q)


# ---------- Dźwięki i napisy ----------

func _dzwieki() -> void:
	var otwarty := absf(q) > _eps
	var predkosc := clampf(absf(omega) / _v_ref, 0.0, 1.0)

	if otwarty != _byl_otwarty:
		_byl_otwarty = otwarty
		if otwarty:
			_zagraj(dzwiek_otwarcie)
		else:
			_zagraj(dzwiek_zamkniecie, linear_to_db(maxf(predkosc, 0.15)))
		_odswiez_prompt()

	if dzwiek_skrzyp != null:
		if predkosc > 0.12:
			_sfx_skrzyp.volume_db = glosnosc_db + linear_to_db(predkosc)
			_sfx_skrzyp.pitch_scale = lerpf(0.9, 1.15, predkosc)
			if not _sfx_skrzyp.playing:
				_sfx_skrzyp.play()
		elif _sfx_skrzyp.playing:
			_sfx_skrzyp.stop()


func _zagraj(strumien: AudioStream, dodatkowe_db: float = 0.0) -> void:
	if strumien == null:
		return
	_sfx.stream = strumien
	_sfx.volume_db = glosnosc_db + dodatkowe_db
	_sfx.play()


func _odswiez_prompt() -> void:
	if zablokowane:
		prompt_text = prompt_zablokowane
	elif absf(q) > _eps:
		prompt_text = prompt_zamknij
	else:
		prompt_text = prompt_otworz
