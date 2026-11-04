extends CanvasLayer
# Intro po starcie nowej gry: czarne tło pojawia się powoli, napisy wchodzą fade'em
# linia po linii z góry na dół, potem strona powoli zanika, a na końcu całe intro.
# Samo przechodzi dalej (czas czytania zależy od długości tekstu). SPACJA (lub ESC) = pomiń.
#
# Użycie: w scenie gry (start_game.tscn) dodaj zwykły Node o nazwie "Intro",
# przypisz ten skrypt i wszystko edytuj w Inspektorze.
# Tekst: każda linia to osobny napis, strony rozdzielaj linią  ---
# Intro pokazuje się raz na uruchomienie gry (po śmierci i ZRESETUJ nie wraca).

@export_group("Treść")
@export var nazwa_postaci: String = "IMIĘ NAZWISKO"
@export var podtytul: String = "uczeń, 17 lat"
@export_multiline var tekst: String = """Wpisz tutaj historię postaci.
Każda linia pojawia się osobno, jedna pod drugą.
---
Drugą stronę oddzielasz linią z trzema myślnikami.
---
Trzecia strona. Tyle ich, ile chcesz."""

@export_group("Wygląd")
@export var font: Font                          # wrzuć tu Monocraft.ttf
@export var rozmiar_tytulu: int = 64
@export var rozmiar_tekstu: int = 30
@export var rozmiar_podpowiedzi: int = 20
@export var kolor_tytulu: Color = Color(0.85, 0.12, 0.09)
@export var kolor_tekstu: Color = Color(0.92, 0.92, 0.92)
@export var kolor_tla: Color = Color.BLACK

@export_group("Tempo")
@export var czas_wejscia: float = 2.0                # tło intro pojawia się z gry (s)
@export var czas_pojawiania_linii: float = 1.4       # ile trwa fade jednej linii (s)
@export var odstep_miedzy_liniami: float = 1.0       # co ile s startuje następna linia
@export var czas_czytania_na_znak: float = 0.06      # s na znak: czas, jaki strona stoi po pojawieniu się
@export var min_czas_czytania: float = 2.5           # minimalny czas stania strony (s)
@export var czas_znikania_strony: float = 1.5        # fade out strony (s)
@export var przerwa_miedzy_stronami: float = 0.8
@export var czas_zakonczenia: float = 2.5            # końcowy, powolny fade całego intro (s)
@export var czas_skipu: float = 0.6                  # fade po wciśnięciu SPACJI (s)

@export_group("Zachowanie")
@export var pauzuj_gre: bool = true                  # gra stoi w miejscu na czas intro
@export var pokazuj_przy_kazdym_starcie: bool = false   # true = także po śmierci / restarcie sceny

const GRUPA := "intro_aktywne"   # pauza.gd po tym wie, że nie wolno otwierać menu

static var _pokazane: bool = false

var _f: Font
var _root: Control
var _naglowek: Array[CanvasItem] = []
var _strona_box: VBoxContainer
var _hint: Label
var _strony: PackedStringArray = []
var _linie: Array[Label] = []
var _tweeny: Array[Tween] = []
var _koniec: bool = false


func _ready() -> void:
	layer = 95   # nad ekranem śmierci (90), pod jumpscare (100+)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _pokazane and not pokazuj_przy_kazdym_starcie:
		queue_free()
		return
	_strony = _podziel(tekst)
	if _strony.is_empty():
		queue_free()
		return
	_pokazane = true
	add_to_group(GRUPA)
	_zbuduj()
	_start.call_deferred()   # po _ready gracza, który ustawia kursor


func _podziel(txt: String) -> PackedStringArray:
	var wynik := PackedStringArray()
	for kawalek in txt.split("---"):
		var s := kawalek.strip_edges()
		if s != "":
			wynik.append(s)
	return wynik


# ---------- Budowa ----------

func _font_zastepczy() -> Font:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(
		["Monocraft", "Minecraft", "Minecraftia", "Consolas", "DejaVu Sans Mono", "monospace"])
	sf.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	sf.hinting = TextServer.HINTING_NONE
	sf.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return sf


func _etykieta(txt: String, rozmiar: int, kolor: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	l.add_theme_font_override("font", _f)
	l.add_theme_font_size_override("font_size", rozmiar)
	l.add_theme_color_override("font_color", kolor)
	# cień jak w Minecrafcie: przyciemniona kopia koloru, przesunięta w dół i w prawo
	l.add_theme_color_override("font_shadow_color", Color(kolor.darkened(0.75), 1.0))
	l.add_theme_constant_override("shadow_offset_x", maxi(rozmiar / 8, 2))
	l.add_theme_constant_override("shadow_offset_y", maxi(rozmiar / 8, 2))
	l.modulate.a = 0.0
	return l


func _zbuduj() -> void:
	_f = font if font != null else _font_zastepczy()

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_root.modulate.a = 0.0
	add_child(_root)

	var tlo := ColorRect.new()
	tlo.color = kolor_tla
	tlo.set_anchors_preset(Control.PRESET_FULL_RECT)
	tlo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(tlo)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 140)
	margin.add_theme_constant_override("margin_right", 140)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 110)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	# nagłówek (pojawia się raz, na początku, i stoi do końca intro)
	var tytul := _etykieta(nazwa_postaci, rozmiar_tytulu, kolor_tytulu)
	box.add_child(tytul)
	_naglowek.append(tytul)

	if podtytul.strip_edges() != "":
		var pod := _etykieta(podtytul, rozmiar_tekstu, kolor_tekstu.darkened(0.35))
		box.add_child(pod)
		_naglowek.append(pod)

	var linia := ColorRect.new()
	linia.color = kolor_tytulu.darkened(0.4)
	linia.custom_minimum_size = Vector2(0, 4)
	linia.mouse_filter = Control.MOUSE_FILTER_IGNORE
	linia.modulate.a = 0.0
	box.add_child(linia)
	_naglowek.append(linia)

	# treść: linie jedna pod drugą, układ stały (puste, dopóki nie wjadą)
	_strona_box = VBoxContainer.new()
	_strona_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_strona_box.add_theme_constant_override("separation", 14)
	_strona_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_strona_box)

	_hint = _etykieta("[SPACJA] pomiń", rozmiar_podpowiedzi, Color(0.65, 0.65, 0.65))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -80.0
	_hint.offset_bottom = -30.0
	_root.add_child(_hint)


func _zbuduj_strone(txt: String) -> void:
	for c in _strona_box.get_children():
		_strona_box.remove_child(c)
		c.queue_free()
	_strona_box.modulate.a = 1.0
	_linie.clear()

	for surowa in txt.split("\n"):
		var s := surowa.strip_edges()
		if s == "":
			var odstep := Control.new()
			odstep.custom_minimum_size = Vector2(0, rozmiar_tekstu)
			odstep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_strona_box.add_child(odstep)
			continue
		var l := _etykieta(s, rozmiar_tekstu, kolor_tekstu)
		_strona_box.add_child(l)
		_linie.append(l)


# ---------- Przebieg ----------

func _start() -> void:
	if pauzuj_gre:
		get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_przebieg()


func _fade(w: CanvasItem, cel: float, czas: float) -> void:
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.tween_property(w, "modulate:a", cel, maxf(czas, 0.01))
	_tweeny.append(tw)


func _czekaj(czas: float) -> void:
	await get_tree().create_timer(maxf(czas, 0.01)).timeout


func _przebieg() -> void:
	# 1) tło wjeżdża powoli
	_fade(_root, 1.0, czas_wejscia)
	await _czekaj(czas_wejscia + 0.3)
	if _koniec:
		return

	# 2) nagłówek: tytuł, podtytuł, linia (z góry na dół)
	_fade(_hint, 0.6, czas_pojawiania_linii)
	for w in _naglowek:
		_fade(w, 1.0, czas_pojawiania_linii)
		await _czekaj(odstep_miedzy_liniami)
		if _koniec:
			return
	await _czekaj(czas_pojawiania_linii - odstep_miedzy_liniami)
	if _koniec:
		return

	# 3) strony: linie wjeżdżają po kolei, strona stoi czas potrzebny na przeczytanie, zanika
	for i in _strony.size():
		_zbuduj_strone(_strony[i])
		for l in _linie:
			_fade(l, 1.0, czas_pojawiania_linii)
			await _czekaj(odstep_miedzy_liniami)
			if _koniec:
				return

		var czytanie := maxf(_strony[i].length() * czas_czytania_na_znak, min_czas_czytania)
		await _czekaj(czas_pojawiania_linii + czytanie)
		if _koniec:
			return

		if i < _strony.size() - 1:
			_fade(_strona_box, 0.0, czas_znikania_strony)
			await _czekaj(czas_znikania_strony + przerwa_miedzy_stronami)
			if _koniec:
				return

	# 4) ostatnia strona nie znika osobno: powoli gaśnie całe intro (napisy + tło razem)
	_zakoncz(czas_zakonczenia)


func _input(event: InputEvent) -> void:
	if _koniec:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.physical_keycode == KEY_SPACE or event.physical_keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		_zakoncz(czas_skipu)


func _zakoncz(czas: float) -> void:
	if _koniec:
		return
	_koniec = true
	for t in _tweeny:
		if t.is_valid():
			t.kill()
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, maxf(czas, 0.01))
	await tw.finished
	if pauzuj_gre:
		get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_free()   # razem z tym znika grupa "intro_aktywne"
