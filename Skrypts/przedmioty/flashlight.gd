class_name Flashlight
extends SpotLight3D

@export var starts_unlocked: bool = false
@export var max_battery: float = 100.0
@export var start_battery_percent: float = 100.0
@export var drain_per_second: float = 0.5
@export var base_energy: float = 3.0
@export var flicker_below: float = 20.0
@export var hold_time: float = 3.0

@export var battery_item: Item
@export var battery_name: String = "Bateria"

@export var model_root: Node3D

@export var reload_animations: Array[StringName] = [&"BateriaAction", &"CylinderAction", &"Cylinder_001Action"]
@export var debug_animations: bool = false
@export var debug_input: bool = false
@export var debug_reload: bool = true

@export_group("Dźwięki")
@export var reload_sound: AudioStream
@export var reload_sound_delay: float = 0.0
@export var wait_for_sound: bool = true
@export var toggle_sound: AudioStream
@export var flicker_start_sound: AudioStream
@export var dead_sound: AudioStream
@export var no_battery_sound: AudioStream
@export var sound_volume_db: float = 0.0

const PLAYER_PREFIX := "FlashlightAnim_"

var battery: float
var unlocked: bool = false
var is_on: bool = false
var is_busy: bool = false

var dim_factor: float = 1.0

var _gracz: Node = null
var _players: Array = []
var _flicker_timer: float = 0.0
var _flicker_sound_played: bool = false

var _f_down: bool = false
var _f_time: float = 0.0
var _f_handled: bool = false

var _rest_pose: Dictionary = {}

var _sfx_reload: AudioStreamPlayer
var _sfx_toggle: AudioStreamPlayer
var _sfx_alert: AudioStreamPlayer


func _ready() -> void:
	battery = max_battery * clampf(start_battery_percent, 0.0, 100.0) / 100.0
	shadow_enabled = true
	visible = true
	unlocked = starts_unlocked

	var n := get_parent()
	while n != null and not (n is CharacterBody3D):
		n = n.get_parent()
	_gracz = n

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


# ---------- Sprawdzanie wyposażenia ----------

func _latarka_wyposazona() -> bool:
	return is_visible_in_tree()


# ---------- Model ----------

func _setup_model() -> void:
	if model_root == null:
		model_root = _find_model_root()
	if debug_animations:
		print("Flashlight: model_root = ", model_root.get_path())
	_save_rest_pose(model_root)
	_build_players()


func _find_model_root() -> Node3D:
	var node: Node = self
	while node != null:
		if node is Node3D and _has_original_player(node):
			return node as Node3D
		if node is Camera3D or node is CharacterBody3D:
			break
		node = node.get_parent()
	push_warning("Flashlight: nie znaleziono AnimationPlayera ani w tym węźle, ani wyżej. Wskaż 'Model Root' w Inspektorze.")
	return self


func _has_original_player(node: Node) -> bool:
	var found: Array = []
	_collect_players(node, found)
	return not found.is_empty()


func _save_rest_pose(node: Node, wylacz_cienie: bool = true) -> void:
	for child in node.get_children():
		if child == self:
			continue
		if child is Node3D:
			_rest_pose[child] = {"t": child.transform, "v": child.visible}
		if wylacz_cienie and child is GeometryInstance3D:
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_save_rest_pose(child, wylacz_cienie)


func _restore_rest_pose() -> void:
	for node in _rest_pose:
		if is_instance_valid(node):
			node.transform = _rest_pose[node]["t"]
			node.visible = _rest_pose[node]["v"]


# ---------- Animacje ----------

func _collect_players(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is AnimationPlayer and not String(child.name).begins_with(PLAYER_PREFIX):
			out.append(child)
		_collect_players(child, out)


# Szukamy animacji w całym graczu (gdy model_root nie zawiera AnimationPlayera z animacją baterii)
func _search_root() -> Node:
	return _gracz if _gracz != null else model_root


# Najpierw odtwarzacze z model_root, potem reszta gracza
func _all_players() -> Array:
	var players: Array = []
	_collect_players(model_root, players)
	var rest: Array = []
	_collect_players(_search_root(), rest)
	for p in rest:
		if not players.has(p):
			players.append(p)
	return players


func _find_animation(anim_name: StringName, used: Array) -> Dictionary:
	var players: Array = _all_players()
	var wanted := String(anim_name).strip_edges().to_lower()

	for p: AnimationPlayer in players:
		for full in p.get_animation_list():
			var f := String(full).strip_edges().to_lower()
			if f == wanted or f.ends_with("/" + wanted):
				return {"player": p, "key": full}

	var stripped := wanted.trim_suffix("action")
	for p: AnimationPlayer in players:
		for full in p.get_animation_list():
			var f := String(full).strip_edges().to_lower()
			if used.has(String(full)):
				continue
			if f.begins_with(stripped) or f.contains("/" + stripped):
				return {"player": p, "key": full}
	return {}


# Czy wszystkie zbudowane odtwarzacze nadal żyją i wiszą w drzewie
func _players_ok() -> bool:
	var jest := false
	for p in _players:
		if p == null:
			continue
		if not is_instance_valid(p) or not p.is_inside_tree():
			return false
		jest = true
	return jest


func _build_players() -> void:
	# sprzątamy stare odtwarzacze, żeby się nie dublowały
	for stary in _players:
		if stary != null and is_instance_valid(stary):
			if stary.get_parent() != null:
				stary.get_parent().remove_child(stary)
			stary.queue_free()
	_players.clear()
	var used: Array = []

	if debug_animations:
		var all: Array = _all_players()
		for p: AnimationPlayer in all:
			print("Player: ", p.get_path(), " animacje: ", p.get_animation_list())

	for idx in reload_animations.size():
		var n := reload_animations[idx]
		var found := _find_animation(n, used)
		if found.is_empty():
			var all2: Array = _all_players()
			var names: Array = []
			for p2: AnimationPlayer in all2:
				names.append(str(p2.get_path()) + ": " + str(p2.get_animation_list()))
			push_warning("Flashlight: NIE ZNALEZIONO animacji '%s' w żadnym AnimationPlayerze gracza. Dostępne: %s" % [n, names])
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

		_save_rest_pose(root, false)   # żeby po animacji przywrócić też węzły spoza model_root
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
		p.active = true
		p.speed_scale = 1.0
		p.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
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

		if node == self or subnames.begins_with("light_energy"):
			if debug_animations:
				print("[", anim_name, "] USUNIĘTO track światła: ", path)
			anim.remove_track(i)
			continue

		if _is_constant_track(anim, i):
			if debug_animations:
				print("[", anim_name, "] USUNIĘTO track stały: ", path)
			anim.remove_track(i)
			continue

		if debug_animations:
			print("[", anim_name, "] zostaje track ", i, ": ", anim.track_get_path(i), " typ ", anim.track_get_type(i))

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


func _play_all() -> void:
	# odtwarzacze mogły zniknąć (przepięty / zduplikowany model): odbuduj je
	if model_root == null or not is_instance_valid(model_root):
		_setup_model()
	elif not _players_ok():
		_build_players()

	var longest := 0.0
	for i in _players.size():
		var p = _players[i]
		if p == null or not is_instance_valid(p):
			continue
		var n := reload_animations[i]
		p.active = true
		p.speed_scale = 1.0
		p.stop()
		p.play(n)
		longest = maxf(longest, p.get_animation(n).length)
		if debug_animations:
			print("GRA: ", n, " (", p.get_animation(n).length, " s) playing=", p.is_playing())

	var sound_len := 0.0
	if reload_sound != null:
		sound_len = reload_sound_delay + reload_sound.get_length()
		_play_sfx(_sfx_reload, reload_sound, reload_sound_delay)

	if longest > 0.0:
		await get_tree().create_timer(longest + 0.05).timeout

	for p in _players:
		if p != null and is_instance_valid(p):
			p.stop()
			p.clear_caches()
	_restore_rest_pose()
	await get_tree().process_frame
	_restore_rest_pose()

	if wait_for_sound:
		var remaining := sound_len - longest - 0.05
		if remaining > 0.0:
			await get_tree().create_timer(remaining).timeout


# ---------- Światło ----------

func _energia() -> float:
	return base_energy * dim_factor


func _set_light(state: bool) -> void:
	is_on = state
	light_energy = _energia() if state else 0.0
	if debug_input:
		print("światło: ", state, " | energia: ", light_energy, " | bateria: ", snappedf(battery, 0.1))


func pick_up() -> void:
	unlocked = true
	if battery > 0.0 and _latarka_wyposazona():
		_set_light(true)


func zabierz() -> void:
	unlocked = false
	_f_down = false
	_f_handled = false
	_f_time = 0.0
	_set_light(false)


func _toggle_light() -> void:
	if not unlocked or not _latarka_wyposazona():
		return

	if is_on:
		_set_light(false)
		_play_sfx(_sfx_toggle, toggle_sound)
	elif battery > 0.0:
		_set_light(true)
		_play_sfx(_sfx_toggle, toggle_sound)


# ---------- Wejście ----------

func _wejscie_zablokowane() -> bool:
	if _gracz == null or not _gracz.has_method("moze_sterowac"):
		return false
	return not _gracz.call("moze_sterowac")


func _unhandled_input(event: InputEvent) -> void:
	if not unlocked or not _latarka_wyposazona() or is_busy or _wejscie_zablokowane():
		return

	if event.is_action_pressed("flashlight") and not event.is_echo():
		_f_down = true
		_f_time = 0.0
		_f_handled = false

	elif event.is_action_released("flashlight"):
		if _f_down and not _f_handled:
			_toggle_light()
		_f_down = false
		_f_handled = false


func _process(delta: float) -> void:
	# Schowana latarka nie działa i nie zużywa baterii.
	if not _latarka_wyposazona():
		_f_down = false
		_f_handled = false
		_f_time = 0.0

		if is_on:
			_set_light(false)

		return

	if _f_down and _wejscie_zablokowane():
		_f_down = false
		_f_handled = false
		_f_time = 0.0

	if _f_down and not _f_handled and not is_busy:
		_f_time += delta
		if _f_time >= hold_time:
			_f_handled = true
			probuj_przeladowac()

	if not is_on or is_busy:
		return

	battery = maxf(battery - drain_per_second * delta, 0.0)

	if battery <= 0.0:
		_set_light(false)
		_play_sfx(_sfx_alert, dead_sound)
		return

	var percent := battery / max_battery * 100.0
	if percent < flicker_below:
		if not _flicker_sound_played:
			_flicker_sound_played = true
			_play_sfx(_sfx_alert, flicker_start_sound)
		_flicker(delta, 1.0 - percent / flicker_below)
	else:
		light_energy = _energia()


func _flicker(delta: float, strength: float) -> void:
	_flicker_timer -= delta
	if _flicker_timer > 0.0:
		return

	_flicker_timer = randf_range(0.03, lerpf(0.5, 0.12, strength))

	if randf() < 0.15 + strength * 0.45:
		light_energy = 0.0
	else:
		light_energy = _energia() * randf_range(0.25, 1.0)


# ---------- Przeładowanie ----------

func _dbg(tekst: String) -> void:
	if debug_reload and OS.is_debug_build():
		print("[latarka] ", tekst)


func jest_bateria(item: Item) -> bool:
	if item == null:
		return false
	if battery_item != null:
		if item == battery_item:
			return true
		if item.resource_path != "" and item.resource_path == battery_item.resource_path:
			return true
	var szukana := battery_name.strip_edges().to_lower()
	return szukana != "" and item.nazwa.strip_edges().to_lower() == szukana


func moze_przeladowac() -> bool:
	return unlocked and _latarka_wyposazona() and not is_busy and battery < max_battery - 0.01


func _znajdz_baterie(inv: Node) -> Item:
	if battery_item != null:
		return battery_item
	for slot in inv.sloty:
		if slot != null and slot.item != null and jest_bateria(slot.item):
			return slot.item
	return null


func probuj_przeladowac() -> void:
	_dbg("próba przeładowania (bateria latarki: %.1f / %.1f)" % [battery, max_battery])

	if not unlocked or not _latarka_wyposazona() or is_busy:
		return

	if battery >= max_battery - 0.01:
		_dbg("bateria latarki jest pełna, przeładowanie zbędne")
		return

	var inv := get_node_or_null("/root/Inventory")
	if inv == null:
		push_warning("Flashlight: brak autoloadu 'Inventory' (Project Settings -> Globals -> Autoload, nazwa dokładnie: Inventory)")
		return

	var bateria := _znajdz_baterie(inv)
	if bateria == null:
		_dbg("w ekwipunku nie ma przedmiotu '%s', przeładowanie zablokowane" % battery_name)
		_play_sfx(_sfx_alert, no_battery_sound)
		return

	var ilosc: int = inv.ile(bateria)
	_dbg("baterii w ekwipunku: %d" % ilosc)

	if ilosc <= 0:
		_dbg("brak baterii w ekwipunku, przeładowanie zablokowane")
		_play_sfx(_sfx_alert, no_battery_sound)
		return

	inv.usun_item(bateria, 1)
	_dbg("zużyto 1 baterię, startuje animacja")
	reload_flashlight()


func reload_flashlight() -> void:
	if not unlocked or not _latarka_wyposazona() or is_busy:
		return

	is_busy = true
	_set_light(false)

	await _play_all()

	charge_battery(max_battery)

	_f_down = false
	_f_handled = false
	_f_time = 0.0

	is_busy = false

	if _latarka_wyposazona() and unlocked and battery > 0.0:
		_set_light(true)


func charge_battery(amount: float) -> void:
	battery = clampf(battery + amount, 0.0, max_battery)

	if battery / max_battery * 100.0 >= flicker_below:
		_flicker_sound_played = false
