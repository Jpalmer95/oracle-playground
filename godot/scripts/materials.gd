extends Node
## Authored Jolt PhysicsMaterials + albedo colors for the hangar lab.

const PROFILES := {
	"ice": {"friction": 0.02, "bounce": 0.05, "density": 0.9, "color": Color(0.72, 0.88, 0.95)},
	"rubber": {"friction": 1.4, "bounce": 0.85, "density": 1.1, "color": Color(0.18, 0.18, 0.2)},
	"metal": {"friction": 0.45, "bounce": 0.15, "density": 3.2, "color": Color(0.62, 0.64, 0.68)},
	"wood": {"friction": 0.7, "bounce": 0.2, "density": 0.7, "color": Color(0.55, 0.36, 0.2)},
	"glass": {"friction": 0.2, "bounce": 0.55, "density": 0.5, "color": Color(0.75, 0.9, 0.95, 0.45)},
}

func profile_names() -> PackedStringArray:
	return PackedStringArray(PROFILES.keys())


func make_physics_material(kind: String) -> PhysicsMaterial:
	var p: Dictionary = PROFILES.get(kind, PROFILES["wood"])
	var mat := PhysicsMaterial.new()
	mat.friction = p["friction"]
	mat.bounce = p["bounce"]
	return mat


func make_visual_material(kind: String) -> StandardMaterial3D:
	var p: Dictionary = PROFILES.get(kind, PROFILES["wood"])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = p["color"]
	mat.roughness = 0.35 if kind != "metal" else 0.25
	mat.metallic = 0.85 if kind == "metal" else 0.0
	if kind == "glass":
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.05
	if kind == "ice":
		mat.roughness = 0.08
		mat.metallic = 0.15
	return mat


func density(kind: String) -> float:
	return float(PROFILES.get(kind, PROFILES["wood"])["density"])


func spawn_cube(kind: String, at: Vector3, size: float = 0.6, parent: Node = null) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "Cube_%s" % kind
	body.mass = maxf(0.2, size * size * size * 200.0 * density(kind))
	body.physics_material_override = make_physics_material(kind)
	body.continuous_cd = true
	body.contact_monitor = true
	body.max_contacts_reported = 8
	body.collision_layer = 4
	body.collision_mask = 7
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size
	mesh.mesh = box
	mesh.material_override = make_visual_material(kind)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * size
	col.shape = shape
	body.add_child(mesh)
	body.add_child(col)
	body.position = at
	body.add_to_group("grabbable")
	if parent:
		parent.add_child(body)
	return body
