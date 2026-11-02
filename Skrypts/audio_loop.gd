extends RefCounted
# Wspólny helper do zapętlania dźwięku (zastępuje trzy kopie: _zapetl / _loop_stream / _prepare_loop).
# Użycie (preload zamiast class_name, działa nawet gdy Godot nie odświeżył listy klas):
#   const AudioLoop := preload("res://Skrypts/audio_loop.gd")
#   if not AudioLoop.zapetl(stream):
#       player.finished.connect(player.play)   # np. WAV: odpalamy ponownie po końcu


# Włącza zapętlenie w samym strumieniu (OGG / MP3).
# Zwraca true, jeśli się udało. Dla pozostałych formatów (np. WAV) zwraca false.
static func zapetl(stream: AudioStream) -> bool:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
		return true
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
		return true
	return false
