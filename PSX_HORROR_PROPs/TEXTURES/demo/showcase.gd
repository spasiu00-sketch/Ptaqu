extends Node3D
## Showcase room of PSX Horror Props by bitkiln (https://bitkiln.itch.io).
## Every prop of the pack stands in rows per category with its name. Keys: P PSX shader on/off,
## 1 vertex snapping, 2 affine texture mapping, 3 15-bit colour + dithering, 4 virtual resolution,
## L labels, H help. The camera keys are in fly_camera.gd.

const PSX := preload("res://shaders/apply_psx.gd")
const RESOLUTIONS := [240.0, 480.0, 120.0]
const KEYS := "WASD / arrows move    mouse look (click)    Shift faster    F walk / fly    E Q up / down    Esc free the mouse\n" + \
		"P PSX shader on / off    1 vertex snapping    2 affine textures    3 15-bit colour    4 resolution    L labels    H help"

@export var psx_enabled := true
@export var title := "PSX HORROR PROPS"
@export var subtitle := ""
@export var room_min := Vector3.ZERO
@export var room_max := Vector3.ZERO

var _labels_visible := true
var _fps_wait := 0.0

@onready var _camera = $Camera
@onready var _help: Label = $HUD/Help
@onready var _status: Label = $HUD/Status


func _ready() -> void:
	_help.text = title + ("   " + subtitle if subtitle != "" else "") + "\n" + KEYS
	set_psx(psx_enabled)


## Turns the PSX shader on or off for the whole room.
func set_psx(on: bool) -> void:
	psx_enabled = on
	if on:
		PSX.apply(self)
	else:
		PSX.restore(self)
	_update_status()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_P:
			set_psx(not psx_enabled)
		KEY_1:
			PSX.set_setting("vertex_snap", not PSX.settings["vertex_snap"])
		KEY_2:
			PSX.set_setting("affine_strength", 0.0 if PSX.settings["affine_strength"] > 0.0 else 1.0)
		KEY_3:
			var on: bool = not PSX.settings["color_15bit"]
			PSX.set_setting("color_15bit", on)
			PSX.set_setting("dithering", on)
		KEY_4:
			var i := RESOLUTIONS.find(PSX.settings["snap_resolution"])
			PSX.set_setting("snap_resolution", RESOLUTIONS[(i + 1) % RESOLUTIONS.size()])
		KEY_L:
			_labels_visible = not _labels_visible
			get_tree().call_group("labels", "set_visible", _labels_visible)
		KEY_H:
			_help.visible = not _help.visible
		_:
			return
	_update_status()
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_fps_wait -= delta
	if _fps_wait <= 0.0:
		_fps_wait = 0.5
		_update_status()


func _update_status() -> void:
	if not is_node_ready():
		return
	var s := "PSX shader %s" % ("ON" if psx_enabled else "OFF")
	if psx_enabled:
		s += "    snap %s    affine %s    15-bit %s    %d lines" % [
			"on" if PSX.settings["vertex_snap"] else "off",
			"on" if PSX.settings["affine_strength"] > 0.0 else "off",
			"on" if PSX.settings["color_15bit"] else "off",
			int(PSX.settings["snap_resolution"])]
	s += "    |    %s    |    %d fps" % ["fly" if _camera.get("flying") else "walk", Engine.get_frames_per_second()]
	_status.text = s
