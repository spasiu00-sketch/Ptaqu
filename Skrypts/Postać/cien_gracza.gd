extends Node3D
# Model gracza widoczny wyłącznie jako cień (kamera go nie renderuje).
# Animacjami zajmuje się skrypt gracza, ten skrypt tylko chowa model przed kamerą.
#
# TRYB TESTOWY: klawisz F2 pokazuje model i odsuwa kamerę za plecy postaci,
# żeby można było sprawdzić animację chodzenia. Ponowne F2 wraca do normalnego widoku.
# Kamerą nie ruszamy bezpośrednio: ustawiamy graczowi camera_extra_offset,
# dzięki temu nie psujemy kucania ani kołysania kamery.

@export var tryb_testowy: bool = true                 # false = F2 nic nie robi (na wersję końcową)
@export var klawisz_testowy: Key = KEY_F2
@export var odsuniecie_kamery: float = 2.5            # ile metrów za plecami postaci w trybie testowym
@export var podniesienie_kamery: float = 0.4          # ile metrów wyżej w trybie testowym

var _meshe: Array[Node] = []
var _gracz: Node
var _widoczny: bool = false


func _ready() -> void:
	_meshe = find_children("*", "GeometryInstance3D", true, false)
	_gracz = get_parent()
	_ustaw_widocznosc(false)
	# latarka konfiguruje się deferred i może nadpisać cast_shadow, więc ustawiamy stan jeszcze raz
	await get_tree().process_frame
	await get_tree().process_frame
	_ustaw_widocznosc(_widoczny)


func _unhandled_input(event: InputEvent) -> void:
	if not tryb_testowy:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == klawisz_testowy:
		_ustaw_widocznosc(not _widoczny)


func _ustaw_widocznosc(widoczny: bool) -> void:
	_widoczny = widoczny
	var tryb := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if widoczny \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	for mesh in _meshe:
		mesh.cast_shadow = tryb

	if _gracz != null and "camera_extra_offset" in _gracz:
		_gracz.set("camera_extra_offset",
				Vector3(0.0, podniesienie_kamery, odsuniecie_kamery) if widoczny else Vector3.ZERO)
