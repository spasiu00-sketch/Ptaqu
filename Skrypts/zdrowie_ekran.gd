class_name EkranZdrowia
extends CanvasLayer
# Nakładka na obraz: im mniej życia, tym ciemniejsze brzegi ekranu, odbarwienie,
# rozmazanie obrazu (zmęczenie) i pulsowanie (jak w Battlefroncie / Callu of Duty).
# Tworzy ją gracz (character_body_3d.gd). Sterowanie:
#   ustaw_natezenie(0..1)  - 0 = pełne życie, 1 = prawie martwy
#   blysk_obrazen()        - krótki czerwony błysk po trafieniu
#   smierc()               - ekran stopniowo robi się czarny

@export var plynnosc: float = 3.0           # jak szybko ekran dochodzi do docelowego natężenia
@export var pulsowanie: bool = true         # pulsowanie winiety i rozmazania (jak oddech / serce)
@export var kolor_krwi: Color = Color(0.45, 0.0, 0.0)
@export var szybkosc_czernienia: float = 0.6   # po śmierci: jak szybko ekran robi się czarny

@export_group("Rozmazanie")
@export var rozmycie_wlaczone: bool = true
@export var rozmycie_px: float = 7.0        # maksymalny promień rozmazania w pikselach (przy 1.0 natężenia)
@export_range(0.0, 1.0, 0.01) var rozmycie_start: float = 0.15   # od jakiego natężenia zaczyna się rozmazanie

const SHADER_CODE := """
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float death : hint_range(0.0, 1.0) = 0.0;
uniform float blur : hint_range(0.0, 1.0) = 0.0;
uniform float blur_px = 7.0;
uniform vec3 blood_color : source_color = vec3(0.45, 0.0, 0.0);

void fragment() {
	vec2 uv = SCREEN_UV;

	// odległość od środka: 0 = środek, 1 = róg ekranu
	float d = length(uv - 0.5) * 1.41421;

	vec3 col = texture(screen_tex, uv).rgb;

	// rozmazanie: mocniejsze na brzegach, lekko pulsuje razem z oddechem
	if (blur > 0.001) {
		float r = blur * blur_px * (0.4 + 0.9 * d) * (1.0 + 0.4 * pulse);
		vec3 sum = col;
		for (int i = 0; i < 8; i++) {
			float a = float(i) * 0.785398;
			vec2 o = vec2(cos(a), sin(a)) * r * SCREEN_PIXEL_SIZE;
			sum += texture(screen_tex, uv + o).rgb;
			sum += texture(screen_tex, uv + o * 0.5).rgb;
		}
		col = sum / 17.0;
	}

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
var _mat: ShaderMaterial
var _cel: float = 0.0
var _aktualne: float = 0.0
var _blysk: float = 0.0
var _smierc: float = 0.0
var _martwy: bool = false
var _czas: float = 0.0


func _ready() -> void:
	layer = 1   # pod HUD (2), ekwipunkiem (3) i jumpscare (100+)

	var shader := Shader.new()
	shader.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("blood_color", Vector3(kolor_krwi.r, kolor_krwi.g, kolor_krwi.b))
	_mat.set_shader_parameter("blur_px", rozmycie_px)

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

	# nic do rysowania = wyłączamy nakładkę (oszczędność)
	var aktywna := _aktualne > 0.002 or _blysk > 0.0 or _smierc > 0.0
	_rect.visible = aktywna
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
