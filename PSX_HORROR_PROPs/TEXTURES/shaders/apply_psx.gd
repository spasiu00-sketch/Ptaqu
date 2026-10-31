extends RefCounted
## PSX material swapper for Godot 4.3+ (bitkiln - PSX Horror Props - https://bitkiln.itch.io).
##
## Walks a node tree and replaces the StandardMaterial3D / ORMMaterial3D of every MeshInstance3D with a
## ShaderMaterial that uses psx_lit.gdshader. It keeps the albedo colour and texture, UV scale and offset,
## texture repeat, vertex colours, emission (colour, texture, energy, operator), alpha scissor, unshaded
## mode and cull mode. Alpha-blended materials (soft transparency) are left as they are.
##
##     const PSX := preload("res://shaders/apply_psx.gd")
##     PSX.apply(self)                              # PSX look for everything under this node
##     PSX.restore(self)                            # the original materials again
##     PSX.set_setting("snap_resolution", 480.0)    # change a setting on every PSX material
##
## Converted materials are cached, so every instance of a model shares one ShaderMaterial.

const SHADER := preload("psx_lit.gdshader")
const SHADER_DOUBLE_SIDED := preload("psx_lit_double_sided.gdshader")
const META_SURFACES := &"psx_original_surface_materials"
const META_OVERRIDE := &"psx_original_material_override"

## The look every PSX material shares (see psx_lit.gdshader). Change it with set_setting().
static var settings := {
	"vertex_snap": true,
	"snap_resolution": 240.0,
	"affine_strength": 1.0,
	"color_15bit": true,
	"dithering": true,
	"dither_strength": 1.0,
}

static var _cache := {}
static var _front_shader: Shader = null


## Converts every MeshInstance3D under root (root included). Returns the number of surfaces changed.
static func apply(root: Node) -> int:
	var changed := 0
	for mi in _mesh_instances(root):
		changed += _apply_to(mi)
	return changed


## Puts the original materials back on every MeshInstance3D under root. Returns the number of nodes restored.
static func restore(root: Node) -> int:
	var restored := 0
	for mi in _mesh_instances(root):
		var done := false
		if mi.has_meta(META_OVERRIDE):
			mi.material_override = mi.get_meta(META_OVERRIDE)
			mi.remove_meta(META_OVERRIDE)
			done = true
		if mi.has_meta(META_SURFACES):
			var originals: Array = mi.get_meta(META_SURFACES)
			for s in mini(originals.size(), mi.get_surface_override_material_count()):
				mi.set_surface_override_material(s, originals[s])
			mi.remove_meta(META_SURFACES)
			done = true
		if done:
			restored += 1
	return restored


## True when a MeshInstance3D under root currently shows PSX materials.
static func is_applied(root: Node) -> bool:
	for mi in _mesh_instances(root):
		if mi.has_meta(META_SURFACES) or mi.has_meta(META_OVERRIDE):
			return true
	return false


## Changes one setting (vertex_snap, snap_resolution, affine_strength, color_15bit, dithering,
## dither_strength) on every PSX material made so far and on the ones made later.
static func set_setting(setting: String, value: Variant) -> void:
	settings[setting] = value
	for m in _cache.values():
		(m as ShaderMaterial).set_shader_parameter(setting, value)


## Forgets the cached materials (the next apply() makes new ones).
static func clear_cache() -> void:
	_cache.clear()


## The PSX version of one material (cached). Returns the material itself when it cannot be converted.
static func convert_material(source: Material) -> Material:
	if source == null or not (source is BaseMaterial3D):
		return source
	if _cache.has(source):
		return _cache[source]
	var src := source as BaseMaterial3D
	if src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA or \
			src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
		return source
	var m := ShaderMaterial.new()
	m.resource_name = (src.resource_name + "_psx") if src.resource_name != "" else "psx"
	m.shader = _shader_for(src.cull_mode)
	m.render_priority = src.render_priority
	m.set_shader_parameter("albedo_color", src.albedo_color)
	m.set_shader_parameter("albedo_texture", src.albedo_texture)
	m.set_shader_parameter("use_vertex_color", src.vertex_color_use_as_albedo)
	m.set_shader_parameter("uv_scale", Vector2(src.uv1_scale.x, src.uv1_scale.y))
	m.set_shader_parameter("uv_offset", Vector2(src.uv1_offset.x, src.uv1_offset.y))
	m.set_shader_parameter("clamp_uv", not src.texture_repeat)
	var scissor := src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR or \
			src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	m.set_shader_parameter("alpha_scissor", scissor)
	m.set_shader_parameter("alpha_scissor_threshold",
			src.alpha_scissor_threshold if src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else 0.5)
	m.set_shader_parameter("unshaded", src.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
	if src.emission_enabled:
		m.set_shader_parameter("emission_color", src.emission)
		m.set_shader_parameter("emission_texture", src.emission_texture)
		m.set_shader_parameter("use_emission_texture", src.emission_texture != null)
		m.set_shader_parameter("emission_multiply", src.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY)
		m.set_shader_parameter("emission_energy", src.emission_energy_multiplier)
	for setting in settings:
		m.set_shader_parameter(setting, settings[setting])
	_cache[source] = m
	return m


static func _shader_for(cull: int) -> Shader:
	if cull == BaseMaterial3D.CULL_DISABLED:
		return SHADER_DOUBLE_SIDED
	if cull == BaseMaterial3D.CULL_FRONT:
		if _front_shader == null:
			_front_shader = Shader.new()
			_front_shader.code = SHADER.code.replace("cull_back", "cull_front")
		return _front_shader
	return SHADER


static func _apply_to(mi: MeshInstance3D) -> int:
	if mi.material_override != null:
		if mi.has_meta(META_OVERRIDE):
			return 0
		var psx := convert_material(mi.material_override)
		if psx == mi.material_override:
			return 0
		mi.set_meta(META_OVERRIDE, mi.material_override)
		mi.material_override = psx
		return 1
	if mi.mesh == null or mi.has_meta(META_SURFACES):
		return 0
	var originals := []
	var changed := 0
	for s in mi.get_surface_override_material_count():
		originals.append(mi.get_surface_override_material(s))
		var active := mi.get_active_material(s)
		var psx := convert_material(active)
		if psx != active:
			mi.set_surface_override_material(s, psx)
			changed += 1
	if changed > 0:
		mi.set_meta(META_SURFACES, originals)
	return changed


static func _mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			found.append(n as MeshInstance3D)
		stack.append_array(n.get_children())
	return found
