class_name CzarnyStwor
extends Node
# Jak Herobrine: bardzo rzadko pojawia się daleko za plecami gracza, stoi nieruchomo i patrzy.
# Gdy tylko kamera złapie go w kadr (nawet skrajem ekranu), znika natychmiast i wydaje dźwięk.
# Użycie: Node jako dziecko Gracza (CharacterBody3D) + ten skrypt.
# Własny model: przypisz scenę w polu "Scena" (puste = czarna kapsuła).

enum Strona { ZA_PLECAMI, LEWA, PRAWA, LOSOWA_BOCZNA }

@export var wlaczony: bool = true

@export_group("Szansa")
@export_range(0.0, 1.0, 0.001) var szansa: float = 0.02   # szansa przy każdym sprawdzeniu
@export var interwal_sprawdzania: float = 10.0            # co ile s losujemy
@export var cooldown: float = 90.0                        # min. przerwa po pojawieniu się (s)
@export var max_czas_zycia: float = 20.0                  # znika sam, jeśli gracz się nie odwróci

@export_group("Miejsce")
@export var strona: Strona = Strona.ZA_PLECAMI            # ZA_PLECAMI = Herobrine; LEWA / PRAWA = dźwięk mocno w jednej słuchawce
@export var kat_boczny: float = 70.0                      # ile stopni od "tyłu" w stronę boku (90 = dokładnie z boku)
@export var max_kat: float = 35.0                         # rozrzut wokół wybranego kierunku (stopnie)
@export var odleglosc: float = 18.0                       # max odległość od gracza (m)
@export var min_odleglosc: float = 10.0                   # min odległość od gracza (m)
@export var wymagaj_linii_wzroku: bool = true             # true = pojawia się tylko tam, gdzie nic nie zasłania (widać go po odwróceniu)
@export_flags_3d_physics var maska_kolizji: int = 1

@export_group("Wygląd")
@export var scena: PackedScene
@export var wysokosc: float = 1.9
@export var promien: float = 0.3

@export_group("Dźwięk - pojawienie i ambient")
@export var dzwiek_pojawienia: AudioStream               # jednorazowy dźwięk przy pojawieniu się
@export var dzwiek_ambient: AudioStream                  # pętla z pozycji stwora, dopóki stoi (np. szept, oddech)

@export_group("Dźwięk - zniknięcie")
@export var dzwieki_znikniecia: Array[AudioStream] = []  # losowany jeden przy każdym zniknięciu
@export var glosnosc_znikniecia_db: float = 0.0
@export var pitch_min: float = 0.9                       # losowa wysokość dźwięku
@export var pitch_max: float = 1.1
@export var dzwiek_gdy_zniknie_sam: bool = false         # true = dźwięk także, gdy gracz się nie odwrócił
@export var znikniecie_w_glowie: bool = false            # true = dźwięk 2D (bez pozycji), głośno "w głowie"

@export_group("Dźwięk 3D")
@export var glosnosc_db: float = 0.0
@export var unit_size: float = 10.0                      # im większe, tym głośniej z daleka
@export var max_dystans_dzwieku: float = 40.0
@export_range(0.0, 3.0, 0.1) var sila_panoramy: float = 2.0   # >1 = mocniej w jednym uchu

@export_group("Zachowanie")
@export var czas_widocznosci: float = 0.5               # ile s stwór jest jeszcze widoczny po wejściu w kadr (0 = znika natychmiast)
@export var znikaj_tylko_gdy_niezasloniety: bool = false   # false = Herobrine: znika zawsze, gdy wejdzie w kadr; true = ściana/kolizja między kamerą a stworem blokuje zniknięcie

@export_group("Test")
@export var tryb_testowy: bool = true
@export var klawisz_testowy: Key = KEY_F6
@export var debug_widzenie: bool = false   # true = co 0,5 s pisze w konsoli diagnostykę widzenia stwora

var gracz: CharacterBody3D

var _kamera: Camera3D
var _stwor: Node3D
var _ambient: AudioStreamPlayer3D
var _zycie: float = 0.0
var _do_sprawdzenia: float = 0.0
var _cooldown_left: float = 0.0
var _zobaczony_czas: float = -1.0   # -1 = jeszcze niezauważony


func _ready() -> void:
	set_process(false)   # włączamy dopiero, gdy mamy gracza i kamerę
	if gracz == null:
		gracz = _znajdz_gracza()
	if gracz == null:
		push_warning("czarny_stwor: nie znaleziono gracza (CharacterBody3D)")
		return

	# dzieci dostają _ready() przed rodzicem: czekamy, aż gracz skończy (wtedy @onready camera jest ustawione)
	if not gracz.is_node_ready():
		await gracz.ready

	_kamera = gracz.get("camera") as Camera3D
	if _kamera == null:
		_kamera = gracz.find_child("Camera3D", true, false) as Camera3D
	if _kamera == null:
		push_warning("czarny_stwor: gracz nie ma kamery")
		return

	_do_sprawdzenia = interwal_sprawdzania
	set_process(true)


# Szuka gracza w górę drzewa, a jeśli go tam nie ma, w całej scenie
func _znajdz_gracza() -> CharacterBody3D:
	var n := get_parent()
	while n != null:
		if n is CharacterBody3D:
			return n as CharacterBody3D
		n = n.get_parent()
	var sc := get_tree().current_scene
	if sc != null:
		for w in sc.find_children("*", "CharacterBody3D", true, false):
			if w.get("camera") != null:
				return w as CharacterBody3D
	return null


func wymus() -> void:
	if gracz == null or _kamera == null:
		return
	if _stwor == null:
		_pojaw()


func _unhandled_input(event: InputEvent) -> void:
	if not tryb_testowy or _kamera == null:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == klawisz_testowy:
		wymus()


func _process(delta: float) -> void:
	if _stwor != null:
		_zycie += delta
		if debug_widzenie:
			_debug_info(delta)
		if not wlaczony or _zycie >= max_czas_zycia:
			_znikaj(false)
		elif _zobaczony_czas >= 0.0:
			# gracz już go zobaczył: odliczamy czas widoczności, potem znika
			_zobaczony_czas += delta
			if _zobaczony_czas >= czas_widocznosci:
				_znikaj(true)
		elif _widziany():
			if czas_widocznosci <= 0.0:
				_znikaj(true)
			else:
				_zobaczony_czas = 0.0
		return

	if not wlaczony:
		return
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_do_sprawdzenia -= delta
	if _do_sprawdzenia > 0.0:
		return
	_do_sprawdzenia = interwal_sprawdzania
	if _cooldown_left <= 0.0 and randf() < szansa:
		_pojaw()


# ---------- Pojawianie ----------

func _pojaw() -> bool:
	if gracz.has_method("is_dead") and gracz.call("is_dead"):
		return false
	if gracz.has_method("_inventory_open") and gracz.call("_inventory_open"):
		return false

	var poz = _znajdz_miejsce()
	if poz == null:
		return false

	_stwor = _zrob_model()
	add_child(_stwor)
	_stwor.top_level = true
	_stwor.global_position = poz
	var cel := Vector3(_kamera.global_position.x, poz.y, _kamera.global_position.z)
	if not cel.is_equal_approx(poz):
		_stwor.look_at(cel, Vector3.UP)   # patrzy na gracza

	# dźwięk ambient: odtwarzacz 3D przyklejony do stwora, znika razem z nim
	if dzwiek_ambient != null:
		_ambient = _zrob_odtwarzacz(dzwiek_ambient, glosnosc_db)
		_ambient.position.y = wysokosc * 0.7
		_stwor.add_child(_ambient)
		_zapetl(dzwiek_ambient)
		_ambient.play()

	_graj_3d(dzwiek_pojawienia, poz + Vector3.UP * wysokosc * 0.7, glosnosc_db)

	_zycie = 0.0
	_zobaczony_czas = -1.0
	_cooldown_left = cooldown
	return true


func _kierunek_bazowy() -> Vector3:
	var tyl := _kamera.global_transform.basis.z
	tyl.y = 0.0
	tyl = tyl.normalized()
	# dodatni obrót wokół UP od tyłu = prawa strona gracza
	match strona:
		Strona.LEWA:
			return tyl.rotated(Vector3.UP, -deg_to_rad(kat_boczny))
		Strona.PRAWA:
			return tyl.rotated(Vector3.UP, deg_to_rad(kat_boczny))
		Strona.LOSOWA_BOCZNA:
			var znak := 1.0 if randf() < 0.5 else -1.0
			return tyl.rotated(Vector3.UP, deg_to_rad(kat_boczny) * znak)
		_:
			return tyl


func _znajdz_miejsce():
	var od := _kamera.global_position
	var przestrzen := gracz.get_world_3d().direct_space_state
	var baza := _kierunek_bazowy()

	for i in 12:
		var kierunek := baza.rotated(Vector3.UP, deg_to_rad(randf_range(-max_kat, max_kat)))
		var dystans := randf_range(min_odleglosc, odleglosc)
		var punkt := gracz.global_position + kierunek * dystans

		var q_podloga := PhysicsRayQueryParameters3D.create(
				punkt + Vector3.UP * 2.0, punkt + Vector3.DOWN * 4.0, maska_kolizji, [gracz.get_rid()])
		var podloga := przestrzen.intersect_ray(q_podloga)
		if podloga.is_empty():
			continue
		var stopy: Vector3 = podloga["position"]

		# nie w ścianie: między kamerą a stworem nie może być przeszkody
		var srodek := stopy + Vector3.UP * wysokosc * 0.5
		if wymagaj_linii_wzroku:
			var q_sciana := PhysicsRayQueryParameters3D.create(od, srodek, maska_kolizji, [gracz.get_rid()])
			if not przestrzen.intersect_ray(q_sciana).is_empty():
				continue

		# nie może pojawić się w kadrze
		if _w_kadrze(stopy):
			continue

		return stopy
	return null


func _zrob_model() -> Node3D:
	if scena != null:
		var inst := scena.instantiate() as Node3D
		if inst != null:
			return inst

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.BLACK

	var mesh := CapsuleMesh.new()
	mesh.radius = promien
	mesh.height = wysokosc
	mesh.material = mat

	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position.y = wysokosc * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return root


# ---------- Wykrywanie spojrzenia ----------

func _w_kadrze(p: Vector3) -> bool:
	return _kamera.is_position_in_frustum(p)


func _zasloniete(p: Vector3) -> bool:
	var przestrzen := gracz.get_world_3d().direct_space_state
	var od := _kamera.global_position
	var kier := (p - od).normalized()
	# koniec promienia tuż przed punktem, żeby nie trafiał w podłogę pod stopami ani w sam model
	var koniec := p - kier * 0.15
	var wyjatki: Array[RID] = [gracz.get_rid()]
	_zbierz_kolizje(_stwor, wyjatki)   # własna kolizja stwora (jeśli model ją ma) nie może go "zasłaniać"
	var q := PhysicsRayQueryParameters3D.create(od, koniec, maska_kolizji, wyjatki)
	var trafienie := przestrzen.intersect_ray(q)
	if debug_widzenie and not trafienie.is_empty():
		print("[stwor] zasłonięty przez: ", (trafienie["collider"] as Node).get_path())
	return not trafienie.is_empty()


func _zbierz_kolizje(wezel: Node, out: Array[RID]) -> void:
	if wezel is CollisionObject3D:
		out.append((wezel as CollisionObject3D).get_rid())
	for d in wezel.get_children():
		_zbierz_kolizje(d, out)


# Punkty testowe liczone z PRAWDZIWEGO obrysu modelu (siatka 3x3x3 po jego AABB),
# więc nie zależy od tego, gdzie model ma origin ani jaką ustawiłeś 'Wysokosc'.
func _punkty_testowe() -> PackedVector3Array:
	var out := PackedVector3Array()
	var meshe: Array = _stwor.find_children("*", "GeometryInstance3D", true, false)
	if _stwor is GeometryInstance3D:
		meshe.append(_stwor)

	var ma := false
	var obrys := AABB()
	for m in meshe:
		var g := m as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var a: AABB = g.global_transform * g.get_aabb()
		obrys = a if not ma else obrys.merge(a)
		ma = true

	if not ma:
		# model bez meshy: stary sposób (stopy, tułów, głowa)
		for h in [0.05, wysokosc * 0.5, wysokosc]:
			out.append(_stwor.global_position + Vector3.UP * h)
		return out

	for ix in 3:
		for iy in 3:
			for iz in 3:
				out.append(obrys.position + obrys.size * Vector3(ix * 0.5, iy * 0.5, iz * 0.5))
	return out


func _widziany() -> bool:
	for p in _punkty_testowe():
		if not _w_kadrze(p):
			continue
		if znikaj_tylko_gdy_niezasloniety and _zasloniete(p):
			continue
		return true
	return false


var _dbg_t: float = 0.0

func _debug_info(delta: float) -> void:
	_dbg_t -= delta
	if _dbg_t > 0.0:
		return
	_dbg_t = 0.5
	var pts := _punkty_testowe()
	var w_kadrze := 0
	var zaslonietych := 0
	for p in pts:
		if _w_kadrze(p):
			w_kadrze += 1
			if _zasloniete(p):
				zaslonietych += 1
	var kier := (_stwor.global_position - _kamera.global_position).normalized()
	var kat := rad_to_deg(acos(clampf((-_kamera.global_transform.basis.z).dot(kier), -1.0, 1.0)))
	print("[stwor] dystans %.1f m | kąt od osi kamery %.0f° | punktów %d, w kadrze %d, zasłoniętych %d | kamera far %.0f | poz stwora %s" % [
		_kamera.global_position.distance_to(_stwor.global_position), kat,
		pts.size(), w_kadrze, zaslonietych, _kamera.far, str(_stwor.global_position)])


func _znikaj(widziany: bool) -> void:
	if _stwor == null:
		return
	if widziany or dzwiek_gdy_zniknie_sam:
		_dzwiek_znikniecia(_stwor.global_position + Vector3.UP * wysokosc * 0.7)
	_stwor.queue_free()   # razem z nim znika też odtwarzacz ambientu
	_stwor = null
	_ambient = null


# ---------- Dźwięk ----------

func _dzwiek_znikniecia(poz: Vector3) -> void:
	if dzwieki_znikniecia.is_empty():
		return
	var strumien: AudioStream = dzwieki_znikniecia.pick_random()
	if strumien == null:
		return
	var pitch := randf_range(minf(pitch_min, pitch_max), maxf(pitch_min, pitch_max))

	if znikniecie_w_glowie:
		var p2 := AudioStreamPlayer.new()
		p2.stream = strumien
		p2.volume_db = glosnosc_znikniecia_db
		p2.pitch_scale = pitch
		add_child(p2)
		p2.finished.connect(p2.queue_free)
		p2.play()
	else:
		_graj_3d(strumien, poz, glosnosc_znikniecia_db, pitch)


func _zrob_odtwarzacz(strumien: AudioStream, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = strumien
	p.volume_db = db
	p.unit_size = unit_size
	p.max_distance = max_dystans_dzwieku
	p.panning_strength = sila_panoramy
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	return p


# Dźwięk zostaje w miejscu, nawet gdy stwór już zniknął
func _graj_3d(strumien: AudioStream, poz: Vector3, db: float, pitch: float = 1.0) -> void:
	if strumien == null:
		return
	var p := _zrob_odtwarzacz(strumien, db)
	p.pitch_scale = pitch
	p.top_level = true
	add_child(p)
	p.global_position = poz
	p.finished.connect(p.queue_free)
	p.play()


func _zapetl(strumien: AudioStream) -> void:
	if strumien is AudioStreamOggVorbis:
		(strumien as AudioStreamOggVorbis).loop = true
	elif strumien is AudioStreamMP3:
		(strumien as AudioStreamMP3).loop = true
	elif _ambient != null:
		_ambient.finished.connect(_ambient.play)   # np. WAV
