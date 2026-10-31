class_name Item
extends Resource
# Definicja przedmiotu. Twórz pliki .tres typu Item (Nowy zasób -> Item).

const ODLEGLOSC_RZUTU := 1.0   # ile metrów przed graczem ląduje wyrzucony przedmiot
const MARGINES_SCIANY := 0.3   # odstęp od ściany, gdy przed graczem jest przeszkoda

@export var nazwa: String = "Przedmiot"
@export_multiline var opis: String = ""
@export var ikona: Texture2D
@export var stackowalny: bool = false
@export_range(1, 99) var max_stack: int = 1
@export var uzywalny: bool = false
@export var laduje_baterie: float = 0.0   # >0 = po użyciu ładuje baterię latarki o tyle (max 100)

@export_group("Wyrzucanie")
@export var scena_swiata: PackedScene     # model przedmiotu na ziemi (opcjonalnie, jeśli puste, używana jest kopia zapamiętana przy podniesieniu)
@export var jest_latarka: bool = false    # true = wyrzucenie zabiera graczowi latarkę (zachowuje baterię)

# Kopia węzła przedmiotu zapamiętana przy podniesieniu (tylko w trakcie gry, nie zapisuje się do pliku)
var szablon: Node3D = null


# Zwraca true, jeśli przedmiot został zużyty
func uzyj(gracz: Node) -> bool:
	if not uzywalny or gracz == null:
		return false
	if laduje_baterie > 0.0:
		var latarka = gracz.get("flashlight")
		if latarka != null and latarka.battery < latarka.max_battery:
			latarka.charge_battery(laduje_baterie)
			return true
	return false


# Kładzie model przedmiotu na ziemi przed graczem. Zwraca true, jeśli się udało
# (wtedy ekwipunek ma usunąć jedną sztukę).
func wyrzuc(gracz: Node3D) -> bool:
	if gracz == null:
		return false

	# latarka: zapamiętujemy baterię, nie wyrzucamy w trakcie wymiany baterii
	var latarka = null
	var bateria := -1.0
	if jest_latarka:
		latarka = gracz.get("flashlight")
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

	gracz.get_tree().current_scene.add_child(instancja)
	instancja.global_position = _znajdz_miejsce(gracz)
	instancja.global_rotation.y = gracz.global_rotation.y

	if not _ustaw_przedmiot(instancja, bateria, instancja):
		push_warning("Item '%s': w modelu nie znaleziono przedmiot.gd, nie da się go podnieść" % nazwa)

	if jest_latarka:
		_zabierz_latarke(gracz)
	return true


func _ustaw_przedmiot(wezel: Node, bateria: float, korzen: Node) -> bool:
	if wezel.has_method("ustaw_wyrzucony"):
		wezel.ustaw_wyrzucony(self, bateria, korzen)
		return true
	for dziecko in wezel.get_children():
		if _ustaw_przedmiot(dziecko, bateria, korzen):
			return true
	return false


# Gasi latarkę i chowa model z ręki. Działanie wraca po podniesieniu (give_flashlight).
func _zabierz_latarke(gracz: Node3D) -> void:
	var latarka = gracz.get("flashlight")
	if latarka != null:
		latarka.unlocked = false
		latarka._f_down = false
		latarka._f_handled = false
		latarka._f_time = 0.0
		latarka._set_light(false)
	var reka = gracz.get("held_root")
	if reka != null:
		reka.visible = false


# Punkt na podłodze przed graczem (z uwzględnieniem ścian)
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

	# ściana przed graczem -> kładziemy bliżej
	var dystans := ODLEGLOSC_RZUTU
	var q_sciana := PhysicsRayQueryParameters3D.create(glowa, glowa + przod * ODLEGLOSC_RZUTU)
	q_sciana.exclude = wyklucz
	var sciana := swiat.intersect_ray(q_sciana)
	if not sciana.is_empty():
		dystans = maxf(glowa.distance_to(sciana["position"]) - MARGINES_SCIANY, 0.2)

	var punkt := glowa + przod * dystans

	# podłoga pod tym punktem
	var q_podloga := PhysicsRayQueryParameters3D.create(punkt, punkt + Vector3.DOWN * 4.0)
	q_podloga.exclude = wyklucz
	var podloga := swiat.intersect_ray(q_podloga)
	if podloga.is_empty():
		return gracz.global_position + przod * dystans
	return podloga["position"]
