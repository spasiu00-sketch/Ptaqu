class_name InventorySlot
extends RefCounted
# Jeden zajęty slot ekwipunku (pusty slot = null w Inventory.sloty).

var item: Item
var ilosc: int = 1


func _init(p_item: Item = null, p_ilosc: int = 1) -> void:
	item = p_item
	ilosc = p_ilosc
