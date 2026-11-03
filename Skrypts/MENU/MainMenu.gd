class_name MainMenu
extends Control

@export_file("*.tscn") var game_scene_path: String = "res://Scenes/start_game.tscn"
@export var game_title: String = "PTAQU"
@export var subtitle: String = "NIE JESTEŚ SAM"
@export var move_sound: AudioStream
@export var select_sound: AudioStream
@export var dust_count: int = 70
@export var fog_count: int = 10

@export_group("Muzyka")
@export var muzyka: AudioStream
@export_range(-40.0, 6.0, 0.5) var muzyka_glosnosc_db: float = -6.0
@export var muzyka_fade_in: float = 3.0
@export_group("")

const MAIN_ITEMS: Array[String] = ["NOWA GRA", "OPCJE", "WYJDŹ"]
const OPTIONS_COUNT := 3

const COL_NORMAL := Color(0.78, 0.75, 0.70)
const COL_SELECTED := Color(0.93, 0.26, 0.20)
const COL_TITLE := Color(0.92, 0.89, 0.82)
const COL_BLOOD := Color(0.62, 0.07, 0.06)
const COL_SUB := Color(0.80, 0.16, 0.13)
const COL_FOOTER := Color(0.88, 0.85, 0.78)

const SIL := Color(0.04, 0.035, 0.06)
const WIN_DARK := Color(0.11, 0.11, 0.16)
const WIN_LIT := Color(0.92, 0.72, 0.38)
const FENCE := Color(0.05, 0.045, 0.065)

const SCHOOL_X := 0.5
const SCHOOL_SCALE := 0.9

enum Mode { MAIN, OPTIONS }

const POST_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float piksel = 2.0;
uniform float poziomy = 40.0;
uniform float grain = 0.035;
uniform float vignette = 0.9;
uniform float aberration = 0.0012;
uniform float desaturate = 0.15;
uniform float jasnosc = 1.12;

const float M[16] = float[16](0.0, 8.0, 2.0, 10.0,
							  12.0, 4.0, 14.0, 6.0,
							  3.0, 11.0, 1.0, 9.0,
							  15.0, 7.0, 13.0, 5.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 rozmiar = vec2(textureSize(screen_tex, 0));
	vec2 siatka = floor(SCREEN_UV * rozmiar / piksel);
	vec2 uv = (siatka + 0.5) * piksel / rozmiar;

	vec2 dir = SCREEN_UV - 0.5;
	float d2 = dot(dir, dir);

	float ab = aberration * smoothstep(0.08, 0.35, d2);
	vec3 col;
	col.r = texture(screen_tex, uv + vec2(ab, 0.0)).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - vec2(ab, 0.0)).b;

	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), desaturate);
	col *= jasnosc;

	int i = (int(siatka.y) % 4) * 4 + (int(siatka.x) % 4);
	col += (M[i] / 16.0 - 0.5) / poziomy;
	col = floor(col * poziomy + 0.5) / poziomy;

	col += (hash(siatka + floor(TIME * 24.0)) - 0.5) * grain;

	col *= 0.95 + 0.05 * sin(SCREEN_UV.y * rozmiar.y * 3.14159);

	col *= clamp(1.0 - d2 * vignette, 0.0, 1.0);

	COLOR = vec4(col, 1.0);
}
"""

var _mode: Mode = Mode.MAIN
var _index: int = 0
var _labels: Array[Label] = []
var _menu_box: VBoxContainer
var _title: Label
var _font: FontVariation
var _sfx: AudioStreamPlayer
var _music: AudioStreamPlayer
var _music_tween: Tween
var _dust: Array = []
var _fog: Array = []
var _lit: Array = []
var _time: float = 0.0
var _volume: int = 8
var _starting: bool = false
var _lamp_dip: float = 0.0
var _glitch_t: float = 0.0

var _vp_back: SubViewport
var _vp_front: SubViewport
var _bake_layers: Array[Control] = []
var _bake_pending: bool = false
var _windows: Array[Dictionary] = []
var _lit_windows: Array[Dictionary] = []

var _loading_layer: CanvasLayer
var _loading_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	RenderingServer.set_default_clear_color(Color.BLACK)

	_volume = clampi(roundi(db_to_linear(AudioServer.get_bus_volume_db(0)) * 10.0), 0, 10)

	_sfx = AudioStreamPlayer.new()
	add_child(_sfx)
	_start_music()

	_make_font()
	_build_ui()
	_build_post_effect()
	_build_atmosphere()
	_build_bake_layers()
	_rebuild_menu()

	resized.connect(_schedule_bake)
	_schedule_bake()

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 2.0)


func _make_font() -> void:
	var base := SystemFont.new()
	base.font_names = PackedStringArray(
		["Georgia", "Palatino Linotype", "Times New Roman", "DejaVu Serif", "serif"])
	base.font_weight = 700
	base.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	base.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	base.generate_mipmaps = true
	_font = FontVariation.new()
	_font.base_font = base
	_font.spacing_glyph = 5


func _make_label(text: String, font_size: int, color: Color, shadow: Color = Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.03, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_shadow_color", shadow)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 90)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var root := VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 10)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(root)

	_title = _make_label(game_title, 120, COL_TITLE, COL_BLOOD)
	_title.add_theme_constant_override("shadow_offset_x", 5)
	_title.add_theme_constant_override("shadow_offset_y", 5)
	root.add_child(_title)
	if subtitle != "":
		root.add_child(_make_label(subtitle, 22, COL_SUB))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 60)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(spacer)

	_menu_box = VBoxContainer.new()
	_menu_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_box.add_theme_constant_override("separation", 14)
	_menu_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_menu_box)

	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.6)
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -64.0
	bar.offset_bottom = 0.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	var footer := _make_label(
		"STRZAŁKI / W S — WYBÓR        ENTER — ZATWIERDŹ        ESC — WSTECZ", 20, COL_FOOTER)
	footer.add_theme_constant_override("outline_size", 4)
	footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -64.0
	footer.offset_bottom = 0.0
	footer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(footer)


func _build_post_effect() -> void:
	var shader := Shader.new()
	shader.code = POST_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = mat
	add_child(rect)


func _build_atmosphere() -> void:
	var s := get_viewport_rect().size
	for i in dust_count:
		_dust.append({
			"p": Vector2(randf() * s.x, randf() * s.y),
			"v": randf_range(4.0, 16.0),
			"s": randf_range(0.8, 2.6),
			"ph": randf() * TAU
		})
	for i in fog_count:
		_fog.append({
			"p": Vector2(randf() * s.x, randf_range(s.y * 0.3, s.y * 1.05)),
			"r": randf_range(180.0, 380.0),
			"v": randf_range(5.0, 14.0) * (1.0 if randf() > 0.5 else -1.0),
			"ph": randf() * TAU
		})

	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	for i in 120:
		_lit.append(rng.randf() < 0.10)


func _build_bake_layers() -> void:
	_vp_back = _make_bake_viewport(_draw_back, false)
	_vp_front = _make_bake_viewport(_draw_front, true)


func _make_bake_viewport(draw_fn: Callable, transparent: bool) -> SubViewport:
	var vp := SubViewport.new()
	vp.transparent_bg = transparent
	vp.disable_3d = true
	vp.size = Vector2i(2, 2)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)

	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp.add_child(layer)
	layer.draw.connect(draw_fn.bind(layer))
	_bake_layers.append(layer)
	return vp


func _schedule_bake() -> void:
	if _bake_pending:
		return
	_bake_pending = true
	_bake.call_deferred()


func _bake() -> void:
	_bake_pending = false
	var s := size
	if s.x < 2.0 or s.y < 2.0:
		return

	_build_windows(s)

	var px := Vector2i(roundi(s.x), roundi(s.y))
	for vp: SubViewport in [_vp_back, _vp_front]:
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.size = px
	for layer in _bake_layers:
		layer.queue_redraw()

	await get_tree().process_frame
	for vp: SubViewport in [_vp_back, _vp_front]:
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _draw_back(c: CanvasItem) -> void:
	var s := size

	var top := Color(0.09, 0.10, 0.15)
	var bottom := Color(0.25, 0.09, 0.09)
	c.draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0.0), s, Vector2(0.0, s.y)]),
		PackedColorArray([top, top, bottom, bottom]))

	var moon := Vector2(s.x * 0.2, s.y * 0.2)
	for k in 6:
		c.draw_circle(moon, s.y * (0.10 - k * 0.012), Color(0.7, 0.75, 0.9, 0.025))
	c.draw_circle(moon, s.y * 0.04, Color(0.82, 0.85, 0.92, 0.9))
	c.draw_circle(moon + Vector2(s.y * 0.012, -s.y * 0.006), s.y * 0.008, Color(0.65, 0.68, 0.78, 0.7))


func _draw_front(c: CanvasItem) -> void:
	var s := size
	var g := _school_geometry(s)
	var u: float = g["u"]
	var cx: float = g["cx"]
	var ground: float = g["ground"]
	var center: Rect2 = g["center"]
	var left: Rect2 = g["left"]
	var right: Rect2 = g["right"]

	c.draw_rect(left, SIL)
	c.draw_rect(right, SIL)
	c.draw_rect(center, SIL)

	for r: Rect2 in [left, right]:
		c.draw_colored_polygon(PackedVector2Array([
			Vector2(r.position.x - 8.0, r.position.y),
			Vector2(r.position.x + r.size.x * 0.5, r.position.y - u * 0.03),
			Vector2(r.end.x + 8.0, r.position.y)]), SIL)
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(center.position.x - 8.0, center.position.y),
		Vector2(center.position.x + center.size.x * 0.5, center.position.y - u * 0.04),
		Vector2(center.end.x + 8.0, center.position.y)]), SIL)

	var tower := Rect2(cx - u * 0.05, center.position.y - u * 0.13, u * 0.10, u * 0.14)
	c.draw_rect(tower, SIL)
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(tower.position.x - u * 0.012, tower.position.y),
		Vector2(cx, tower.position.y - u * 0.07),
		Vector2(tower.end.x + u * 0.012, tower.position.y)]), SIL)

	var clock := Vector2(cx, tower.position.y + tower.size.y * 0.42)
	c.draw_circle(clock, u * 0.026, Color(0.62, 0.58, 0.50, 0.9))
	c.draw_line(clock, clock + Vector2(0.0, -u * 0.019), Color(0.05, 0.04, 0.05), 2.0)
	c.draw_line(clock, clock + Vector2(u * 0.012, u * 0.006), Color(0.05, 0.04, 0.05), 2.0)

	for win in _windows:
		_draw_window(c, win["w"], WIN_DARK)

	c.draw_rect(Rect2(cx - u * 0.02, ground - u * 0.065, u * 0.04, u * 0.065), Color(0.015, 0.01, 0.02))

	c.draw_rect(Rect2(0.0, ground, s.x, s.y - ground), Color(0.035, 0.03, 0.045))

	var fx0 := cx - u * 0.80
	var fx1 := cx + u * 0.80
	c.draw_rect(Rect2(fx0, ground - u * 0.035, fx1 - fx0, 3.0), FENCE)
	var x := fx0
	while x < fx1:
		c.draw_rect(Rect2(x, ground - u * 0.05, 3.0, u * 0.05), FENCE)
		x += u * 0.014


func _school_geometry(s: Vector2) -> Dictionary:
	var u := s.y * SCHOOL_SCALE
	var cx := s.x * SCHOOL_X
	var ground := s.y * 0.95

	var c_w := u * 0.55
	var c_h := u * 0.19
	var w_w := u * 0.40
	var w_h := u * 0.13

	var center := Rect2(cx - c_w * 0.5, ground - c_h, c_w, c_h)
	var left := Rect2(center.position.x - w_w, ground - w_h, w_w, w_h)
	var right := Rect2(center.end.x, ground - w_h, w_w, w_h)
	return {"u": u, "cx": cx, "ground": ground, "center": center, "left": left, "right": right}


func _build_windows(s: Vector2) -> void:
	_windows.clear()
	_lit_windows.clear()

	var g := _school_geometry(s)
	var u: float = g["u"]
	var center: Rect2 = g["center"]
	var left: Rect2 = g["left"]
	var right: Rect2 = g["right"]

	var regions: Array = [
		[Rect2(left.position.x + u * 0.01, left.position.y + u * 0.015,
			left.size.x - u * 0.02, left.size.y - u * 0.03), 2, 5],
		[Rect2(right.position.x + u * 0.01, right.position.y + u * 0.015,
			right.size.x - u * 0.02, right.size.y - u * 0.03), 2, 5],
		[Rect2(center.position.x + u * 0.01, center.position.y + u * 0.015,
			center.size.x - u * 0.02, center.size.y * 0.62), 2, 7],
	]

	var idx := 0
	for reg in regions:
		var r: Rect2 = reg[0]
		var rows: int = reg[1]
		var cols: int = reg[2]
		var cw := r.size.x / cols
		var ch := r.size.y / rows
		for y in rows:
			for x in cols:
				var w := Rect2(r.position.x + x * cw + cw * 0.2, r.position.y + y * ch + ch * 0.18,
					cw * 0.6, ch * 0.64)
				var entry := {"w": w, "cw": cw, "i": idx}
				_windows.append(entry)
				if _lit[idx % _lit.size()]:
					_lit_windows.append(entry)
				idx += 1


func _draw_window(c: CanvasItem, w: Rect2, col: Color) -> void:
	c.draw_rect(w, col)
	c.draw_line(Vector2(w.position.x + w.size.x * 0.5, w.position.y),
		Vector2(w.position.x + w.size.x * 0.5, w.end.y), SIL, 1.5)
	c.draw_line(Vector2(w.position.x, w.position.y + w.size.y * 0.5),
		Vector2(w.end.x, w.position.y + w.size.y * 0.5), SIL, 1.5)


func _rebuild_menu() -> void:
	for c in _menu_box.get_children():
		c.queue_free()
	_labels.clear()

	var count := MAIN_ITEMS.size() if _mode == Mode.MAIN else OPTIONS_COUNT
	for i in count:
		var l := _make_label("", 38, COL_NORMAL)
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.mouse_entered.connect(_select.bind(i))
		l.gui_input.connect(_on_label_input.bind(i))
		_menu_box.add_child(l)
		_labels.append(l)

	_index = clampi(_index, 0, count - 1)
	_refresh()


func _item_text(i: int) -> String:
	if _mode == Mode.MAIN:
		return MAIN_ITEMS[i]
	match i:
		0:
			return "GŁOŚNOŚĆ    <  %d  >" % _volume
		1:
			return "PEŁNY EKRAN:  %s" % ("TAK" if _is_fullscreen() else "NIE")
		_:
			return "WSTECZ"


func _refresh() -> void:
	for i in _labels.size():
		var sel := i == _index
		_labels[i].text = ("»  %s  «" % _item_text(i)) if sel else _item_text(i)
		_labels[i].add_theme_color_override("font_color", COL_SELECTED if sel else COL_NORMAL)
		_labels[i].add_theme_color_override(
			"font_shadow_color", Color(0.5, 0.0, 0.0, 0.8) if sel else Color(0, 0, 0, 0))


func _select(i: int) -> void:
	if _starting or i == _index or i >= _labels.size():
		return
	_index = i
	_play(move_sound)
	_refresh()


func _on_label_input(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_index = i
		_refresh()
		_activate()


func _activate() -> void:
	if _starting:
		return
	_play(select_sound)
	if _mode == Mode.MAIN:
		match _index:
			0: _start_game()
			1:
				_mode = Mode.OPTIONS
				_index = 0
				_rebuild_menu()
			2: get_tree().quit()
	else:
		match _index:
			0: _adjust(1)
			1: _adjust(1)
			2: _go_main()


func _adjust(dir: int) -> void:
	if _mode != Mode.OPTIONS:
		return
	if _index == 0:
		_volume = clampi(_volume + dir, 0, 10)
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(_volume / 10.0, 0.0001)))
	elif _index == 1:
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_WINDOWED if _is_fullscreen() else DisplayServer.WINDOW_MODE_FULLSCREEN)
	_play(move_sound)
	_refresh()


func _go_main() -> void:
	_mode = Mode.MAIN
	_index = 1
	_rebuild_menu()


func _is_fullscreen() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func _start_game() -> void:
	if game_scene_path == "" or not ResourceLoader.exists(game_scene_path):
		push_error("Menu Ptaqu: nie znaleziono sceny gry: '%s'" % game_scene_path)
		return

	_starting = true

	var err := ResourceLoader.load_threaded_request(game_scene_path)
	if err != OK:
		push_error("Menu Ptaqu: load_threaded_request zwróciło błąd %d (%s)" % [err, game_scene_path])
		_starting = false
		return

	_fade_music(-60.0, 1.2)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 1.2)
	await tw.finished

	var progress: Array = []
	while true:
		var status := ResourceLoader.load_threaded_get_status(game_scene_path, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			push_error("Menu Ptaqu: ładowanie sceny nie powiodło się (status %d, %s)" % [status, game_scene_path])
			_hide_loading()
			_starting = false
			modulate.a = 1.0
			_fade_music(muzyka_glosnosc_db, 0.5)
			return
		if _loading_layer == null:
			_show_loading()
		var percent := int(progress[0] * 100.0) if not progress.is_empty() else 0
		_loading_label.text = "ŁADOWANIE  %d%%" % percent
		await get_tree().process_frame

	var packed := ResourceLoader.load_threaded_get(game_scene_path) as PackedScene
	if packed == null:
		push_error("Menu Ptaqu: wczytany zasób nie jest sceną: '%s'" % game_scene_path)
		_hide_loading()
		_starting = false
		modulate.a = 1.0
		_fade_music(muzyka_glosnosc_db, 0.5)
		return

	get_tree().change_scene_to_packed(packed)


func _show_loading() -> void:
	_loading_layer = CanvasLayer.new()
	_loading_layer.layer = 100
	add_child(_loading_layer)

	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_layer.add_child(bg)

	_loading_label = _make_label("ŁADOWANIE  0%", 28, COL_NORMAL)
	_loading_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading_layer.add_child(_loading_label)


func _hide_loading() -> void:
	if _loading_layer != null:
		_loading_layer.queue_free()
	_loading_layer = null
	_loading_label = null


func _start_music() -> void:
	if muzyka == null:
		return
	_music = AudioStreamPlayer.new()
	_music.name = "MuzykaMenu"
	_music.stream = muzyka
	_music.volume_db = -60.0
	add_child(_music)

	if not _loop_stream(muzyka):
		_music.finished.connect(_music.play)
	_music.play()
	_fade_music(muzyka_glosnosc_db, maxf(muzyka_fade_in, 0.01))


func _loop_stream(stream: AudioStream) -> bool:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
		return true
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
		return true
	return false


func _fade_music(target_db: float, czas: float) -> void:
	if _music == null:
		return
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", target_db, czas)


func _play(stream: AudioStream) -> void:
	if stream == null:
		return
	_sfx.stream = stream
	_sfx.play()


func _key(event: InputEvent, keycode: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == keycode


func _unhandled_input(event: InputEvent) -> void:
	if _starting:
		return

	if event.is_action_pressed("ui_down") or _key(event, KEY_S):
		_select((_index + 1) % _labels.size())
	elif event.is_action_pressed("ui_up") or _key(event, KEY_W):
		_select((_index - 1 + _labels.size()) % _labels.size())
	elif event.is_action_pressed("ui_accept"):
		_activate()
	elif event.is_action_pressed("ui_left") or _key(event, KEY_A):
		_adjust(-1)
	elif event.is_action_pressed("ui_right") or _key(event, KEY_D):
		_adjust(1)
	elif event.is_action_pressed("ui_cancel") and _mode == Mode.OPTIONS:
		_go_main()


func _lamp_level() -> float:
	return clampf(0.88 + 0.07 * sin(_time * 2.3) - _lamp_dip, 0.05, 1.0)


func _process(delta: float) -> void:
	_time += delta
	var s := size

	for p in _dust:
		var pos: Vector2 = p["p"]
		pos.y -= p["v"] * delta
		if pos.y < -10.0:
			pos = Vector2(randf() * s.x, s.y + 10.0)
		p["p"] = pos

	for f in _fog:
		var pos: Vector2 = f["p"]
		pos.x += f["v"] * delta
		if pos.x > s.x + 400.0:
			pos.x = -400.0
		elif pos.x < -400.0:
			pos.x = s.x + 400.0
		f["p"] = pos

	if randf() < 0.006:
		_lamp_dip = randf_range(0.25, 0.55)
	_lamp_dip = maxf(_lamp_dip - delta * 2.5, 0.0)
	var lamp := _lamp_level()

	if _glitch_t <= 0.0 and randf() < 0.004:
		_glitch_t = randf_range(0.06, 0.22)
	if _glitch_t > 0.0:
		_glitch_t -= delta
		var k := randf_range(0.4, 0.9)
		_title.modulate = Color(1.0, k, k)
		_title.add_theme_constant_override("shadow_offset_x", randi_range(-10, 10))
		_title.add_theme_constant_override("shadow_offset_y", randi_range(-4, 6))
	else:
		_title.modulate = Color(lamp, lamp, lamp)
		_title.add_theme_constant_override("shadow_offset_x", 5)
		_title.add_theme_constant_override("shadow_offset_y", 5)

	for i in _labels.size():
		if i == _index:
			var flick := 0.85 + 0.15 * sin(_time * 3.0) + randf_range(-0.03, 0.03)
			_labels[i].modulate.a = clampf(flick * lamp + 0.15, 0.0, 1.0)
		else:
			_labels[i].modulate.a = 1.0

	queue_redraw()


func _draw() -> void:
	var s := size
	var lamp := _lamp_level()
	var full := Rect2(Vector2.ZERO, s)

	if _vp_back != null:
		draw_texture_rect(_vp_back.get_texture(), full, false)

	var cx := s.x * 0.5
	var a0 := 0.08 * lamp
	draw_polygon(
		PackedVector2Array([
			Vector2(cx - 24.0, 0.0), Vector2(cx + 24.0, 0.0),
			Vector2(cx + s.x * 0.40, s.y), Vector2(cx - s.x * 0.40, s.y)]),
		PackedColorArray([
			Color(0.8, 0.7, 0.55, a0), Color(0.8, 0.7, 0.55, a0),
			Color(0.5, 0.1, 0.08, 0.0), Color(0.5, 0.1, 0.08, 0.0)]))

	var glow := Vector2(s.x * 0.5, s.y * 0.40)
	for k in 7:
		draw_circle(glow, s.y * (0.42 - k * 0.05), Color(0.55, 0.08, 0.06, 0.03 * lamp))

	if _vp_front != null:
		draw_texture_rect(_vp_front.get_texture(), full, false)

	for win in _lit_windows:
		var w: Rect2 = win["w"]
		var cw: float = win["cw"]
		var i: int = win["i"]
		var a := 0.8 + 0.2 * sin(_time * 6.0 + i * 2.3)
		if fmod(_time + i * 1.7, 11.0) < 0.2:
			a = 0.0
		if a > 0.3:
			draw_rect(w.grow(cw * 0.12), Color(0.9, 0.6, 0.25, 0.10 * a))
		_draw_window(self, w, WIN_DARK.lerp(WIN_LIT, a))

	for f in _fog:
		var pos: Vector2 = f["p"] + Vector2(0.0, sin(_time * 0.3 + f["ph"]) * 20.0)
		var r: float = f["r"]
		for k in 6:
			draw_circle(pos, r * (1.0 - k * 0.14), Color(0.38, 0.22, 0.22, 0.02))

	for p in _dust:
		var pos: Vector2 = p["p"] + Vector2(sin(_time * 0.5 + p["ph"]) * 10.0, 0.0)
		var a := (0.08 + 0.20 * (0.5 + 0.5 * sin(_time * 1.1 + p["ph"]))) * lamp
		var sz: float = p["s"]
		draw_circle(pos, sz, Color(0.80, 0.74, 0.68, a))
