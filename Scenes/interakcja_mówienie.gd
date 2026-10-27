extends StaticBody3D

@export var prompt_text: String = "Obejrzyj"   # pokaże się jako "[E] Obejrzyj"
@export_multiline var tekst: String = "Wpisz tutaj tekst w Inspektorze."
@export var czas_wyswietlania: float = 4.0
@export var efekt_pisania: bool = true
@export var czytaj_na_glos: bool = false   # synteza mowy systemu (TTS)
@export var dzwiek: AudioStream            # opcjonalny dźwięk przy interakcji
@export var tylko_raz: bool = false

var _uzyty := false
var _audio: AudioStreamPlayer3D
var _tween: Tween


func _ready() -> void:
	if dzwiek:
		_audio = AudioStreamPlayer3D.new()
		_audio.stream = dzwiek
		add_child(_audio)


# Wywoływane przez gracza po naciśnięciu [E] (z argumentem lub bez)
func interact(_gracz = null) -> void:
	if tylko_raz and _uzyty:
		return
	_uzyty = true

	_pokaz_napis(tekst)

	if _audio:
		_audio.play()

	if czytaj_na_glos:
		_mow(tekst)


func _pobierz_label() -> Label:
	var istniejacy := get_tree().get_first_node_in_group("napis_dialogowy")
	if istniejacy:
		return istniejacy as Label

	var warstwa := CanvasLayer.new()
	warstwa.layer = 50
	get_tree().root.add_child(warstwa)

	var label := Label.new()
	label.add_to_group("napis_dialogowy")
	label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -140
	label.offset_bottom = -40
	label.offset_left = 80
	label.offset_right = -80
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 8)
	warstwa.add_child(label)
	return label


func _pokaz_napis(t: String) -> void:
	var label := _pobierz_label()
	if _tween and _tween.is_valid():
		_tween.kill()

	label.text = t
	label.modulate.a = 1.0

	_tween = create_tween()
	if efekt_pisania:
		label.visible_ratio = 0.0
		_tween.tween_property(label, "visible_ratio", 1.0, maxf(0.3, t.length() * 0.03))
	else:
		label.visible_ratio = 1.0

	_tween.tween_interval(czas_wyswietlania)
	_tween.tween_property(label, "modulate:a", 0.0, 0.6)


func _mow(t: String) -> void:
	var glosy := DisplayServer.tts_get_voices_for_language("pl")
	if glosy.is_empty():
		push_warning("Brak polskiego głosu TTS w systemie – pokazuję tylko napis.")
		return
	DisplayServer.tts_stop()
	DisplayServer.tts_speak(t, glosy[0])
