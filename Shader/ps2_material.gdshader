shader_type spatial;
render_mode specular_disabled, cull_back;

// Tekstury wygładzone (bilinear + mipmapy), bez "pływania" jak na PS1
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Bardzo delikatne drżenie wierzchołków (0 = wyłączone, 1 = pełne przyciąganie do siatki)
uniform float vertex_wobble : hint_range(0.0, 1.0) = 0.15;
uniform vec2 snap_resolution = vec2(320.0, 240.0);

// Lekkie "wypalenie" kolorów, żeby tekstury nie wyglądały zbyt czysto
uniform float color_levels : hint_range(8.0, 256.0) = 96.0;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 ndc = clip.xyz / clip.w;
	vec2 snapped = floor(ndc.xy * snap_resolution + 0.5) / snap_resolution;
	ndc.xy = mix(ndc.xy, snapped, vertex_wobble);
	clip.xyz = ndc * clip.w;
	POSITION = clip;
}

void fragment() {
	vec3 col = texture(albedo_texture, UV).rgb * tint.rgb;
	col = floor(col * color_levels + 0.5) / color_levels;
	ALBEDO = col;
	ROUGHNESS = 0.9;
	METALLIC = 0.0;
}
