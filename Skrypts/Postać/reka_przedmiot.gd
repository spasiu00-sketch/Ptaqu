class_name RekaPrzedmiotow
extends Node3D

## Przedmioty w ręku z paskiem 9 slotów na dole ekranu.
## - Przypisanie: w ekwipunku (Tab) przeciągnij przedmiot na slot paska.
##   Na pasku: PPM = wyczyść slot, przeciągnięcie na inny slot = zamiana miejscami.
## - Klawisze 1-9 / kółko myszy = wyjmij / schowaj przedmiot z danego slotu paska.
## - G = wyrzuć na ziemię to, co masz w ręce (przedmiot z paska albo latarkę).
## Przedmiot da się przypisać tylko, jeśli ma model w ręku (węzeł z przedmiot_wrece.gd).

signal zmieniono_przedmiot(indeks: int)

const GRUPA := "reka_przedmiotow"
const KLAWISZE_SLOTOW := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
const ROZMIAR_PASKA := 9

const COL_TLO := Color(0.030, 0.024, 0.027, 0.82)
const COL_RAMKA := Color(0.17, 0.11, 0.11)
const COL_AKTYWNY_TLO := Color(0.17, 0.030, 0.030, 0.92)
const COL_AKTYWNY_RAMKA := Color(0.88, 0.16, 0.12)
const COL_CEL_TLO := Color(0.115, 0.075, 0.078, 0.92)
const COL_CEL_RAMKA := Color(0.62, 0.10, 0.08)
const COL_TEKST := Color(0.83, 0.79, 0.73)
const COL_TEKST_CICHY := Color(0.52, 0.47, 0.43)

@export var gracz: CharacterBody3D
@export var auto_przypisz_nowe: bool = false   # true = nowy przedmiot z modelem w ręku sam trafia na pierwszy wolny slot i się wyjmuje
@export var czas_zmiany: float = 0.14
@export var opuszczenie: float = 0.35
@export var kolko_myszy: bool = true
@export var klawisz_chowania: Key = KEY_X
@export var klawisz_wyrzutu: Key = KEY_G
@export var pokaz_nazwe: bool = true
@export var pasek_widoczny: bool = true
@export var pasek_tylko_w_ekwipunku: bool = true   # true = pasek widać tylko przy otwartym ekwipunku (Tab)

var _sloty: Array[Node3D] = []
var _obslugi: Array = []
var _poz: Array[Vector3] = []
var _byl_dostepny: Array[bool] = []
var _aktywny: int = -1
var _w_zmianie: bool = false
var _tryb_myszy_poprzedni: Input.MouseMode = Input.MOUSE_MODE_VISIBLE

var _pasek: Array[Item] = []      # co jest przypisane do slotów 1-9 (null = pusty)
var _hb_ostatni: int = -1         # ostatnio wybrany slot paska
var _hb_cel_drop: int = -1        # slot paska pod kursorem podczas przeciągania
var _inv: Node

var _napis: Label
var _tween_napisu: Tween

var _hud: CanvasLayer
var _hb_margines: MarginContainer
var _hb_rzad: HBoxContainer
var _hb_sloty: Array[Dictionary] = []   # {"root", "tlo", "ikona", "nazwa", "numer", "ilosc"}
var _font: Font
var _st_zwykly: StyleBoxFlat
var _st_aktywny: StyleBoxFlat
var _st_cel: StyleBoxFlat


func _ready() -> void:
	add_to_group(GRUPA)
	if gracz == null:
		gracz = _znajdz_gracza()
	if gracz == null:
		push_warning("reka_przedmiotow: nie znaleziono gracza (CharacterBody3D)")

	_inv = get_node_or_null("/root/Inventory")
	if _inv == null:
		push_warning("reka_przedmiotow: brak autoloadu 'Inventory'")

	_pasek.resize(ROZMIAR_PASKA)

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
	_zbuduj_pasek()
	if _inv != null:
		_inv.zmieniono.connect(_po_zmianie_ekwipunku)


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

func _to_samo(a: Item, b: Item) -> bool:
	if a == null or b == null:
		return false
	if a == b:
		return true
	return a.resource_path != "" and a.resource_path == b.resource_path


func _item_obslugi(i: int) -> Item:
	var o = _obslugi[i]
	if o == null:
		return null
	return o.get("item") as Item


# Indeks modelu w ręku (dziecko tego węzła) dla danego Itemu, -1 = brak modelu
func _indeks_dla(item: Item) -> int:
	if item == null:
		return -1
	for i in _sloty.size():
		if _to_samo(_item_obslugi(i), item):
			return i
	return -1


func _item_z_ekwipunku(z: int) -> Item:
	if _inv == null or z < 0 or z >= _inv.sloty.size():
		return null
	var slot = _inv.sloty[z]
	return null if slot == null else slot.item


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


# Który slot paska odpowiada aktualnie trzymanemu przedmiotowi (-1 = żaden)
func _hb_aktywny() -> int:
	if _aktywny < 0:
		return -1
	var item := _item_obslugi(_aktywny)
	if item == null:
		return -1
	if _hb_ostatni >= 0 and _to_samo(_pasek[_hb_ostatni], item):
		return _hb_ostatni
	for h in ROZMIAR_PASKA:
		if _to_samo(_pasek[h], item):
			return h
	return -1


func wyposaz_obsluge(obsluga: Node) -> void:
	var i := _obslugi.find(obsluga)
	if i >= 0 and _dostepny(i):
		_wybierz(i)


# ---------- Wyjmowanie / chowanie ----------

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
	_odswiez_pasek()
	zmieniono_przedmiot.emit(_aktywny)


func _schowaj_natychmiast() -> void:
	if _aktywny < 0:
		return
	_ukryj_slot(_aktywny)
	_aktywny = -1
	_odswiez_pasek()
	zmieniono_przedmiot.emit(-1)


# Wybór slotu paska (klawisze 1-9): ten sam slot drugi raz = schowaj
func _wybierz_pasek(h: int) -> void:
	if h < 0 or h >= ROZMIAR_PASKA:
		return
	var idx := _indeks_dla(_pasek[h])
	if idx < 0 or not _dostepny(idx):
		return
	if idx == _aktywny:
		_hb_ostatni = -1
		_wybierz(-1)
	else:
		_hb_ostatni = h
		_wybierz(idx)


func _przewin(kierunek: int) -> void:
	if _w_zmianie:
		return
	var lista: Array[int] = []
	for h in ROZMIAR_PASKA:
		var idx := _indeks_dla(_pasek[h])
		if idx >= 0 and _dostepny(idx):
			lista.append(h)
	if lista.is_empty():
		return
	var obecny := _hb_aktywny()
	var pozycja := lista.find(obecny)
	var nowy: int
	if pozycja < 0:
		nowy = lista[0] if kierunek > 0 else lista[lista.size() - 1]
	else:
		nowy = lista[posmod(pozycja + kierunek, lista.size())]
	if nowy != obecny:
		_wybierz_pasek(nowy)


# ---------- Wyrzucanie (G) ----------

func _wyrzuc_trzymany() -> void:
	if _w_zmianie or gracz == null or _inv == null:
		return

	var item: Item = null
	if _aktywny >= 0:
		item = _item_obslugi(_aktywny)
	else:
		item = _latarka_w_rece()
	if item == null:
		return

	# usuwamy z ekwipunku tylko wtedy, gdy model faktycznie pojawił się na ziemi
	if item.wyrzuc(gracz):
		_inv.usun_item(item, 1)


# Latarka (poza paskiem) też jest "w ręku", gdy jest odblokowana i widoczna
func _latarka_w_rece() -> Item:
	var latarka = gracz.get("flashlight")
	var reka = gracz.get("held_root")
	if latarka == null or reka == null or not latarka.unlocked or not reka.visible:
		return null
	for slot in _inv.sloty:
		if slot != null and slot.item != null and slot.item.jest_latarka:
			return slot.item
	return null


# ---------- Pętla i wejście ----------

func _po_zmianie_ekwipunku() -> void:
	# przedmiot, którego już nie ma w ekwipunku, znika z paska
	for h in ROZMIAR_PASKA:
		if _pasek[h] != null and not _inv.ma(_pasek[h]):
			_pasek[h] = null
	_odswiez_pasek()


func _auto_przypisz(i: int) -> void:
	var item := _item_obslugi(i)
	if item == null:
		return
	for h in ROZMIAR_PASKA:
		if _to_samo(_pasek[h], item):
			return
	for h in ROZMIAR_PASKA:
		if _pasek[h] == null:
			_pasek[h] = item
			_odswiez_pasek()
			_wybierz_pasek(h)
			return


func _process(_delta: float) -> void:
	if not _w_zmianie:
		for i in _sloty.size():
			var teraz := _dostepny(i)
			var wczesniej: bool = _byl_dostepny[i]
			_byl_dostepny[i] = teraz
			if teraz and not wczesniej and auto_przypisz_nowe:
				_auto_przypisz(i)
			elif not teraz and i == _aktywny:
				_schowaj_natychmiast()

	var chce_widoczna := _aktywny >= 0 or _w_zmianie
	if visible != chce_widoczna:
		visible = chce_widoczna
		if chce_widoczna and gracz != null:
			gracz.set_process(true)

	if _hud != null:
		var pokaz := pasek_widoczny
		if gracz != null:
			if bool(gracz.call("is_dead")):
				pokaz = false
			elif pasek_tylko_w_ekwipunku and not bool(gracz.call("_inventory_open")):
				pokaz = false
		if _hud.visible != pokaz:
			_hud.visible = pokaz
			
			
	_tryb_myszy_poprzedni = Input.mouse_mode


func _unhandled_input(event: InputEvent) -> void:
	if not _moze_sterowac():
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		var idx := KLAWISZE_SLOTOW.find(k)
		if idx >= 0 and idx < ROZMIAR_PASKA:
			_wybierz_pasek(idx)
		elif k == klawisz_chowania:
			_wybierz(-1)
		elif k == klawisz_wyrzutu:
			_wyrzuc_trzymany()
		return

	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if kolko_myszy and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_przewin(-1)
		elif kolko_myszy and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_przewin(1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if _tryb_myszy_poprzedni != Input.MOUSE_MODE_CAPTURED:
				return
			if _aktywny >= 0 and not _w_zmianie:
				var o = _obslugi[_aktywny]
				if o != null and o.has_method("uzyj_glowny"):
					o.call("uzyj_glowny")
					get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _hb_cel_drop != -1:
		_hb_cel_drop = -1
		_odswiez_pasek()


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

	var h := _hb_aktywny()
	var numer := str(h + 1) if h >= 0 else "-"
	_napis.text = "[%s]  %s" % [numer, nazwa]
	_napis.modulate.a = 1.0
	if _tween_napisu != null and _tween_napisu.is_valid():
		_tween_napisu.kill()
	_tween_napisu = create_tween()
	_tween_napisu.tween_interval(1.2)
	_tween_napisu.tween_property(_napis, "modulate:a", 0.0, 0.5)


# ---------- Pasek 9 slotów (HUD) ----------

func _styl(tlo: Color, ramka: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = tlo
	s.border_color = ramka
	s.anti_aliasing = false
	return s


func _zbuduj_pasek() -> void:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(
		["Georgia", "Palatino Linotype", "Times New Roman", "DejaVu Serif", "serif"])
	f.font_weight = 600
	_font = f

	_st_zwykly = _styl(COL_TLO, COL_RAMKA)
	_st_aktywny = _styl(COL_AKTYWNY_TLO, COL_AKTYWNY_RAMKA)
	_st_cel = _styl(COL_CEL_TLO, COL_CEL_RAMKA)

	# layer 4: nad ekwipunkiem (3), żeby dało się upuszczać na pasek przedmioty z ekwipunku
	_hud = CanvasLayer.new()
	_hud.layer = 4
	add_child(_hud)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)

	_hb_margines = MarginContainer.new()
	_hb_margines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hb_margines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hb_margines)

	var kolumna := VBoxContainer.new()
	kolumna.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hb_margines.add_child(kolumna)

	var odstep := Control.new()
	odstep.size_flags_vertical = Control.SIZE_EXPAND_FILL
	odstep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kolumna.add_child(odstep)

	_hb_rzad = HBoxContainer.new()
	_hb_rzad.alignment = BoxContainer.ALIGNMENT_CENTER
	_hb_rzad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kolumna.add_child(_hb_rzad)

	for i in ROZMIAR_PASKA:
		_hb_sloty.append(_zrob_slot_paska(i))

	_uklad_paska()
	get_viewport().size_changed.connect(_uklad_paska)
	_odswiez_pasek()


func _zrob_etykiete(kolor: Color, h_align: HorizontalAlignment, v_align: VerticalAlignment) -> Label:
	var l := Label.new()
	l.horizontal_alignment = h_align
	l.vertical_alignment = v_align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", _font)
	l.add_theme_color_override("font_color", kolor)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	return l


func _zrob_slot_paska(i: int) -> Dictionary:
	var r := Control.new()
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	r.gui_input.connect(_hb_input.bind(i))
	r.mouse_exited.connect(_hb_wyjscie.bind(i))
	r.set_drag_forwarding(_hb_drag.bind(i), _hb_can_drop.bind(i), _hb_drop.bind(i))
	_hb_rzad.add_child(r)

	var tlo := Panel.new()
	tlo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tlo.add_theme_stylebox_override("panel", _st_zwykly)
	r.add_child(tlo)

	var ikona := TextureRect.new()
	ikona.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ikona.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ikona.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(ikona)

	# nazwa tekstem, gdy przedmiot nie ma ikony
	var nazwa := _zrob_etykiete(COL_TEKST, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
	nazwa.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.add_child(nazwa)

	var numer := _zrob_etykiete(COL_TEKST_CICHY, HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP)
	numer.text = str(i + 1)
	r.add_child(numer)

	var ilosc := _zrob_etykiete(COL_TEKST, HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_BOTTOM)
	r.add_child(ilosc)

	return {"root": r, "tlo": tlo, "ikona": ikona, "nazwa": nazwa, "numer": numer, "ilosc": ilosc}


# Rozmiary liczone z wysokości okna (przelicza się przy zmianie rozdzielczości)
func _uklad_paska() -> void:
	if _hb_rzad == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var s := clampi(int(minf(vp.y * 0.075, vp.x * 0.06)), 40, 96)

	_hb_margines.add_theme_constant_override("margin_bottom", int(vp.y * 0.03))
	_hb_rzad.add_theme_constant_override("separation", maxi(int(s * 0.08), 3))

	var ramka := maxi(int(s / 40.0), 1)
	for st in [_st_zwykly, _st_aktywny, _st_cel]:
		st.set_border_width_all(ramka)
		st.set_corner_radius_all(maxi(int(s * 0.04), 2))

	var pad := int(s * 0.14)
	var pad_mały := int(s * 0.06)
	var font_maly := clampi(int(s * 0.2), 10, 22)
	for sl in _hb_sloty:
		(sl["root"] as Control).custom_minimum_size = Vector2(s, s)
		(sl["tlo"] as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		(sl["ikona"] as Control).set_anchors_and_offsets_preset(
				Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, pad)
		(sl["nazwa"] as Label).set_anchors_and_offsets_preset(
				Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, pad_mały)
		(sl["nazwa"] as Label).add_theme_font_size_override("font_size", font_maly)
		for klucz in ["numer", "ilosc"]:
			var l := sl[klucz] as Label
			l.set_anchors_and_offsets_preset(
					Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, pad_mały)
			l.add_theme_font_size_override("font_size", font_maly)


func _odswiez_pasek() -> void:
	if _hb_sloty.is_empty():
		return
	var aktywny := _hb_aktywny()
	for h in ROZMIAR_PASKA:
		var sl: Dictionary = _hb_sloty[h]
		var item: Item = _pasek[h]
		var ikona := sl["ikona"] as TextureRect
		var nazwa := sl["nazwa"] as Label
		var ilosc := sl["ilosc"] as Label

		if item == null:
			ikona.texture = null
			nazwa.text = ""
			ilosc.text = ""
		else:
			ikona.texture = item.ikona
			nazwa.text = item.nazwa if item.ikona == null else ""
			var ile: int = _inv.ile(item) if _inv != null else 1
			ilosc.text = ("x%d" % ile) if ile > 1 else ""

		var st: StyleBoxFlat = _st_zwykly
		if h == _hb_cel_drop:
			st = _st_cel
		elif h == aktywny:
			st = _st_aktywny
		(sl["tlo"] as Panel).add_theme_stylebox_override("panel", st)


func _zrob_podglad_drag(item: Item) -> Control:
	var podglad := Control.new()
	var rozm := 64.0
	if item.ikona != null:
		var tr := TextureRect.new()
		tr.texture = item.ikona
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.size = Vector2(rozm, rozm)
		tr.position = -tr.size * 0.5
		tr.modulate = Color(1, 1, 1, 0.85)
		podglad.add_child(tr)
	else:
		var l := _zrob_etykiete(COL_TEKST, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
		l.text = item.nazwa
		podglad.add_child(l)
	return podglad


# ---------- Pasek: mysz i przeciąganie ----------

func _hb_input(event: InputEvent, h: int) -> void:
	# PPM na slocie (przy otwartym ekwipunku) czyści przypisanie
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT and _pasek[h] != null:
		_pasek[h] = null
		_odswiez_pasek()


func _hb_wyjscie(h: int) -> void:
	if _hb_cel_drop == h:
		_hb_cel_drop = -1
		_odswiez_pasek()


func _hb_drag(_poz_kursora: Vector2, h: int) -> Variant:
	var item := _pasek[h]
	if item == null:
		return null
	(_hb_sloty[h]["root"] as Control).set_drag_preview(_zrob_podglad_drag(item))
	return {"hb": h}


func _hb_can_drop(_poz_kursora: Vector2, dane: Variant, h: int) -> bool:
	var ok := false
	if dane is Dictionary:
		if dane.has("hb"):
			ok = int(dane["hb"]) != h
		elif dane.has("z"):
			# z ekwipunku da się przypisać tylko przedmiot, który ma model w ręku
			ok = _indeks_dla(_item_z_ekwipunku(int(dane["z"]))) >= 0
	if ok and _hb_cel_drop != h:
		_hb_cel_drop = h
		_odswiez_pasek()
	return ok


func _hb_drop(_poz_kursora: Vector2, dane: Variant, h: int) -> void:
	if not (dane is Dictionary):
		return
	if dane.has("hb"):
		var z := int(dane["hb"])
		var tmp: Item = _pasek[z]
		_pasek[z] = _pasek[h]
		_pasek[h] = tmp
	elif dane.has("z"):
		var item := _item_z_ekwipunku(int(dane["z"]))
		if _indeks_dla(item) < 0:
			return
		for i in ROZMIAR_PASKA:   # jeden przedmiot = jeden slot
			if _to_samo(_pasek[i], item):
				_pasek[i] = null
		_pasek[h] = item
	_hb_cel_drop = -1
	_odswiez_pasek()
