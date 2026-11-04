class_name Item
extends Resource

const ODLEGLOSC_RZUTU := 1.0
const MARGINES_SCIANY := 0.3

@export var nazwa: String = "Przedmiot"
@export_multiline var opis: String = ""
@export var ikona: Texture2D
@export var stackowalny: bool = false
@export_range(1, 99) var max_stack: int = 1
@export var uzywalny: bool = false
@export var laduje_baterie: float = 0.0

@export_group("Wyrzucanie")
@export var scena_swiata: PackedScene
@export var jest_latarka: bool = false

var szablon: Node3D = null


func uzyj(gracz: Node) -> bool:
	if not uzywalny or gracz == null:
		return false
	if laduje_baterie > 0.0:
		var latarka: Flashlight = gracz.get("flashlight") as Flashlight
		if latarka != null and latarka.battery < latarka.max_battery:
			latarka.charge_battery(laduje_baterie)
			return true
	return false


func wyrzuc(gracz: Node3D) -> bool:
	if gracz == null:
		return false

	var bateria := -1.0
	if jest_latarka:
		var latarka: Flashlight = gracz.get("flashlight") as Flashlight
		if latarka != null:
			if latarka.is_busy:
				return false
			bateria = latarka.battery

	var instancja: Node3D = null
	if scena_swiata != null:
		instancja = scena_swiata.instantiate() as Node3D
	elif szablon != null and is_instance_valid(szablon):
		instancja = szablon.duplicate() as Node3D

	if instancja == null:
		push_warning("Item '%s': brak modelu do wyrzucenia (ustaw 'Scena Swiata' albo najpierw podnieś przedmiot z ziemi)" % nazwa)
		return false

	var punkt := _znajdz_miejsce(gracz)
	gracz.get_tree().current_scene.add_child(instancja)
	instancja.global_rotation.y = gracz.global_rotation.y
	instancja.global_position = punkt
	_ustaw_na_punkcie(instancja, punkt)
	
	if not _ustaw_przedmiot(instancja, bateria, instancja):
		push_warning("Item '%s': w modelu nie znaleziono przedmiot.gd, nie da się go podnieść" % nazwa)

	if jest_latarka and gracz.has_method("schowaj_latarke"):
		gracz.call("schowaj_latarke")
	return true


func _ustaw_przedmiot(wezel: Node, bateria: float, korzen: Node) -> bool:
	if wezel.has_method("ustaw_wyrzucony"):
		wezel.ustaw_wyrzucony(self, bateria, korzen)
		return true
	for dziecko in wezel.get_children():
		if _ustaw_przedmiot(dziecko, bateria, korzen):
			return true
	return false


func _znajdz_miejsce(gracz: Node3D) -> Vector3:
	var swiat := gracz.get_world_3d().direct_space_state
	var kamera := gracz.get_viewport().get_camera_3d()
	var glowa: Vector3 = kamera.global_position if kamera != null else gracz.global_position + Vector3.UP * 1.5

	var przod: Vector3 = -gracz.global_transform.basis.z
	przod.y = 0.0
	przod = przod.normalized()

	var wyklucz: Array[RID] = []
	if gracz is CollisionObject3D:
		wyklucz.append((gracz as CollisionObject3D).get_rid())

	var dystans := ODLEGLOSC_RZUTU
	var q_sciana := PhysicsRayQueryParameters3D.create(glowa, glowa + przod * ODLEGLOSC_RZUTU)
	q_sciana.exclude = wyklucz
	var sciana := swiat.intersect_ray(q_sciana)
	if not sciana.is_empty():
		dystans = maxf(glowa.distance_to(sciana["position"]) - MARGINES_SCIANY, 0.2)

	var punkt := glowa + przod * dystans

	var q_podloga := PhysicsRayQueryParameters3D.create(punkt, punkt + Vector3.DOWN * 4.0)
	q_podloga.exclude = wyklucz
	var podloga := swiat.intersect_ray(q_podloga)
	if podloga.is_empty():
		return gracz.global_position + przod * dystans
	return podloga["position"]

# Przesuwa cały model tak, by jego środek (XZ) był w 'punkt', a spód leżał na podłodze.
# Niweluje offset modelu względem origin korzenia sceny przedmiotu.
func _ustaw_na_punkcie(korzen: Node3D, punkt: Vector3) -> void:
	var aabb := AABB()
	var jest := false
	for m in korzen.find_children("*", "GeometryInstance3D", true, false):
		var g := m as GeometryInstance3D
		var a: AABB = g.global_transform * g.get_aabb()
		aabb = a if not jest else aabb.merge(a)
		jest = true
	if not jest:
		return
	var srodek := aabb.get_center()
	korzen.global_position += Vector3(
			punkt.x - srodek.x,
			punkt.y - aabb.position.y,
			punkt.z - srodek.z)
