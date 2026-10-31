class_name GlitchKamery
extends CanvasLayer
# Nakładka z glitchem na obraz. Co jakiś czas (losowo) na chwilę zakłóca ekran.
# Gracz tworzy ją sam. Ręcznie: GlitchKamery.new() albo wywołaj trigger() np. z jumpscare.

@export var wlaczony: bool = true
@export var min_przerwa: float = 6.0
@export var max_przerwa: float = 20.0
@export var min_czas: float = 0.1
@export var max_czas: float = 0.5
@export_range(0.0, 1.0) var max_sila: float = 1.0
@export var dzwiek: AudioStream
@export var glosnosc_db: float = -6.0
@export var debug_glitch: bool = false

var _rect: ColorRect
var _mat: ShaderMaterial
var _sfx: AudioStreamPlayer
var _do_nastepnego: float = 0.0
var _pozostalo: float = 0.0
var _czas_trwania: float = 0.0


func _ready() -> void:
	layer = 1   # pod HUD (2) i jumpscare (100+)

	var shader := load("res://Shader/glitch.gdshader") as Shader
	if shader == null:
		push_warning("GlitchKamery: brak pliku res://Shader/glitch.gdshader")
		set_process(false)
		return

	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("strength", 0.0)

	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)

	_sfx = AudioStreamPlayer.new()
	_sfx.volume_db = glosnosc_db
	add_child(_sfx)

	_losuj_przerwe()


func _losuj_przerwe() -> void:
	_do_nastepnego = randf_range(min_przerwa, maxf(max_przerwa, min_przerwa))


# Wywołaj ręcznie, żeby wymusić glitch (czas <= 0 = losowy)
func trigger(czas: float = -1.0, sila: float = -1.0) -> void:
	if _mat == null:
		return
	_czas_trwania = czas if czas > 0.0 else randf_range(min_czas, max_czas)
	_pozostalo = _czas_trwania
	_mat.set_shader_parameter("strength", sila if sila >= 0.0 else max_sila)
	_rect.visible = true
	if dzwiek != null:
		_sfx.stream = dzwiek
		_sfx.play()
	if debug_glitch:
		print("glitch: %.2f s" % _czas_trwania)


func _process(delta: float) -> void:
	if not wlaczony:
		return

	if _pozostalo > 0.0:
		_pozostalo -= delta
		if _pozostalo <= 0.0:
			_mat.set_shader_parameter("strength", 0.0)
			_rect.visible = false
			_losuj_przerwe()
			return
		# siła drga w trakcie glitcha
		var sila := randf_range(0.3, 1.0) * max_sila
		_mat.set_shader_parameter("strength", sila)
		_mat.set_shader_parameter("seed_time", Time.get_ticks_msec() / 1000.0)
		return

	_do_nastepnego -= delta
	if _do_nastepnego <= 0.0:
		trigger()
