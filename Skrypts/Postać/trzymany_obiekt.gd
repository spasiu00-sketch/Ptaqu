extends Node3D

## Skrypt wisi na węźle "Cofanie" (dziecko Camera3D).
## Camera3D
## ├─ Cofanie                  <- TEN SKRYPT
## │   └─ Untitled_test animacji
## │       ├─ AudioStreamPlayer3D
## │       └─ HeldFlashlight
## └─ InteractRay              <- poza Cofanie, żeby się nie cofał

@export_group("Węzły")
@export var obiekt: Node3D                  # Untitled_test animacji
@export var swiatlo: Light3D                # HeldFlashlight (opcjonalnie, tylko do przyciemniania)

@export_group("Cofanie")
@export_flags_3d_physics var maska_kolizji: int = 1
@export var dlugosc_obiektu: float = 0.5    # jak daleko model wystaje do przodu od swojej pozycji
@export var margines: float = 0.05
@export var maks_cofniecie: float = 0.6
@export var plynnosc: float = 14.0
@export var pochylenie_stopnie: float = 15.0   # opuszczenie końcówki przy ścianie, 0 = bez pochylania

@export_group("Światło")
@export var przyciemnianie_przy_scianie: float = 0.0   # 0 = bez zmian, 0.5 = przy ścianie 50% jasności

var _kamera: Node3D
var _baza: Transform3D
var _pivot: Vector3
var _ray: RayCast3D
var _energia: float = 1.0


func _ready() -> void:
	_kamera = get_parent() as Node3D
	if _kamera == null or obiekt == null:
		push_error("trzymany_obiekt.gd: 'Cofanie' musi być dzieckiem Camera3D i mieć przypisane pole 'Obiekt'.")
		set_process(false)
		return

	if find_child("InteractRay", true, false):
		push_warning("trzymany_obiekt.gd: przenieś InteractRay pod Camera3D (obok Cofanie), inaczej cofa się razem z latarką.")

	_baza = transform

	# Pozycja modelu w przestrzeni kamery (punkt obrotu przy pochylaniu)
	var kamera_inv := _kamera.global_transform.affine_inverse()
	_pivot = (kamera_inv * obiekt.global_transform).origin

	if swiatlo:
		_energia = swiatlo.light_energy

	# Promień wykrywający ścianę przed ręką
	_ray = RayCast3D.new()
	_ray.collision_mask = maska_kolizji
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true
	_ray.position = Vector3(_pivot.x, _pivot.y, 0.0)
	var dystans := absf(_pivot.z) + dlugosc_obiektu + margines
	_ray.target_position = Vector3(0.0, 0.0, -dystans)
	_kamera.add_child.call_deferred(_ray)
	await get_tree().process_frame

	# Wyklucz gracza (CharacterBody3D) i kolizje samego modelu
	var node: Node = _kamera
	while node:
		if node is CollisionObject3D:
			_ray.add_exception(node)
		node = node.get_parent()
	_wyklucz_dzieci(self)


func _wyklucz_dzieci(wezel: Node) -> void:
	for dziecko in wezel.get_children():
		if dziecko is CollisionObject3D:
			_ray.add_exception(dziecko)
		_wyklucz_dzieci(dziecko)


func _process(delta: float) -> void:
	if _ray == null or not is_instance_valid(_ray) or not _ray.is_inside_tree():
		return

	var cofniecie := 0.0
	if _ray.is_colliding():
		var trafienie := _ray.to_local(_ray.get_collision_point())
		var odleglosc := absf(trafienie.z)
		var potrzebne := absf(_pivot.z) + dlugosc_obiektu + margines
		cofniecie = clampf(potrzebne - odleglosc, 0.0, maks_cofniecie)

	var wspolczynnik := cofniecie / maxf(maks_cofniecie, 0.001)

	# Obrót wokół pozycji modelu (nie wokół kamery) + cofnięcie do tyłu
	var rot := Basis(Vector3.RIGHT, deg_to_rad(-pochylenie_stopnie * wspolczynnik))
	var przesuniecie := Vector3(0.0, -0.05 * wspolczynnik, cofniecie)
	var cel := _baza * Transform3D(rot, _pivot - rot * _pivot + przesuniecie)

	var t := 1.0 - exp(-plynnosc * delta)
	transform = transform.interpolate_with(cel, t)

	if przyciemnianie_przy_scianie > 0.0 and swiatlo and is_instance_valid(swiatlo):
		var cel_energia := _energia * (1.0 - przyciemnianie_przy_scianie * wspolczynnik)
		swiatlo.light_energy = lerpf(swiatlo.light_energy, cel_energia, t)
