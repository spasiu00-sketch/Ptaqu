shader_type spatial;
// vertex_lighting = oświetlenie liczone na wierzchołkach (Gouraud), jak na PS1
render_mode vertex_lighting, specular_disabled, cull_back;

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Siatka "przyciągania" wierzchołków. Mniejsze wartości = mocniejsze drżenie.
// Odpowiada rozdzielczości w połowie szerokości/wysokości ekranu (np. 320x240 -> 160x120).
uniform vec2 snap_resolution = vec2(160.0, 120.0);

// Liczba poziomów jasności na kanał koloru (PS1 ~ 32). Mniej = bardziej "plakatowo".
uniform float color_levels : hint_range(2.0, 256.0) = 32.0;

// 0.0 = normalne mapowanie tekstur, 1.0 = pełne "pływanie" tekstur jak na PS1
uniform float affine_amount : hint_range(0.0, 1.0) = 1.0;

varying vec2 affine_uv;
varying float vert_w;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));

	// 1. Przyciąganie wierzchołków do siatki ekranu (drżenie geometrii)
	vec3 ndc = clip.xyz / clip.w;
	ndc.xy = floor(ndc.xy * snap_resolution + 0.5) / snap_resolution;
	clip.xyz = ndc * clip.w;
	POSITION = clip;

	// 2. Afiniczne mapowanie tekstur (bez korekcji perspektywy)
	// Mnożymy UV przez w, a w fragmencie dzielimy przez interpolowane w.
	affine_uv = UV * mix(1.0, clip.w, affine_amount);
	vert_w = mix(1.0, clip.w, affine_amount);
}

void fragment() {
	vec2 uv = affine_uv / vert_w;
	vec3 col = texture(albedo_texture, uv).rgb * tint.rgb;

	// 3. Ograniczona paleta kolorów
	col = floor(col * color_levels + 0.5) / color_levels;

	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
