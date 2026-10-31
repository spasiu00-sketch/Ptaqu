class_name InventoryUI
extends CanvasLayer
# Ekwipunek budowany w kodzie. Tworzy go player (character_body_3d.gd), otwierany klawiszem Tab.

const KOLUMNY := 5

var gracz: Node
var otwarty: bool = false

var _inv: Node
var _siatka: GridContainer
var _przyciski: Array[Button] = []
var _opis: Label
var _btn_uzyj: Button
var _btn_wyrzuc: Button
var _wybrany: int = -1


func _ready() -> void:
	layer = 3   # nad HUD (2), pod jumpscare (100+)
	visible = false
	_inv = get_node_or_null("/root/Inventory")
	if _inv == null:
		push_warning("InventoryUI: brak autoloadu 'Inventory' (Project Settings -> Globals -> Autoload)")
		return
	_zbuduj()
	_inv.zmieniono.connect(_odswiez)


func otworz() -> void:
	if _inv == null:
		return
	otwarty = true
	visible = true
	_wybrany = -1
	_odswiez()


func zamknij() -> void:
	otwarty = false
	visible = false


func _zbuduj() -> void:
	var centrum := CenterContainer.new()
	centrum.set_anchors_preset(Control.PRESET_FULL_RECT)
	centrum.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centrum)

	var panel := PanelContainer.new()
	var styl := StyleBoxFlat.new()
	styl.bg_color = Color(0.04, 0.03, 0.04, 0.92)
	styl.border_color = Color(0.55, 0.08, 0.06)
	styl.set_border_width_all(2)
	styl.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", styl)
	centrum.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var tytul := Label.new()
	tytul.text = "EKWIPUNEK"
	tytul.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tytul.add_theme_font_size_override("font_size", 28)
	tytul.add_theme_color_override("font_color", Color(0.9, 0.25, 0.2))
	box.add_child(tytul)

	_siatka = GridContainer.new()
	_siatka.columns = KOLUMNY
	_siatka.add_theme_constant_override("h_separation", 6)
	_siatka.add_theme_constant_override("v_separation", 6)
	box.add_child(_siatka)

	for i in _inv.ROZMIAR:
		var b := Button.new()
		b.custom_minimum_size = Vector2(110, 70)
		b.clip_text = true
		b.focus_mode = Control.FOCUS_NONE
		b.expand_icon = true
		b.pressed.connect(_wybierz.bind(i))
		_siatka.add_child(b)
		_przyciski.append(b)

	_opis = Label.new()
	_opis.custom_minimum_size = Vector2(0, 60)
	_opis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_opis)

	var akcje := HBoxContainer.new()
	akcje.alignment = BoxContainer.ALIGNMENT_CENTER
	akcje.add_theme_constant_override("separation", 12)
	box.add_child(akcje)

	_btn_uzyj = Button.new()
	_btn_uzyj.text = "UŻYJ"
	_btn_uzyj.focus_mode = Control.FOCUS_NONE
	_btn_uzyj.pressed.connect(_uzyj)
	akcje.add_child(_btn_uzyj)

	_btn_wyrzuc = Button.new()
	_btn_wyrzuc.text = "WYRZUĆ"
	_btn_wyrzuc.focus_mode = Control.FOCUS_NONE
	_btn_wyrzuc.pressed.connect(_wyrzuc)
	akcje.add_child(_btn_wyrzuc)


func _wybierz(i: int) -> void:
	_wybrany = i
	_odswiez()


func _odswiez() -> void:
	if _inv == null or _przyciski.is_empty():
		return
	if _wybrany >= 0 and _inv.sloty[_wybrany] == null:
		_wybrany = -1

	for i in _przyciski.size():
		var slot = _inv.sloty[i]
		var b := _przyciski[i]
		if slot == null:
			b.text = ""
			b.icon = null
			b.tooltip_text = ""
		else:
			var item: Item = slot.item
			b.icon = item.ikona
			b.text = item.nazwa if slot.ilosc <= 1 else "%s x%d" % [item.nazwa, slot.ilosc]
			b.tooltip_text = item.opis
		b.modulate = Color(1.0, 0.6, 0.55) if i == _wybrany else Color.WHITE

	var wybrany_slot = null if _wybrany < 0 else _inv.sloty[_wybrany]
	if wybrany_slot == null:
		_opis.text = ""
		_btn_uzyj.disabled = true
		_btn_wyrzuc.disabled = true
	else:
		var it: Item = wybrany_slot.item
		_opis.text = "%s\n%s" % [it.nazwa, it.opis]
		_btn_uzyj.disabled = not it.uzywalny
		_btn_wyrzuc.disabled = false


func _uzyj() -> void:
	if _wybrany < 0:
		return
	var slot = _inv.sloty[_wybrany]
	if slot == null:
		return
	var item: Item = slot.item
	if item.uzyj(gracz):
		_inv.usun(_wybrany, 1)


func _wyrzuc() -> void:
	if _wybrany >= 0:
		_inv.usun(_wybrany, 1)
