extends StaticBody3D
# Przedmiot leżący na ziemi. Gracz podnosi go klawiszem E (patrz character_body_3d.gd).
# Skrypt wisi na węźle StaticBody3D. Model i kolizja są jego dziećmi albo rodzeństwem w tej samej scenie.

# Tekst wyświetlany na ekranie po najechaniu na przedmiot (po "[E] ")
@export var prompt_text: String = "Podnieś"
@export var daje_latarke: bool = true   # true = ten przedmiot to latarka (odblokowuje ją)
@export var item: Item                  # opcjonalnie: przedmiot wkładany do ekwipunku
@export var ilosc: int = 1
# Co usunąć po podniesieniu. Puste = automatycznie: korzeń sceny przedmiotu (np. "Latarka"),
# a jeśli StaticBody3D leży bezpośrednio w scenie poziomu, tylko ten węzeł.
@export var korzen_do_usuniecia: Node

# Stan baterii zapamiętany przy wyrzuceniu latarki (-1 = brak, nie zmieniamy baterii)
var bateria: float = -1.0


# Wywoływane przez Item.wyrzuc() zaraz po postawieniu modelu na ziemi
func ustaw_wyrzucony(wyrzucony: Item, zapisana_bateria: float, korzen: Node) -> void:
	item = wyrzucony
	ilosc = 1
	daje_latarke = wyrzucony.jest_latarka
	bateria = zapisana_bateria
	korzen_do_usuniecia = korzen   # po podniesieniu znika cały wyrzucony model


func interact(player: Node) -> void:
	var cel := _cel_usuniecia()
	_przygotuj_item(cel)

	if item != null:
		var inv := get_node_or_null("/root/Inventory")
		if inv == null or not inv.dodaj(item, ilosc):
			return   # brak miejsca albo brak autoloadu: przedmiot zostaje na ziemi

	if daje_latarke and player.has_method("give_flashlight"):
		# najpierw przywracamy baterię, potem włączamy latarkę
		if bateria >= 0.0:
			var latarka = player.get("flashlight")
			if latarka != null:
				latarka.battery = clampf(bateria, 0.0, latarka.max_battery)
		player.give_flashlight()

	cel.queue_free()


# Zapewnia, że przedmiot w ekwipunku da się wyrzucić: latarka dostaje własny Item
# (jeśli pole Item jest puste), a Item zapamiętuje model do postawienia na ziemi.
func _przygotuj_item(cel: Node) -> void:
	if daje_latarke:
		if item == null:
			item = Item.new()
			item.nazwa = "Latarka"
			item.opis = "Latarka na baterie."
		item.jest_latarka = true

	if item == null or item.scena_swiata != null:
		return

	# kopia węzła (model + kolizja + ten skrypt), robiona zanim przedmiot zniknie z ziemi
	var kopia := cel.duplicate() as Node3D
	if kopia == null:
		push_warning("przedmiot.gd: nie udało się zapamiętać modelu (korzeń przedmiotu musi być Node3D)")
		return

	# stara kopia (jeśli jest, jest ważna i nie wisi w drzewie) idzie do usunięcia
	var stara = item.szablon
	if is_instance_valid(stara) and not stara.is_inside_tree():
		stara.queue_free()
	item.szablon = kopia


# Co usunąć po podniesieniu
func _cel_usuniecia() -> Node:
	if is_instance_valid(korzen_do_usuniecia):
		return korzen_do_usuniecia
	var rodzic := get_parent()
	# rodzic jest korzeniem wstawionej sceny przedmiotu (a nie całym poziomem)
	if rodzic != null and rodzic != get_tree().current_scene and rodzic.scene_file_path != "":
		return rodzic
	return self
