extends Node
## Async test runner — needs a live SceneTree for physics frames.

var _failures := 0


func _ready() -> void:
	print("Oracle tests starting")
	await get_tree().process_frame
	_test_materials()
	await _test_thruster_direction()
	await _test_independent_hands()
	await _test_central_force_no_torque()
	_test_xr_rig_decoupled()
	await _test_flight_is_gravity_free()
	await _test_velocity_damping()
	await _test_impact_wobble_settles()
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


func _test_central_force_no_torque() -> void:
	print("[central force no oscillation]")
	# Regression for the oscillation bug: with apply_at_hands=false (default),
	# an offset hand force must NOT create angular velocity. This is the
	# SuperSonic-smooth path; the old offset-torque path caused tumble that
	# stabilize_upright fought -> oscillation on opposite/same-direction input.
	var world := Node3D.new()
	get_tree().root.add_child(world)
	var player: OraclePlayer = _make_player(world)
	player.gravity_scale = 0.0
	player.stabilize_upright = false
	player.apply_at_hands = false
	player.gear = 1
	await get_tree().physics_frame
	# Fire an offset force repeatedly — net result must be linear, no spin.
	for i in 20:
		player.apply_thruster(Vector3.FORWARD, 1.0, player.global_position + Vector3(-0.4, 0.8, 0))
		await get_tree().physics_frame
	_ok(player.angular_velocity.length() < 0.5,
		"central force produces no torque, w=%s" % player.angular_velocity)
	_ok(player.linear_velocity.length() > 1.0,
		"central force still translates, v=%s" % player.linear_velocity)
	world.queue_free()
	await get_tree().process_frame


func _test_xr_rig_decoupled() -> void:
	print("[xr rig decoupled]")
	# Regression: the tracked XROrigin3D must be a SIBLING of the physics body,
	# never a child. A child inherits body tumble rotation -> nausea.
	var player: OraclePlayer = _make_player(get_tree().root)
	var origin := player.get_node_or_null("XROrigin3D") as XROrigin3D
	_ok(origin == null, "XROrigin3D is not a child of the body")
	var sibling := player.get_parent().get_node_or_null("XROrigin3D") as XROrigin3D
	_ok(sibling != null, "XROrigin3D is a sibling at scene root")
	player.queue_free()
	await get_tree().process_frame


func _test_flight_is_gravity_free() -> void:
	print("[flight gravity-free]")
	var world := Node3D.new()
	get_tree().root.add_child(world)
	var player: OraclePlayer = _make_player(world)
	_ok(player.gravity_scale == 0.0, "flight_mode => gravity_scale 0 (SuperSonic hover)")
	player.queue_free()
	world.queue_free()
	await get_tree().process_frame


func _test_velocity_damping() -> void:
	print("[velocity damping]")
	var world := Node3D.new()
	get_tree().root.add_child(world)
	var player: OraclePlayer = _make_player(world)
	player.gravity_scale = 0.0
	player.stabilize_upright = false
	player.gear = 1
	# Accelerate, then stop thrusting and confirm velocity decays (halo-to-hover).
	for i in 30:
		player.apply_thruster(Vector3.FORWARD, 1.0)
		await get_tree().physics_frame
	var peak := player.linear_velocity.length()
	for i in 30:
		await get_tree().physics_frame
	var after := player.linear_velocity.length()
	_ok(after < peak * 0.5, "velocity decays after thrust ends (peak=%.2f after=%.2f)" % [peak, after])
	player.queue_free()
	world.queue_free()
	await get_tree().process_frame


func _test_impact_wobble_settles() -> void:
	print("[impact wobble settles]")
	# Regression: after a collision imparts spin (angular_velocity), the body
	# must re-stabilize quickly. angular_damp + the damped stabilizer must bleed
	# a starting spin to near-zero within ~0.5s, not oscillate forever.
	var world := Node3D.new()
	get_tree().root.add_child(world)
	var player: OraclePlayer = _make_player(world)
	player.gravity_scale = 0.0
	player.stabilize_upright = true
	# Simulate a ram: shove angular velocity directly, like hitting a crate.
	player.angular_velocity = Vector3(0.0, 2.0, -1.0)
	var peak := player.angular_velocity.length()
	var settled_at := -1
	for i in 90:
		await get_tree().physics_frame
		if settled_at < 0 and player.angular_velocity.length() < peak * 0.15:
			settled_at = i
	_ok(settled_at >= 0 and settled_at < 45, "spin settles <~0.5s (peak=%.2f settled_frame=%d w=%s)" % [
		peak, settled_at, player.angular_velocity])
	player.queue_free()
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
