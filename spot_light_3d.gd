class_name Flashlight
extends SpotLight3D

@export var starts_unlocked: bool = false
@export var max_battery: float = 100.0
@export var start_battery_percent: float = 100.0   # do testów: np. 15, żeby od razu migotała
@export var drain_per_second: float = 0.5
@export var base_energy: float = 3.0
@export var flicker_below: float = 20.0            # poniżej tego % zaczyna migotać
@export var hold_time: float = 3.0                 # ile sekund trzymać F, żeby przeładować

# Animacje przeładowania, odtwarzane NARAZ (spacje na początku nazw są ignorowane)
@export var reload_animations: Array[StringName] = [&"BateriaAction", &"CylinderAction", &"Cylinder_001Action"]
@export var debug_animations: bool = false
@export var debug_input: bool = false

@export_group("Dźwięki")
@export var reload_sound: AudioStream              # dźwięk wymiany baterii
@export var reload_sound_delay: float = 0.0        # opóźnienie startu dźwięku względem animacji (s)
@export var wait_for_sound: bool = true            # czy latarka czeka z zapaleniem na koniec dźwięku
@export var toggle_sound: AudioStream              # klik włączania/wyłączania
@export var flicker_start_sound: AudioStream       # gdy bateria zaczyna migotać
@export var dead_sound: AudioStream                # gdy bateria padnie
@export var sound_volume_db: float = 0.0

const PLAYER_PREFIX := "FlashlightAnim_"

var battery: float
var unlocked: bool = false
var is_on: bool = false
var is_busy: bool = false
var _players: Array = []   # AnimationPlayer lub null, kolejność jak w reload_animations
var _flicker_timer: float = 0.0
var _flicker_sound_played: bool = false

var _f_down: bool = false
var _f_time: float = 0.0
var _f_handled: bool = false

var _rest_pose: Dictionary = {}   # Node3D -> {"t": Transform3D, "v": bool}

var _sfx_reload: AudioStreamPlayer
var _sfx_toggle: AudioStreamPlayer
var _sfx_alert: AudioStreamPlayer


func _ready() -> void:
	battery = max_battery * clampf(start_battery_percent, 0.0, 100.0) / 100.0
	shadow_enabled = true
	visible = true   # NIE ruszamy visible: to rodzic modelu latarki
	unlocked = starts_unlocked

	# osobne odtwarzacze, żeby dźwięki nie ucinały się nawzajem
	_sfx_reload = _make_sfx()
	_sfx_toggle = _make_sfx()
	_sfx_alert = _make_sfx()

	_set_light(unlocked and battery > 0.0)
	_ensure_key_action("flashlight", KEY_F)

	_setup_model.call_deferred()


func _make_sfx() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db = sound_volume_db
	add_child(p)
	return p


func _play_sfx(player: AudioStreamPlayer, stream: AudioStream, delay: float = 0.0) -> void:
	if stream == null:
		return
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	player.stream = stream
	player.play()


func _ensure_key_action(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)


# ---------- Model: pozycje spoczynkowe i cienie ----------

func _setup_model() -> void:
	_save_rest_pose(self)
	_build_players()


func _save_rest_pose(node: Node) -> void:
	for child in node.get_children():
		if child is Node3D:
			_rest_pose[child] = {"t": child.transform, "v": child.visible}
		if child is GeometryInstance3D:
			# model nie może zasłaniać własnego światła
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_save_rest_pose(child)


func _restore_rest_pose() -> void:
	for node in _rest_pose:
		if is_instance_valid(node):
			node.transform = _rest_pose[node]["t"]
			node.visible = _rest_pose[node]["v"]


# ---------- Animacje ----------

# Zbiera oryginalne playery (pomija te utworzone przez ten skrypt)
func _collect_players(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is AnimationPlayer and not String(child.name).begins_with(PLAYER_PREFIX):
			out.append(child)
		_collect_players(child, out)


func _find_animation(anim_name: StringName, used: Array) -> Dictionary:
	var players: Array = []
	_collect_players(self, players)
	var wanted := String(anim_name).strip_edges().to_lower()

	# 1) dokładna nazwa (ignoruje spacje na początku/końcu)
	for p: AnimationPlayer in players:
		for full in p.get_animation_list():
			var f := String(full).strip_edges().to_lower()
			if f == wanted or f.ends_with("/" + wanted):
				return {"player": p, "key": full}

	# 2) przybliżona nazwa (bez końcówki "action"), pomija już użyte animacje
	var stripped := wanted.trim_suffix("action")
	for p: AnimationPlayer in players:
		for full in p.get_animation_list():
			var f := String(full).strip_edges().to_lower()
			if used.has(String(full)):
				continue
			if f.begins_with(stripped) or f.contains("/" + stripped):
				return {"player": p, "key": full}
	return {}


func _build_players() -> void:
	_players.clear()
	var used: Array = []

	if debug_animations:
		var all: Array = []
		_collect_players(self, all)
		for p: AnimationPlayer in all:
			print("Player: ", p.get_path(), " animacje: ", p.get_animation_list())

	for idx in reload_animations.size():
		var n := reload_animations[idx]
		var found := _find_animation(n, used)
		if found.is_empty():
			var all2: Array = []
			_collect_players(self, all2)
			var names: Array = []
			for p2: AnimationPlayer in all2:
				names.append_array(p2.get_animation_list())
			push_warning("Flashlight: NIE ZNALEZIONO animacji '%s'. Dostępne: %s" % [n, names])
			_players.append(null)
			continue

		var src: AnimationPlayer = found["player"]
		var key: StringName = found["key"]
		used.append(String(key))

		var root := src.get_node_or_null(src.root_node)
		if root == null:
			push_warning("Flashlight: root_node playera %s nie wskazuje na węzeł" % src.name)
			_players.append(null)
			continue

		var anim: Animation = src.get_animation(key).duplicate()
		anim.loop_mode = Animation.LOOP_NONE
		_fix_track_paths(anim, root, n)

		var lib := AnimationLibrary.new()
		lib.add_animation(n, anim)

		var p := AnimationPlayer.new()
		p.name = PLAYER_PREFIX + str(idx)
		src.get_parent().add_child(p)
		p.root_node = src.root_node
		p.add_animation_library(&"", lib)
		_players.append(p)

		if debug_animations:
			print("ZNALEZIONO: ", n, " jako '", key, "' | tracków po filtrze: ", anim.get_track_count(), " | długość: ", anim.length)


func _values_equal(a: Variant, b: Variant) -> bool:
	if a is Vector3 and b is Vector3:
		return (a as Vector3).is_equal_approx(b)
	if a is Quaternion and b is Quaternion:
		return (a as Quaternion).is_equal_approx(b)
	if a is Vector2 and b is Vector2:
		return (a as Vector2).is_equal_approx(b)
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b))
	return a == b


# true, jeśli track ma stałą wartość (nic nie animuje)
func _is_constant_track(anim: Animation, i: int) -> bool:
	var t := anim.track_get_type(i)
	if t != Animation.TYPE_POSITION_3D and t != Animation.TYPE_ROTATION_3D \
			and t != Animation.TYPE_SCALE_3D and t != Animation.TYPE_VALUE:
		return false
	var count := anim.track_get_key_count(i)
	if count <= 1:
		return true
	var first: Variant = anim.track_get_key_value(i, 0)
	for k in range(1, count):
		if not _values_equal(first, anim.track_get_key_value(i, k)):
			return false
	return true


# Szuka węzła po nazwie, ignorując spacje na początku/końcu nazwy
func _find_node_loose(root: Node, wanted: String) -> Node:
	var w := wanted.strip_edges()
	var direct := root.find_child(wanted, true, false)
	if direct != null:
		return direct
	var queue: Array = [root]
	while not queue.is_empty():
		var cur: Node = queue.pop_front()
		for c in cur.get_children():
			if String(c.name).strip_edges() == w:
				return c
			queue.append(c)
	return null


# Naprawia ścieżki, usuwa tracki stałe i tracki światła, robi pozycje względnymi
func _fix_track_paths(anim: Animation, root: Node, anim_name: StringName) -> void:
	for i in range(anim.get_track_count() - 1, -1, -1):
		var path := anim.track_get_path(i)
		var names := path.get_concatenated_names()
		var subnames := path.get_concatenated_subnames()

		if names == "":
			continue

		var node := root.get_node_or_null(NodePath(names))

		if node == null:
			var last := String(path.get_name(path.get_name_count() - 1))
			node = _find_node_loose(root, last)
			if node == null:
				push_warning("[%s] NIE ZNALEZIONO węzła dla ścieżki %s" % [anim_name, path])
				anim.remove_track(i)
				continue
			var new_path := String(root.get_path_to(node))
			if subnames != "":
				new_path += ":" + subnames
			anim.track_set_path(i, NodePath(new_path))

		# track rusza samo światło -> usuwamy
		if node == self or subnames.begins_with("light_energy"):
			if debug_animations:
				print("[", anim_name, "] USUNIĘTO track światła: ", path)
			anim.remove_track(i)
			continue

		# track stały (nic nie animuje) -> usuwamy, żeby nie nadpisywał innych animacji
		if _is_constant_track(anim, i):
			if debug_animations:
				print("[", anim_name, "] USUNIĘTO track stały: ", path)
			anim.remove_track(i)
			continue

		if debug_animations:
			print("[", anim_name, "] zostaje track ", i, ": ", anim.track_get_path(i), " typ ", anim.track_get_type(i))

		# animacja pozycji względna: start = pozycja modelu w scenie
		if node is Node3D:
			var t := anim.track_get_type(i)
			var is_pos := t == Animation.TYPE_POSITION_3D \
					or (t == Animation.TYPE_VALUE and subnames.begins_with("position"))
			if is_pos and anim.track_get_key_count(i) > 0:
				var first: Vector3 = anim.track_get_key_value(i, 0)
				var offset: Vector3 = (node as Node3D).position - first
				for k in anim.track_get_key_count(i):
					var v: Vector3 = anim.track_get_key_value(i, k)
					anim.track_set_key_value(i, k, v + offset)


# Odpala wszystkie animacje naraz razem z dźwiękiem, czeka na najdłuższą,
# przywraca pozycje modelu i (opcjonalnie) dogrywa resztę dźwięku
func _play_all() -> void:
	var longest := 0.0
	for i in _players.size():
		var p = _players[i]
		if p == null:
			continue
		var n := reload_animations[i]
		p.stop()
		p.play(n)
		longest = maxf(longest, p.get_animation(n).length)
		if debug_animations:
			print("GRA: ", n, " (", p.get_animation(n).length, " s)")

	# dźwięk startuje równolegle z animacjami (+ ewentualne opóźnienie)
	var sound_len := 0.0
	if reload_sound != null:
		sound_len = reload_sound_delay + reload_sound.get_length()
		_play_sfx(_sfx_reload, reload_sound, reload_sound_delay)

	if longest > 0.0:
		await get_tree().create_timer(longest + 0.05).timeout

	for p in _players:
		if p != null:
			p.stop()
			p.clear_caches()
	_restore_rest_pose()
	await get_tree().process_frame
	_restore_rest_pose()   # drugi raz, gdyby player jeszcze coś nadpisał

	# dźwięk dłuższy niż animacje: czekamy do jego końca
	if wait_for_sound:
		var remaining := sound_len - longest - 0.05
		if remaining > 0.0:
			await get_tree().create_timer(remaining).timeout


# ---------- Światło ----------

# Gasi/zapala TYLKO światło (energia). Model zostaje widoczny.
func _set_light(state: bool) -> void:
	is_on = state
	light_energy = base_energy if state else 0.0
	if debug_input:
		print("światło: ", state, " | energia: ", light_energy, " | bateria: ", snappedf(battery, 0.1))


# Wywoływane z player.gd po podniesieniu latarki z ziemi
func pick_up() -> void:
	unlocked = true
	if battery > 0.0:
		_set_light(true)


func _toggle_light() -> void:
	if is_on:
		_set_light(false)
		_play_sfx(_sfx_toggle, toggle_sound)
	elif battery > 0.0:
		_set_light(true)
		_play_sfx(_sfx_toggle, toggle_sound)


# ---------- Wejście: tap F = przełącz, przytrzymanie F = przeładuj ----------

func _unhandled_input(event: InputEvent) -> void:
	if not unlocked or is_busy:
		return

	if event.is_action_pressed("flashlight") and not event.is_echo():
		_f_down = true
		_f_time = 0.0
		_f_handled = false

	elif event.is_action_released("flashlight"):
		if _f_down and not _f_handled:
			_toggle_light()   # krótkie wciśnięcie
		_f_down = false
		_f_handled = false


func _process(delta: float) -> void:
	# Mierzenie przytrzymania F
	if _f_down and not _f_handled and not is_busy:
		_f_time += delta
		if _f_time >= hold_time:
			_f_handled = true
			if battery < max_battery:
				reload_flashlight()

	if not is_on or is_busy:
		return

	battery = maxf(battery - drain_per_second * delta, 0.0)

	if battery <= 0.0:
		_set_light(false)
		_play_sfx(_sfx_alert, dead_sound)           # bateria padła
		return

	var percent := battery / max_battery * 100.0
	if percent < flicker_below:
		if not _flicker_sound_played:               # raz, na początku migotania
			_flicker_sound_played = true
			_play_sfx(_sfx_alert, flicker_start_sound)
		_flicker(delta, 1.0 - percent / flicker_below)
	else:
		light_energy = base_energy


# strength: 0 (tuż poniżej progu) ... 1 (bateria na wyczerpaniu)
func _flicker(delta: float, strength: float) -> void:
	_flicker_timer -= delta
	if _flicker_timer > 0.0:
		return

	_flicker_timer = randf_range(0.03, lerpf(0.5, 0.12, strength))

	if randf() < 0.15 + strength * 0.45:
		light_energy = 0.0
	else:
		light_energy = base_energy * randf_range(0.25, 1.0)


func reload_flashlight() -> void:
	is_busy = true
	_set_light(false)   # światło gaśnie, model zostaje widoczny

	await _play_all()

	charge_battery(max_battery)

	_f_down = false
	_f_handled = false
	_f_time = 0.0

	is_busy = false
	_set_light(true)    # po animacji (i dźwięku) świeci ponownie


func charge_battery(amount: float) -> void:
	battery = clampf(battery + amount, 0.0, max_battery)
	# po naładowaniu powyżej progu dźwięk migotania może zagrać ponownie
	if battery / max_battery * 100.0 >= flicker_below:
		_flicker_sound_played = false
