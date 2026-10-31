// PSX lit shader for Godot 4.3+ (Forward+, Mobile and Compatibility renderers)
// bitkiln - PSX Horror Props - https://bitkiln.itch.io
//
// The look of the first PlayStation:
//   * vertex snapping to the pixel grid of a low virtual resolution (the famous wobble)
//   * affine texture mapping (no perspective correction), blendable with correct mapping
//   * nearest texture sampling without mipmaps
//   * optional 15-bit colour (5 bits per channel) with a 4x4 ordered dither
//   * emission for flames, bulbs and screens, alpha scissor cut-outs, vertex colours
// Lights and fog come from Godot: diffuse only, no specular highlights, like the console.
//
// psx_lit.gdshader culls back faces, psx_lit_double_sided.gdshader is the same code without culling.
// shaders/apply_psx.gd converts the materials of a whole scene to these shaders and back.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

group_uniforms surface;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_nearest, repeat_enable;
// Multiply the albedo by the vertex colours of the mesh.
uniform bool use_vertex_color = false;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
// Keep the UVs inside the texture (clamp to edge, for atlases). Turn off for tiling textures.
uniform bool clamp_uv = true;
// Cut-outs: pixels with alpha below the threshold are not drawn.
uniform bool alpha_scissor = false;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;
// Ignore lights: the surface shows its texture colour as it is.
uniform bool unshaded = false;

group_uniforms emission;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform sampler2D emission_texture : source_color, hint_default_black, filter_nearest, repeat_enable;
uniform bool use_emission_texture = false;
// Off: emission = (colour + texture) x energy.  On: emission = colour x texture x energy.
uniform bool emission_multiply = false;
uniform float emission_energy : hint_range(0.0, 16.0) = 1.0;

group_uniforms psx;
// Snap every vertex to the pixel grid of the virtual resolution.
uniform bool vertex_snap = true;
// Virtual vertical resolution in lines (snapping and dither size). The width follows the aspect ratio.
uniform float snap_resolution : hint_range(60.0, 1080.0, 1.0) = 240.0;
// 0 = perspective-correct textures, 1 = full affine warping like the console.
uniform float affine_strength : hint_range(0.0, 1.0) = 1.0;
// Reduce the surface colour to 15 bits (5 bits per channel).
uniform bool color_15bit = true;
// 4x4 ordered dither before the colour reduction.
uniform bool dithering = true;
uniform float dither_strength : hint_range(0.0, 2.0) = 1.0;
group_uniforms;

// xy = UV * w and z = w: dividing them per pixel gives screen-space (affine) UVs.
varying vec3 psx_affine;

float psx_bayer4(vec2 p) {
	vec2 a = mod(floor(p), 4.0);
	vec2 lo = mod(a, 2.0);
	vec2 hi = floor(a * 0.5);
	float m = 4.0 * mod(2.0 * lo.x + 3.0 * lo.y, 4.0) + mod(2.0 * hi.x + 3.0 * hi.y, 4.0);
	return (m + 0.5) / 16.0 - 0.5;
}

vec3 psx_to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 psx_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	UV = UV * uv_scale + uv_offset;
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	if (vertex_snap && clip.w > 0.0001) {
		vec2 grid = vec2(snap_resolution * VIEWPORT_SIZE.x / max(VIEWPORT_SIZE.y, 1.0), snap_resolution) * 0.5;
		clip.xy = round(clip.xy / clip.w * grid) / grid * clip.w;
	}
	POSITION = clip;
	psx_affine = vec3(UV * clip.w, clip.w);
}

void fragment() {
	vec2 uv = UV;
	if (affine_strength > 0.0) {
		uv = mix(UV, psx_affine.xy / max(psx_affine.z, 0.00001), affine_strength);
	}
	if (clamp_uv) {
		vec2 half_texel = 0.5 / vec2(textureSize(albedo_texture, 0));
		uv = clamp(uv, half_texel, vec2(1.0) - half_texel);
	}
	vec4 albedo = albedo_color * texture(albedo_texture, uv);
	if (use_vertex_color) {
		albedo *= COLOR;
	}
	if (alpha_scissor && albedo.a < alpha_scissor_threshold) {
		discard;
	}
	vec3 color = albedo.rgb;
	if (color_15bit) {
		vec3 c = psx_to_srgb(clamp(color, vec3(0.0), vec3(1.0))) * 255.0;
		if (dithering) {
			c += psx_bayer4(floor(FRAGCOORD.xy * snap_resolution / max(VIEWPORT_SIZE.y, 1.0))) * 8.0 * dither_strength;
		}
		color = psx_to_linear(floor(clamp(c, vec3(0.0), vec3(255.0)) / 8.0) / 31.0);
	}
	vec3 etex = use_emission_texture ? texture(emission_texture, uv).rgb : vec3(emission_multiply ? 1.0 : 0.0);
	vec3 emission = (emission_multiply ? emission_color.rgb * etex : emission_color.rgb + etex) * emission_energy;
	if (unshaded) {
		emission += color;
		color = vec3(0.0);
	}
	ALBEDO = color;
	EMISSION = emission;
}
