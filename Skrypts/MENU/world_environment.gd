extends WorldEnvironment

@onready var env: Environment = environment


func _ready() -> void:
	if env == null:
		return

	env.fog_enabled = false
