extends Node
## ToolRegistry — data-driven tool + palette lookup, parsed from config/tools.json.
## The scalability contract: tools and palettes are DATA, not code. Adding,
## removing, or reordering tools is a JSON edit — human or agent — with no
## recompile. New tool *kinds* (fluid, light, audio) add one dispatch branch in
## OracleBuilder; new instances of existing kinds need only a JSON entry.

const CONFIG_PATH := "res://config/tools.json"

var _data: Dictionary = {}
var _tools: Dictionary = {}       # id -> {name, category, kind, params}
var _palettes: Dictionary = {}    # id -> {name, tools: [ids]}
var _load_error := ""


func _ready() -> void:
	reload()


func reload() -> bool:
	_load_error = ""
	_tools = {}
	_palettes = {}
	if not FileAccess.file_exists(CONFIG_PATH):
		_load_error = "missing config: " + CONFIG_PATH
		push_warning("ToolRegistry: " + _load_error)
		return false
	var text := FileAccess.get_file_as_string(CONFIG_PATH)
	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		_load_error = "invalid JSON in " + CONFIG_PATH
		push_warning("ToolRegistry: " + _load_error)
		return false
	_data = parsed
	var tools_raw = parsed.get("tools", {})
	if tools_raw is Dictionary:
		_tools = tools_raw
	for pid in (parsed.get("palettes", {}) as Dictionary).keys():
		var p = parsed["palettes"][pid]
		if p is Dictionary:
			_palettes[pid] = {"name": p.get("name", pid), "tools": p.get("tools", [])}
	return true


func load_error() -> String:
	return _load_error


func has_tool(id: String) -> bool:
	return _tools.has(id)


func tool(id: String) -> Dictionary:
	return _tools.get(id, {})


func tool_name(id: String) -> String:
	return str(_tools.get(id, {}).get("name", id))


func tool_kind(id: String) -> String:
	return str(_tools.get(id, {}).get("kind", ""))


func tool_params(id: String) -> Dictionary:
	return _tools.get(id, {}).get("params", {})


func tool_ids() -> Array:
	return _tools.keys()


func has_palette(id: String) -> bool:
	return _palettes.has(id)


func palette_ids() -> Array:
	return _palettes.keys()


func palette_name(id: String) -> String:
	return str(_palettes.get(id, {}).get("name", id))


func palette_tool_ids(id: String) -> Array:
	return _palettes.get(id, {}).get("tools", [])