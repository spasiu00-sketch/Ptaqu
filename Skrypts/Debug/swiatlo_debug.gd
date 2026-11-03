@tool
class_name SwiatloEdytora
extends DirectionalLight3D
# Światło widoczne tylko w edytorze, żeby poziom nie był czarny podczas budowy.
# W uruchomionej grze węzeł sam się usuwa, więc nie psuje klimatu ciemnego poziomu.

func _ready() -> void:
	if Engine.is_editor_hint():
		light_energy = 0.8
		rotation_degrees = Vector3(-50.0, -30.0, 0.0)
		shadow_enabled = false
	else:
		queue_free()
