class_name ViewmodelClipGuard
extends Node3D
# Chroni model trzymany w ręku przed wchodzeniem w ściany:
# 1) zmniejsza near plane kamery,
# 2) cofa i opuszcza latarkę, gdy przed kamerą jest przeszkoda.

@export var target_path: NodePath                 # węzeł do odsuwania (latarka albo jej pivot)
@export var camera_near: float = 0.02             # near plane kamery (domyślnie 0.05)
@export var reach: float = 0.75                   # od tej odległości od ściany zaczyna się cofanie
@export var max_push: float = 0.35                # maksymalne cofnięcie (m)
@export var tilt_degrees: float = 25.0            # o ile opuścić lufę przy ścianie (0 = wyłączone)
@export var smooth: float = 14.0                  # szybkość wygładzania
@export_flags_3d_physics var collision_mask: int = 1

var _target: Node3D
var _camera: Camera3D
var _base_pos: Vector3
var _base_rot: Vector3
var _amount: float = 0.0
var _exclude: Array[RID] = []


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	if _target == null:
		push_warning("ViewmodelClipGuard: ustaw 'Target Path' na węzeł latarki")
		set_physics_process(false)
		return

	_camera = _find_camera()
	if _camera != null:
		_camera.near = camera_near
	else:
		push_warning("ViewmodelClipGuard: nie znaleziono Camera3D")

	# ignorujemy ciało gracza, żeby promień nie trafiał w niego
	var n: Node = self
	while n != null:
		if n is CollisionObject3D:
			_exclude.append((n as CollisionObject3D).get_rid())
		n = n.get_parent()

	# pozycja bazowa zapamiętana po jednej klatce, gdy inne skrypty ustawią model
	await get_tree().process_frame
	_base_pos = _target.position
	_base_rot = _target.rotation_degrees


func _find_camera() -> Camera3D:
	var n: Node = self
	while n != null:
		if n is Camera3D:
			return n
		n = n.get_parent()
	return get_viewport().get_camera_3d()


func _physics_process(delta: float) -> void:
	if _target == null or _camera == null:
		return

	var from := _camera.global_position
	var to := from + (-_camera.global_transform.basis.z) * reach
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask, _exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	var wanted := 0.0
	if not hit.is_empty():
		var dist := from.distance_to(hit["position"])
		wanted = clampf(reach - dist, 0.0, max_push)

	_amount = lerpf(_amount, wanted, 1.0 - exp(-smooth * delta))

	var k := _amount / max_push if max_push > 0.0 else 0.0
	_target.position = _base_pos + Vector3(0.0, -0.05 * k, _amount)
	_target.rotation_degrees = _base_rot + Vector3(tilt_degrees * k, 0.0, 0.0)
