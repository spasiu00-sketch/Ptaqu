class_name InteraktywnyZawias
extends AnimatableBody3D
# Obiekt otwierany jak w Phasmophobii: celujesz, przytrzymujesz E i ruszasz myszką.
# Po puszczeniu E obiekt dalej się rusza z bezwładnością (można trzasnąć drzwiami).
#
# USTAWIENIE:
#  - węzeł AnimatableBody3D z tym skryptem stoi DOKŁADNIE w miejscu zawiasu
#    (jego pozycja = oś obrotu). Model i CollisionShape3D są jego dziećmi, przesuniętymi od zawiasu.
#  - scena w pozycji ZAMKNIĘTEJ (q = 0)
#  - ZAWIAS: obraca wokół 'Os Lokalna' (domyślnie Y), SZUFLADA: przesuwa wzdłuż 'Os Lokalna'
#  - 'Kat Otwarcia' / 'Przesuw Otwarcia' ze znakiem minus = otwiera się w drugą stronę

enum Typ { ZAWIAS, SZUFLADA }

@export var typ: Typ = Typ.ZAWIAS
@export var os_lokalna: Vector3 = Vector3.UP         # ZAWIAS: oś obrotu, SZUFLADA: kierunek wysuwania
@export var kat_otwarcia: float = 90.0               # stopnie (ZAWIAS), ze znakiem = kierunek otwierania
@export var przesuw_otwarcia: float = 0.4            # metry (SZUFLADA), ze znakiem = kierunek
@export_range(0.0, 1.0, 0.01) var start_otwarcie: float = 0.0   # 0 = zamknięte, 1 = otwarte do końca

@export_group("Przeciąganie")
@export var akcja: StringName = &"interact"
@export var czulosc_kat: float = 0.006               # rad na piksel myszy (ZAWIAS)
@export var czulosc_przesuw: float = 0.0025          # m na piksel myszy (SZUFLADA)
@export var maks_dystans: float = 3.0                # dalej od kamery = puszcza

@export_group("Fizyka")
@export var tlumienie: float = 2.5                   # im więcej, tym szybciej wyhamowuje po puszczeniu
@export_range(0.0, 1.0, 0.05) var odbicie: float = 0.2   # odbicie od ograniczników
@export var zatrzask: float = 0.05                   # ułamek zakresu, w którym wolny obiekt sam domyka się na 0
@export var zablokowane: bool = false
@export var klucz: Item                              # puste = zamknięte na stałe (do odblokowania z kodu)
@export var zuzyj_klucz: bool = false

@export_group("Napisy")
@export var prompt_otworz: String = "Otwórz (przytrzymaj i przeciągnij)"
@export var prompt_zamknij: String = "Zamknij (przytrzymaj i przeciągnij)"
@export var prompt_zablokowane: String = "Zamknięte"

@export_group("Dźwięki")
@export var dzwiek_otwarcie: AudioStream             # gdy obiekt rusza z pozycji zamkniętej
@export var dzwiek_zamkniecie: AudioStream           # gdy wraca do pozycji zamkniętej (głośność zależy od siły trzaśnięcia)
@export var dzwiek_skrzyp: AudioStream               # gra podczas szybkiego ruchu
@export var dzwiek_zamkniete: AudioStream            # próba otwarcia zamkniętego
@export var dzwiek_odblokowanie: AudioStream
@export var glosnosc_db: float = 0.0

# odczytywane przez gracza ([E] + tekst)
var prompt_text: String = ""

var q: float = 0.0        # aktualne otwarcie: radiany (ZAWIAS) albo metry (SZUFLADA)
var omega: float = 0.0    # prędkość zmiany q

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
var _chwyt_lok: Vector3 = Vector3.ZERO   # punkt chwytu w układzie obiektu (podąża za obiektem)
var _mysz: Vector2 = Vector2.ZERO
var _byl_otwarty: bool = false

var _sfx: AudioStreamPlayer3D
var _sfx_skrzyp: AudioStreamPlayer3D


func _ready() -> void:
	sync_to_physics = true   # ruch poprawnie popycha gracza (CharacterBody3D)
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
	set_physics_process(false)   # działa tylko, gdy obiekt się rusza


func _zrob_sfx() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.unit_size = 6.0
	add_child(p)
	return p


func _exit_tree() -> void:
	if _trzyma:
		_blokuj_kamere(false)


# ---------- Interakcja ----------

# Wołane przez gracza po naciśnięciu [E]
func interact(gracz = null) -> void:
	if _trzyma or gracz == null:
		return
	if zablokowane and not _odblokuj():
		_zagraj(dzwiek_zamkniete)
		return

	_gracz = gracz as Node3D
	if _gracz == null:
		return

	var ray := _gracz.get("interact_ray") as RayCast3D
	var pkt: Vector3 = ray.get_collision_point() if ray != null and ray.is_colliding() else global_position
	_chwyt_lok = to_local(pkt)

	_trzyma = true
	_mysz = Vector2.ZERO
	_blokuj_kamere(true)
	set_physics_process(true)


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


# Gracz nie może się rozglądać podczas przeciągania (patrz poprawka w skrypcie gracza)
func _blokuj_kamere(wlacz: bool) -> void:
	if _gracz == null or not is_instance_valid(_gracz):
		return
	if "kamera_zablokowana" in _gracz:
		_gracz.set("kamera_zablokowana", wlacz)
	else:
		_gracz.set("kontrola_zablokowana", wlacz)   # zapasowo: blokuje też ruch


func _input(event: InputEvent) -> void:
	if _trzyma and event is InputEventMouseMotion:
		_mysz += event.relative


func _pusc() -> void:
	_trzyma = false
	_blokuj_kamere(false)
	_mysz = Vector2.ZERO
	_odswiez_prompt()


func _powinien_puscic() -> bool:
	if _gracz == null or not is_instance_valid(_gracz):
		return true
	if not Input.is_action_pressed(akcja) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return true
	if _gracz.has_method("is_dead") and _gracz.call("is_dead"):
		return true
	if _gracz.has_method("_inventory_open") and _gracz.call("_inventory_open"):
		return true
	var cam := _gracz.get("camera") as Camera3D
	if cam != null and cam.global_position.distance_to(to_global(_chwyt_lok)) > maks_dystans:
		return true
	return false


# ---------- Fizyka ----------

func _physics_process(delta: float) -> void:
	if _trzyma:
		if _powinien_puscic():
			_pusc()
		else:
			var czulosc := czulosc_kat if typ == Typ.ZAWIAS else czulosc_przesuw
			var dq := _mysz.dot(_kierunek_ekranu()) * czulosc
			_mysz = Vector2.ZERO
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

		# wolny obiekt blisko zamknięcia sam wskakuje w zatrzask
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


func _zastosuj() -> void:
	if typ == Typ.ZAWIAS:
		basis = _baza_basis * Basis(_os, q)
	else:
		position = _baza_poz + _baza_basis * (_os * q)


# Kierunek (na ekranie), w którym trzeba ruszyć myszką, żeby q rosło.
# Liczony z ruchu punktu chwytu, więc działa z dowolnej strony i dla dowolnej orientacji.
func _kierunek_ekranu() -> Vector2:
	var cam := _gracz.get("camera") as Camera3D
	if cam == null:
		return Vector2(0.0, -1.0)
	var os_w := (global_transform.basis * _os).normalized()
	var t: Vector3
	if typ == Typ.ZAWIAS:
		t = os_w.cross(to_global(_chwyt_lok) - global_position)
	else:
		t = os_w
	var b := cam.global_transform.basis
	var sd := Vector2(t.dot(b.x), -t.dot(b.y))   # y ekranu rośnie w dół
	if sd.length() < 0.05:
		return Vector2(0.0, -1.0)
	return sd.normalized()


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
