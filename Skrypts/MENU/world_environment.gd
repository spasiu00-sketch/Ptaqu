@tool
extends WorldEnvironment

# Tylko w edytorze: jasny ambient, żeby poziom nie był czarny podczas budowy.
# Przed zapisem sceny oryginalne ustawienia wracają, więc gra wygląda jak dawniej.

@export var ambient_edytora: Color = Color(0.75, 0.75, 0.8)
@export var energia_edytora: float = 1.0

@onready var env: Environment = environment

var _zapamietane: bool = false
var _stare_zrodlo: Environment.AmbientSource
var _stary_kolor: Color
var _stara_energia: float


func _ready() -> void:
	if env == null:
		push_warning("WorldEnvironment nie ma przypisanego zasobu Environment.")
		return

	if Engine.is_editor_hint():
		_zapamietaj()
		_wlacz_podglad()
		return

	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.75, 0.8)
	env.fog_density = 0.02


func _zapamietaj() -> void:
	if _zapamietane:
		return
	_stare_zrodlo = env.ambient_light_source
	_stary_kolor = env.ambient_light_color
	_stara_energia = env.ambient_light_energy
	_zapamietane = true


func _wlacz_podglad() -> void:
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient_edytora
	env.ambient_light_energy = energia_edytora


func _przywroc() -> void:
	if not _zapamietane:
		return
	env.ambient_light_source = _stare_zrodlo
	env.ambient_light_color = _stary_kolor
	env.ambient_light_energy = _stara_energia


func _notification(what: int) -> void:
	if not Engine.is_editor_hint() or env == null or not _zapamietane:
		return
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_przywroc()
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_wlacz_podglad()
