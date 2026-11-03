extends Node
## SimReadyLoader — loads compiled SimReady OpenUSD (.sim.json + .glb) and
## Aether-Forge `usd-brep` Rube Goldberg assets into Jolt Physics (Phases B & C).
##
## Preserves:
## - Real-world meters (`asset_extents`), validated `mass`, `center_of_mass`, `inertia`
## - Analytic primitives (`SphereShape3D`, `CapsuleShape3D`, `CylinderShape3D`, `BoxShape3D`)
##   so round items roll smoothly at 90-120 Hz without triangle-edge chatter
## - Compound `ConvexPolygonShape3D` hulls so concave props (mugs, bowls, chutes)
##   have genuinely hollow interiors
## - `PhysicsMaterial` (`static_friction`, `dynamic_friction`, `restitution`)
## - Multi-body articulations (`HingeJoint3D`, `SliderJoint3D`, world-fixed bases)
## - SimReady `GSP.001` `grasp_lines` metadata for `Grabber3D` handle snapping.

const SIMREADY_DIR := "res://assets/simready"
const BREP_DIR := "res://assets/brep"

var _spec_cache: Dictionary = {}


func reload_catalog() -> void:
	_spec_cache.clear()


func resolve_spec_path(slug_or_path: String) -> String:
	if slug_or_path.ends_with(".sim.json") and FileAccess.file_exists(slug_or_path):
		return slug_or_path
	var p1 := "%s/%s/%s.sim.json" % [SIMREADY_DIR, slug_or_path, slug_or_path]
	if FileAccess.file_exists(p1):
		return p1
	var p2 := "%s/%s/%s.sim.json" % [BREP_DIR, slug_or_path, slug_or_path]
	if FileAccess.file_exists(p2):
		return p2
	return ""


func has_asset(slug_or_path: String) -> bool:
	return resolve_spec_path(slug_or_path) != ""


func load_spec(slug_or_path: String) -> Dictionary:
	var path := resolve_spec_path(slug_or_path)
	if path == "":
		push_warning("SimReadyLoader: missing spec for '%s'" % slug_or_path)
		return {}
	if _spec_cache.has(path):
		return _spec_cache[path]
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	if parsed is Dictionary:
		_spec_cache[path] = parsed
		return parsed
	push_warning("SimReadyLoader: invalid JSON in '%s'" % path)
	return {}


func spawn_asset(slug_or_path: String, at_world: Vector3, parent: Node3D) -> Node3D:
	var spec := load_spec(slug_or_path)
	if spec.is_empty():
		return null
	var spec_path := resolve_spec_path(slug_or_path)
	var base_dir := spec_path.get_base_dir()
	var bodies_spec: Array = spec.get("rigid_bodies", [])
	var joints_spec: Array = spec.get("joints", [])
	if bodies_spec.is_empty():
		return null

	# Single-body asset without joints -> return the RigidBody3D directly
	if bodies_spec.size() == 1 and joints_spec.is_empty():
		var rb_node := _build_rigid_body(bodies_spec[0], spec, base_dir, false)
		rb_node.position = at_world
		if parent != null:
			parent.add_child(rb_node)
		return rb_node

	# Multi-body / articulated assembly -> root Node3D holding all bodies + joints
	var root := Node3D.new()
	root.name = "SimReady_%s" % str(spec.get("slug", "assembly"))
	root.position = at_world
	root.set_meta("simready_slug", str(spec.get("slug", "")))
	root.set_meta("simready_qcode", str(spec.get("qcode", "")))
	root.set_meta("simready_mass", float(spec.get("mass", 1.0)))
	if parent != null:
		parent.add_child(root)

	# Identify bodies anchored to the world via a 'fixed' joint with empty body0
	var fixed_to_world: Dictionary = {}
	for j in joints_spec:
		if j is Dictionary and str(j.get("type", "")) == "fixed":
			if str(j.get("body0", "")) == "":
				fixed_to_world[str(j.get("body1", ""))] = true

	var body_map: Dictionary = {}
	for b_dict in bodies_spec:
		if not (b_dict is Dictionary):
			continue
		var bname := str(b_dict.get("name", "Body"))
		var is_static_base := fixed_to_world.has(bname)
		var rb := _build_rigid_body(b_dict, spec, base_dir, is_static_base)
		rb.position = _vec3(b_dict.get("position", [0, 0, 0]))
		rb.quaternion = _quat(b_dict.get("rotation", [0, 0, 0, 1]))
		root.add_child(rb)
		body_map[bname] = rb

	# Wire Jolt joints between child RigidBody3Ds
	for j in joints_spec:
		if not (j is Dictionary):
			continue
		var jtype := str(j.get("type", ""))
		if jtype == "fixed":
			continue
		var b0_name := str(j.get("body0", ""))
		var b1_name := str(j.get("body1", ""))
		if not body_map.has(b0_name) or not body_map.has(b1_name):
			continue
		var b0: RigidBody3D = body_map[b0_name]
		var b1: RigidBody3D = body_map[b1_name]
		var lp0 := _vec3(j.get("local_pos0", [0, 0, 0]))
		var axis := _vec3(j.get("axis", [1, 0, 0])).normalized()
		if axis.length() < 0.001:
			axis = Vector3.RIGHT

		if jtype == "hinge":
			var hinge := HingeJoint3D.new()
			hinge.name = "Joint_%s" % str(j.get("name", "Hinge"))
			# Position joint at body0's local_pos0 in assembly space
			hinge.position = b0.position + (b0.transform.basis * lp0)
			# Godot HingeJoint3D rotates around its local Z axis; align local +Z with `axis`
			hinge.transform.basis = _basis_with_z(axis)
			var low_deg := float(j.get("lower_limit", -45.0))
			var high_deg := float(j.get("upper_limit", 45.0))
			hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
			hinge.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(low_deg))
			hinge.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(high_deg))
			root.add_child(hinge)
			hinge.node_a = hinge.get_path_to(b0)
			hinge.node_b = hinge.get_path_to(b1)
		elif jtype == "slider":
			var slider := SliderJoint3D.new()
			slider.name = "Joint_%s" % str(j.get("name", "Slider"))
			slider.position = b0.position + (b0.transform.basis * lp0)
			slider.transform.basis = _basis_with_x(axis)
			slider.set_param(SliderJoint3D.PARAM_LINEAR_LIMIT_LOWER, float(j.get("lower_limit", -0.25)))
			slider.set_param(SliderJoint3D.PARAM_LINEAR_LIMIT_UPPER, float(j.get("upper_limit", 0.25)))
			root.add_child(slider)
			slider.node_a = slider.get_path_to(b0)
			slider.node_b = slider.get_path_to(b1)

	return root


func _build_rigid_body(
	b_dict: Dictionary,
	spec: Dictionary,
	base_dir: String,
	is_fixed_base: bool
) -> RigidBody3D:
	var body := RigidBody3D.new()
	var bname := str(b_dict.get("name", spec.get("slug", "SimReadyProp")))
	body.name = bname

	var raw_mass := maxf(0.02, float(b_dict.get("mass", spec.get("mass", 1.0))))
	# Soft-clamp extreme industrial masses to [0.02, 200.0] for solver stability
	body.mass = clampf(raw_mass, 0.02, 200.0)
	body.continuous_cd = true
	body.contact_monitor = true
	body.max_contacts_reported = 8
	body.collision_layer = 4
	body.collision_mask = 7

	if is_fixed_base:
		body.freeze = true
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	else:
		body.add_to_group("grabbable")

	var com := _vec3(b_dict.get("center_of_mass", [0, 0, 0]))
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = com

	var in_vec := _vec3(b_dict.get("inertia", [0, 0, 0]))
	if in_vec.length() > 0.00001:
		body.inertia = Vector3(
			maxf(0.0001, in_vec.x),
			maxf(0.0001, in_vec.y),
			maxf(0.0001, in_vec.z)
		)

	var pmat_dict: Dictionary = b_dict.get("physics_material", {})
	body.physics_material_override = _make_physics_material(pmat_dict)

	# Metadata for inspection, balance tests, and Grabber3D grasp-line snapping
	body.set_meta("simready_slug", str(spec.get("slug", "")))
	body.set_meta("simready_qcode", str(spec.get("qcode", "")))
	body.set_meta("simready_category", str(spec.get("category", "")))
	body.set_meta("simready_mass", raw_mass)
	body.set_meta("asset_extents", spec.get("asset_extents", []))
	body.set_meta("grasp_lines", b_dict.get("grasp_lines", []))

	var visual_mat := _make_visual_material(pmat_dict, spec.get("visual_mesh", {}))
	var colliders: Array = b_dict.get("colliders", [])
	var added_visual := false

	# 1. If spec carries direct B-Rep tessellated arrays (`visual_mesh`), build ArrayMesh
	if spec.has("visual_mesh") and spec["visual_mesh"] is Dictionary:
		var vm_node := _build_brep_visual_mesh(spec["visual_mesh"], visual_mat)
		if vm_node != null:
			body.add_child(vm_node)
			added_visual = true

	# 2. Try loading companion .glb (imported resource first, then runtime GLTFDocument hot-load)
	if not added_visual and spec.has("glb_file"):
		var glb_path := "%s/%s" % [base_dir, str(spec["glb_file"])]
		var inst: Node = _instantiate_glb(glb_path)
		if inst != null:
			inst.name = "VisualGLB"
			body.add_child(inst)
			added_visual = true

	# 3. Build all Jolt CollisionShape3D nodes (analytic primitives + compound convex hulls)
	var col_idx := 0
	for col in colliders:
		if not (col is Dictionary):
			continue
		var ctype := str(col.get("type", ""))
		var shape_node := CollisionShape3D.new()
		shape_node.name = "Col_%d_%s" % [col_idx, str(col.get("name", ctype))]
		col_idx += 1

		var c_pos := _vec3(col.get("position", [0, 0, 0]))
		var c_quat := _quat(col.get("rotation", [0, 0, 0, 1]))
		shape_node.position = c_pos
		shape_node.quaternion = c_quat

		var shape: Shape3D = null
		var vis_mesh: Mesh = null

		match ctype:
			"sphere":
				var sph := SphereShape3D.new()
				sph.radius = maxf(0.005, float(col.get("radius", 0.05)))
				shape = sph
				if not added_visual:
					var sm := SphereMesh.new()
					sm.radius = sph.radius
					sm.height = sph.radius * 2.0
					vis_mesh = sm
			"capsule":
				var cap := CapsuleShape3D.new()
				cap.radius = maxf(0.005, float(col.get("radius", 0.02)))
				cap.height = maxf(cap.radius * 2.0, float(col.get("height", 0.1)))
				shape = cap
				if not added_visual:
					var cm := CapsuleMesh.new()
					cm.radius = cap.radius
					cm.height = cap.height
					vis_mesh = cm
			"cylinder":
				var cyl := CylinderShape3D.new()
				cyl.radius = maxf(0.005, float(col.get("radius", 0.02)))
				cyl.height = maxf(0.005, float(col.get("height", 0.1)))
				shape = cyl
				if not added_visual:
					var cym := CylinderMesh.new()
					cym.top_radius = cyl.radius
					cym.bottom_radius = cyl.radius
					cym.height = cyl.height
					vis_mesh = cym
			"box":
				var box := BoxShape3D.new()
				var sz := _vec3(col.get("size", [0.1, 0.1, 0.1]))
				box.size = Vector3(maxf(0.005, sz.x), maxf(0.005, sz.y), maxf(0.005, sz.z))
				shape = box
				if not added_visual:
					var bm := BoxMesh.new()
					bm.size = box.size
					vis_mesh = bm
			"convex_hull":
				var pts_raw: Array = col.get("points", [])
				if pts_raw.size() >= 4:
					var packed_pts := PackedVector3Array()
					for p in pts_raw:
						if p is Array and p.size() >= 3:
							packed_pts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
					if packed_pts.size() >= 4:
						var ch := ConvexPolygonShape3D.new()
						ch.points = packed_pts
						shape = ch

		if shape != null:
			shape_node.shape = shape
			body.add_child(shape_node)
			if vis_mesh != null:
				var mi := MeshInstance3D.new()
				mi.mesh = vis_mesh
				mi.position = c_pos
				mi.quaternion = c_quat
				mi.material_override = visual_mat
				body.add_child(mi)

	return body


func _instantiate_glb(glb_path: String) -> Node:
	if ResourceLoader.exists(glb_path):
		var packed: Resource = load(glb_path)
		if packed is PackedScene:
			return (packed as PackedScene).instantiate()
	var abs_path := ProjectSettings.globalize_path(glb_path)
	if FileAccess.file_exists(glb_path) or FileAccess.file_exists(abs_path):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var err := doc.append_from_file(abs_path, state)
		if err == OK:
			return doc.generate_scene(state)
	return null


func _build_brep_visual_mesh(vm: Dictionary, mat: Material) -> MeshInstance3D:
	var pts_raw: Array = vm.get("points", [])
	var norms_raw: Array = vm.get("normals", [])
	var idx_raw: Array = vm.get("indices", [])
	if pts_raw.is_empty() or idx_raw.is_empty():
		return null
	var verts := PackedVector3Array()
	for p in pts_raw:
		verts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	var norms := PackedVector3Array()
	for n in norms_raw:
		norms.append(Vector3(float(n[0]), float(n[1]), float(n[2])))
	var indices := PackedInt32Array()
	for idx in idx_raw:
		indices.append(int(idx))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	if norms.size() == verts.size():
		arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = indices

	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "BrepVisualMesh"
	mi.mesh = am
	mi.material_override = mat
	return mi


func _make_physics_material(pmat: Dictionary) -> PhysicsMaterial:
	var mat := PhysicsMaterial.new()
	var sf := float(pmat.get("static_friction", 0.55))
	var df := float(pmat.get("dynamic_friction", sf))
	mat.friction = clampf((sf + df) * 0.5, 0.01, 2.0)
	mat.bounce = clampf(float(pmat.get("restitution", 0.15)), 0.0, 1.0)
	return mat


func _make_visual_material(pmat: Dictionary, vm: Dictionary) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	if vm.has("color"):
		var c: Array = vm["color"]
		mat.albedo_color = Color(float(c[0]), float(c[1]), float(c[2]))
		mat.metallic = float(vm.get("metallic", 0.2))
		mat.roughness = float(vm.get("roughness", 0.4))
		return mat
	var name_s := str(pmat.get("name", "")).to_lower()
	if "steel" in name_s or "chrome" in name_s or "metal" in name_s:
		mat.albedo_color = Color(0.68, 0.71, 0.75)
		mat.metallic = 0.85
		mat.roughness = 0.25
	elif "rubber" in name_s or "tpe" in name_s or "grip" in name_s:
		mat.albedo_color = Color(0.18, 0.19, 0.22)
		mat.metallic = 0.05
		mat.roughness = 0.8
	elif "wood" in name_s or "cardboard" in name_s:
		mat.albedo_color = Color(0.62, 0.43, 0.25)
		mat.metallic = 0.0
		mat.roughness = 0.65
	else:
		mat.albedo_color = Color(0.75, 0.52, 0.18)
		mat.metallic = 0.15
		mat.roughness = 0.42
	return mat


func _vec3(arr) -> Vector3:
	if arr is Array and arr.size() >= 3:
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return Vector3.ZERO


func _quat(arr) -> Quaternion:
	if arr is Array and arr.size() >= 4:
		var q := Quaternion(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
		return q.normalized() if q.length_squared() > 0.0001 else Quaternion.IDENTITY
	return Quaternion.IDENTITY


func _basis_with_z(z_axis: Vector3) -> Basis:
	var z := z_axis.normalized()
	var up := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)


func _basis_with_x(x_axis: Vector3) -> Basis:
	var x := x_axis.normalized()
	var up := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
	var z := x.cross(up).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)
