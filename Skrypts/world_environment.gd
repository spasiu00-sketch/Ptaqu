extends WorldEnvironment

@onready var env: Environment = environment


func _ready() -> void:
	if env == null:
		push_warning("WorldEnvironment nie ma przypisanego zasobu Environment.")
		return
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.75, 0.8)
	env.fog_density = 0.02
