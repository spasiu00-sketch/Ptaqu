class_name Item
extends Resource
# Definicja przedmiotu. Twórz pliki .tres typu Item (Nowy zasób -> Item).

@export var nazwa: String = "Przedmiot"
@export_multiline var opis: String = ""
@export var ikona: Texture2D
@export var stackowalny: bool = false
@export_range(1, 99) var max_stack: int = 1
@export var uzywalny: bool = false
@export var laduje_baterie: float = 0.0   # >0 = po użyciu ładuje baterię latarki o tyle (max 100)


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
