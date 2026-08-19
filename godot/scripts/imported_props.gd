extends Node3D
## Instantiates GLBs from res://assets/imported as convex Jolt rigid bodies.

const IMPORT_DIR := "res://assets/imported"


func load_folder() -> int:
	var dir := DirAccess.open(IMPORT_DIR)
	if dir == null:
		print("Imported: no folder ", IMPORT_DIR)
		return 0
	var spawned := 0
	var x := -6.0
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.get_extension().to_lower() in ["glb", "gltf"]:
			var path := IMPORT_DIR.path_join(fname)
			if has_node(NodePath(fname.get_basename())):
				fname = dir.get_next()
				continue
			var inst := wrap_glb(path, Vector3(x, 1.2, -14), self)
			if inst:
				inst.name = fname.get_basename()
				x += 2.4
				spawned += 1
		fname = dir.get_next()
	print("Imported props: ", spawned)
	return spawned


func wrap_glb(path: String, at: Vector3, parent: Node3D) -> RigidBody3D:
	## Public wrapper reused by OracleBuilder so the convex-wrap logic lives once.
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path)
	if packed == null:
		push_warning("Imported: failed to load %s" % path)
		return null
	var root: Node = packed.instantiate() if packed is PackedScene else null
	if root == null:
		return null
	var body := RigidBody3D.new()
	body.position = at
	body.mass = 8.0
	body.continuous_cd = true
	body.collision_layer = 4
	body.collision_mask = 7
	body.add_child(root)
	# Convex hull from first MeshInstance3D we find.
	var mesh_inst := _find_mesh(root)
	var col := CollisionShape3D.new()
	if mesh_inst and mesh_inst.mesh:
		var convex: Shape3D = mesh_inst.mesh.create_convex_shape()
		if convex:
			col.shape = convex
		else:
			var box := BoxShape3D.new()
			box.size = Vector3.ONE
			col.shape = box
	else:
		var box := BoxShape3D.new()
		box.size = Vector3.ONE
		col.shape = box
	body.add_child(col)
	if parent:
		parent.add_child(body)
	return body


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var found := _find_mesh(c)
		if found:
			return found
	return null
