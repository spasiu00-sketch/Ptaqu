extends Node3D
# Ręka gracza: trzyma wiele przedmiotów (latarka, aparat, łyżka...), w ręku widać jeden.
# Wisi na węźle "Reka" (dziecko Cofanie). Każde dziecko typu Node3D to jeden SLOT.
# Slot jest "obsługiwany" przez pierwszy węzeł (sam slot albo jego potomek), który ma metodę
# czy_dostepny(): Flashlight (spot_light_3d.gd) albo przedmiot_w_rece.gd.
#
# Interfejs przedmiotu (wszystko oprócz czy_dostepny / equip / unequip jest opcjonalne):
#   czy_dostepny() -> bool     czy gracz w ogóle ma ten przedmiot
#   equip() / unequip()        wzięty do ręki / schowany
#   mozna_schowac() -> bool    false = np. trwa animacja przeładowania
#   uzyj_glowny()              LPM
#   nazwa_przedmiotu (String)  nazwa pokazywana po wyjęciu

signal zmieniono_przedmiot(indeks: int)   # -1 = pusta ręka

const GRUPA := "reka_przedmiotow"
const KLAWISZE_SLOTOW := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]

@export var gracz: CharacterBody3D                  # puste = szuka w górę drzewa
@export var wyposaz_nowy_automatycznie: bool = true # podniesiony przedmiot od razu ląduje w ręku
@export var czas_zmiany: float = 0.14               # czas opuszczania / podnoszenia (s)
@export var opuszczenie: float = 0.35               # o ile metrów w dół chowa się przedmiot
@export var kolko_myszy: bool = true
@export var klawisz_chowania: Key = KEY_X
@export var pokaz_nazwe: bool = true

var _sloty: Array[Node3D] = []
var _obslugi: Array = []            # węzeł obsługujący slot albo null
var _poz: Array[Vector3] = []       # pozycja spoczynkowa slotu
var _byl_dostepny: Array[bool] = []
var _aktywny: int = -1
var _w_zmianie: bool = false
var _tryb_myszy_poprzedni: Input.MouseMode = Input.MOUSE_MODE_VISIBLE

var _napis: Label
var _tween_napisu: Tween


func _ready() -> void:
	add_to_group(GRUPA)
	if gracz == null:
		gracz = _znajdz_gracza()
	if gracz == null:
		push_warning("reka_przedmiotow: nie znaleziono gracza (CharacterBody3D)")

	for dziecko in get_children():
		if not (dziecko is Node3D):
			continue
		var obsluga := _znajdz_obsluge(dziecko)
		if obsluga == null:
			push_warning("reka_przedmiotow: slot '%s' nie ma przedmiotu z metodą czy_dostepny() (nie da się go wyjąć)" % dziecko.name)
		_sloty.append(dziecko)
		_obslugi.append(obsluga)
		_poz.append(dziecko.position)
		_byl_dostepny.append(false)
		dziecko.visible = false
		if obsluga != null and obsluga.has_method("unequip"):
			obsluga.call("unequip")

	visible = false
	_zbuduj_napis()


func _znajdz_gracza() -> CharacterBody3D:
	var n := get_parent()
	while n != null:
		if n is CharacterBody3D:
			return n as CharacterBody3D
		n = n.get_parent()
	return null


func _znajdz_obsluge(wezel: Node) -> Node:
	if wezel.has_method("czy_dostepny"):
		return wezel
	for dziecko in wezel.get_children():
		var znaleziony := _znajdz_obsluge(dziecko)
		if znaleziony != null:
			return znaleziony
	return null


# ---------- Pomocnicze ----------

func _dostepny(i: int) -> bool:
	var o = _obslugi[i]
	return o != null and bool(o.call("czy_dostepny"))


func _moze_schowac(i: int) -> bool:
	var o = _obslugi[i]
	return o == null or not o.has_method("mozna_schowac") or bool(o.call("mozna_schowac"))


func _moze_sterowac() -> bool:
	if gracz == null:
		return false
	if gracz.call("is_dead"):
		return false
	if gracz.call("_inventory_open"):
		return false
	if gracz.get("kontrola_zablokowana"):
		return false
	return true


# Wołane przez przedmiot, który sam chce trafić do ręki (np. latarka przy przeładowaniu z ekwipunku)
func wyposaz_obsluge(obsluga: Node) -> void:
	var i := _obslugi.find(obsluga)
	if i >= 0 and _dostepny(i):
		_wybierz(i)


# ---------- Zmiana przedmiotu ----------

func _ukryj_slot(i: int) -> void:
	var o = _obslugi[i]
	if o != null and o.has_method("unequip"):
		o.call("unequip")
	_sloty[i].visible = false
	_sloty[i].position = _poz[i]


func _pokaz_slot(i: int) -> void:
	_sloty[i].position = _poz[i] + Vector3(0.0, -opuszczenie, 0.0)
	_sloty[i].visible = true
	var o = _obslugi[i]
	if o != null and o.has_method("equip"):
		o.call("equip")


func _animuj(wezel: Node3D, cel: Vector3) -> void:
	if czas_zmiany <= 0.0:
		wezel.position = cel
		return
	var tw := create_tween()
	tw.tween_property(wezel, "position", cel, czas_zmiany).set_trans(Tween.TRANS_SINE)
	await tw.finished


# indeks -1 = schowaj wszystko
func _wybierz(indeks: int) -> void:
	if _w_zmianie or indeks == _aktywny:
		return
	if indeks >= _sloty.size():
		return
	if _aktywny >= 0 and not _moze_schowac(_aktywny):
		return

	_w_zmianie = true

	if _aktywny >= 0:
		await _animuj(_sloty[_aktywny], _poz[_aktywny] + Vector3(0.0, -opuszczenie, 0.0))
		_ukryj_slot(_aktywny)
		_aktywny = -1

	if indeks >= 0 and _dostepny(indeks):
		_pokaz_slot(indeks)
		_aktywny = indeks
		await _animuj(_sloty[indeks], _poz[indeks])
		_pokaz_napis(indeks)

	_w_zmianie = false
	zmieniono_przedmiot.emit(_aktywny)


# Przedmiot zniknął (np. wyrzucony z ekwipunku): chowamy go bez animacji
func _schowaj_natychmiast() -> void:
	if _aktywny < 0:
		return
	_ukryj_slot(_aktywny)
	_aktywny = -1
	zmieniono_przedmiot.emit(-1)


func _przewin(kierunek: int) -> void:
	if _w_zmianie:
		return
	var lista: Array[int] = []
	for i in _sloty.size():
		if _dostepny(i):
			lista.append(i)
	if lista.is_empty():
		return
	var pozycja := lista.find(_aktywny)
	var nowy: int
	if pozycja < 0:
		nowy = lista[0] if kierunek > 0 else lista[lista.size() - 1]
	else:
		nowy = lista[posmod(pozycja + kierunek, lista.size())]
	if nowy != _aktywny:
		_wybierz(nowy)


# ---------- Pętla ----------

func _process(_delta: float) -> void:
	if not _w_zmianie:
		for i in _sloty.size():
			var teraz := _dostepny(i)
			var wczesniej: bool = _byl_dostepny[i]
			_byl_dostepny[i] = teraz
			if teraz and not wczesniej and wyposaz_nowy_automatycznie and not _w_zmianie:
				_wybierz(i)
			elif not teraz and i == _aktywny:
				_schowaj_natychmiast()

	# Ręka sama decyduje o swojej widoczności (gracz ukrywał ją do podniesienia latarki)
	var chce_widoczna := _aktywny >= 0 or _w_zmianie
	if visible != chce_widoczna:
		visible = chce_widoczna
		if chce_widoczna and gracz != null:
			gracz.set_process(true)   # gracz kołysze ręką tylko w swoim _process

	_tryb_myszy_poprzedni = Input.mouse_mode


# ---------- Wejście ----------

func _unhandled_input(event: InputEvent) -> void:
	if not _moze_sterowac():
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		var idx := KLAWISZE_SLOTOW.find(k)
		if idx >= 0 and idx < _sloty.size():
			if _dostepny(idx):
				_wybierz(-1 if idx == _aktywny else idx)
		elif k == klawisz_chowania:
			_wybierz(-1)
		return

	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if kolko_myszy and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_przewin(-1)
		elif kolko_myszy and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_przewin(1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			# pierwsze kliknięcie po powrocie do gry tylko przechwytuje mysz
			if _tryb_myszy_poprzedni != Input.MOUSE_MODE_CAPTURED:
				return
			if _aktywny >= 0 and not _w_zmianie:
				var o = _obslugi[_aktywny]
				if o != null and o.has_method("uzyj_glowny"):
					o.call("uzyj_glowny")
					get_viewport().set_input_as_handled()


# ---------- Napis z nazwą przedmiotu ----------

func _zbuduj_napis() -> void:
	var warstwa := CanvasLayer.new()
	warstwa.layer = 2
	add_child(warstwa)

	_napis = Label.new()
	_napis.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_napis.offset_top = -200.0
	_napis.offset_bottom = -160.0
	_napis.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_napis.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_napis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_napis.add_theme_font_size_override("font_size", 22)
	_napis.add_theme_color_override("font_outline_color", Color.BLACK)
	_napis.add_theme_constant_override("outline_size", 6)
	_napis.modulate.a = 0.0
	warstwa.add_child(_napis)


func _pokaz_napis(i: int) -> void:
	if not pokaz_nazwe or _napis == null:
		return
	var nazwa: String = _sloty[i].name
	var o = _obslugi[i]
	if o != null:
		var wlasna = o.get("nazwa_przedmiotu")
		if wlasna != null and str(wlasna) != "":
			nazwa = str(wlasna)

	_napis.text = "[%d]  %s" % [i + 1, nazwa]
	_napis.modulate.a = 1.0
	if _tween_napisu != null and _tween_napisu.is_valid():
		_tween_napisu.kill()
	_tween_napisu = create_tween()
	_tween_napisu.tween_interval(1.2)
	_tween_napisu.tween_property(_napis, "modulate:a", 0.0, 0.5)
