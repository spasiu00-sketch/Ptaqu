extends Control

@export_file("*.tscn") var game_scene_path: String = "res://Scenes/start_game.tscn"   
@export var game_title: String = "PTAQU"
@export var subtitle: String = "NIE JESTEŚ SAM"
@export var move_sound: AudioStream
@export var select_sound: AudioStream
@export var dust_count: int = 70
@export var fog_count: int = 10
# wpisz swoją ścieżkę
const MAIN_ITEMS: Array[String] = ["NOWA GRA", "OPCJE", "WYJDŹ"]
const OPTIONS_COUNT := 3

# kolory jaśniejsze i czytelniejsze niż wcześniej
const COL_NORMAL := Color(0.78, 0.75, 0.70)
const COL_SELECTED := Color(0.93, 0.26, 0.20)
const COL_TITLE := Color(0.92, 0.89, 0.82)
const COL_BLOOD := Color(0.62, 0.07, 0.06)
const COL_SUB := Color(0.80, 0.16, 0.13)
const COL_FOOTER := Color(0.88, 0.85, 0.78)

# szkoła w tle: SCHOOL_X 0.5 = środek, 0.78 = przesunięta w prawo (nie koliduje z menu)
const SCHOOL_X := 0.5
const SCHOOL_SCALE := 0.9

enum Mode { MAIN, OPTIONS }

# Efekt PS2: pikselizacja, dithering, posteryzacja, scanlines, lekkie ziarno.
# Aberracja chromatyczna tylko na brzegach (wcześniej robiła kolorowe obwódki na tekście).
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

	// dithering Bayera + ograniczona paleta (look PS2)
	int i = (int(siatka.y) % 4) * 4 + (int(siatka.x) % 4);
	col += (M[i] / 16.0 - 0.5) / poziomy;
	col = floor(col * poziomy + 0.5) / poziomy;

	// ziarno
	col += (hash(siatka + floor(TIME * 24.0)) - 0.5) * grain;

	// scanlines
	col *= 0.95 + 0.05 * sin(SCREEN_UV.y * rozmiar.y * 3.14159);

	// winieta, łagodniejsza niż wcześniej
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
var _dust: Array = []
var _fog: Array = []
var _lit: Array = []
var _win_i: int = 0
var _time: float = 0.0
var _volume: int = 8
var _starting: bool = false
var _lamp_dip: float = 0.0
var _glitch_t: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	RenderingServer.set_default_clear_color(Color.BLACK)

	_volume = clampi(roundi(db_to_linear(AudioServer.get_bus_volume_db(0)) * 10.0), 0, 10)

	_sfx = AudioStreamPlayer.new()
	add_child(_sfx)

	_make_font()
	_build_ui()
	_build_post_effect()   # musi być ostatnim dzieckiem
	_build_atmosphere()
	_rebuild_menu()

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 2.0)


# ---------- Budowa interfejsu ----------

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

	# stopka: ciemny pasek + jasny, większy tekst (wcześniej była nieczytelna)
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

	# które okna szkoły się świecą (stałe przy każdym uruchomieniu)
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	for i in 120:
		_lit.append(rng.randf() < 0.10)


# ---------- Menu ----------

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
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 1.2)
	await tw.finished
	var err := get_tree().change_scene_to_file(game_scene_path)
	if err != OK:
		push_error("Menu Ptaqu: change_scene_to_file zwróciło błąd %d (%s)" % [err, game_scene_path])
		_starting = false
		modulate.a = 1.0


func _play(stream: AudioStream) -> void:
	if stream == null:
		return
	_sfx.stream = stream
	_sfx.play()


# ---------- Wejście ----------

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


# ---------- Animacja i tło ----------

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

	# awaria lampy: nagłe przygaszenie i powolny powrót (słabsze niż wcześniej)
	if randf() < 0.006:
		_lamp_dip = randf_range(0.25, 0.55)
	_lamp_dip = maxf(_lamp_dip - delta * 2.5, 0.0)
	var lamp := _lamp_level()

	# tytuł: migotanie + rzadki glitch
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

	# wybrana pozycja: żywe pulsowanie (z zapasem jasności, żeby nigdy nie znikała)
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

	# tło: nocne niebo przechodzące w bordową ziemię (jaśniejsze niż wcześniej)
	var top := Color(0.09, 0.10, 0.15)
	var bottom := Color(0.25, 0.09, 0.09)
	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0.0), s, Vector2(0.0, s.y)]),
		PackedColorArray([top, top, bottom, bottom]))

	# księżyc z poświatą
	var moon := Vector2(s.x * 0.2, s.y * 0.2)
	for k in 6:
		draw_circle(moon, s.y * (0.10 - k * 0.012), Color(0.7, 0.75, 0.9, 0.025))
	draw_circle(moon, s.y * 0.04, Color(0.82, 0.85, 0.92, 0.9))
	draw_circle(moon + Vector2(s.y * 0.012, -s.y * 0.006), s.y * 0.008, Color(0.65, 0.68, 0.78, 0.7))

	# stożek światła z żarówki wiszącej u góry (delikatniejszy)
	var cx := s.x * 0.5
	var a0 := 0.08 * lamp
	draw_polygon(
		PackedVector2Array([
			Vector2(cx - 24.0, 0.0), Vector2(cx + 24.0, 0.0),
			Vector2(cx + s.x * 0.40, s.y), Vector2(cx - s.x * 0.40, s.y)]),
		PackedColorArray([
			Color(0.8, 0.7, 0.55, a0), Color(0.8, 0.7, 0.55, a0),
			Color(0.5, 0.1, 0.08, 0.0), Color(0.5, 0.1, 0.08, 0.0)]))

	# czerwona poświata za tytułem
	var glow := Vector2(s.x * 0.5, s.y * 0.40)
	for k in 7:
		draw_circle(glow, s.y * (0.42 - k * 0.05), Color(0.55, 0.08, 0.06, 0.03 * lamp))

	_draw_school(s)

	# mgła: warstwowe miękkie koła (na wierzchu szkoły)
	for f in _fog:
		var pos: Vector2 = f["p"] + Vector2(0.0, sin(_time * 0.3 + f["ph"]) * 20.0)
		var r: float = f["r"]
		for k in 6:
			draw_circle(pos, r * (1.0 - k * 0.14), Color(0.38, 0.22, 0.22, 0.02))

	# pył w powietrzu
	for p in _dust:
		var pos: Vector2 = p["p"] + Vector2(sin(_time * 0.5 + p["ph"]) * 10.0, 0.0)
		var a := (0.08 + 0.20 * (0.5 + 0.5 * sin(_time * 1.1 + p["ph"]))) * lamp
		var sz: float = p["s"]
		draw_circle(pos, sz, Color(0.80, 0.74, 0.68, a))


# ---------- Szkoła w tle ----------

func _draw_school(s: Vector2) -> void:
	_win_i = 0
	var u := s.y * SCHOOL_SCALE
	var cx := s.x * SCHOOL_X
	var ground := s.y * 0.95
	var sil := Color(0.04, 0.035, 0.06)

	var c_w := u * 0.55   # część środkowa
	var c_h := u * 0.19
	var w_w := u * 0.40   # skrzydła
	var w_h := u * 0.13

	var center := Rect2(cx - c_w * 0.5, ground - c_h, c_w, c_h)
	var left := Rect2(center.position.x - w_w, ground - w_h, w_w, w_h)
	var right := Rect2(center.end.x, ground - w_h, w_w, w_h)

	# bryły
	draw_rect(left, sil)
	draw_rect(right, sil)
	draw_rect(center, sil)

	# dachy (niskie, trójkątne)
	for r in [left, right]:
		draw_colored_polygon(PackedVector2Array([
			Vector2(r.position.x - 8.0, r.position.y),
			Vector2(r.position.x + r.size.x * 0.5, r.position.y - u * 0.03),
			Vector2(r.end.x + 8.0, r.position.y)]), sil)
	draw_colored_polygon(PackedVector2Array([
		Vector2(center.position.x - 8.0, center.position.y),
		Vector2(center.position.x + center.size.x * 0.5, center.position.y - u * 0.04),
		Vector2(center.end.x + 8.0, center.position.y)]), sil)

	# wieża zegarowa
	var tower := Rect2(cx - u * 0.05, center.position.y - u * 0.13, u * 0.10, u * 0.14)
	draw_rect(tower, sil)
	draw_colored_polygon(PackedVector2Array([
		Vector2(tower.position.x - u * 0.012, tower.position.y),
		Vector2(cx, tower.position.y - u * 0.07),
		Vector2(tower.end.x + u * 0.012, tower.position.y)]), sil)

	# zegar (stoi na tej samej godzinie, niepokojące)
	var clock := Vector2(cx, tower.position.y + tower.size.y * 0.42)
	draw_circle(clock, u * 0.026, Color(0.62, 0.58, 0.50, 0.9))
	draw_line(clock, clock + Vector2(0.0, -u * 0.019), Color(0.05, 0.04, 0.05), 2.0)
	draw_line(clock, clock + Vector2(u * 0.012, u * 0.006), Color(0.05, 0.04, 0.05), 2.0)

	# okna
	_draw_windows(Rect2(left.position.x + u * 0.01, left.position.y + u * 0.015,
		left.size.x - u * 0.02, left.size.y - u * 0.03), 2, 5, sil)
	_draw_windows(Rect2(right.position.x + u * 0.01, right.position.y + u * 0.015,
		right.size.x - u * 0.02, right.size.y - u * 0.03), 2, 5, sil)
	_draw_windows(Rect2(center.position.x + u * 0.01, center.position.y + u * 0.015,
		center.size.x - u * 0.02, center.size.y * 0.62), 2, 7, sil)

	# drzwi wejściowe
	draw_rect(Rect2(cx - u * 0.02, ground - u * 0.065, u * 0.04, u * 0.065), Color(0.015, 0.01, 0.02))

	# teren
	draw_rect(Rect2(0.0, ground, s.x, s.y - ground), Color(0.035, 0.03, 0.045))

	# płot
	var fence := Color(0.05, 0.045, 0.065)
	var fx0 := cx - u * 0.80
	var fx1 := cx + u * 0.80
	draw_rect(Rect2(fx0, ground - u * 0.035, fx1 - fx0, 3.0), fence)
	var x := fx0
	while x < fx1:
		draw_rect(Rect2(x, ground - u * 0.05, 3.0, u * 0.05), fence)
		x += u * 0.014


func _draw_windows(r: Rect2, rows: int, cols: int, sil: Color) -> void:
	var cw := r.size.x / cols
	var ch := r.size.y / rows
	for y in rows:
		for x in cols:
			var w := Rect2(r.position.x + x * cw + cw * 0.2, r.position.y + y * ch + ch * 0.18,
				cw * 0.6, ch * 0.64)
			var col := Color(0.11, 0.11, 0.16)
			var lit: bool = _lit[_win_i % _lit.size()]
			if lit:
				var a := 0.8 + 0.2 * sin(_time * 6.0 + _win_i * 2.3)
				if fmod(_time + _win_i * 1.7, 11.0) < 0.2:
					a = 0.0   # okno co jakiś czas gaśnie
				col = col.lerp(Color(0.92, 0.72, 0.38), a)
				if a > 0.3:
					draw_rect(w.grow(cw * 0.12), Color(0.9, 0.6, 0.25, 0.10 * a))
			draw_rect(w, col)
			# ramy okien
			draw_line(Vector2(w.position.x + w.size.x * 0.5, w.position.y),
				Vector2(w.position.x + w.size.x * 0.5, w.end.y), sil, 1.5)
			draw_line(Vector2(w.position.x, w.position.y + w.size.y * 0.5),
				Vector2(w.end.x, w.position.y + w.size.y * 0.5), sil, 1.5)
			_win_i += 1
