extends CanvasLayer
# Menu pauzy pod Esc: KONTYNUUJ / OPCJE / ZAKOŃCZ GRĘ. Cała gra jest zapauzowana.
# Użycie: w scenie gry (start_game.tscn) dodaj zwykły Node o nazwie "Pauza"
# i przypisz ten skrypt. Gracz jest szukany automatycznie (pole 'Gracz' opcjonalne).
#
# Esc nie otwiera pauzy, gdy: jest otwarty ekwipunek (Esc go zamyka), gracz nie żyje,
# trwa intro. W opcjach Esc wraca do menu pauzy.

@export var gracz: CharacterBody3D
@export var font: Font                       # ta sama czcionka co w intro (Monocraft.ttf)
@export var tytul: String = "PAUZA"
@export var rozmiar_czcionki: int = 32
@export var dzwiek_klik: AudioStream
@export var glosnosc_klik_db: float = -6.0

const COL_DIM := Color(0.0, 0.0, 0.0, 0.72)
const COL_PANEL := Color(0.030, 0.024, 0.027, 0.97)
const COL_BORDER := Color(0.30, 0.04, 0.04)
const COL_TEXT := Color(0.83, 0.79, 0.73)
const COL_BLOOD := Color(0.82, 0.14, 0.11)
const GRUPA_INTRO := "intro_aktywne"

var _f: Font
var _root: Control
var _glowne: VBoxContainer
var _opcje: VBoxContainer
var _btn_wznow: Button
var _btn_wstecz: Button
var _lbl_glos: Label
var _btn_pelny: Button
var _sfx: AudioStreamPlayer

var _st_panel: StyleBoxFlat
var _st_btn: StyleBoxFlat
var _st_btn_hover: StyleBoxFlat
var _st_btn_press: StyleBoxFlat

var _otwarta: bool = false
var _w_opcjach: bool = false
var _inv_otwarty: bool = false   # stan ekwipunku z poprzedniej klatki (niezależny od kolejności _input)
var _volume: int = 8


func _ready() -> void:
	layer = 80   # nad HUD i ekwipunkiem, pod ekranem śmierci (90) i jumpscare (100+)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_f = font if font != null else _font_zastepczy()
	_zbuduj()
	_znajdz_gracza.call_deferred()


func _znajdz_gracza() -> void:
	if gracz != null:
		return
	var znalezione := get_tree().root.find_children("*", "CharacterBody3D", true, false)
	if not znalezione.is_empty():
		gracz = znalezione[0] as CharacterBody3D


func _font_zastepczy() -> Font:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(
		["Monocraft", "Minecraft", "Minecraftia", "Consolas", "DejaVu Sans Mono", "monospace"])
	sf.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	sf.hinting = TextServer.HINTING_NONE
	sf.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return sf


# ---------- Budowa ----------

func _styl(tlo: Color, ramka: Color, margines: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = tlo
	s.border_color = ramka
	s.set_border_width_all(2)
	s.set_corner_radius_all(0)
	s.anti_aliasing = false
	s.set_content_margin_all(margines)
	return s


func _etykieta(txt: String, rozmiar: int, kolor: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	l.add_theme_font_override("font", _f)
	l.add_theme_font_size_override("font_size", rozmiar)
	l.add_theme_color_override("font_color", kolor)
	l.add_theme_color_override("font_shadow_color", Color(kolor.darkened(0.75), 1.0))
	l.add_theme_constant_override("shadow_offset_x", maxi(rozmiar / 8, 2))
	l.add_theme_constant_override("shadow_offset_y", maxi(rozmiar / 8, 2))
	return l


func _przycisk(txt: String, akcja: Callable, szerokosc: float = 11.0) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(rozmiar_czcionki * szerokosc, 0)
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b.add_theme_font_override("font", _f)
	b.add_theme_font_size_override("font_size", rozmiar_czcionki)
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 0.80))
	b.add_theme_color_override("font_focus_color", Color(1.0, 0.85, 0.80))
	b.add_theme_color_override("font_pressed_color", COL_BLOOD)
	b.add_theme_stylebox_override("normal", _st_btn)
	b.add_theme_stylebox_override("hover", _st_btn_hover)
	b.add_theme_stylebox_override("focus", _st_btn_hover)
	b.add_theme_stylebox_override("pressed", _st_btn_press)
	b.pressed.connect(func() -> void:
		_klik()
		akcja.call())
	return b


func _zbuduj() -> void:
	var m := int(rozmiar_czcionki * 0.35)
	_st_panel = _styl(COL_PANEL, COL_BORDER, int(rozmiar_czcionki * 1.2))
	_st_btn = _styl(Color(0.10, 0.025, 0.025), Color(0.38, 0.06, 0.05), m)
	_st_btn_hover = _styl(Color(0.19, 0.035, 0.030), Color(0.85, 0.15, 0.11), m)
	_st_btn_press = _styl(Color(0.06, 0.012, 0.012), Color(0.55, 0.09, 0.07), m)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _st_panel)
	centrum.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(rozmiar_czcionki * 0.6))
	panel.add_child(box)

	box.add_child(_etykieta(tytul, int(rozmiar_czcionki * 1.6), COL_BLOOD))

	var linia := ColorRect.new()
	linia.color = Color(COL_BORDER, 0.9)
	linia.custom_minimum_size = Vector2(0, 3)
	linia.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(linia)

	# --- menu główne ---
	_glowne = VBoxContainer.new()
	_glowne.add_theme_constant_override("separation", int(rozmiar_czcionki * 0.5))
	box.add_child(_glowne)
	_btn_wznow = _przycisk("KONTYNUUJ", wznow)
	_glowne.add_child(_btn_wznow)
	_glowne.add_child(_przycisk("OPCJE", _pokaz_opcje))
	_glowne.add_child(_przycisk("ZAKOŃCZ GRĘ", _zakoncz_gre))

	# --- opcje ---
	_opcje = VBoxContainer.new()
	_opcje.add_theme_constant_override("separation", int(rozmiar_czcionki * 0.5))
	_opcje.visible = false
	box.add_child(_opcje)

	var rzad := HBoxContainer.new()
	rzad.add_theme_constant_override("separation", int(rozmiar_czcionki * 0.4))
	_opcje.add_child(rzad)
	rzad.add_child(_przycisk("-", _zmien_glos.bind(-1), 1.6))
	_lbl_glos = _etykieta("", rozmiar_czcionki, COL_TEXT)
	_lbl_glos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rzad.add_child(_lbl_glos)
	rzad.add_child(_przycisk("+", _zmien_glos.bind(1), 1.6))

	_btn_pelny = _przycisk("", _przelacz_pelny_ekran)
	_opcje.add_child(_btn_pelny)
	_btn_wstecz = _przycisk("WSTECZ", _pokaz_glowne)
	_opcje.add_child(_btn_wstecz)

	if dzwiek_klik != null:
		_sfx = AudioStreamPlayer.new()
		_sfx.stream = dzwiek_klik
		_sfx.volume_db = glosnosc_klik_db
		add_child(_sfx)


func _klik() -> void:
	if _sfx != null:
		_sfx.play()


# ---------- Wejście ----------

func _process(_delta: float) -> void:
	# Zapamiętujemy stan ekwipunku z poprzedniej klatki: gracz zamyka go na tym samym Esc,
	# więc w _input nie wiemy, czy zdążył to już zrobić.
	if gracz != null and is_instance_valid(gracz) and not _otwarta:
		_inv_otwarty = bool(gracz.call("_inventory_open"))


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if not get_tree().get_nodes_in_group(GRUPA_INTRO).is_empty():
		return

	if _otwarta:
		get_viewport().set_input_as_handled()
		if _w_opcjach:
			_pokaz_glowne()
		else:
			wznow()
		return

	if _inv_otwarty:
		return
	if gracz != null and is_instance_valid(gracz) and bool(gracz.call("is_dead")):
		return

	get_viewport().set_input_as_handled()
	pauzuj()


# ---------- Pauza ----------

func pauzuj() -> void:
	if _otwarta:
		return
	_otwarta = true
	get_tree().paused = true
	visible = true
	_pokaz_glowne()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func wznow() -> void:
	if not _otwarta:
		return
	_otwarta = false
	visible = false
	get_tree().paused = false
	# klatka zwłoki: gracz mógł w tym samym Esc ustawić kursor na widoczny
	await get_tree().process_frame
	if not _otwarta:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _pokaz_glowne() -> void:
	_w_opcjach = false
	_opcje.visible = false
	_glowne.visible = true
	_btn_wznow.grab_focus()


func _pokaz_opcje() -> void:
	_w_opcjach = true
	_glowne.visible = false
	_opcje.visible = true
	_volume = clampi(roundi(db_to_linear(AudioServer.get_bus_volume_db(0)) * 10.0), 0, 10)
	_odswiez_opcje()
	_btn_wstecz.grab_focus()


func _zakoncz_gre() -> void:
	get_tree().quit()


# ---------- Opcje ----------

func _zmien_glos(kierunek: int) -> void:
	_volume = clampi(_volume + kierunek, 0, 10)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(_volume) / 10.0, 0.0001)))
	_odswiez_opcje()


func _jest_pelny_ekran() -> bool:
	var tryb := DisplayServer.window_get_mode()
	return tryb == DisplayServer.WINDOW_MODE_FULLSCREEN \
			or tryb == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func _przelacz_pelny_ekran() -> void:
	DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_WINDOWED if _jest_pelny_ekran() \
			else DisplayServer.WINDOW_MODE_FULLSCREEN)
	await get_tree().process_frame   # system zmienia tryb okna z opóźnieniem
	_odswiez_opcje()


func _odswiez_opcje() -> void:
	_lbl_glos.text = "GŁOŚNOŚĆ: %d" % _volume
	_btn_pelny.text = "PEŁNY EKRAN: %s" % ("TAK" if _jest_pelny_ekran() else "NIE")
