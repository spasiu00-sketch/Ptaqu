extends Node
# Ambient / muzyka w tle w trakcie gry (słyszana "w głowie" gracza, nie z konkretnego miejsca).
# Użycie: dodaj do sceny poziomu zwykły węzeł Node, przypisz ten skrypt
# i wybierz plik dźwiękowy w polu "Muzyka".
# Sterowanie z innych skryptów (np. jumpscare):
#   $Ambient.ustaw_glosnosc(-30.0, 0.5)   # ściszenie
#   $Ambient.zatrzymaj(2.0)               # płynne wyciszenie i stop
#   $Ambient.start()                      # ponowny start

@export var muzyka: AudioStream
@export_range(-40.0, 6.0, 0.5) var glosnosc_db: float = -12.0
@export var fade_in: float = 4.0            # płynne wejście muzyki (s)
@export var opoznienie_startu: float = 0.0  # ile sekund po starcie sceny zacznie grać
@export var autostart: bool = true

const CISZA_DB := -60.0

var _player: AudioStreamPlayer
var _tween: Tween


func _ready() -> void:
	if muzyka == null:
		push_warning("ambient: nie wybrano pliku w polu 'Muzyka'")
		return

	_player = AudioStreamPlayer.new()
	_player.name = "AmbientPlayer"
	_player.stream = muzyka
	_player.volume_db = CISZA_DB
	add_child(_player)

	# OGG / MP3 zapętlamy w stremie, resztę (np. WAV) odpalamy ponownie po końcu
	if not _zapetl(muzyka):
		_player.finished.connect(_player.play)

	if autostart:
		start()


func _zapetl(stream: AudioStream) -> bool:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
		return true
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
		return true
	return false


func start() -> void:
	if _player == null or _player.playing:
		return
	if opoznienie_startu > 0.0:
		await get_tree().create_timer(opoznienie_startu).timeout
		if not is_instance_valid(_player) or _player.playing:
			return
	_player.volume_db = CISZA_DB
	_player.play()
	ustaw_glosnosc(glosnosc_db, maxf(fade_in, 0.01))


func ustaw_glosnosc(db: float, czas: float = 1.0) -> void:
	if _player == null:
		return
	_zabij_tween()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", db, maxf(czas, 0.01))


func zatrzymaj(czas: float = 2.0) -> void:
	if _player == null or not _player.playing:
		return
	_zabij_tween()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", CISZA_DB, maxf(czas, 0.01))
	_tween.tween_callback(_player.stop)


func _zabij_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
