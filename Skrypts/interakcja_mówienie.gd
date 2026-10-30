extends StaticBody3D

@export var prompt_text: String = "Obejrzyj"   # pokaże się jako "[E] Obejrzyj"
@export_multiline var tekst: String = "Wpisz tutaj tekst w Inspektorze."
@export var czas_wyswietlania: float = 4.0
@export var efekt_pisania: bool = true
@export var czytaj_na_glos: bool = false   # synteza mowy systemu (TTS)
@export var dzwiek: AudioStream            # opcjonalny dźwięk przy interakcji
@export var tylko_raz: bool = false
@export var debug_czas: bool = false       # true = wypisuje w Output, ile ms trwa każdy etap

const GRUPA_NAPISU := "napis_dialogowy"
const JEZYK_TTS := "pl"
const GLOSNOSC_TTS := 50
const PREDKOSC_PISANIA := 0.03   # sekundy na jeden znak
const ZNAKI_POLSKIE := "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ"

# Wspólne dla wszystkich obiektów: głos TTS wybieramy i "rozgrzewamy" tylko raz,
# przy starcie sceny, a nie w momencie naciśnięcia E.
static var _glos_tts: String = ""
static var _glos_gotowy: bool = false

var _uzyty := false
var _pisze := false   # true, dopóki trwa efekt pisania tekstu
var _audio: AudioStreamPlayer3D
var _tween: Tween


func _ready() -> void:
	if dzwiek:
		_audio = AudioStreamPlayer3D.new()
		_audio.stream = dzwiek
		add_child(_audio)
	_rozgrzej_napis.call_deferred()
	if czytaj_na_glos:
		_przygotuj_glos.call_deferred()


# Wywoływane przez gracza po naciśnięciu [E] (z argumentem lub bez)
func interact(_gracz = null) -> void:
	if tylko_raz and _uzyty:
		return
	# Ponowna interakcja w trakcie pisania / czytania przerywałaby TTS (ok. 200 ms laga),
	# dlatego ignorujemy ją, aż poprzednia się skończy
	if _zajety():
		return
	_uzyty = true

	var t0 := Time.get_ticks_usec()
	_pokaz_napis(tekst)
	t0 = _zmierz("napis", t0)

	if _audio:
		_audio.play()
		t0 = _zmierz("dźwięk", t0)

	if czytaj_na_glos:
		_mow(tekst)
		_zmierz("TTS", t0)


func _zajety() -> bool:
	return _pisze or (czytaj_na_glos and DisplayServer.tts_is_speaking())


func _zmierz(nazwa: String, start: int) -> int:
	if debug_czas:
		print("[interakcja] %s: %.1f ms" % [nazwa, (Time.get_ticks_usec() - start) / 1000.0])
	return Time.get_ticks_usec()


# ---------- Napis ----------

func _pobierz_label() -> Label:
	var istniejacy := get_tree().get_first_node_in_group(GRUPA_NAPISU) as Label
	if istniejacy:
		return istniejacy
	return _stworz_label()


func _stworz_label() -> Label:
	var warstwa := CanvasLayer.new()
	warstwa.layer = 50
	get_tree().root.add_child(warstwa)

	var label := Label.new()
	label.add_to_group(GRUPA_NAPISU)
	label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -140
	label.offset_bottom = -40
	label.offset_left = 80
	label.offset_right = -80
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	warstwa.add_child(label)
	return label


# Tworzy etykietę z góry i rysuje na niej (niewidocznie) polskie znaki,
# żeby czcionka wygenerowała glify przy starcie, a nie przy pierwszej interakcji
func _rozgrzej_napis() -> void:
	var label := _pobierz_label()
	if label.text == "":
		label.text = ZNAKI_POLSKIE + " 0123456789 abcdefghijklmnopqrstuvwxyz"
		label.modulate.a = 0.0


func _pokaz_napis(t: String) -> void:
	var label := _pobierz_label()
	if _tween and _tween.is_valid():
		_tween.kill()

	label.text = t
	label.modulate.a = 1.0

	_tween = create_tween()
	if efekt_pisania:
		_pisze = true
		label.visible_ratio = 0.0
		_tween.tween_property(label, "visible_ratio", 1.0, maxf(0.3, t.length() * PREDKOSC_PISANIA))
		_tween.tween_callback(func() -> void: _pisze = false)
	else:
		label.visible_ratio = 1.0

	_tween.tween_interval(czas_wyswietlania)
	_tween.tween_property(label, "modulate:a", 0.0, 0.6)


# ---------- Mowa (TTS) ----------

# Wybiera głos i wypowiada ciszę (głośność 0), żeby silnik mowy uruchomił się przy starcie
func _przygotuj_glos() -> void:
	if _glos_gotowy:
		return
	_glos_gotowy = true
	var glosy := DisplayServer.tts_get_voices_for_language(JEZYK_TTS)
	if glosy.is_empty():
		push_warning("Brak polskiego głosu TTS w systemie – pokazuję tylko napis.")
		return
	_glos_tts = glosy[0]
	DisplayServer.tts_speak(".", _glos_tts, 0)


func _mow(t: String) -> void:
	_przygotuj_glos()   # zabezpieczenie, gdyby _ready nie zdążyło
	if _glos_tts == "":
		return
	DisplayServer.tts_speak(t, _glos_tts, GLOSNOSC_TTS)
