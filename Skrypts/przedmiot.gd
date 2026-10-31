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


func interact(player: Node) -> void:
	if item != null:
		var inv := get_node_or_null("/root/Inventory")
		if inv == null or not inv.dodaj(item, ilosc):
			return   # brak miejsca albo brak autoloadu: przedmiot zostaje na ziemi

	if daje_latarke and player.has_method("give_flashlight"):
		player.give_flashlight()

	_usun_przedmiot()


func _usun_przedmiot() -> void:
	var cel: Node = korzen_do_usuniecia
	if cel == null:
		var rodzic := get_parent()
		# rodzic jest korzeniem wstawionej sceny przedmiotu (a nie całym poziomem)
		if rodzic != null and rodzic != get_tree().current_scene and rodzic.scene_file_path != "":
			cel = rodzic
		else:
			cel = self
	cel.queue_free()
