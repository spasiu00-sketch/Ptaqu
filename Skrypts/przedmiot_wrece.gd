extends Node3D
# Dowolny przedmiot trzymany w ręku (aparat, łyżka, klucz...).
# Wisi na korzeniu modelu, który jest dzieckiem węzła "Reka" (patrz reka_przedmiotow.gd).
# Przedmiot jest dostępny, gdy gracz ma w ekwipunku Item z pola "Item"
# (albo gdy zaznaczone "Zawsze Dostepny", przydatne do testów).
#
# LPM = użycie: dźwięk, animacja, błysk światła (np. flesz aparatu) i sygnał "uzyto".
# Własne zachowanie dodasz, podpinając się pod sygnał: $Aparat.uzyto.connect(...)

signal uzyto

@export var nazwa_przedmiotu: String = "Przedmiot"   # pokazuje się po wyjęciu z kieszeni
@export var item: Item                               # ten sam plik .tres, który podnosisz z ziemi
@export var zawsze_dostepny: bool = false

@export_group("Użycie (LPM)")
@export var odstep: float = 0.5                      # minimalny czas między użyciami (s)
@export var dzwiek: AudioStream
@export var glosnosc_db: float = 0.0
@export var anim_player: AnimationPlayer             # puste = pierwszy AnimationPlayer w tym modelu
@export var animacja: StringName = &""               # puste = bez animacji
@export var blysk: Light3D                           # np. OmniLight3D jako flesz (domyślnie wyłączony)
@export var blysk_czas: float = 0.08

var _sfx: AudioStreamPlayer
var _zajety: bool = false
var _wyposazony: bool = false


func _ready() -> void:
	_sfx = AudioStreamPlayer.new()
	_sfx.volume_db = glosnosc_db
	add_child(_sfx)

	if anim_player == null:
		var playery := find_children("*", "AnimationPlayer", true, false)
		if not playery.is_empty():
			anim_player = playery[0] as AnimationPlayer
	if blysk != null:
		blysk.visible = false


# ---------- Interfejs dla reka_przedmiotow.gd ----------

func czy_dostepny() -> bool:
	if zawsze_dostepny:
		return true
	if item == null:
		return false
	var inv := get_node_or_null("/root/Inventory")
	return inv != null and bool(inv.ma(item))


func equip() -> void:
	_wyposazony = true


func unequip() -> void:
	_wyposazony = false
	if anim_player != null:
		anim_player.stop()
	if blysk != null:
		blysk.visible = false


func mozna_schowac() -> bool:
	return true


func uzyj_glowny() -> void:
	if _zajety or not _wyposazony:
		return
	_zajety = true

	if dzwiek != null:
		_sfx.stream = dzwiek
		_sfx.volume_db = glosnosc_db
		_sfx.play()
	if anim_player != null and animacja != &"" and anim_player.has_animation(animacja):
		anim_player.stop()
		anim_player.play(animacja)
	if blysk != null:
		_zablysnij()

	uzyto.emit()

	await get_tree().create_timer(maxf(odstep, 0.05)).timeout
	_zajety = false


func _zablysnij() -> void:
	blysk.visible = true
	await get_tree().create_timer(maxf(blysk_czas, 0.01)).timeout
	if is_instance_valid(blysk):
		blysk.visible = false
