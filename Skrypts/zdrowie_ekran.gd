class_name EkranZdrowia
extends CanvasLayer
# Nakładka na obraz: im mniej życia, tym ciemniejsze brzegi ekranu, odbarwienie,
# rozmazanie obrazu i pulsowanie (jak w Battlefroncie / Callu of Duty).
# Rysuje też rozmazanie ze zmęczenia (sprint), żeby cały efekt był JEDNYM odczytem ekranu.
# Tworzy ją gracz (character_body_3d.gd). Sterowanie:
#   ustaw_natezenie(0..1)  - 0 = pełne życie, 1 = prawie martwy
#   ustaw_zmeczenie(0..1)  - 0 = wypoczęty, 1 = na limicie wytrzymałości
#   blysk_obrazen()        - krótki czerwony błysk po trafieniu
#   smierc()               - ekran stopniowo robi się czarny

@export var plynnosc: float = 3.0           # jak szybko ekran dochodzi do docelowego natężenia
@export var pulsowanie: bool = true         # pulsowanie winiety i rozmazania (jak oddech / serce)
@export var kolor_krwi: Color = Color(0.45, 0.0, 0.0)
@export var szybkosc_czernienia: float = 0.6   # po śmierci: jak szybko ekran robi się czarny

@export_group("Rozmazanie")
@export var rozmycie_wlaczone: bool = true
@export var rozmycie_lod: float = 3.0       # maksymalny poziom mipmapy przy rozmazaniu z życia (3 ~ promień 7-8 px)
@export_range(0.0, 1.0, 0.01) var rozmycie_start: float = 0.15   # od jakiego natężenia zaczyna się rozmazanie

# Rozmazanie = jedna próbka z mipmapy ekranu (zamiast 17 próbek na piksel)
const SHADER_CODE := """
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float death : hint_range(0.0, 1.0) = 0.0;
uniform float blur : hint_range(0.0, 1.0) = 0.0;
uniform float fatigue : hint_range(0.0, 1.0) = 0.0;
uniform float blur_lod = 3.0;
uniform vec3 blood_color : source_color = vec3(0.45, 0.0, 0.0);

void fragment() {
	vec2 uv = SCREEN_UV;

	// odległość od środka: 0 = środek, 1 = róg ekranu
	float d = length(uv - 0.5) * 1.41421;
	float dc = distance(uv, vec2(0.5));

	// poziom rozmazania: z życia (mocniejsze na brzegach, pulsuje) albo ze zmęczenia, bierzemy większy
	float lod = 0.0;
	if (blur > 0.001) {
		lod = blur * blur_lod * (0.4 + 0.9 * d) * (1.0 + 0.4 * pulse);
	}
	if (fatigue > 0.001) {
		lod = max(lod, fatigue * 3.5 * (0.4 + dc * 1.2));
	}
	vec3 col = textureLod(screen_tex, uv, lod).rgb;

	// winieta ze zmęczenia
	col *= 1.0 - smoothstep(0.35, 0.9, dc) * fatigue * 0.6;

	// im większe intensity, tym bliżej środka zaczyna się ciemność
	float start = mix(1.0, 0.0, intensity);
	float v = smoothstep(start, start + 0.7, d);

	// odbarwienie i ogólne przyciemnienie
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), intensity * 0.75);
	col *= 1.0 - intensity * 0.35;

	// czerwonawy odcień na brzegach
	col = mix(col, blood_color, v * intensity * 0.45);

	// ciemna winieta (pulsuje razem z sercem)
	float dark = clamp(v * (0.45 + 0.5 * intensity) * (1.0 + 0.3 * pulse), 0.0, 1.0);
	col *= 1.0 - dark;

	// błysk po otrzymaniu obrażeń
	col = mix(col, blood_color * 1.6, flash * 0.4 * smoothstep(0.15, 1.0, d));

	// śmierć: wszystko do czerni
	col *= 1.0 - death;

	COLOR = vec4(col, 1.0);
}
"""

var _rect: ColorRect
var _kopia: BackBufferCopy
var _mat: ShaderMaterial
var _cel: float = 0.0
var _aktualne: float = 0.0
var _zmeczenie: float = 0.0
var _blysk: float = 0.0
var _smierc: float = 0.0
var _martwy: bool = false
var _czas: float = 0.0
var _aktywna: bool = false


func _ready() -> void:
	layer = 1   # pod HUD (2), ekwipunkiem (3) i jumpscare (100+)

	var shader := Shader.new()
	shader.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("blood_color", Vector3(kolor_krwi.r, kolor_krwi.g, kolor_krwi.b))
	_mat.set_shader_parameter("blur_lod", rozmycie_lod)

	# Bez tego kolejna nakładka z hint_screen_texture nie widzi wyniku poprzedniej
	# (Godot kopiuje ekran tylko raz). Włączony tylko, gdy nakładka jest widoczna.
	_kopia = BackBufferCopy.new()
	_kopia.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_kopia.visible = false
	add_child(_kopia)

	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)


# natezenie: 0.0 (pełne życie) ... 1.0 (prawie martwy). natychmiast = bez płynnego przejścia
func ustaw_natezenie(natezenie: float, natychmiast: bool = false) -> void:
	_cel = clampf(natezenie, 0.0, 1.0)
	if natychmiast:
		_aktualne = _cel


# sila: 0.0 (wypoczęty) ... 1.0 (na limicie wytrzymałości)
func ustaw_zmeczenie(sila: float) -> void:
	_zmeczenie = clampf(sila, 0.0, 1.0)


func blysk_obrazen() -> void:
	_blysk = 1.0


func smierc() -> void:
	_martwy = true


func _process(delta: float) -> void:
	_czas += delta
	_aktualne = lerpf(_aktualne, _cel, 1.0 - exp(-plynnosc * delta))
	_blysk = move_toward(_blysk, 0.0, delta * 2.5)
	if _martwy:
		_smierc = move_toward(_smierc, 1.0, delta * szybkosc_czernienia)

	# nic do rysowania = wyłączamy nakładkę (oszczędność: brak odczytu ekranu)
	var aktywna := _aktualne > 0.002 or _blysk > 0.0 or _smierc > 0.0 or _zmeczenie > 0.01
	if aktywna != _aktywna:
		_aktywna = aktywna
		_rect.visible = aktywna
		_kopia.visible = aktywna
	if not aktywna:
		return

	# tempo "serca / oddechu" rośnie, im mniej życia
	var puls := 0.0
	if pulsowanie:
		var tempo := lerpf(1.5, 4.5, _aktualne)
		puls = (0.5 + 0.5 * sin(_czas * tempo * TAU * 0.5)) * _aktualne

	# rozmazanie zaczyna się dopiero po przekroczeniu progu i narasta do maksimum
	var rozmycie := 0.0
	if rozmycie_wlaczone:
		rozmycie = smoothstep(rozmycie_start, 1.0, _aktualne)

	_mat.set_shader_parameter("intensity", _aktualne)
	_mat.set_shader_parameter("pulse", puls)
	_mat.set_shader_parameter("flash", _blysk)
	_mat.set_shader_parameter("death", _smierc)
	_mat.set_shader_parameter("blur", rozmycie)
	_mat.set_shader_parameter("fatigue", _zmeczenie)
