shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

uniform float saturation : hint_range(0.0, 2.0) = 0.8;
uniform float contrast : hint_range(0.5, 2.0) = 1.1;
uniform vec3 color_tint : source_color = vec3(0.93, 1.0, 0.95);   // lekko zielonkawy, "chory" odcień
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.5;
uniform float grain : hint_range(0.0, 0.3) = 0.05;
uniform float scanlines : hint_range(0.0, 0.5) = 0.06;
uniform float scanline_count = 240.0;
uniform float aberration : hint_range(0.0, 0.01) = 0.0015;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = uv - vec2(0.5);

	// Delikatna aberracja chromatyczna na krawędziach ekranu
	vec2 offset = dir * aberration * 10.0 * length(dir);
	vec3 col;
	col.r = texture(screen_tex, uv + offset).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - offset).b;

	// Korekcja kolorów
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, saturation);
	col = (col - 0.5) * contrast + 0.5;
	col *= color_tint;

	// Winieta
	float v = 1.0 - smoothstep(0.25, 0.8, length(dir));
	col *= mix(1.0, v, vignette_strength);

	// Linie skanowania (efekt CRT)
	col *= 1.0 - scanlines * (0.5 + 0.5 * sin(uv.y * scanline_count * 6.28318));

	// Ziarno
	float n = hash(uv * 1000.0 + fract(TIME) * 10.0) - 0.5;
	col += n * grain;

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
