extends Node3D
class_name OracleArena
## Builds the hangar: floor, ramps, material pads, crates, pool.

const DestructibleScript := preload("res://scripts/destructible.gd")
const WaterScript := preload("res://scripts/water_body.gd")
const WaterShader := preload("res://shaders/water_surface.gdshader")


func build() -> void:
	_static_box("Floor", Vector3(0, -0.25, 0), Vector3(80, 0.5, 80), Color(0.22, 0.22, 0.24))
	_static_box("BackWall", Vector3(0, 6, -40), Vector3(80, 12, 0.4), Color(0.16, 0.16, 0.18))
	_static_box("IceLane", Vector3(-22, 0.05, 0), Vector3(10, 0.1, 40), Color(0.7, 0.86, 0.95), "ice")
	_static_box("RubberPit", Vector3(18, 0.08, 8), Vector3(8, 0.16, 8), Color(0.12, 0.12, 0.13), "rubber")
	_ramp(Vector3(6, 0, -10), 8.0, 2.4, 4.0)
	_lights()
	_material_stacks()
	_crate_pyramid()
	_pool(Vector3(0, 0.0, 22), 8.0)
	_simready_rube_bench()


func _static_box(p_name: String, at: Vector3, size: Vector3, color: Color, kind: String = "") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = p_name
	body.position = at
	body.collision_layer = 1
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	if kind != "":
		mat = MaterialLab.make_visual_material(kind)
		body.physics_material_override = MaterialLab.make_physics_material(kind)
	mesh.material_override = mat
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(mesh)
	body.add_child(col)
	add_child(body)
	return body


func _ramp(at: Vector3, length: float, height: float, width: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Ramp"
	body.position = at
	var angle := atan2(height, length)
	body.rotation.x = -angle
	var size := Vector3(width, 0.25, sqrt(length * length + height * height))
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.32, 0.22)
	mesh.material_override = mat
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(mesh)
	body.add_child(col)
	add_child(body)


func _lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "HangarSun"
	sun.rotation_degrees = Vector3(-42, -25, 0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.92, 0.82)
	sun.shadow_enabled = true
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.name = "PoolFill"
	fill.position = Vector3(0, 4, 22)
	fill.light_color = Color(0.4, 0.75, 0.8)
	fill.light_energy = 2.4
	fill.omni_range = 18.0
	add_child(fill)


func _material_stacks() -> void:
	var kinds := ["ice", "rubber", "metal", "wood", "glass"]
	for i in kinds.size():
		var kind: String = kinds[i]
		var x := -10.0 + float(i) * 3.2
		for y in 3:
			var cube: RigidBody3D = MaterialLab.spawn_cube(kind, Vector3(x, 0.4 + y * 0.65, -6), 0.55, self)
			if kind in ["wood", "glass"]:
				cube.set_script(DestructibleScript)
				cube.kind = kind
				cube.shatter_impulse = 10.0 if kind == "glass" else 16.0


func _crate_pyramid() -> void:
	for row in 4:
		for col in (4 - row):
			var x := 12.0 + float(col) * 0.7 - float(4 - row) * 0.35
			var y := 0.4 + float(row) * 0.65
			var crate: RigidBody3D = MaterialLab.spawn_cube("wood", Vector3(x, y, 4), 0.6, self)
			crate.set_script(DestructibleScript)
			crate.kind = "wood"
			crate.name = "Crate_%d_%d" % [row, col]


func _pool(at: Vector3, radius: float) -> void:
	var water := Node3D.new()
	water.set_script(WaterScript)
	water.name = "Pool"
	water.position = at
	water.radius = radius
	water.wave_height = 0.18
	water.wave_scale = 0.55
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	plane.subdivide_width = 48
	plane.subdivide_depth = 48
	mesh.mesh = plane
	var sh := ShaderMaterial.new()
	sh.shader = WaterShader
	mesh.material_override = sh
	water.add_child(mesh)
	# basin
	_static_box("Basin", at + Vector3(0, -1.1, 0), Vector3(radius * 2.2, 2.0, radius * 2.2), Color(0.15, 0.2, 0.22))
	add_child(water)
	# a few floaters
	for i in 4:
		MaterialLab.spawn_cube("wood", at + Vector3(-2 + i * 1.2, 1.2, 0), 0.45, self)


func _simready_rube_bench() -> void:
	# Workbench pedestal for SimReady hand-manipulation + balance props
	_static_box("SimReadyBench", Vector3(-6.0, 0.45, 3.5), Vector3(3.6, 0.9, 1.2), Color(0.25, 0.27, 0.30))
	var props := [
		["hammer", Vector3(-7.2, 1.05, 3.5)],
		["screwdriver", Vector3(-6.6, 1.05, 3.5)],
		["mug", Vector3(-6.0, 1.05, 3.5)],
		["bowl", Vector3(-5.4, 1.05, 3.5)],
		["scissors", Vector3(-4.8, 1.05, 3.5)],
		["brep_balance_rod", Vector3(-6.0, 1.15, 3.1)],
	]
	for entry in props:
		var slug: String = entry[0]
		var pos: Vector3 = entry[1]
		if SimReadyLoader.has_asset(slug):
			SimReadyLoader.spawn_asset(slug, pos, self)

	# Rube Goldberg starter station: inclined B-Rep U-channel chute -> domino chain -> SimReady bowl catcher
	if SimReadyLoader.has_asset("brep_chute_straight"):
		var chute := SimReadyLoader.spawn_asset("brep_chute_straight", Vector3(-2.0, 1.35, 3.5), self)
		if chute is RigidBody3D:
			chute.freeze = true
			chute.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			chute.rotation_degrees = Vector3(0, 0, -16)
	for i in 5:
		if SimReadyLoader.has_asset("brep_domino"):
			SimReadyLoader.spawn_asset("brep_domino", Vector3(-0.9 + float(i) * 0.11, 0.12, 3.5), self)
	if SimReadyLoader.has_asset("playground_swing_seesaw"):
		SimReadyLoader.spawn_asset("playground_swing_seesaw", Vector3(14.0, 0.0, -14.0), self)
