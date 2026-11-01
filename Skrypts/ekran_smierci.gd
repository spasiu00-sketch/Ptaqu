class_name EkranSmierci
extends CanvasLayer
# Ekran po śmierci gracza: krwawa winieta, napis "NIE ZDANE" (drżenie, duchy, glitch)
# i przycisk "ZRESETUJ", który wczytuje grę od nowa (tak jak "NOWA GRA" w menu).
# Tworzy go gracz (character_body_3d.gd) po śmierci i wywołuje pokaz().

@export_file("*.tscn") var scena_gry: String = "res://Scenes/start_game.tscn"   # ta sama co w MainMenu
@export var tekst_tytulu: String = "NIE ZDANE"
@export var tekst_przycisku: String = "ZRESETUJ"
@export var dzwiek: AudioStream                 # opcjonalny dźwięk przy pojawieniu się napisu
@export var glosnosc_db: float = 0.0
@export var opoznienie_przycisku: float = 2.2   # po ilu sekundach od pokazania można kliknąć przycisk

const COL_TYTUL := Color(0.78, 0.07, 0.05)
const COL_DUCH := Color(0.45, 0.0, 0.0)
const COL_TEKST := Color(0.86, 0.80, 0.74)

# Tło: ciemność ze szkarłatną winietą, która powoli pulsuje
const SHADER_TLA := """
shader_type canvas_item;
uniform float sila : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float d = length(UV - 0.5) * 1.41421;
	float v = smoothstep(0.30, 1.0, d);
	float puls = 0.85 + 0.15 * sin(TIME * 1.6);
	vec3 rgb = vec3(0.34, 0.0, 0.0) * v * puls;
	float a = (0.66 + 0.30 * v) * sila;
	COLOR = vec4(rgb, a);
}
"""

var _root: Control
var _tlo: ColorRect
var _mat: ShaderMaterial
var _tytul: Label
var _duch_a: Label
var _duch_b: Label
var _spacer: Control
var _przycisk: Button
var _czern: ColorRect
var _font: FontVariation
var _st_norm: StyleBoxFlat
var _st_hover: StyleBoxFlat
var _st_press: StyleBoxFlat
var _st_off: StyleBoxFlat

var _sila_tla: float = 0.0
var _alfa_tytulu: float = 0.0
var _czas: float = 0.0
var _glitch: float = 0.0
var _pokazany: bool = false
var _restart: bool = false


func _ready() -> void:
	layer = 90   # nad HUD i ekwipunkiem, pod jumpscare (100+)
	visible = false
	_zbuduj()
	_uklad()
	get_viewport().size_changed.connect(_uklad)


# ---------- Budowa ----------

func _zbuduj() -> void:
	var baza := SystemFont.new()
	baza.font_names = PackedStringArray(
		["Georgia", "Palatino Linotype", "Times New Roman", "DejaVu Serif", "serif"])
	baza.font_weight = 800
	baza.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	baza.generate_mipmaps = true
	_font = FontVariation.new()
	_font.base_font = baza

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # klik nie przechodzi do gry
	add_child(_root)

	var shader := Shader.new()
	shader.code = SHADER_TLA
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_tlo = ColorRect.new()
	_tlo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tlo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tlo.material = _mat
	_root.add_child(_tlo)

	var centrum := CenterContainer.new()
	centrum.set_anchors_preset(Control.PRESET_FULL_RECT)
	centrum.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(centrum)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centrum.add_child(box)

	_tytul = _zrob_napis(tekst_tytulu, COL_TYTUL)
	box.add_child(_tytul)

	# "duchy" napisu: czerwone kopie za głównym napisem, drżą podczas glitcha
	_duch_a = _zrob_napis(tekst_tytulu, COL_DUCH)
	_duch_b = _zrob_napis(tekst_tytulu, Color(0.0, 0.18, 0.22, 0.55))
	for g in [_duch_a, _duch_b]:
		g.show_behind_parent = true
		g.set_anchors_preset(Control.PRESET_FULL_RECT)
		_tytul.add_child(g)

	_spacer = Control.new()
	_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_spacer)

	_st_norm = _styl(Color(0.09, 0.02, 0.02, 0.92), Color(0.42, 0.06, 0.05))
	_st_hover = _styl(Color(0.20, 0.035, 0.03, 0.96), Color(0.90, 0.16, 0.12))
	_st_press = _styl(Color(0.05, 0.01, 0.01, 0.96), Color(0.60, 0.09, 0.07))
	_st_off = _styl(Color(0.05, 0.04, 0.04, 0.8), Color(0.14, 0.10, 0.10))

	_przycisk = Button.new()
	_przycisk.text = tekst_przycisku
	_przycisk.focus_mode = Control.FOCUS_ALL
	_przycisk.disabled = true
	_przycisk.modulate.a = 0.0
	_przycisk.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_przycisk.add_theme_font_override("font", _font)
	_przycisk.add_theme_color_override("font_color", COL_TEKST)
	_przycisk.add_theme_color_override("font_hover_color", Color(1.0, 0.86, 0.80))
	_przycisk.add_theme_color_override("font_focus_color", Color(1.0, 0.86, 0.80))
	_przycisk.add_theme_color_override("font_pressed_color", COL_TYTUL)
	_przycisk.add_theme_color_override("font_disabled_color", Color(COL_TEKST, 0.35))
	_przycisk.add_theme_stylebox_override("normal", _st_norm)
	_przycisk.add_theme_stylebox_override("hover", _st_hover)
	_przycisk.add_theme_stylebox_override("focus", _st_hover)
	_przycisk.add_theme_stylebox_override("pressed", _st_press)
	_przycisk.add_theme_stylebox_override("disabled", _st_off)
	_przycisk.pressed.connect(_zresetuj)
	box.add_child(_przycisk)

	# czarna zasłona na wygaszenie przed wczytaniem sceny
	_czern = ColorRect.new()
	_czern.color = Color(0, 0, 0, 0)
	_czern.set_anchors_preset(Control.PRESET_FULL_RECT)
	_czern.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_czern)


func _zrob_napis(tekst: String, kolor: Color) -> Label:
	var l := Label.new()
	l.text = tekst
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.add_theme_font_override("font", _font)
	l.add_theme_color_override("font_color", kolor)
	l.add_theme_color_override("font_outline_color", Color(0.03, 0.0, 0.0, 0.95))
	return l


func _styl(tlo: Color, ramka: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = tlo
	s.border_color = ramka
	s.anti_aliasing = false
	return s


# Rozmiary liczone z wysokości okna, więc wygląda tak samo w każdej rozdzielczości
func _uklad() -> void:
	if _root == null:
		return
	var h := get_viewport().get_visible_rect().size.y
	var px := clampi(int(h * 0.17), 48, 280)
	_font.spacing_glyph = int(px * 0.06)

	for l in [_tytul, _duch_a, _duch_b]:
		l.add_theme_font_size_override("font_size", px)
	_tytul.add_theme_constant_override("outline_size", int(px * 0.07))
	_tytul.add_theme_color_override("font_shadow_color", Color(0.35, 0.0, 0.0, 0.8))
	_tytul.add_theme_constant_override("shadow_offset_x", int(px * 0.03))
	_tytul.add_theme_constant_override("shadow_offset_y", int(px * 0.05))

	_spacer.custom_minimum_size = Vector2(0, h * 0.09)

	var font_btn := clampi(int(h * 0.042), 18, 60)
	_przycisk.add_theme_font_size_override("font_size", font_btn)
	var ramka := maxi(int(h / 360.0), 1)
	for st in [_st_norm, _st_hover, _st_press, _st_off]:
		st.set_border_width_all(ramka)
		st.set_corner_radius_all(maxi(int(h * 0.004), 2))
		st.content_margin_left = int(font_btn * 1.6)
		st.content_margin_right = int(font_btn * 1.6)
		st.content_margin_top = int(font_btn * 0.5)
		st.content_margin_bottom = int(font_btn * 0.5)


# ---------- Pokazanie ----------

func pokaz() -> void:
	if _pokazany:
		return
	_pokazany = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if dzwiek != null:
		var sfx := AudioStreamPlayer.new()
		sfx.stream = dzwiek
		sfx.volume_db = glosnosc_db
		add_child(sfx)
		sfx.finished.connect(sfx.queue_free)
		sfx.play()

	_tytul.scale = Vector2(1.35, 1.35)   # napis "uderza" z powiększenia

	var tw := create_tween()
	tw.tween_property(self, "_sila_tla", 1.0, 1.6)
	tw.parallel().tween_property(self, "_alfa_tytulu", 1.0, 0.3).set_delay(0.9)
	tw.parallel().tween_property(_tytul, "scale", Vector2.ONE, 1.0) \
			.set_delay(0.9).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_przycisk, "modulate:a", 1.0, 0.8).set_delay(opoznienie_przycisku)

	await get_tree().create_timer(opoznienie_przycisku).timeout
	if not is_inside_tree() or _restart:
		return
	_przycisk.disabled = false
	_przycisk.grab_focus()   # Enter / Spacja też działają


# ---------- Animacja ----------

func _process(delta: float) -> void:
	if not _pokazany:
		return
	_czas += delta
	_mat.set_shader_parameter("sila", _sila_tla)
	_tytul.pivot_offset = _tytul.size * 0.5

	var px := float(_tytul.get_theme_font_size("font_size"))

	# rzadkie, krótkie glitche: napis drga, duchy się rozjeżdżają, kolor mruga
	if _glitch <= 0.0 and randf() < 0.012:
		_glitch = randf_range(0.05, 0.22)

	var alfa := _alfa_tytulu * (0.86 + 0.14 * sin(_czas * 7.0))
	var kolor := Color(1.0, 1.0, 1.0, alfa)
	var dx_a := sin(_czas * 1.3) * px * 0.012   # spokojny dryf duchów
	var dx_b := -sin(_czas * 1.1) * px * 0.012
	var dy := 0.0

	if _glitch > 0.0:
		_glitch -= delta
		var k := randf_range(0.35, 0.9)
		kolor = Color(1.0, k, k, alfa * randf_range(0.35, 1.0))
		dx_a = randf_range(-1.0, 1.0) * px * 0.07
		dx_b = randf_range(-1.0, 1.0) * px * 0.07
		dy = randf_range(-1.0, 1.0) * px * 0.025

	_tytul.modulate = kolor
	_przesun_ducha(_duch_a, dx_a, dy)
	_przesun_ducha(_duch_b, dx_b, -dy)

	# ramka przycisku lekko pulsuje
	if not _przycisk.disabled:
		var p := 0.5 + 0.5 * sin(_czas * 2.2)
		_st_norm.border_color = Color(0.42, 0.06, 0.05).lerp(Color(0.75, 0.11, 0.08), p)


func _przesun_ducha(duch: Label, dx: float, dy: float) -> void:
	duch.offset_left = dx
	duch.offset_right = dx
	duch.offset_top = dy
	duch.offset_bottom = dy


# ---------- Reset ----------

func _zresetuj() -> void:
	if _restart:
		return
	_restart = true
	_przycisk.disabled = true

	# ekwipunek to autoload i przeżywa zmianę sceny, więc czyścimy go jak przy nowej grze
	var inv := get_node_or_null("/root/Inventory")
	if inv != null and inv.has_method("reset"):
		inv.reset()

	var tw := create_tween()
	tw.tween_property(_czern, "color:a", 1.0, 0.6)
	await tw.finished

	if scena_gry != "" and ResourceLoader.exists(scena_gry):
		get_tree().change_scene_to_file(scena_gry)
	else:
		get_tree().reload_current_scene()
