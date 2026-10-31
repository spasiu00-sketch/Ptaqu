extends Node

signal zmieniono

const ROZMIAR := 20
var sloty: Array = []  # każdy slot: {"item": Item, "ilosc": int} albo null

func _ready() -> void:
	sloty.resize(ROZMIAR)
	sloty.fill(null)

func dodaj(item: Item, ilosc: int = 1) -> bool:
	# najpierw dołóż do istniejącego stacka
	if item.stackowalny:
		for slot in sloty:
			if slot and slot.item == item and slot.ilosc < item.max_stack:
				var wolne = item.max_stack - slot.ilosc
				var dodane = min(wolne, ilosc)
				slot.ilosc += dodane
				ilosc -= dodane
				if ilosc <= 0:
					zmieniono.emit()
					return true
	# potem szukaj pustego slotu
	for i in ROZMIAR:
		if sloty[i] == null:
			sloty[i] = {"item": item, "ilosc": ilosc}
			zmieniono.emit()
			return true
	return false  # brak miejsca

func usun(indeks: int, ilosc: int = 1) -> void:
	var slot = sloty[indeks]
	if slot == null:
		return
	slot.ilosc -= ilosc
	if slot.ilosc <= 0:
		sloty[indeks] = null
	zmieniono.emit()
