shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float seed_time = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;

	if (strength <= 0.001) {
		COLOR = vec4(texture(screen_tex, uv).rgb, 1.0);
	} else {
		float t = floor(seed_time * 20.0);

		// przesunięcie poziomych pasów
		float rows = mix(10.0, 45.0, hash(vec2(t, 1.0)));
		float row = floor(uv.y * rows);
		float chance = step(1.0 - strength * 0.5, hash(vec2(row, t)));
		uv.x += (hash(vec2(row, t + 7.0)) - 0.5) * 0.35 * strength * chance;

		// pionowe "rolowanie" obrazu
		uv.y = fract(uv.y + (hash(vec2(t, 5.0)) - 0.5) * 0.08 * strength * step(0.7, hash(vec2(t, 9.0))));

		// rozdzielenie kanałów RGB
		float split = 0.012 * strength * (0.4 + hash(vec2(t, 3.0)));
		vec3 col;
		col.r = texture(screen_tex, uv + vec2(split, 0.0)).r;
		col.g = texture(screen_tex, uv).g;
		col.b = texture(screen_tex, uv - vec2(split, 0.0)).b;

		// losowe bloki szumu
		vec2 blk = floor(SCREEN_UV * vec2(32.0, 18.0));
		float nb = step(1.0 - 0.05 * strength, hash(blk + t));
		col = mix(col, vec3(hash(blk * 1.7 + t)), nb * 0.85);

		// krótkie rozbłyski koloru i negatyw
		float flash = step(0.88, hash(vec2(t, 11.0))) * strength;
		col = mix(col, col.brg, flash * 0.6);
		col = mix(col, 1.0 - col, step(0.96, hash(vec2(t, 13.0))) * strength * 0.7);

		COLOR = vec4(col, 1.0);
	}
}
