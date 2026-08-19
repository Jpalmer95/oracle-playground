extends Node
## HUDMenu — the primary system hub. A nested, data-driven menu tree rendered
## on the wrist. Tools auto-populate from ToolRegistry; mode/settings/radio are
## declared as item kinds. Adding a plugin later = register one submenu here.

signal changed            # bump version; renderer watches this to rebuild
signal opened
signal closed

enum ItemKind { SUBMENU, ACTION, TOGGLE, SELECT }

var version := 0
var open := false
var player: OraclePlayer = null    # bound by main.gd; mode/settings write here

# Navigation: each level is {title: String, items: Array}.
var _stack: Array = []
var _root: Dictionary = {}


func _ready() -> void:
	_build_root()


func bind_player(p: OraclePlayer) -> void:
	player = p
	_build_root()       # mode labels depend on player state
	_bump()


func set_open(v: bool) -> void:
	if open == v:
		return
	open = v
	if open:
		opened.emit()
	else:
		closed.emit()
	_bump()


func toggle_open() -> void:
	set_open(not open)


func is_open() -> bool:
	return open


func _bump() -> void:
	version += 1
	changed.emit()


# --- tree construction -------------------------------------------------------

func _build_root() -> void:
	_root = {
		"title": "ORACLE HUB",
		"items": [
			_submenu("Tools", _tools_level()),
			_submenu("Mode & Motion", _mode_level()),
			_submenu("Radio", _radio_level()),
			_submenu("Settings", _settings_level()),
		],
	}
	_stack = [_root]


func _tools_level() -> Array:
	# Auto-populate: one submenu per palette in tools.json.
	var out: Array = []
	for pid in ToolRegistry.palette_ids():
		var pid_s: String = pid
		out.append(_submenu(ToolRegistry.palette_name(pid_s), _palette_level(pid_s)))
	return out


func _palette_level(pid: String) -> Array:
	var out: Array = []
	for tid in ToolRegistry.palette_tool_ids(pid):
		var tid_s: String = tid
		out.append(_action(ToolRegistry.tool_name(tid_s), "spawn", tid_s))
	return out


func _mode_level() -> Array:
	var on_ground := player != null and player.is_ground_mode()
	var mode_label := "Mode: GROUND" if on_ground else "Mode: FLIGHT"
	var out: Array = []
	out.append(_toggle(mode_label, "toggle_mode"))
	out.append(_select("Walk Speed", "walk_speed",
		["Slow", "Normal", "Fast", "Sprint"], _walk_speed_index()))
	out.append(_select("Gravity", "gravity",
		["Moon", "Earth", "Heavy"], _gravity_index()))
	return out


func _radio_level() -> Array:
	var out: Array = []
	var play_label: String = "Pause" if Radio.playing else "Play"
	var track: String = Radio.current_name()
	if track == "":
		track = "(no track loaded)"
	out.append(_action("Music: " + play_label, "radio_toggle", ""))
	out.append(_action("Next Track", "radio_next", ""))
	out.append(_action("Prev Track", "radio_prev", ""))
	out.append(_action(("Now: %s" % track).left(28), "radio_show", ""))
	out.append(_select("Volume", "volume", ["0%", "25%", "50%", "75%", "100%"], _volume_index()))
	return out


func _settings_level() -> Array:
	var out: Array = []
	var stab := player != null and player.stabilize_upright
	out.append(_toggle("Stabilize Up: %s" % ("ON" if stab else "OFF"), "toggle_stabilize"))
	out.append(_action("Undo Last", "undo", ""))
	out.append(_action("Clear All", "clear", ""))
	return out


# --- item factories ----------------------------------------------------------

func _submenu(label: String, children: Array) -> Dictionary:
	return {"kind": ItemKind.SUBMENU, "label": label, "children": children, "title": label}


func _action(label: String, action_id: String, arg: String) -> Dictionary:
	return {"kind": ItemKind.ACTION, "label": label, "action": action_id, "arg": arg}


func _toggle(label: String, action_id: String) -> Dictionary:
	return {"kind": ItemKind.TOGGLE, "label": label, "action": action_id}


func _select(label: String, action_id: String, options: Array, current: int) -> Dictionary:
	return {"kind": ItemKind.SELECT, "label": label, "action": action_id,
		"options": options, "current": clamp(current, 0, options.size() - 1)}


# --- navigation & reading ----------------------------------------------------

func current_level() -> Dictionary:
	if _stack.is_empty():
		return _root
	return _stack.back()


func level_title() -> String:
	return str(current_level().get("title", ""))


func level_items() -> Array:
	return current_level().get("items", [])


func _push_level(title: String, items: Array) -> void:
	_stack.append({"title": title, "items": items})
	_bump()


func go_back() -> void:
	if _stack.size() > 1:
		_stack.pop_back()
		_bump()


func back_button_label() -> String:
	if _stack.size() > 1:
		return "Back"
	return "Close"


func can_go_back() -> bool:
	return _stack.size() > 1


# --- dispatch ----------------------------------------------------------------

func activate(item: Dictionary) -> void:
	match item.get("kind", -1):
		ItemKind.SUBMENU:
			_push_level(str(item.get("title", item.get("label", "?"))), item.get("children", []))
		ItemKind.ACTION:
			_dispatch(item.get("action", ""), str(item.get("arg", "")))
		ItemKind.TOGGLE:
			_dispatch(item.get("action", ""), "")


func activate_index(idx: int) -> void:
	var items := level_items()
	if idx < 0 or idx >= items.size():
		return
	activate(items[idx])


# --- actions ----------------------------------------------------------------

func _dispatch(action: String, arg: String) -> void:
	match action:
		"spawn":
			OracleBuilder.spawn_tool(arg, _spawn_pos())
		"undo":
			OracleBuilder.undo()
		"clear":
			OracleBuilder.clear()
		"toggle_mode":
			if player:
				player.set_ground_mode(not player.is_ground_mode())
			_build_root()
		"toggle_stabilize":
			if player:
				player.stabilize_upright = not player.stabilize_upright
			_build_root()
		"walk_speed":
			if player:
				_cycle_walk_speed()
			_build_root()
		"gravity":
			if player:
				_cycle_gravity()
			_build_root()
		"volume":
			_cycle_volume()
			_build_root()
		"radio_toggle":
			Radio.toggle()
			_build_root()
		"radio_next":
			Radio.next()
			_build_root()
		"radio_prev":
			Radio.prev()
			_build_root()
		"radio_show":
			pass
		_:
			push_warning("HUDMenu: unknown action '%s'" % action)


func _spawn_pos() -> Vector3:
	# Spawn ~1.5 m in front of the player's facing.
	if player == null:
		return Vector3(0, 1.5, 0)
	var fwd := -player.global_transform.basis.z.normalized()
	return player.global_position + fwd * 1.5 + Vector3.UP * 0.2


# --- select helpers ----------------------------------------------------------

const WALK_SPEEDS := [1.5, 3.5, 5.5, 8.0]
const GRAVITIES := [3.0, 9.8, 20.0]

func _walk_speed_index() -> int:
	if player == null:
		return 1
	var v := player.walk_speed
	for i in WALK_SPEEDS.size():
		if absf(WALK_SPEEDS[i] - v) < 0.4:
			return i
	return 1


func _cycle_walk_speed() -> void:
	var i := (_walk_speed_index() + 1) % WALK_SPEEDS.size()
	player.walk_speed = WALK_SPEEDS[i]


func _gravity_index() -> int:
	if player == null:
		return 1
	var g := player.gravity_scale * 9.8 if player.is_ground_mode() else 9.8
	for i in GRAVITIES.size():
		if absf(GRAVITIES[i] - g) < 1.5:
			return i
	return 1


func _cycle_gravity() -> void:
	var i := (_gravity_index() + 1) % GRAVITIES.size()
	if player:
		# Store real gravity via gravity_scale relative to Earth.
		player.gravity_scale = GRAVITIES[i] / 9.8


func _volume_index() -> int:
	var v := Radio.volume_linear()
	var opts := [0.0, 0.25, 0.5, 0.75, 1.0]
	for i in opts.size():
		if absf(opts[i] - v) < 0.06:
			return i
	return 2


func _cycle_volume() -> void:
	var opts := [0.0, 0.25, 0.5, 0.75, 1.0]
	var i := (_volume_index() + 1) % opts.size()
	Radio.set_volume(opts[i])