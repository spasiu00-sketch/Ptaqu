extends Node
# Autoload "Inventory" (Project Settings -> Globals -> Autoload).

signal zmieniono

const ROZMIAR := 20
var sloty: Array = []   # każdy slot: {"item": Item, "ilosc": int} albo null


func _ready() -> void:
	sloty.resize(ROZMIAR)
	sloty.fill(null)


func _max_w_slocie(item: Item) -> int:
	return item.max_stack if item.stackowalny else 1


# Czy cała podana ilość zmieści się w ekwipunku
func ma_miejsce(item: Item, ilosc: int = 1) -> bool:
	if item == null:
		return false
	var na_slot := _max_w_slocie(item)
	var wolne := 0
	for slot in sloty:
		if slot == null:
			wolne += na_slot
		elif slot.item == item:
			wolne += maxi(na_slot - slot.ilosc, 0)
	return wolne >= ilosc


# Dodaje wszystko albo nic. Zwraca false, gdy brak miejsca.
func dodaj(item: Item, ilosc: int = 1) -> bool:
	if item == null or ilosc <= 0 or not ma_miejsce(item, ilosc):
		return false
	var na_slot := _max_w_slocie(item)

	# najpierw dokładamy do istniejących stacków
	for slot in sloty:
		if ilosc <= 0:
			break
		if slot != null and slot.item == item and slot.ilosc < na_slot:
			var dodane: int = mini(na_slot - slot.ilosc, ilosc)
			slot.ilosc += dodane
			ilosc -= dodane

	# reszta do pustych slotów
	for i in ROZMIAR:
		if ilosc <= 0:
			break
		if sloty[i] == null:
			var dodane: int = mini(na_slot, ilosc)
			sloty[i] = {"item": item, "ilosc": dodane}
			ilosc -= dodane

	zmieniono.emit()
	return true


func usun(indeks: int, ilosc: int = 1) -> void:
	if indeks < 0 or indeks >= ROZMIAR:
		return
	var slot = sloty[indeks]
	if slot == null:
		return
	slot.ilosc -= ilosc
	if slot.ilosc <= 0:
		sloty[indeks] = null
	zmieniono.emit()


func ile(item: Item) -> int:
	var suma := 0
	for slot in sloty:
		if slot != null and slot.item == item:
			suma += slot.ilosc
	return suma


func ma(item: Item) -> bool:
	return ile(item) > 0
