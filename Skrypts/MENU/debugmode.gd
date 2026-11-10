extends CanvasLayer
# DEBUG MENU: F1 otwiera / zamyka.
# Użycie: Project Settings -> Globals -> Autoload -> dodaj ten skrypt, nazwa: DebugMenu.
# (Jako autoload działa też wireframe, bo musi być włączony przed załadowaniem meshy.)
# Menu blokuje sterowanie graczem (kontrola_zablokowana) i pokazuje kursor.
# Skróty z innych skryptów nadal działają: F2 model-cień, F3 -10 HP, F4 +10 HP, F5 oczy, F6 stwór.

@export var klawisz: Key = KEY_F1
@export var tylko_w_debug_buildzie: bool = true   # false = menu także w wersji wydanej
@export var hud_na_start: bool = false            # HUD z parametrami od razu po starcie
@export var szybkosc_noclip: float = 8.0

const COL_PANEL := Color(0.030, 0.024, 0.027, 0.96)
const COL_BORDER := Color(0.30, 0.04, 0.04)
const COL_TEXT := Color(0.83, 0.79, 0.73)
const COL_BLOOD := Color(0.82, 0.14, 0.11)
const COL_HUD := Color(0.55, 1.0, 0.60)
const GRUPA_INTRO := "intro_aktywne"
const MAX_LOG := 6
const TRYBY_RENDERU := [
	Viewport.DEBUG_DRAW_DISABLED,
	Viewport.DEBUG_DRAW_UNSHADED,
	Viewport.DEBUG_DRAW_WIREFRAME,
	Viewport.DEBUG_DRAW_OVERDRAW,
]

var gracz: Gracz
var _otwarte: bool = false
var _stara_kontrola: bool = false
var _pauza_dbg: bool = false
var _nastepne_szukanie: int = 0

var _god: bool = false
var _noclip: bool = false
var _nieskonczona: bool = false
var _drain_orig: float = 0.5
var _spam_stwor: bool = false
var _spam_orig: Dictionary = {}
var _zapis_poz: Vector3 = Vector3.ZERO
var _zapis_rot: Vector2 = Vector2.ZERO
var _zapis_ok: bool = false

var _stwor_cache: CzarnyStwor
var _glitch_cache: GlitchKamery
var _item_bat: Item
var _item_test: Item

var _root: Control
var _panel: PanelContainer
var _tabs: TabContainer
var _hud: Label
var _lbl_ekw: Label
var _lista_js: VBoxContainer
var _opt_render: OptionButton
var _checki: Array[Dictionary] = []
var _suwaki: Array[Dictionary] = []
var _logi: PackedStringArray = []
var _hud_timer: float = 0.0


func _ready() -> void:
	if tylko_w_debug_buildzie and not OS.is_debug_build():
		queue_free()
		return
	layer = 110   # nad jumpscare (100+)
	process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.set_debug_generate_wireframes(true)
	_zbuduj()
	_panel.visible = false
	_hud.visible = hud_na_start


# ---------- Wejście ----------

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == klawisz:
		get_viewport().set_input_as_handled()
		_przelacz()


func _przelacz() -> void:
	if _otwarte:
		_zamknij()
		return
	if not get_tree().get_nodes_in_group(GRUPA_INTRO).is_empty():
		return
	if get_tree().paused:
		return   # pauza / intro mają pierwszeństwo
	_otworz()


func _otworz() -> void:
	_otwarte = true
	var g := _g()
	if g != null:
		if g.call("_inventory_open"):
			g.call("_toggle_inventory")
		_stara_kontrola = g.kontrola_zablokowana
		g.kontrola_zablokowana = true   # blokuje ruch, rozglądanie i przechwytywanie myszy
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_przebuduj_jumpscare()
	_synchronizuj()
	_odswiez_ekw()


func _zamknij() -> void:
	_otwarte = false
	_panel.visible = false
	if _pauza_dbg:
		_pauza_dbg = false
		get_tree().paused = false
	var g := _g()
	if g != null:
		g.kontrola_zablokowana = _stara_kontrola
		if not g.is_dead():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------- Szukanie węzłów ----------

func _g() -> Gracz:
	if is_instance_valid(gracz):
		return gracz
	gracz = null
	_noclip = false
	_stwor_cache = null
	_glitch_cache = null
	if Time.get_ticks_msec() < _nastepne_szukanie:
		return null
	_nastepne_szukanie = Time.get_ticks_msec() + 500
	var l: Array = []
	_szukaj(get_tree().root, func(n: Node) -> bool: return n is Gracz, l, true)
	if not l.is_empty():
		gracz = l[0] as Gracz
	return gracz


func _szukaj(wezel: Node, filtr: Callable, out: Array, pierwszy: bool) -> void:
	if pierwszy and not out.is_empty():
		return
	if wezel != self and filtr.call(wezel):
		out.append(wezel)
	for d in wezel.get_children():
		_szukaj(d, filtr, out, pierwszy)


func _latarka() -> Flashlight:
	var g := _g()
	return g.flashlight if g != null else null


func _oczy() -> Object:
	var g := _g()
	return g.oczy if g != null else null


func _stwor() -> CzarnyStwor:
	if is_instance_valid(_stwor_cache):
		return _stwor_cache
	var g := _g()
	if g == null:
		return null
	var l: Array = []
	_szukaj(g, func(n: Node) -> bool: return n is CzarnyStwor, l, true)
	if not l.is_empty():
		_stwor_cache = l[0] as CzarnyStwor
	return _stwor_cache


func _glitch_kamery() -> GlitchKamery:
	if is_instance_valid(_glitch_cache):
		return _glitch_cache
	var l: Array = []
	_szukaj(get_tree().root, func(n: Node) -> bool: return n is GlitchKamery, l, true)
	if not l.is_empty():
		_glitch_cache = l[0] as GlitchKamery
	return _glitch_cache


func _inv() -> Node:
	return get_node_or_null("/root/Inventory")


func _env() -> Environment:
	var l: Array = []
	_szukaj(get_tree().root, func(n: Node) -> bool: return n is WorldEnvironment, l, true)
	if l.is_empty():
		return null
	return (l[0] as WorldEnvironment).environment


func _log(tekst: String) -> void:
	print("[debug] ", tekst)
	_logi.append(tekst)
	while _logi.size() > MAX_LOG:
		_logi.remove_at(0)


# ---------- Akcje: gracz ----------

func _zadaj(v: float) -> void:
	var g := _g()
	if g != null:
		g.take_damage(v)
		_log("obrażenia: %.0f" % v)


func _ulecz(v: float) -> void:
	var g := _g()
	if g != null:
		g.heal(v)
		_log("leczenie: %.0f" % v)


func _zabij() -> void:
	var g := _g()
	if g != null and not g.is_dead():
		g.take_damage(g.health + 1.0)
		_log("zabito gracza")


func _ustaw_zycie(v: float) -> void:
	var g := _g()
	if g != null and not g.is_dead():
		g.call("_set_health", v)


func _ustaw_god(w: bool) -> void:
	_god = w
	_log("godmode: %s" % w)


func _ustaw_noclip(w: bool) -> void:
	var g := _g()
	_noclip = w and g != null
	if g == null:
		return
	g.set_physics_process(not _noclip)   # fizyka gracza stoi, lecimy swobodnie
	g.velocity = Vector3.ZERO
	_log("noclip: %s" % _noclip)


func _zapisz_poz() -> void:
	var g := _g()
	if g == null:
		return
	_zapis_poz = g.global_position
	_zapis_rot = Vector2(g.camera.rotation.x, g.rotation.y)
	_zapis_ok = true
	_log("zapisano pozycję %.1f %.1f %.1f" % [_zapis_poz.x, _zapis_poz.y, _zapis_poz.z])


func _wczytaj_poz() -> void:
	var g := _g()
	if g == null or not _zapis_ok:
		_log("brak zapisanej pozycji")
		return
	g.global_position = _zapis_poz
	g.velocity = Vector3.ZERO
	g.camera.rotation.x = _zapis_rot.x
	g.rotation.y = _zapis_rot.y
	_log("wczytano pozycję")


func _reset_sceny() -> void:
	var inv := _inv()
	if inv != null and inv.has_method("reset"):
		inv.reset()
	_zamknij()
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


# ---------- Akcje: latarka ----------

func _l_daj() -> void:
	var g := _g()
	if g != null:
		g.give_flashlight()
		_log("dano latarkę")


func _l_schowaj() -> void:
	var g := _g()
	if g != null:
		g.schowaj_latarke()
		_log("schowano latarkę")


func _l_pelna() -> void:
	var l := _latarka()
	if l != null:
		l.charge_battery(l.max_battery)
		_log("bateria latarki 100%")


func _l_slaba() -> void:
	var l := _latarka()
	if l != null:
		l.battery = l.max_battery * 0.15
		_log("bateria latarki 15%")


func _l_toggle() -> void:
	var l := _latarka()
	if l != null:
		l.call("_toggle_light")


func _l_reload() -> void:
	var l := _latarka()
	if l != null:
		l.probuj_przeladowac()


func _ustaw_nieskonczona(w: bool) -> void:
	var l := _latarka()
	if l == null:
		return
	if w and not _nieskonczona:
		_drain_orig = l.drain_per_second
		l.drain_per_second = 0.0
		_nieskonczona = true
	elif not w and _nieskonczona:
		l.drain_per_second = _drain_orig
		_nieskonczona = false
	_log("nieskończona bateria: %s" % _nieskonczona)


# ---------- Akcje: ekwipunek ----------

func _item_baterii() -> Item:
	var l := _latarka()
	if l != null and l.battery_item != null:
		return l.battery_item
	if _item_bat == null:
		_item_bat = Item.new()
		_item_bat.nazwa = l.battery_name if l != null else "Bateria"
		_item_bat.opis = "Bateria testowa (debug)."
		_item_bat.stackowalny = true
		_item_bat.max_stack = 99
		_item_bat.uzywalny = true
		_item_bat.laduje_baterie = 100.0
	return _item_bat


func _dodaj_baterie(n: int) -> void:
	var inv := _inv()
	if inv == null:
		_log("brak autoloadu Inventory")
		return
	_log("dodano baterie x%d: %s" % [n, "OK" if inv.dodaj(_item_baterii(), n) else "brak miejsca"])
	_odswiez_ekw()


func _dodaj_testowy() -> void:
	var inv := _inv()
	if inv == null:
		_log("brak autoloadu Inventory")
		return
	if _item_test == null:
		_item_test = Item.new()
		_item_test.nazwa = "Testowy przedmiot"
		_item_test.opis = "Przedmiot z debug menu."
	_log("dodano testowy: %s" % ("OK" if inv.dodaj(_item_test, 1) else "brak miejsca"))
	_odswiez_ekw()


func _wyczysc_ekw() -> void:
	var inv := _inv()
	if inv != null:
		inv.reset()
		_log("wyczyszczono ekwipunek")
	_odswiez_ekw()


func _tekst_ekw() -> String:
	var inv := _inv()
	if inv == null:
		return "(brak autoloadu Inventory)"
	var t := PackedStringArray()
	for i in inv.ROZMIAR:
		var s = inv.sloty[i]
		if s != null:
			t.append("%2d: %s x%d" % [i + 1, s.item.nazwa, s.ilosc])
	return "\n".join(t) if not t.is_empty() else "(pusty)"


func _odswiez_ekw() -> void:
	if _lbl_ekw != null:
		_lbl_ekw.text = _tekst_ekw()


# ---------- Akcje: strach ----------

func _wymus_oczy() -> void:
	var o := _oczy()
	if o != null:
		o.wymus()
		_log("wymuszono oczy")
	else:
		_log("brak oczu (oczy_wlaczone?)")


func _wymus_stwora() -> void:
	var s := _stwor()
	if s == null:
		var g := _g()
		if g == null:
			return
		s = CzarnyStwor.new()
		s.name = "CzarnyStwor"
		g.add_child(s)
		_stwor_cache = s
		_log("utworzono węzeł CzarnyStwor")
	s.wymus()
	_log("wymuszono stwora")


func _ustaw_spam_stwora(w: bool) -> void:
	var s := _stwor()
	if s == null:
		return
	if w and not _spam_stwor:
		_spam_orig = {"szansa": s.szansa, "interwal": s.interwal_sprawdzania, "cooldown": s.cooldown}
		s.szansa = 1.0
		s.interwal_sprawdzania = 2.0
		s.cooldown = 0.0
		_spam_stwor = true
	elif not w and _spam_stwor:
		s.szansa = _spam_orig["szansa"]
		s.interwal_sprawdzania = _spam_orig["interwal"]
		s.cooldown = _spam_orig["cooldown"]
		_spam_stwor = false
	_log("stwór - tryb częsty: %s" % _spam_stwor)


func _glitch_teraz(czas: float, sila: float) -> void:
	var gk := _glitch_kamery()
	if gk == null and get_tree().current_scene != null:
		gk = GlitchKamery.new()
		get_tree().current_scene.add_child(gk)
		_glitch_cache = gk
		_log("utworzono GlitchKamery")
	if gk != null:
		gk.trigger(czas, sila)
		_log("glitch %.1f s" % czas)


func _odpal_js(t: JumpscareTrigger) -> void:
	if is_instance_valid(t):
		t.call("_odpal")
		_log("jumpscare: %s" % t.name)


func _tp_do(t: Node3D) -> void:
	var g := _g()
	if g != null and is_instance_valid(t):
		g.global_position = t.global_position + Vector3.UP * 0.3
		g.velocity = Vector3.ZERO
		_log("teleport do: %s" % t.name)


func _przebuduj_jumpscare() -> void:
	if _lista_js == null:
		return
	for c in _lista_js.get_children():
		c.queue_free()
	var l: Array = []
	_szukaj(get_tree().root, func(n: Node) -> bool: return n is JumpscareTrigger, l, false)
	if l.is_empty():
		var e := Label.new()
		e.text = "(brak JumpscareTrigger w scenie)"
		_lista_js.add_child(e)
		return
	for n in l:
		var t := n as JumpscareTrigger
		_przyciski(_lista_js, [
			["Odpal: %s" % t.name, _odpal_js.bind(t)],
			["TP (wywoła trigger)", _tp_do.bind(t)],
		])


# ---------- Akcje: świat / render ----------

func _ustaw_pauze(w: bool) -> void:
	_pauza_dbg = w
	get_tree().paused = w


func _ustaw_mgle(w: bool) -> void:
	var e := _env()
	if e != null:
		e.fog_enabled = w
		_log("mgła: %s" % w)


func _ustaw_vsync(w: bool) -> void:
	DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if w else DisplayServer.VSYNC_DISABLED)


func _wezel_widoczny(nazwa: String) -> bool:
	var n := get_tree().root.find_child(nazwa, true, false)
	return n != null and bool(n.get("visible"))


func _ustaw_wezel(nazwa: String, w: bool) -> void:
	var n := get_tree().root.find_child(nazwa, true, false)
	if n != null:
		n.set("visible", w)


# ---------- Pętla ----------

func _process(delta: float) -> void:
	var g := _g() if (_god or _noclip) else null

	if _god and g != null and not g.is_dead() and g.health < g.max_health:
		g.heal(g.max_health)

	if _noclip and g != null and not g.is_dead() and not _otwarte and not get_tree().paused:
		var ruch := Input.get_vector("left", "right", "forward", "back")
		var kier := g.camera.global_transform.basis * Vector3(ruch.x, 0.0, ruch.y)
		if Input.is_physical_key_pressed(KEY_SPACE):
			kier.y += 1.0
		if Input.is_physical_key_pressed(KEY_CTRL):
			kier.y -= 1.0
		var v := szybkosc_noclip * (3.0 if Input.is_action_pressed("sprint") else 1.0)
		g.global_position += kier.limit_length(1.0) * v * delta
		g.velocity = Vector3.ZERO

	_hud_timer -= delta
	if _hud_timer <= 0.0:
		_hud_timer = 0.15
		if _hud.visible:
			_odswiez_hud()
		if _otwarte:
			_odswiez_ekw()


func _odswiez_hud() -> void:
	var t := PackedStringArray()
	t.append("FPS %d | %.1f ms | draw calls %d | węzły %d" % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])

	var g := _g()
	if g == null:
		t.append("(brak gracza w scenie)")
	else:
		t.append("poz %.1f %.1f %.1f" % [g.global_position.x, g.global_position.y, g.global_position.z])
		t.append("prędkość %.1f | %s | %s | %s" % [
			float(g.get("_h_speed")),
			"ziemia" if g.is_on_floor() else "powietrze",
			"kuca" if g.get("_crouching") else "stoi",
			"sprint" if g.get("_sprinting") else "-"])
		t.append("HP %.0f/%.0f | wytrzymałość %.0f%%%s" % [
			g.health, g.max_health, g.stamina * 100.0,
			" (WYCZERPANY)" if g.is_exhausted() else ""])
		var l := g.flashlight
		if l != null:
			t.append("latarka: %s | %s | bateria %.0f%%%s" % [
				"odblokowana" if l.unlocked else "zablokowana",
				"świeci" if l.is_on else "zgaszona",
				l.battery / maxf(l.max_battery, 0.001) * 100.0,
				" | zajęta" if l.is_busy else ""])
		var cel = g.call("_get_interact_target")
		if cel is Node:
			t.append("cel: %s" % (cel as Node).name)

	var flagi := PackedStringArray()
	if _god:
		flagi.append("GOD")
	if _noclip:
		flagi.append("NOCLIP")
	if _nieskonczona:
		flagi.append("INF BAT")
	if Engine.time_scale != 1.0:
		flagi.append("czas x%.2f" % Engine.time_scale)
	if not flagi.is_empty():
		t.append("[" + ", ".join(flagi) + "]")

	for wpis in _logi:
		t.append("> " + wpis)
	_hud.text = "\n".join(t)


# ---------- Budowa UI ----------

func _styl(tlo: Color, ramka: Color, margines: int = 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = tlo
	s.border_color = ramka
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.set_content_margin_all(margines)
	return s


func _zrob_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	var normal := _styl(Color(0.10, 0.025, 0.025), Color(0.38, 0.06, 0.05))
	var hover := _styl(Color(0.19, 0.035, 0.030), Color(0.85, 0.15, 0.11))
	var pressed := _styl(Color(0.06, 0.012, 0.012), Color(0.55, 0.09, 0.07))
	for typ in ["Button", "OptionButton"]:
		t.set_stylebox("normal", typ, normal)
		t.set_stylebox("hover", typ, hover)
		t.set_stylebox("pressed", typ, pressed)
		t.set_stylebox("focus", typ, hover)
		t.set_color("font_color", typ, COL_TEXT)
		t.set_color("font_hover_color", typ, Color(1.0, 0.85, 0.80))
		t.set_color("font_pressed_color", typ, COL_BLOOD)
	for typ in ["Label", "CheckBox"]:
		t.set_color("font_color", typ, COL_TEXT)
	t.set_color("font_hover_color", "CheckBox", Color(1.0, 0.85, 0.80))
	t.set_color("font_pressed_color", "CheckBox", Color(1.0, 0.85, 0.80))
	t.set_color("font_hover_pressed_color", "CheckBox", Color(1.0, 0.85, 0.80))
	t.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())
	t.set_stylebox("tab_selected", "TabContainer", _styl(Color(0.17, 0.03, 0.03), COL_BLOOD, 5))
	t.set_stylebox("tab_unselected", "TabContainer", _styl(Color(0.06, 0.04, 0.04), COL_BORDER, 5))
	t.set_stylebox("tab_hovered", "TabContainer", _styl(Color(0.12, 0.03, 0.03), COL_BLOOD, 5))
	t.set_color("font_selected_color", "TabContainer", Color(1.0, 0.85, 0.80))
	t.set_color("font_unselected_color", "TabContainer", Color(0.6, 0.55, 0.5))
	t.set_color("font_hovered_color", "TabContainer", Color(1.0, 0.85, 0.80))
	return t


func _zbuduj() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# HUD (prawy górny róg)
	_hud = Label.new()
	_hud.anchor_left = 1.0
	_hud.anchor_right = 1.0
	_hud.offset_right = -12.0
	_hud.offset_top = 10.0
	_hud.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_theme_font_size_override("font_size", 15)
	_hud.add_theme_color_override("font_color", COL_HUD)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 5)
	_root.add_child(_hud)

	# panel menu (lewa strona)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_panel.offset_left = 12.0
	_panel.offset_right = 560.0
	_panel.offset_top = 12.0
	_panel.offset_bottom = -12.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.theme = _zrob_theme()
	_panel.add_theme_stylebox_override("panel", _styl(COL_PANEL, COL_BORDER, 10))
	_root.add_child(_panel)

	var kol := VBoxContainer.new()
	_panel.add_child(kol)

	var tytul := Label.new()
	tytul.text = "DEBUG MENU   [F1 - zamknij]"
	tytul.add_theme_color_override("font_color", COL_BLOOD)
	tytul.add_theme_font_size_override("font_size", 18)
	kol.add_child(tytul)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	kol.add_child(_tabs)

	_karta_gracz()
	_karta_latarka()
	_karta_ekwipunek()
	_karta_strach()
	_karta_swiat()
	_karta_render()


func _karta(nazwa: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = nazwa
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(sc)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	sc.add_child(box)
	return box


func _naglowek(box: Control, tekst: String) -> void:
	var l := Label.new()
	l.text = "— " + tekst + " —"
	l.add_theme_color_override("font_color", COL_BLOOD)
	box.add_child(l)


func _opis(box: Control, tekst: String) -> Label:
	var l := Label.new()
	l.text = tekst
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(0.52, 0.47, 0.43))
	box.add_child(l)
	return l


func _przyciski(box: Control, lista: Array) -> void:
	var rzad := HBoxContainer.new()
	rzad.add_theme_constant_override("separation", 6)
	box.add_child(rzad)
	for p in lista:
		var b := Button.new()
		b.text = p[0]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(p[1])
		rzad.add_child(b)


func _check(box: Control, tekst: String, getter: Callable, setter: Callable) -> void:
	var c := CheckBox.new()
	c.text = tekst
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(w: bool) -> void: setter.call(w))
	box.add_child(c)
	_checki.append({"c": c, "g": getter})


# Przełącznik pola bool na obiekcie zwracanym przez 'cel' (odwroc = pokazuje zaprzeczenie pola)
func _check_prop(box: Control, tekst: String, cel: Callable, prop: String, odwroc: bool = false) -> void:
	_check(box, tekst,
		func() -> bool:
			var o = cel.call()
			return o != null and (bool(o.get(prop)) != odwroc),
		func(w: bool) -> void:
			var o = cel.call()
			if o != null:
				o.set(prop, w != odwroc))


func _suwak(box: Control, tekst: String, mn: float, mx: float, krok: float,
		getter: Callable, setter: Callable, format: String = "%.1f") -> void:
	var rzad := HBoxContainer.new()
	box.add_child(rzad)
	var l := Label.new()
	l.text = tekst
	l.custom_minimum_size.x = 170
	rzad.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = krok
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size.x = 120
	rzad.add_child(s)
	var w := Label.new()
	w.custom_minimum_size.x = 56
	w.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rzad.add_child(w)
	s.value_changed.connect(func(v: float) -> void:
		w.text = format % v
		setter.call(v))
	_suwaki.append({"s": s, "g": getter, "w": w, "f": format})


func _suwak_prop(box: Control, tekst: String, mn: float, mx: float, krok: float,
		cel: Callable, prop: String, format: String = "%.1f") -> void:
	_suwak(box, tekst, mn, mx, krok,
		func() -> float:
			var o = cel.call()
			return float(o.get(prop)) if o != null else mn,
		func(v: float) -> void:
			var o = cel.call()
			if o != null:
				o.set(prop, v),
		format)


func _synchronizuj() -> void:
	for e in _checki:
		(e["c"] as CheckBox).set_pressed_no_signal(bool(e["g"].call()))
	for e in _suwaki:
		var v := float(e["g"].call())
		(e["s"] as HSlider).set_value_no_signal(v)
		(e["w"] as Label).text = (e["f"] as String) % v
	_opt_render.select(maxi(TRYBY_RENDERU.find(get_viewport().debug_draw), 0))


# ---------- Karty ----------

func _karta_gracz() -> void:
	var b := _karta("Gracz")
	_naglowek(b, "ŻYCIE")
	_przyciski(b, [["-10 HP", _zadaj.bind(10.0)], ["+10 HP", _ulecz.bind(10.0)]])
	_przyciski(b, [["Pełne życie", _ulecz.bind(1000.0)], ["Zabij", _zabij]])
	_suwak(b, "Życie", 1.0, 100.0, 1.0,
		func() -> float: return _g().health if _g() != null else 100.0,
		_ustaw_zycie, "%.0f")
	_check(b, "Godmode (HP zawsze pełne)", func() -> bool: return _god, _ustaw_god)
	_naglowek(b, "RUCH")
	_check(b, "Noclip / latanie (WASD, SPACJA góra, CTRL dół, SHIFT x3)",
		func() -> bool: return _noclip, _ustaw_noclip)
	_check_prop(b, "Nieskończona wytrzymałość", _g, "stamina_enabled", true)
	_check_prop(b, "Kucanie: przełącznik (toggle)", _g, "crouch_toggle")
	_przyciski(b, [["Zapisz pozycję", _zapisz_poz], ["Wczytaj pozycję", _wczytaj_poz]])
	_naglowek(b, "LOGI GRACZA (w konsoli)")
	_check_prop(b, "Kroki", _g, "debug_footsteps")
	_check_prop(b, "Audio sprintu", _g, "debug_sprint_audio")
	_check_prop(b, "Animacje", _g, "debug_animations")
	_opis(b, "Skróty z innych skryptów: F2 model-cień, F3 -10 HP, F4 +10 HP, F5 oczy, F6 stwór.")


func _karta_latarka() -> void:
	var b := _karta("Latarka")
	_przyciski(b, [["Daj latarkę", _l_daj], ["Schowaj latarkę", _l_schowaj]])
	_przyciski(b, [["Przełącz światło", _l_toggle], ["Przeładuj (z ekw.)", _l_reload]])
	_przyciski(b, [["Bateria 100%", _l_pelna], ["Bateria 15%", _l_slaba]])
	_check(b, "Nieskończona bateria", func() -> bool: return _nieskonczona, _ustaw_nieskonczona)
	_suwak(b, "Bateria %", 0.0, 100.0, 1.0,
		func() -> float:
			var l := _latarka()
			return l.battery / maxf(l.max_battery, 0.001) * 100.0 if l != null else 0.0,
		func(v: float) -> void:
			var l := _latarka()
			if l != null:
				l.battery = l.max_battery * v / 100.0,
		"%.0f")
	_suwak_prop(b, "Moc światła", 0.0, 10.0, 0.1, _latarka, "base_energy")
	_suwak_prop(b, "Zużycie / s", 0.0, 10.0, 0.1, _latarka, "drain_per_second")
	_naglowek(b, "LOGI LATARKI (w konsoli)")
	_check_prop(b, "Animacje", _latarka, "debug_animations")
	_check_prop(b, "Wejście (F)", _latarka, "debug_input")
	_check_prop(b, "Przeładowanie", _latarka, "debug_reload")


func _karta_ekwipunek() -> void:
	var b := _karta("Ekwipunek")
	_przyciski(b, [["+1 bateria", _dodaj_baterie.bind(1)], ["+5 baterii", _dodaj_baterie.bind(5)]])
	_przyciski(b, [["Dodaj testowy przedmiot", _dodaj_testowy], ["Wyczyść ekwipunek", _wyczysc_ekw]])
	_naglowek(b, "ZAWARTOŚĆ")
	_lbl_ekw = Label.new()
	_lbl_ekw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_child(_lbl_ekw)


func _karta_strach() -> void:
	var b := _karta("Strach")
	_naglowek(b, "CZERWONE OCZY")
	_przyciski(b, [["Wymuś oczy", _wymus_oczy]])
	_check_prop(b, "Oczy włączone", _oczy, "wlaczony")
	_naglowek(b, "CZARNY STWÓR")
	_przyciski(b, [["Wymuś stwora", _wymus_stwora]])
	_check_prop(b, "Stwór włączony", _stwor, "wlaczony")
	_check(b, "Tryb częsty (szansa 100%, co 2 s, bez cooldownu)",
		func() -> bool: return _spam_stwor, _ustaw_spam_stwora)
	_naglowek(b, "GLITCH KAMERY")
	_przyciski(b, [["Glitch losowy", _glitch_teraz.bind(-1.0, -1.0)],
		["Glitch mocny 1 s", _glitch_teraz.bind(1.0, 1.0)]])
	_check_prop(b, "Glitch włączony", _glitch_kamery, "wlaczony")
	_check_prop(b, "Log glitcha (w konsoli)", _glitch_kamery, "debug_glitch")
	_naglowek(b, "JUMPSCARE (triggery w scenie)")
	_lista_js = VBoxContainer.new()
	_lista_js.add_theme_constant_override("separation", 4)
	b.add_child(_lista_js)


func _karta_swiat() -> void:
	var b := _karta("Świat")
	_check(b, "HUD z parametrami (FPS, pozycja, HP...)",
		func() -> bool: return _hud.visible,
		func(w: bool) -> void: _hud.visible = w)
	_check(b, "Zatrzymaj grę",
		func() -> bool: return get_tree().paused,
		_ustaw_pauze)
	_suwak(b, "Skala czasu", 0.0, 3.0, 0.05,
		func() -> float: return Engine.time_scale,
		func(v: float) -> void: Engine.time_scale = v, "%.2f")
	_naglowek(b, "ŚRODOWISKO")
	_check(b, "Mgła",
		func() -> bool:
			var e := _env()
			return e != null and e.fog_enabled,
		_ustaw_mgle)
	_check(b, "Chmury",
		func() -> bool: return _wezel_widoczny("Chmury"),
		func(w: bool) -> void: _ustaw_wezel("Chmury", w))
	_check(b, "Księżyc",
		func() -> bool: return _wezel_widoczny("Ksiezyc"),
		func(w: bool) -> void:
			_ustaw_wezel("Ksiezyc", w)
			_ustaw_wezel("PoswiataKsiezyca", w))
	_check(b, "Światło księżyca",
		func() -> bool: return _wezel_widoczny("SwiatloKsiezyca"),
		func(w: bool) -> void: _ustaw_wezel("SwiatloKsiezyca", w))
	_naglowek(b, "SCENA")
	_przyciski(b, [["Zrestartuj scenę (+ czyści ekwipunek)", _reset_sceny]])


func _karta_render() -> void:
	var b := _karta("Render")
	_naglowek(b, "TRYB WIDOKU")
	_opt_render = OptionButton.new()
	_opt_render.focus_mode = Control.FOCUS_NONE
	for n in ["Normalny", "Bez oświetlenia (unshaded)", "Siatka (wireframe)", "Overdraw"]:
		_opt_render.add_item(n)
	_opt_render.item_selected.connect(func(i: int) -> void:
		get_viewport().debug_draw = TRYBY_RENDERU[i])
	b.add_child(_opt_render)
	_naglowek(b, "WYDAJNOŚĆ")
	_check(b, "VSync",
		func() -> bool: return DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED,
		_ustaw_vsync)
	_suwak(b, "Limit FPS (0 = brak)", 0.0, 240.0, 5.0,
		func() -> float: return float(Engine.max_fps),
		func(v: float) -> void: Engine.max_fps = int(v), "%.0f")
