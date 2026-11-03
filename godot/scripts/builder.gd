extends Node
## OracleBuilder — single door through which every spawn/undo/clear verb flows,
## whether invoked from desktop keys, XR ray-select, or headless GDScript.
## Dispatch is keyed on a tool's `kind`; add a new kind = add one match branch.

signal tool_spawned(tool_id: String, node: Node)
signal tool_undone()

const DestructibleScript := preload("res://scripts/destructible.gd")
const BowScript := preload("res://scripts/bow.gd")
const ArrowScript := preload("res://scripts/arrow.gd")

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
		"simready", "brep":
			node = _spawn_simready(params.get("slug", ""), at)
		"bow":
			node = _spawn_bow(at)
		"arrow":
			node = _spawn_arrow(at)
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


func _spawn_simready(slug: String, at: Vector3) -> Node:
	if slug == "" or not SimReadyLoader.has_asset(slug):
		push_warning("OracleBuilder: SimReady/B-Rep asset not found: '%s'" % slug)
		return null
	return SimReadyLoader.spawn_asset(slug, at, _target_parent())


func _spawn_bow(at: Vector3) -> RigidBody3D:
	var bow := BowScript.new()
	bow.position = at
	_target_parent().add_child(bow)
	bow.add_child(_make_bow_visual())
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.06, 0.6, 0.08)
	col.shape = box
	bow.add_child(col)
	bow.add_to_group("grabbable")
	return bow


func _spawn_arrow(at: Vector3) -> RigidBody3D:
	var arrow: RigidBody3D = ArrowScript.new()
	arrow.position = at
	_target_parent().add_child(arrow)
	arrow.rotate_x(PI * 0.5)  # lay shaft along forward (-Z) once spawned
	var col := CollisionShape3D.new()
	var cap := CylinderShape3D.new()
	cap.height = 0.5
	cap.radius = 0.015
	col.shape = cap
	arrow.add_child(col)
	arrow.add_to_group("grabbable")
	return arrow


func _make_bow_visual() -> Node3D:
	## Simple bow: a curved-ish limb (two prisms) + a string line. Placeholder
	## geometry until a Trellis/Blender bow is dropped into assets/imported.
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.22, 0.12)
	mat.roughness = 0.5

	var limb := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.05, 0.62, 0.05)
	limb.mesh = prism
	limb.material_override = mat
	limb.position = Vector3(0, 0, 0)
	root.add_child(limb)

	var top := MeshInstance3D.new()
	var prism2 := PrismMesh.new()
	prism2.size = Vector3(0.045, 0.3, 0.045)
	prism2.subdivide_depth = 2
	top.mesh = prism2
	top.material_override = mat
	top.position = Vector3(0, 0.28, 0.0)
	top.rotation_degrees = Vector3(0, 0, 25)
	root.add_child(top)

	var bottom := top.duplicate()
	bottom.position = Vector3(0, -0.28, 0.0)
	bottom.rotation_degrees = Vector3(0, 0, 180 - 25)
	root.add_child(bottom)
	return root


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