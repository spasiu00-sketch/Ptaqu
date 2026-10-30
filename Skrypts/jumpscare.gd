extends Area3D
class_name JumpscareTrigger

@export var tylko_raz: bool = true
@export var opoznienie: float = 0.0
@export var dzwiek: AudioStream
@export_range(-40.0, 12.0, 0.5) var glosnosc_db: float = 0.0
@export var obraz: Texture2D
@export var czas_pokazania: float = 0.8
@export var sila_wstrzasu: float = 0.15
@export var blysk: bool = true

var _uzyty: bool = false
var _straszak: Node3D


func _ready() -> void:
	_straszak = get_node_or_null("Straszak") as Node3D
	if _straszak:
		_straszak.visible = false
	if obraz == null:
		push_warning("JumpscareTrigger '%s': pole Obraz jest puste" % name)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _uzyty and tylko_raz:
		return
	if not (body is CharacterBody3D):
		return
	_uzyty = true
	if opoznienie > 0.0:
		await get_tree().create_timer(opoznienie).timeout
	_odpal()


func _odpal() -> void:
	_zagraj_dzwiek()
	if blysk:
		_blysk()
	_wstrzas()

	var warstwa_obrazu: CanvasLayer = null
	if obraz:
		warstwa_obrazu = _pokaz_obraz()
	if _straszak:
		_straszak.visible = true

	if warstwa_obrazu or _straszak:
		await get_tree().create_timer(czas_pokazania).timeout
		if is_instance_valid(warstwa_obrazu):
			warstwa_obrazu.queue_free()
		if _straszak:
			_straszak.visible = false


func _zagraj_dzwiek() -> void:
	if dzwiek == null:
		push_warning("JumpscareTrigger '%s': nie wybrano dzwieku w polu Dzwiek" % name)
		return
	var odtwarzacz := AudioStreamPlayer.new()
	odtwarzacz.stream = dzwiek
	odtwarzacz.volume_db = glosnosc_db
	add_child(odtwarzacz)
	odtwarzacz.finished.connect(odtwarzacz.queue_free)
	odtwarzacz.play()


func _pokaz_obraz() -> CanvasLayer:
	var warstwa := CanvasLayer.new()
	warstwa.layer = 101
	get_tree().root.add_child(warstwa)

	var tekstura := TextureRect.new()
	tekstura.texture = obraz
	tekstura.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tekstura.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tekstura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	warstwa.add_child(tekstura)
	tekstura.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tekstura.size = get_viewport().get_visible_rect().size
	tekstura.position = Vector2.ZERO
	return warstwa


func _blysk() -> void:
	var warstwa := CanvasLayer.new()
	warstwa.layer = 100
	get_tree().root.add_child(warstwa)

	var prostokat := ColorRect.new()
	prostokat.color = Color(1, 1, 1, 0.8)
	prostokat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	warstwa.add_child(prostokat)
	prostokat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	prostokat.size = get_viewport().get_visible_rect().size
	prostokat.position = Vector2.ZERO

	var tween := create_tween()
	tween.tween_property(prostokat, "color:a", 0.0, 0.25)
	tween.tween_callback(warstwa.queue_free)


func _wstrzas() -> void:
	var kamera := get_viewport().get_camera_3d()
	if kamera == null or sila_wstrzasu <= 0.0:
		return
	var tween := create_tween()
	for i in 8:
		var losowy := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * sila_wstrzasu
		tween.tween_property(kamera, "h_offset", losowy.x, 0.04)
		tween.parallel().tween_property(kamera, "v_offset", losowy.y, 0.04)
	tween.tween_property(kamera, "h_offset", 0.0, 0.06)
	tween.parallel().tween_property(kamera, "v_offset", 0.0, 0.06)
