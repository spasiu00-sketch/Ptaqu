class_name InventoryUI
extends CanvasLayer
# Ekwipunek budowany w kodzie. Tworzy go player (character_body_3d.gd), otwierany klawiszem Tab.
#
# - sama siatka ikon (bez napisów); nazwa i opis pojawiają się w podpowiedzi po najechaniu myszką
# - rozmiar slotów, odstępy i czcionki liczone z rozmiaru okna (przelicza się przy zmianie rozdzielczości)
# - LPM = zaznacz, dwuklik lub PPM = użyj, ŚPM = obejrzyj model 3D, przyciski na dole: OBEJRZYJ / UŻYJ / WYRZUĆ
# - przedmiot bez ikony dostaje wygenerowany znak zastępczy (pierścień)

const PodgladScript := preload("res://Skrypts/Ekwipunek/podglad_przedmiot.gd")

const KOLUMNY := 5

# ---------- Paleta (ciemna, wypłowiała, krew i rdza) ----------
const COL_DIM := Color(0.0, 0.0, 0.0, 0.74)
const COL_PANEL := Color(0.030, 0.024, 0.027, 0.97)
const COL_PANEL_BORDER := Color(0.30, 0.04, 0.04)
const COL_PANEL_SHADOW := Color(0.40, 0.0, 0.0, 0.35)
const COL_SLOT := Color(0.078, 0.062, 0.066)
const COL_SLOT_BORDER := Color(0.17, 0.11, 0.11)
const COL_SLOT_HOVER := Color(0.115, 0.075, 0.078)
const COL_SLOT_HOVER_BORDER := Color(0.62, 0.10, 0.08)
const COL_SLOT_SEL := Color(0.17, 0.030, 0.030)
const COL_SLOT_SEL_BORDER := Color(0.88, 0.16, 0.12)
const COL_EMPTY := Color(0.044, 0.036, 0.040)
const COL_EMPTY_BORDER := Color(0.10, 0.07, 0.07)
const COL_TEXT := Color(0.83, 0.79, 0.73)
const COL_TEXT_DIM := Color(0.52, 0.47, 0.43)
const COL_BLOOD := Color(0.82, 0.14, 0.11)

var gracz: Node
var otwarty: bool = false

var _inv: Node
var _root: Control
var _panel: PanelContainer
var _box: VBoxContainer
var _siatka: GridContainer
var _linia: ColorRect
var _sloty: Array[Dictionary] = []   # {"root": Control, "tlo": Panel, "ikona": TextureRect, "ilosc": Label}
var _btn_obejrzyj: Button
var _btn_uzyj: Button
var _btn_wyrzuc: Button
var _podglad: CanvasLayer

var _tip: PanelContainer
var _tip_box: VBoxContainer
var _tip_nazwa: Label
var _tip_linia: ColorRect
var _tip_opis: Label
var _tip_podpowiedz: Label

var _wybrany: int = -1
var _hover: int = -1
var _przeciaga: bool = false   # trwa przeciąganie przedmiotu
var _drag_z: int = -1           # slot, z którego przeciągamy
var _drop_cel: int = -1         # slot pod kursorem w trakcie przeciągania
var _rozmiar_slotu: int = 80

var _font: Font
var _placeholder: Texture2D

var _st_panel: StyleBoxFlat
var _st_zwykly: StyleBoxFlat
var _st_hover: StyleBoxFlat
var _st_wybrany: StyleBoxFlat
var _st_pusty: StyleBoxFlat
var _st_tip: StyleBoxFlat
var _st_btn: StyleBoxFlat
var _st_btn_hover: StyleBoxFlat
var _st_btn_pressed: StyleBoxFlat
var _st_btn_off: StyleBoxFlat


func _ready() -> void:
	layer = 3   # nad HUD (2), pod podglądem (4) i jumpscare (100+)
	visible = false
	set_process(false)
	_inv = get_node_or_null("/root/Inventory")
	if _inv == null:
		push_warning("InventoryUI: brak autoloadu 'Inventory' (Project Settings -> Globals -> Autoload)")
		return
	_font = _zrob_font()
	_placeholder = _zrob_placeholder()
	_zbuduj()
	_podglad = PodgladScript.new()
	add_child(_podglad)
	_inv.zmieniono.connect(_odswiez)
	get_viewport().size_changed.connect(_uklad)


func otworz() -> void:
	if _inv == null:
		return
	otwarty = true
	visible = true
	_wybrany = -1
	_hover = -1
	_tip.visible = false
	_uklad()
	_odswiez()
	set_process(true)


func zamknij() -> void:
	if _podglad != null:
		_podglad.zamknij()
	otwarty = false
	visible = false
	_hover = -1
	if _tip != null:
		_tip.visible = false
	set_process(false)


# ---------- Budowa ----------

func _zbuduj() -> void:
	_zrob_style()

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # klik w tło nie przechodzi do gry
	add_child(_root)

	var tlo := ColorRect.new()
	tlo.color = COL_DIM
	tlo.set_anchors_preset(Control.PRESET_FULL_RECT)
	tlo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(tlo)

	var centrum := CenterContainer.new()
	centrum.set_anchors_preset(Control.PRESET_FULL_RECT)
	centrum.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(centrum)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _st_panel)
	centrum.add_child(_panel)

	_box = VBoxContainer.new()
	_panel.add_child(_box)

	_siatka = GridContainer.new()
	_siatka.columns = KOLUMNY
	_box.add_child(_siatka)

	_linia = ColorRect.new()
	_linia.color = Color(COL_PANEL_BORDER, 0.8)
	_linia.custom_minimum_size = Vector2(0, 2)
	_box.add_child(_linia)

	var akcje := HBoxContainer.new()
	akcje.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(akcje)
	_btn_obejrzyj = _zrob_przycisk("OBEJRZYJ", _obejrzyj)
	akcje.add_child(_btn_obejrzyj)
	_btn_uzyj = _zrob_przycisk("UŻYJ", _uzyj)
	akcje.add_child(_btn_uzyj)
	_btn_wyrzuc = _zrob_przycisk("WYRZUĆ", _wyrzuc)
	akcje.add_child(_btn_wyrzuc)

	for i in _inv.ROZMIAR:
		_sloty.append(_zrob_slot(i))

	_zbuduj_tip()   # ostatnie dziecko = rysowane na wierzchu
	_uklad()


func _zrob_style() -> void:
	_st_panel = _styl(COL_PANEL, COL_PANEL_BORDER)
	_st_panel.shadow_color = COL_PANEL_SHADOW
	_st_panel.shadow_size = 22
	_st_zwykly = _styl(COL_SLOT, COL_SLOT_BORDER)
	_st_hover = _styl(COL_SLOT_HOVER, COL_SLOT_HOVER_BORDER)
	_st_wybrany = _styl(COL_SLOT_SEL, COL_SLOT_SEL_BORDER)
	_st_pusty = _styl(COL_EMPTY, COL_EMPTY_BORDER)
	_st_tip = _styl(Color(0.025, 0.020, 0.022, 0.98), Color(0.50, 0.08, 0.06))
	_st_btn = _styl(Color(0.10, 0.025, 0.025), Color(0.38, 0.06, 0.05))
	_st_btn_hover = _styl(Color(0.19, 0.035, 0.030), Color(0.85, 0.15, 0.11))
	_st_btn_pressed = _styl(Color(0.06, 0.012, 0.012), Color(0.55, 0.09, 0.07))
	_st_btn_off = _styl(Color(0.05, 0.04, 0.042), Color(0.12, 0.09, 0.09))


func _styl(tlo: Color, ramka: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = tlo
	s.border_color = ramka
	s.anti_aliasing = false
	return s


func _zrob_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(
		["Georgia", "Palatino Linotype", "Times New Roman", "DejaVu Serif", "serif"])
	f.font_weight = 600
	return f


# Znak zastępczy dla przedmiotów bez ikony: pierścień z kropką w środku
func _zrob_placeholder() -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var srodek := Vector2(31.5, 31.5)
	var kolor := Color(0.55, 0.10, 0.08, 0.9)
	for y in 64:
		for x in 64:
			var d := Vector2(x, y).distance_to(srodek)
			if (d >= 17.0 and d <= 22.0) or d <= 4.5:
				img.set_pixel(x, y, kolor)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


func _zrob_przycisk(tekst: String, akcja: Callable) -> Button:
	var b := Button.new()
	b.text = tekst
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _font)
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 0.80))
	b.add_theme_color_override("font_pressed_color", COL_BLOOD)
	b.add_theme_color_override("font_disabled_color", Color(COL_TEXT_DIM, 0.5))
	b.add_theme_stylebox_override("normal", _st_btn)
	b.add_theme_stylebox_override("hover", _st_btn_hover)
	b.add_theme_stylebox_override("pressed", _st_btn_pressed)
	b.add_theme_stylebox_override("disabled", _st_btn_off)
	b.pressed.connect(akcja)
	return b


func _zrob_slot(i: int) -> Dictionary:
	var r := Control.new()
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	r.mouse_entered.connect(_on_slot_enter.bind(i))
	r.mouse_exited.connect(_on_slot_exit.bind(i))
	r.gui_input.connect(_on_slot_input.bind(i))
	r.set_drag_forwarding(_drag_start.bind(i), _can_drop.bind(i), _drop.bind(i))
	_siatka.add_child(r)

	var tlo := Panel.new()
	tlo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tlo.add_theme_stylebox_override("panel", _st_pusty)
	r.add_child(tlo)

	var ikona := TextureRect.new()
	ikona.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ikona.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ikona.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(ikona)

	# mała liczba przy stosach (tylko gdy > 1)
	var ilosc := Label.new()
	ilosc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ilosc.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	ilosc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ilosc.add_theme_font_override("font", _font)
	ilosc.add_theme_color_override("font_color", COL_TEXT)
	ilosc.add_theme_color_override("font_outline_color", Color.BLACK)
	ilosc.add_theme_constant_override("outline_size", 4)
	r.add_child(ilosc)

	return {"root": r, "tlo": tlo, "ikona": ikona, "ilosc": ilosc}


func _zbuduj_tip() -> void:
	_tip = PanelContainer.new()
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	_tip.add_theme_stylebox_override("panel", _st_tip)
	_root.add_child(_tip)

	_tip_box = VBoxContainer.new()
	_tip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_child(_tip_box)

	_tip_nazwa = _zrob_etykiete(COL_BLOOD)
	_tip_box.add_child(_tip_nazwa)

	_tip_linia = ColorRect.new()
	_tip_linia.color = Color(0.45, 0.07, 0.05, 0.8)
	_tip_linia.custom_minimum_size = Vector2(0, 1)
	_tip_linia.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_box.add_child(_tip_linia)

	_tip_opis = _zrob_etykiete(COL_TEXT)
	_tip_box.add_child(_tip_opis)

	_tip_podpowiedz = _zrob_etykiete(COL_TEXT_DIM)
	_tip_podpowiedz.text = "PPM — użyj"
	_tip_box.add_child(_tip_podpowiedz)


func _zrob_etykiete(kolor: Color) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", _font)
	l.add_theme_color_override("font_color", kolor)
	return l


# ---------- Skalowanie do rozdzielczości ----------

# Wszystkie rozmiary wynikają z rozmiaru slotu, a ten z mniejszego wymiaru okna
func _uklad() -> void:
	if _root == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var s := clampi(int(minf(vp.y * 0.105, vp.x * 0.13)), 44, 132)
	_rozmiar_slotu = s

	var odstep := maxi(int(s * 0.07), 3)
	var pad_ikony := int(s * 0.12)
	var ramka := maxi(int(s / 48.0), 1)
	var rog := maxi(int(s * 0.04), 2)

	for st in [_st_panel, _st_zwykly, _st_hover, _st_wybrany, _st_pusty, _st_tip,
			_st_btn, _st_btn_hover, _st_btn_pressed, _st_btn_off]:
		st.set_border_width_all(ramka)
		st.set_corner_radius_all(rog)
	_st_panel.set_content_margin_all(int(s * 0.24))
	_st_panel.shadow_size = int(s * 0.28)
	_st_tip.set_content_margin_all(int(s * 0.14))
	for st in [_st_btn, _st_btn_hover, _st_btn_pressed, _st_btn_off]:
		st.content_margin_left = int(s * 0.22)
		st.content_margin_right = int(s * 0.22)
		st.content_margin_top = int(s * 0.09)
		st.content_margin_bottom = int(s * 0.09)

	_box.add_theme_constant_override("separation", int(s * 0.2))
	_siatka.add_theme_constant_override("h_separation", odstep)
	_siatka.add_theme_constant_override("v_separation", odstep)
	_linia.custom_minimum_size.y = maxi(ramka, 2)
	(_btn_uzyj.get_parent() as HBoxContainer).add_theme_constant_override("separation", int(s * 0.2))

	var font_ilosc := clampi(int(s * 0.22), 11, 26)
	for sl in _sloty:
		var r := sl["root"] as Control
		r.custom_minimum_size = Vector2(s, s)
		(sl["tlo"] as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		(sl["ikona"] as Control).set_anchors_and_offsets_preset(
				Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, pad_ikony)
		var il := sl["ilosc"] as Label
		il.set_anchors_and_offsets_preset(
				Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, int(s * 0.07))
		il.add_theme_font_size_override("font_size", font_ilosc)

	var font_btn := clampi(int(s * 0.26), 13, 30)
	for b in [_btn_obejrzyj, _btn_uzyj, _btn_wyrzuc]:
		b.add_theme_font_size_override("font_size", font_btn)

	# podpowiedź o stałej szerokości, zawijanie tekstu
	var szer := clampi(int(s * 3.0), 200, 460)
	_tip_nazwa.custom_minimum_size.x = szer
	_tip_opis.custom_minimum_size.x = szer
	_tip_podpowiedz.custom_minimum_size.x = szer
	_tip_nazwa.add_theme_font_size_override("font_size", clampi(int(s * 0.27), 16, 32))
	_tip_opis.add_theme_font_size_override("font_size", clampi(int(s * 0.21), 13, 26))
	_tip_podpowiedz.add_theme_font_size_override("font_size", clampi(int(s * 0.17), 11, 20))
	_tip_box.add_theme_constant_override("separation", int(s * 0.07))

	_panel.reset_size()
	if _tip.visible:
		_tip.reset_size()


# ---------- Odświeżanie ----------

func _odswiez() -> void:
	if _inv == null or _sloty.is_empty():
		return
	if _wybrany >= 0 and _inv.sloty[_wybrany] == null:
		_wybrany = -1

	for i in _sloty.size():
		var slot = _inv.sloty[i]
		var ikona := _sloty[i]["ikona"] as TextureRect
		var ilosc := _sloty[i]["ilosc"] as Label
		if slot == null:
			ikona.texture = null
			ilosc.text = ""
		else:
			var item: Item = slot.item
			ikona.texture = item.ikona if item.ikona != null else _placeholder
			ilosc.text = ("x%d" % slot.ilosc) if slot.ilosc > 1 else ""
		ikona.modulate.a = 0.3 if (_przeciaga and i == _drag_z) else 1.0
		_styl_slotu(i)

	var wybrany_slot = null if _wybrany < 0 else _inv.sloty[_wybrany]
	if wybrany_slot == null:
		_btn_obejrzyj.disabled = true
		_btn_uzyj.disabled = true
		_btn_wyrzuc.disabled = true
	else:
		var it: Item = wybrany_slot.item
		_btn_obejrzyj.disabled = false
		_btn_uzyj.disabled = not _mozna_uzyc(it)
		_btn_wyrzuc.disabled = false

	_pokaz_tip()


func _styl_slotu(i: int) -> void:
	var st: StyleBoxFlat
	if _przeciaga and i == _drop_cel:
		st = _st_hover
	elif i == _wybrany:
		st = _st_wybrany
	elif _inv.sloty[i] == null:
		st = _st_pusty
	elif i == _hover:
		st = _st_hover
	else:
		st = _st_zwykly
	(_sloty[i]["tlo"] as Panel).add_theme_stylebox_override("panel", st)


# ---------- Mysz ----------

func _on_slot_enter(i: int) -> void:
	_hover = i
	_styl_slotu(i)
	_pokaz_tip()


func _on_slot_exit(i: int) -> void:
	if _hover != i:
		return
	_hover = -1
	_styl_slotu(i)
	_tip.visible = false


func _on_slot_input(event: InputEvent, i: int) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_wybierz(i)
		if event.double_click:
			_uzyj()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_wybierz(i)
		_uzyj()
	elif event.button_index == MOUSE_BUTTON_MIDDLE:
		_wybierz(i)
		_obejrzyj()


func _wybierz(i: int) -> void:
	var poprzedni := _wybrany
	_wybrany = i if _inv.sloty[i] != null else -1
	if poprzedni >= 0 and poprzedni != _wybrany:
		_styl_slotu(poprzedni)
	_odswiez()


# ---------- Podpowiedź ----------

func _pokaz_tip() -> void:
	if not otwarty or _przeciaga or _hover < 0 or _hover >= _sloty.size():
		_tip.visible = false
		return
	var slot = _inv.sloty[_hover]
	if slot == null:
		_tip.visible = false
		return

	var it: Item = slot.item
	var ma_opis := it.opis.strip_edges() != ""
	_tip_nazwa.text = it.nazwa
	_tip_opis.text = it.opis
	_tip_opis.visible = ma_opis
	_tip_linia.visible = ma_opis
	_tip_podpowiedz.visible = _mozna_uzyc(it)
	_tip.reset_size()
	_tip.visible = true
	_ustaw_pozycje_tip()


# Podpowiedź idzie za kursorem i nie wychodzi poza ekran
func _ustaw_pozycje_tip() -> void:
	var vp := get_viewport().get_visible_rect().size
	var mysz := get_viewport().get_mouse_position()
	var rozm := _tip.get_combined_minimum_size()
	var off := float(_rozmiar_slotu) * 0.3
	var poz := mysz + Vector2(off, off)
	if poz.x + rozm.x > vp.x:
		poz.x = mysz.x - rozm.x - off * 0.5
	if poz.y + rozm.y > vp.y:
		poz.y = mysz.y - rozm.y - off * 0.5
	poz.x = clampf(poz.x, 0.0, maxf(vp.x - rozm.x, 0.0))
	poz.y = clampf(poz.y, 0.0, maxf(vp.y - rozm.y, 0.0))
	_tip.position = poz


func _process(_delta: float) -> void:
	if _tip.visible:
		_ustaw_pozycje_tip()
	# zaznaczony slot lekko pulsuje (martwe, wolne "oddychanie" ramki)
	if _wybrany >= 0:
		var p := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 2.2)
		_st_wybrany.border_color = COL_SLOT_SEL_BORDER.darkened(0.4 * p)


# ---------- Akcje ----------

# Bateria = przedmiot ładujący latarkę albo ten rozpoznany przez samą latarkę
# (Battery Item / Battery Name), żeby UI i latarka zawsze zgadzały się co do tego, co jest baterią.
func _jest_bateria(item: Item, latarka: Node) -> bool:
	if item.laduje_baterie > 0.0:
		return true
	return latarka != null and bool(latarka.call("jest_bateria", item))


func _latarka() -> Node:
	return gracz.get("flashlight") if gracz != null else null


func _mozna_uzyc(item: Item) -> bool:
	var latarka := _latarka()
	if _jest_bateria(item, latarka):
		return latarka != null and latarka.unlocked and not latarka.is_busy
	return item.uzywalny


# Otwiera podgląd 3D zaznaczonego przedmiotu (obracanie myszką na środku ekranu)
func _obejrzyj() -> void:
	if _wybrany < 0:
		return
	var slot = _inv.sloty[_wybrany]
	if slot == null:
		return
	_tip.visible = false
	if not _podglad.pokaz(slot.item):
		print("Nie można obejrzeć '", slot.item.nazwa, "' (brak modelu, szczegóły w ostrzeżeniach)")


func _uzyj() -> void:
	if _wybrany < 0:
		return
	var slot = _inv.sloty[_wybrany]
	if slot == null:
		return
	var item: Item = slot.item
	var latarka := _latarka()

	# bateria: zamykamy ekwipunek i odpalamy to samo, co przytrzymanie F (animacja wymiany).
	# Baterię zabiera sama latarka (Flashlight.probuj_przeladowac), więc tu niczego nie usuwamy.
	if _jest_bateria(item, latarka):
		if latarka == null or not latarka.unlocked or latarka.is_busy:
			return
		if gracz != null and gracz.has_method("_toggle_inventory"):
			gracz.call("_toggle_inventory")   # zamyka okno i wraca do sterowania myszką
		else:
			zamknij()
		latarka.call_deferred("probuj_przeladowac")
		return

	if item.uzyj(gracz):
		_inv.usun(_wybrany, 1)


func _wyrzuc() -> void:
	if _wybrany < 0:
		return
	var slot = _inv.sloty[_wybrany]
	if slot == null:
		return
	var item: Item = slot.item
	# usuwamy z ekwipunku tylko wtedy, gdy model faktycznie pojawił się na ziemi
	if item.wyrzuc(gracz as Node3D):
		print("Wyrzucono: ", item.nazwa)
		_inv.usun(_wybrany, 1)
	else:
		print("Nie udało się wyrzucić '", item.nazwa, "' (szczegóły w ostrzeżeniach powyżej)")


# ---------- Przeciąganie: przestawianie i układanie przedmiotów ----------

func _drag_start(_poz: Vector2, i: int) -> Variant:
	if _inv == null:
		return null
	var slot = _inv.sloty[i]
	if slot == null:
		return null
	var item: Item = slot.item

	var rozm := float(_rozmiar_slotu) * 0.9
	var podglad := Control.new()
	var tr := TextureRect.new()
	tr.texture = item.ikona if item.ikona != null else _placeholder
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.size = Vector2(rozm, rozm)
	tr.position = -tr.size * 0.5   # ikona wycentrowana na kursorze
	tr.modulate = Color(1, 1, 1, 0.85)
	podglad.add_child(tr)
	(_sloty[i]["root"] as Control).set_drag_preview(podglad)

	_przeciaga = true
	_drag_z = i
	_drop_cel = -1
	_tip.visible = false
	_wybrany = i
	_odswiez()
	return {"z": i}


func _can_drop(_poz: Vector2, dane: Variant, i: int) -> bool:
	if not (dane is Dictionary and dane.has("z")):
		return false
	if _drop_cel != i:
		var stary := _drop_cel
		_drop_cel = i
		if stary >= 0:
			_styl_slotu(stary)
		_styl_slotu(i)
	return int(dane["z"]) != i


func _drop(_poz: Vector2, dane: Variant, i: int) -> void:
	if not (dane is Dictionary and dane.has("z")):
		return
	_inv.przenies(int(dane["z"]), i)   # pusty slot = przeniesienie, ten sam przedmiot = scalenie, inny = zamiana
	_wybrany = i if _inv.sloty[i] != null else -1
	_odswiez()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_przeciaga = false
		_drag_z = -1
		_drop_cel = -1
		if _inv != null and not _sloty.is_empty():
			_odswiez()
