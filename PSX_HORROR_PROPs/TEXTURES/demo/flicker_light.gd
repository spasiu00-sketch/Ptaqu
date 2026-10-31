extends OmniLight3D
## Light that flickers like a failing bulb (mode 0) or a candle flame (mode 1).

@export_enum("Failing bulb", "Candle") var mode := 0
@export var flicker_seed := 1

var _base := 1.0
var _wait := 0.0
var _level := 1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_base = light_energy
	_rng.seed = flicker_seed


func _process(delta: float) -> void:
	if mode == 1:
		_wait -= delta
		if _wait <= 0.0:
			_wait = _rng.randf_range(0.05, 0.12)
			_level = _rng.randf_range(0.78, 1.08)
		light_energy = lerpf(light_energy, _base * _level, 1.0 - exp(-14.0 * delta))
		return
	_wait -= delta
	if _wait > 0.0:
		return
	if _rng.randf() < 0.14:
		light_energy = _base * _rng.randf_range(0.04, 0.35)
		_wait = _rng.randf_range(0.03, 0.11)
	else:
		light_energy = _base * _rng.randf_range(0.93, 1.04)
		_wait = _rng.randf_range(0.15, 1.8)
