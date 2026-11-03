class_name PodgladPrzedmiotu
extends CanvasLayer
# Podgląd 3D przedmiotu z ekwipunku: model na środku ekranu, obracany myszką w dowolną stronę.
# Model bierze z Item.scena_swiata, a jeśli puste, z kopii Item.szablon (zapamiętanej przy podniesieniu).
# Używa własnego świata 3D (SubViewport), więc nie miesza się ze sceną gry.
#
# LPM (przeciągnij) = obracanie, kółko = zoom, R = reset widoku, PPM / Esc / Tab = zamknij

signal zamknieto

const DYSTANS_KAMERY := 2.4
const ROZMIAR_MODELU := 1.0      # największy wymiar modelu po przeskalowaniu (jednostki)
const MIN_ZOOM := 0.5
const MAX_ZOOM := 3.0
const CZULOSC := 0.008           # rad na piksel ruchu myszy
const BEZWLADNOSC := 3.0         # im większe, tym szybciej model przestaje się kręcić po puszczeniu
const PODPOWIEDZ := "LPM (przeciągnij) — obracaj      KÓŁKO — przybliż      R — reset      PPM / ESC — zamknij"

var otwarty: bool = false

var _root: Control
var _kontener: SubViewportContainer
var _vp: SubViewport
var _kamera: Camera3D
var _pivot: Node3D
var _model: Node3D
var _lapacz: Control
var _margines: MarginContainer
var _nazwa: Label
var _podpowiedz: Label
var _font: Font

var _drag: bool = false
var _ruch: Vector2 = Vector2.ZERO
var _predkosc: Vector2 = Vector2.ZERO
var _zoom: float = 1.0
var _cel_zoom: float = 1.0


func _ready() -> void:
	layer = 4   # nad ekwipunkiem (3), pod jumpscare (100+)
	visible = false
	set_process(false)
	_zbuduj()
	_uklad()
	get_viewport().size_changed.connect(_uklad)


# ---------- Budowa ----------

func _zbuduj() -> void:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(
		["Georgia", "Palatino Linotype", "Times New Roman", "DejaVu Serif", "serif"])
	f.font_weight = 600
	_font = f

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var tlo := ColorRect.new()
	tlo.color = Color(0.0, 0.0, 0.0, 0.88)
	tlo.set_anchors_preset(Control.PRESET_FULL_RECT)
	tlo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(tlo)

	# własny świat 3D z przezroczystym tłem
	_kontener = SubViewportContainer.new()
	_kontener.set_anchors_preset(Control.PRESET_FULL_RECT)
	_kontener.stretch = true
	_kontener.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_kontener)

	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var swiat := World3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.62)
	env.ambient_light_energy = 0.8
	swiat.environment = env
	_vp.world_3d = swiat
	_kontener.add_child(_vp)

	_kamera = Camera3D.new()
	_kamera.fov = 35.0
	_kamera.position = Vector3(0.0, 0.0, DYSTANS_KAMERY)
	_vp.add_child(_kamera)
	_kamera.current = true

	var glowne := DirectionalLight3D.new()
	glowne.rotation_degrees = Vector3(-40.0, -35.0, 0.0)
	glowne.light_energy = 1.3
	_vp.add_child(glowne)

	var pomocnicze := DirectionalLight3D.new()
	pomocnicze.rotation_degrees = Vector3(25.0, 145.0, 0.0)
	pomocnicze.light_energy = 0.5
	_vp.add_child(pomocnicze)

	_pivot = Node3D.new()
	_vp.add_child(_pivot)

	# warstwa łapiąca mysz (nad widokiem 3D)
	_lapacz = Control.new()
	_lapacz.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lapacz.mouse_filter = Control.MOUSE_FILTER_STOP
	_lapacz.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_lapacz.gui_input.connect(_on_gui_input)
	_root.add_child(_lapacz)

	# napisy
	_margines = MarginContainer.new()
	_margines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_margines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_margines)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margines.add_child(box)

	_nazwa = _zrob_etykiete(Color(0.82, 0.14, 0.11))
	box.add_child(_nazwa)

	var odstep := Control.new()
	odstep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	odstep.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(odstep)

	_podpowiedz = _zrob_etykiete(Color(0.52, 0.47, 0.43))
	_podpowiedz.text = PODPOWIEDZ
	box.add_child(_podpowiedz)


func _zrob_etykiete(kolor: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", _font)
	l.add_theme_color_override("font_color", kolor)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	return l


func _uklad() -> void:
	if _root == null:
		return
	var h := get_viewport().get_visible_rect().size.y
	var m := int(h * 0.05)
	for strona in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		_margines.add_theme_constant_override(strona, m)
	_nazwa.add_theme_font_size_override("font_size", clampi(int(h * 0.05), 20, 56))
	_podpowiedz.add_theme_font_size_override("font_size", clampi(int(h * 0.026), 12, 26))


# ---------- Otwieranie / zamykanie ----------

# Zwraca false, gdy przedmiot nie ma modelu 3D
func pokaz(item: Item) -> bool:
	if item == null:
		return false
	var model := _zrob_model(item)
	if model == null:
		push_warning("Podgląd: '%s' nie ma modelu (ustaw 'Scena Swiata' w Item albo najpierw podnieś przedmiot z ziemi)" % item.nazwa)
		return false

	_wyczysc()
	_model = model
	_pivot.add_child(_model)
	_wysrodkuj()
	_reset_widoku()

	_nazwa.text = item.nazwa
	_drag = false
	_ruch = Vector2.ZERO
	_predkosc = Vector2.ZERO

	otwarty = true
	visible = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	set_process(true)
	return true


func zamknij() -> void:
	if not otwarty:
		return
	otwarty = false
	visible = false
	_drag = false
	set_process(false)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_wyczysc()
	zamknieto.emit()


func _wyczysc() -> void:
	if _model != null and is_instance_valid(_model):
		_pivot.remove_child(_model)
		_model.queue_free()
	_model = null


func _reset_widoku() -> void:
	_pivot.basis = Basis.from_euler(Vector3(0.35, -0.6, 0.0))
	_predkosc = Vector2.ZERO
	_cel_zoom = 1.0
	_zoom = 1.0


# ---------- Model ----------

func _zrob_model(item: Item) -> Node3D:
	var zrodlo: Node3D = null
	if item.scena_swiata != null:
		zrodlo = item.scena_swiata.instantiate() as Node3D
	elif item.szablon != null and is_instance_valid(item.szablon):
		zrodlo = item.szablon.duplicate() as Node3D
	if zrodlo == null:
		return null
	_oczysc(zrodlo)
	zrodlo.transform = Transform3D.IDENTITY
	return zrodlo


# Zostawia same wizualia: bez skryptów, kolizji, świateł i dźwięków
func _oczysc(wezel: Node) -> void:
	for dziecko in wezel.get_children():
		if dziecko is CollisionShape3D or dziecko is CollisionPolygon3D \
				or dziecko is Light3D or dziecko is AudioStreamPlayer3D:
			wezel.remove_child(dziecko)
			dziecko.free()
		else:
			_oczysc(dziecko)
	wezel.set_script(null)


# Skaluje model do ROZMIAR_MODELU i ustawia jego środek w punkcie obrotu
func _wysrodkuj() -> void:
	var meshe: Array = _model.find_children("*", "GeometryInstance3D", true, false)
	if _model is GeometryInstance3D:
		meshe.append(_model)

	var ma := false
	var obrys := AABB()
	for m in meshe:
		var g := m as GeometryInstance3D
		var a := g.get_aabb()
		var t := g.global_transform
		for i in 8:
			var p := t * a.get_endpoint(i)
			if not ma:
				obrys = AABB(p, Vector3.ZERO)
				ma = true
			else:
				obrys = obrys.expand(p)
	if not ma:
		return

	var najwiekszy := maxf(obrys.size.x, maxf(obrys.size.y, obrys.size.z))
	var s := ROZMIAR_MODELU / maxf(najwiekszy, 0.0001)
	_model.scale = Vector3.ONE * s
	_model.position = -obrys.get_center() * s


# ---------- Wejście ----------

func _input(event: InputEvent) -> void:
	if not otwarty:
		return
	# Esc / Tab zamykają tylko podgląd (ekwipunek zostaje otwarty)
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("inventory"):
		zamknij()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_R:
		_reset_widoku()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_drag = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_cel_zoom = clampf(_cel_zoom * 1.1, MIN_ZOOM, MAX_ZOOM)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_cel_zoom = clampf(_cel_zoom / 1.1, MIN_ZOOM, MAX_ZOOM)
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					zamknij()
	elif event is InputEventMouseMotion and _drag:
		_ruch += event.relative


func _process(delta: float) -> void:
	# obrót wokół osi ekranu (pełna swoboda, bez blokady góra/dół) + bezwładność po puszczeniu
	var d := _ruch * CZULOSC
	_ruch = Vector2.ZERO
	if _drag:
		_predkosc = d / maxf(delta, 0.001)
	else:
		_predkosc = _predkosc.lerp(Vector2.ZERO, 1.0 - exp(-BEZWLADNOSC * delta))
		d = _predkosc * delta

	if d != Vector2.ZERO:
		_pivot.basis = (Basis(Vector3.UP, d.x) * Basis(Vector3.RIGHT, d.y) * _pivot.basis).orthonormalized()

	_zoom = lerpf(_zoom, _cel_zoom, 1.0 - exp(-12.0 * delta))
	_kamera.position.z = DYSTANS_KAMERY / _zoom
