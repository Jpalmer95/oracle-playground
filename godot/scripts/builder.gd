extends Node
## OracleBuilder — single door through which every spawn/undo/clear verb flows,
## whether invoked from desktop keys, XR ray-select, or headless GDScript.
## Dispatch is keyed on a tool's `kind`; add a new kind = add one match branch.

signal tool_spawned(tool_id: String, node: Node)
signal tool_undone()

const DestructibleScript := preload("res://scripts/destructible.gd")

var _undo: Array = []       # most-recent-last; holds Node references
var _parent: Node3D = null

# Reference to the imported-props GLB wrapper (set by main.gd so we reuse its
# convex wrapping instead of duplicating the mesh scan).
var _glb_wrapper: Node = null


func set_parent(p: Node3D) -> void:
	_parent = p


func set_glb_wrapper(w: Node) -> void:
	_glb_wrapper = w


func spawn_tool(id: String, at: Vector3) -> Node:
	if not ToolRegistry.has_tool(id):
		push_warning("OracleBuilder: unknown tool id '%s'" % id)
		return null
	var kind: String = ToolRegistry.tool_kind(id)
	var params: Dictionary = ToolRegistry.tool_params(id)
	var node: Node = null
	match kind:
		"material_cube":
			node = _spawn_material(params.get("material", "wood"), at, params.get("size", 0.55))
		"destructible":
			node = _spawn_destructible(params.get("material", "wood"), at, params.get("size", 0.6))
		"glb":
			node = _spawn_glb(params.get("path", ""), at)
		"undo":
			undo()
			return null
		"clear":
			clear()
			return null
		_:
			push_warning("OracleBuilder: unhandled kind '%s' for tool '%s'" % [kind, id])
			return null
	if node != null:
		_undo.append(node)
		tool_spawned.emit(id, node)
	return node


func _target_parent() -> Node3D:
	if _parent != null:
		return _parent
	# Fall back to the current scene root if no explicit parent was set.
	var scene := get_tree().current_scene
	return scene as Node3D


func _spawn_material(kind: String, at: Vector3, size: float) -> Node:
	return MaterialLab.spawn_cube(kind, at, size, _target_parent())


func _spawn_destructible(kind: String, at: Vector3, size: float) -> Node:
	var cube: RigidBody3D = MaterialLab.spawn_cube(kind, at, size, _target_parent())
	cube.set_script(DestructibleScript)
	cube.set("kind", kind)
	return cube


func _spawn_glb(path: String, at: Vector3) -> Node:
	if path == "" or not ResourceLoader.exists(path):
		push_warning("OracleBuilder: GLB not found: '%s'" % path)
		return null
	if _glb_wrapper != null and _glb_wrapper.has_method("wrap_glb"):
		return _glb_wrapper.wrap_glb(path, at, _target_parent())
	# Fallback: instantiate the packed scene as a plain RigidBody (no convex wrap).
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	var body := RigidBody3D.new()
	body.position = at
	body.mass = 8.0
	body.collision_layer = 4
	body.collision_mask = 7
	body.add_child(packed.instantiate())
	_target_parent().add_child(body)
	return body


func undo() -> bool:
	while not _undo.is_empty():
		var node: Node = _undo.pop_back()
		if is_instance_valid(node):
			node.queue_free()
			tool_undone.emit()
			return true
	return false


func clear() -> int:
	var removed := 0
	for node in _undo:
		if is_instance_valid(node):
			node.queue_free()
			removed += 1
	_undo.clear()
	tool_undone.emit()
	return removed


func undo_count() -> int:
	return _undo.size()