extends Node3D
# Rozstawia baterie w losowych punktach.
# Użycie: dodaj ten węzeł do poziomu, a jako jego dzieci wstaw Marker3D
# w miejscach, gdzie mogą leżeć baterie (połóż je na podłodze).
# Przy każdym starcie sceny wybierana jest losowa część punktów.

@export var scena_baterii: PackedScene                      # scena baterii (StaticBody3D z przedmiot.gd)
@export_range(0.0, 1.0, 0.05) var szansa: float = 0.5       # szansa, że w danym punkcie pojawi się bateria
@export var maks_baterii: int = 15                          # twardy limit sztuk na scenę
@export var losowy_obrot: bool = true
@export var ukryj_markery: bool = true


func _ready() -> void:
	if scena_baterii == null:
		push_warning("baterie_spawner: pole 'Scena Baterii' jest puste")
		return

	var punkty: Array[Marker3D] = []
	for dziecko in get_children():
		if dziecko is Marker3D:
			punkty.append(dziecko)
	punkty.shuffle()   # żeby limit nie faworyzował pierwszych punktów

	var ile := 0
	for punkt in punkty:
		if ile >= maks_baterii:
			break
		if randf() > szansa:
			continue
		var bateria := scena_baterii.instantiate() as Node3D
		if bateria == null:
			push_warning("baterie_spawner: korzeń sceny baterii musi być Node3D")
			return
		add_child(bateria)
		bateria.global_transform = punkt.global_transform
		if losowy_obrot:
			bateria.rotate_y(randf() * TAU)
		ile += 1

	if ukryj_markery:
		for punkt in punkty:
			punkt.visible = false
