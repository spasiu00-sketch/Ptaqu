extends StaticBody3D
# Przedmiot leżący na ziemi. Gracz podnosi go klawiszem E (patrz player.gd).

# Tekst wyświetlany na ekranie po najechaniu na przedmiot (po "[E] ")
@export var prompt_text: String = "Podnieś"

func interact(player: Node) -> void:
	if player.has_method("give_flashlight"):
		player.give_flashlight()
		queue_free()   # usuwa przedmiot ze sceny po podniesieniu
