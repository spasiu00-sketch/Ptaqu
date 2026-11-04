class_name MigotanieSwiatla
extends Light3D
# Horrorowe migotanie światła. Przypisz do OmniLight3D / SpotLight3D.
# Cykl: SPOKÓJ (lekkie drżenie) -> SERIA migotania -> (czasem) CIEMNOŚĆ -> SPOKÓJ.
# Ręcznie: $Lampa.wymus_serie(), $Lampa.wylacz_na(3.0), $Lampa.wlacz()

enum Tryb { LAGODNY, AWARIA, ZEPSUTA }
enum Stan { SPOKOJ, SERIA, CIEMNOSC }

@export var wlaczone: bool = true
@export var tryb: Tryb = Tryb.AWARIA

@export_group("Spokój")
@export var drzenie: float = 0.04                 # lekkie wahania jasności w spokoju (0 = brak)
@export var spokoj_min: float = 4.0               # s między seriami
@export var spokoj_max: float = 14.0

@export_group("Seria migotania")
@export var seria_min: float = 0.3                # s
@export var seria_max: float = 1.4
@export var krok_min: float = 0.02                # s między zmianami jasności w serii
@export var krok_max: float = 0.12
@export_range(0.0, 1.0, 0.05) var szansa_zgaszenia: float = 0.4   # szansa na pełne zgaszenie w kroku
@export_range(0.0, 1.0, 0.05) var min_jasnosc: float = 0.1        # dolna granica jasności w serii

@export_group("Ciemność")
@export_range(0.0, 1.0, 0.05) var szansa_ciemnosci: float = 0.35  # szansa, że po serii światło zgaśnie na dłużej
@export var ciemnosc_min: float = 0.8             # s
@export var ciemnosc_max: float = 3.5
@export var rozblysk_po_ciemnosci: bool = true    # krótki, mocny rozbłysk przy powrocie

@export_group("Żarówka (opcjonalnie)")
@export var mesh_zarowki: MeshInstance3D          # mesh z emisją, migający razem ze światłem
@export var powierzchnia: int = 0
@export var emisja_bazowa: float = 2.0            # emission_energy_multiplier przy pełnej jasności

@export_group("Dźwięk (opcjonalnie)")
@export var dzwiek_bzyczenia: AudioStream         # pętla, głośność zależy od jasności
@export var bzyczenie_db: float = -14.0
@export var dzwiek_klik: AudioStream              # przy gaśnięciu / zapaleniu
@export var klik_db: float = -8.0

var _baza: float = 1.0
var _stan: Stan = Stan.SPOKOJ
var _timer: float = 0.0
var _seria_zostalo: float = 0.0
var _krok: float = 0.0
var _wspolczynnik: float = 1.0
var _czas: float = 0.0
var _mat: StandardMaterial3D
var _bzyk: AudioStreamPlayer3D
var _klik: AudioStreamPlayer3D
var _wymuszone_wylaczenie: bool = false


func _ready() -> void:
	_baza = light_energy
	_czas = randf() * 100.0   # różne lampy nie migają w tym samym rytmie
	_timer = randf_range(spokoj_min, maxf(spokoj_max, spokoj_min))

	if mesh_zarowki != null:
		var org := mesh_zarowki.get_active_material(powierzchnia)
		if org is StandardMaterial3D:
			_mat = org.duplicate() as StandardMaterial3D
			_mat.emission_enabled = true
			mesh_zarowki.set_surface_override_material(powierzchnia, _mat)
		else:
			push_warning("MigotanieSwiatla '%s': materiał żarówki musi być StandardMaterial3D" % name)

	if dzwiek_bzyczenia != null:
		_bzyk = _zrob_audio(dzwiek_bzyczenia, bzyczenie_db)
		if dzwiek_bzyczenia is AudioStreamOggVorbis:
			(dzwiek_bzyczenia as AudioStreamOggVorbis).loop = true
		elif dzwiek_bzyczenia is AudioStreamMP3:
			(dzwiek_bzyczenia as AudioStreamMP3).loop = true
		else:
			_bzyk.finished.connect(_bzyk.play)
		_bzyk.play()
	if dzwiek_klik != null:
		_klik = _zrob_audio(dzwiek_klik, klik_db)

	_ustaw(1.0)


func _zrob_audio(strumien: AudioStream, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = strumien
	p.volume_db = db
	p.unit_size = 6.0
	add_child(p)
	return p


# ---------- API ----------

# Natychmiast odpala serię migotania
func wymus_serie() -> void:
	_zacznij_serie()


# Gasi światło na podany czas (potem wraca normalnie z rozbłyskiem)
func wylacz_na(czas: float) -> void:
	_wymuszone_wylaczenie = false
	_zacznij_ciemnosc(czas)


# Gasi na stałe (do wywołania wlacz())
func wylacz() -> void:
	_wymuszone_wylaczenie = true
	_zacznij_ciemnosc(1.0)


func wlacz() -> void:
	_wymuszone_wylaczenie = false
	_stan = Stan.SPOKOJ
	_timer = randf_range(spokoj_min, maxf(spokoj_max, spokoj_min))
	_ustaw(1.0)
	_zagraj_klik()


# ---------- Logika ----------

func _process(delta: float) -> void:
	if not wlaczone:
		return
	_czas += delta

	match _stan:
		Stan.SPOKOJ:
			_spokoj(delta)
		Stan.SERIA:
			_seria(delta)
		Stan.CIEMNOSC:
			_ciemnosc(delta)


func _spokoj(delta: float) -> void:
	# delikatne, nieregularne drżenie jasności
	var d := sin(_czas * 31.0) * 0.5 + sin(_czas * 13.7 + 1.3) * 0.5
	var cel := 1.0 - drzenie * (0.5 + 0.5 * d)
	_ustaw(lerpf(_wspolczynnik, cel, 1.0 - exp(-20.0 * delta)))

	_timer -= delta
	if _timer <= 0.0:
		_zacznij_serie()


func _zacznij_serie() -> void:
	_stan = Stan.SERIA
	_seria_zostalo = randf_range(seria_min, maxf(seria_max, seria_min))
	_krok = 0.0
	if tryb == Tryb.LAGODNY:
		_seria_zostalo *= 0.5


func _seria(delta: float) -> void:
	_seria_zostalo -= delta
	_krok -= delta

	if _krok <= 0.0:
		_krok = randf_range(krok_min, maxf(krok_max, krok_min))
		var szansa := szansa_zgaszenia
		var dolna := min_jasnosc
		if tryb == Tryb.LAGODNY:
			szansa *= 0.3
			dolna = maxf(min_jasnosc, 0.5)
		elif tryb == Tryb.ZEPSUTA:
			szansa = minf(szansa * 1.5, 0.9)

		if randf() < szansa:
			_ustaw(0.0)
		else:
			_ustaw(randf_range(dolna, 1.0))

	if _seria_zostalo <= 0.0:
		_koniec_serii()


func _koniec_serii() -> void:
	var szansa := szansa_ciemnosci
	if tryb == Tryb.LAGODNY:
		szansa = 0.0
	elif tryb == Tryb.ZEPSUTA:
		szansa = maxf(szansa, 0.8)

	if randf() < szansa:
		_zacznij_ciemnosc(randf_range(ciemnosc_min, maxf(ciemnosc_max, ciemnosc_min)))
	else:
		_wroc_do_spokoju(false)


func _zacznij_ciemnosc(czas: float) -> void:
	_stan = Stan.CIEMNOSC
	_timer = czas
	_krok = randf_range(0.2, 0.8)
	_ustaw(0.0)
	_zagraj_klik()


func _ciemnosc(delta: float) -> void:
	if _wymuszone_wylaczenie:
		_ustaw(0.0)
		return

	_timer -= delta
	_krok -= delta

	# w ZEPSUTEJ lampa czasem na chwilę "łapie" w trakcie ciemności
	if tryb == Tryb.ZEPSUTA and _krok <= 0.0:
		_krok = randf_range(0.3, 1.2)
		if randf() < 0.5:
			_ustaw(randf_range(0.3, 0.9))
			await get_tree().create_timer(randf_range(0.03, 0.1)).timeout
			if _stan == Stan.CIEMNOSC:
				_ustaw(0.0)

	if _timer <= 0.0:
		_wroc_do_spokoju(rozblysk_po_ciemnosci)


func _wroc_do_spokoju(z_rozblyskiem: bool) -> void:
	_stan = Stan.SPOKOJ
	_timer = randf_range(spokoj_min, maxf(spokoj_max, spokoj_min))
	if z_rozblyskiem:
		_ustaw(1.6)
		_zagraj_klik()
		await get_tree().create_timer(0.07).timeout
		if _stan == Stan.SPOKOJ:
			_ustaw(1.0)
	else:
		_ustaw(1.0)


# ---------- Efekt ----------

func _ustaw(wsp: float) -> void:
	_wspolczynnik = wsp
	light_energy = _baza * wsp
	if _mat != null:
		_mat.emission_energy_multiplier = emisja_bazowa * wsp
	if _bzyk != null:
		_bzyk.volume_db = bzyczenie_db if wsp > 0.05 else -60.0
		_bzyk.pitch_scale = clampf(0.9 + 0.2 * wsp, 0.5, 1.4)


func _zagraj_klik() -> void:
	if _klik != null:
		_klik.pitch_scale = randf_range(0.9, 1.1)
		_klik.play()
