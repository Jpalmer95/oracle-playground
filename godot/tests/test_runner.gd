extends Node
## Async test runner — needs a live SceneTree for physics frames.

var _failures := 0


func _ready() -> void:
	print("Oracle tests starting")
	await get_tree().process_frame
	_test_materials()
	await _test_thruster_direction()
	await _test_independent_hands()
	_test_shatter()
	_test_agent_view_api()
	if _failures == 0:
		print("Oracle tests: PASS")
		get_tree().quit(0)
	else:
		print("Oracle tests: FAIL count=", _failures)
		get_tree().quit(1)


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok  ", msg)
	else:
		_failures += 1
		print("  FAIL ", msg)


func _test_materials() -> void:
	print("[materials]")
	for kind in MaterialLab.profile_names():
		var mat := MaterialLab.make_physics_material(kind)
		_ok(mat != null, "physics mat %s" % kind)
		_ok(mat.friction >= 0.0, "friction %s" % kind)
	var ice := MaterialLab.make_physics_material("ice")
	var rubber := MaterialLab.make_physics_material("rubber")
	_ok(ice.friction < rubber.friction, "ice slipperier than rubber")
	_ok(rubber.bounce > ice.bounce, "rubber bouncier than ice")


func _test_thruster_direction() -> void:
	print("[thruster direction]")
	var world := Node3D.new()
	get_tree().root.add_child(world)
	var player: OraclePlayer = _make_player(world)
	player.gravity_scale = 0.0
	player.stabilize_upright = false
	player.apply_at_hands = false
	player.gear = 1
	await get_tree().physics_frame
	await get_tree().physics_frame
	for i in 20:
		player.apply_thruster(Vector3.FORWARD, 1.0)
		await get_tree().physics_frame
	var along := player.linear_velocity.dot(Vector3.FORWARD)
	_ok(along > 1.0, "thrust along look-forward, along=%.3f v=%s" % [along, player.linear_velocity])
	world.queue_free()
	await get_tree().process_frame


func _test_independent_hands() -> void:
	print("[independent hands]")
	var world := Node3D.new()
	get_tree().root.add_child(world)
	var player: OraclePlayer = _make_player(world)
	player.gravity_scale = 0.0
	player.stabilize_upright = false
	player.apply_at_hands = true
	player.gear = 1
	await get_tree().physics_frame
	# Left-only force offset should produce some angular velocity.
	player.apply_thruster(Vector3.FORWARD, 1.0, player.global_position + Vector3(-0.4, 0.8, 0))
	for i in 16:
		await get_tree().physics_frame
	_ok(player.angular_velocity.length() > 0.05 or player.linear_velocity.length() > 0.2,
		"offset hand changes motion, w=%s v=%s" % [player.angular_velocity, player.linear_velocity])
	world.queue_free()
	await get_tree().process_frame


func _test_shatter() -> void:
	print("[shatter]")
	var world := Node3D.new()
	get_tree().root.add_child(world)
	var crate: RigidBody3D = MaterialLab.spawn_cube("wood", Vector3(0, 2, 0), 0.6, world)
	crate.set_script(load("res://scripts/destructible.gd"))
	crate.kind = "wood"
	var shards: Array = crate.shatter()
	_ok(shards.size() >= 4, "shatter spawned %d shards" % shards.size())
	world.queue_free()


func _test_agent_view_api() -> void:
	print("[agent view]")
	_ok(AgentView != null, "AgentView autoload present")
	_ok(AgentView.has_method("capture"), "capture() exists")
	var path: String = AgentView.capture("user://agent_view.png")
	_ok(path != "", "capture returned a path")
	if path != "":
		_ok(FileAccess.file_exists(path) or FileAccess.file_exists("user://agent_view.png"), "png on disk")


func _make_player(parent: Node) -> OraclePlayer:
	var p := RigidBody3D.new()
	p.set_script(load("res://scripts/player.gd"))
	p.position = Vector3(0, 4, 0)
	parent.add_child(p)
	return p
