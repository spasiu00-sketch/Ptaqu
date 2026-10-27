extends Node3D
# Pasek baterii na modelu latarki.
# Początek węzła = lewy koniec paska, pasek rośnie wzdłuż lokalnej osi X (czerwona strzałka gizma).

@export var length: float = 0.10          # długość pełnego paska w metrach
@export var thickness: float = 0.012      # grubość paska
@export var blink_below: float = 0.15     # poniżej tego poziomu (0-1) pasek miga

var flashlight = null     # SpotLight3D ze skryptem flashlight.gd (znajdowany przez grupę)
var bar: MeshInstance3D
var bar_mat: StandardMaterial3D


func _ready() -> void:
	# Ciemne tło paska (pokazuje pełną długość)
	var back := MeshInstance3D.new()
	var back_mesh := BoxMesh.new()
	back_mesh.size = Vector3(length + 0.004, thickness + 0.004, thickness * 0.6)
	back.mesh = back_mesh
	back.position.x = length / 2.0
	var back_mat := StandardMaterial3D.new()
	back_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	back_mat.albedo_color = Color(0.05, 0.05, 0.05)
	back.material_override = back_mat
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(back)

	# Właściwy pasek: zmienia długość i kolor
	bar = MeshInstance3D.new()
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(length, thickness, thickness)
	bar.mesh = bar_mesh
	bar_mat = StandardMaterial3D.new()
	bar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # widoczny nawet w ciemności
	bar_mat.albedo_color = Color.GREEN
	bar.material_override = bar_mat
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.position.x = length / 2.0
	add_child(bar)


func _process(_delta: float) -> void:
	if flashlight == null:
		flashlight = get_tree().get_first_node_in_group("flashlight")
		if flashlight == null:
			return

	var fraction: float = clamp(flashlight.battery / flashlight.max_battery, 0.0, 1.0)

	# Objętość: pasek skraca się od prawej strony, lewy koniec zostaje w miejscu
	bar.scale.x = max(fraction, 0.001)
	bar.position.x = length * fraction / 2.0

	# Kolor: zielony (pełna) -> żółty -> czerwony (pusta)
	bar_mat.albedo_color = Color.from_hsv(fraction * 0.33, 1.0, 1.0)

	# Miganie przy niskiej baterii
	if fraction > 0.0 and fraction < blink_below:
		bar.visible = fmod(Time.get_ticks_msec() / 1000.0, 0.6) < 0.4
	else:
		bar.visible = true
