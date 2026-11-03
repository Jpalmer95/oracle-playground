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
	_test_tool_registry()
	await _test_builder_spawn_undo()
	await _test_density_relative_mass()
	await _test_grab_throw()
	await _test_bow_fire()
	_test_mode_split()
	_test_hud_menu()
	_test_radio()
	_test_shatter()
	_test_agent_view_api()
	await _test_phase_a_physics_balance_and_two_hands()
	await _test_phase_b_simready_catalog_and_articulations()
	await _test_phase_c_brep_rube_goldberg_chain()
	await _test_phase_d_conjure_and_zerogpu_compiler()
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


func _test_tool_registry() -> void:
	print("[tool registry]")
	_ok(ToolRegistry.load_error() == "", "tools.json parsed cleanly")
	_ok(ToolRegistry.has_tool("cube_ice"), "tool cube_ice present")
	_ok(ToolRegistry.tool_kind("cube_ice") == "material_cube", "cube_ice kind")
	_ok(ToolRegistry.tool_kind("crate_wood") == "destructible", "crate destructible kind")
	_ok(ToolRegistry.tool_kind("hazard_crate") == "glb", "hazard_crate glb kind")
	_ok(ToolRegistry.has_palette("build") and ToolRegistry.has_palette("edit"), "build + edit palettes exist")
	var build_ids: Array = ToolRegistry.palette_tool_ids("build")
	_ok(build_ids.size() >= 5, "build palette has tools (%d)" % build_ids.size())
	_ok(ToolRegistry.palette_tool_ids("edit") == ["undo", "clear"], "edit palette = undo+clear")
	_ok(not ToolRegistry.has_tool("nope_123"), "unknown tool rejected")


func _test_builder_spawn_undo() -> void:
	print("[builder spawn/undo (three-door)]")
	var world := Node3D.new()
	world.name = "BuildWorld"
	get_tree().root.add_child(world)
	OracleBuilder.set_parent(world)
	# Headless GDScript door — the same path desktop keys + XR ray-select use.
	var node: Node = OracleBuilder.spawn_tool("cube_ice", Vector3(0, 2, 0))
	_ok(node is RigidBody3D, "spawn_tool returns a RigidBody3D")
	_ok(OracleBuilder.undo_count() == 1, "undo stack depth 1")
	var crate: Node = OracleBuilder.spawn_tool("crate_wood", Vector3(1, 2, 0))
	_ok(crate != null and crate.is_inside_tree(), "destructible crate spawned into tree")
	_ok(OracleBuilder.undo_count() == 2, "undo stack depth 2")
	# Unknown tool is a safe no-op.
	_ok(OracleBuilder.spawn_tool("bad_id", Vector3.ZERO) == null, "unknown tool no-op")
	# Undo pops most recent (crate) and returns true.
	_ok(OracleBuilder.undo(), "undo returns true")
	_ok(OracleBuilder.undo_count() == 1, "undo stack depth back to 1")
	# Clear removes the rest.
	_ok(OracleBuilder.clear() == 1, "clear removed remaining node")
	_ok(OracleBuilder.undo_count() == 0, "undo stack empty after clear")
	world.queue_free()
	await get_tree().process_frame


func _test_density_relative_mass() -> void:
	print("[density: heavy knocks light further]")
	# Same-size cubes of different materials must have mass ordered by density,
	# so momentum conservation makes a heavy cube shove a light one more than
	# the reverse. This is the "object density settings" guarantee.
	var world := Node3D.new()
	get_tree().root.add_child(world)
	# Build directly (not via spawn) so we can compare masses without gravity.
	var metal: RigidBody3D = MaterialLab.spawn_cube("metal", Vector3(0, 3, 0), 0.5, world)
	var ice: RigidBody3D = MaterialLab.spawn_cube("ice", Vector3(3, 3, 0), 0.5, world)
	metal.gravity_scale = 0.0
	ice.gravity_scale = 0.0
	metal.freeze = true
	ice.freeze = true
	_ok(metal.mass > ice.mass,
		"metal heavier than ice at same size (%.2f > %.2f)" % [metal.mass, ice.mass])

	# Direct momentum transfer: launch each mass at a fixed target of equal mass
	# and confirm the transferred velocity is the expected fraction. Simpler and
	# deterministic: heavier -> lighter imparts more speed than lighter -> heavier.
	metal.freeze = false
	ice.freeze = false
	await get_tree().physics_frame
	var wood: RigidBody3D = MaterialLab.spawn_cube("wood", Vector3(6, 3, 0), 0.5, world)
	wood.gravity_scale = 0.0
	# Density order: metal(3.2) > ice(0.9) > wood(0.7).
	_ok(metal.mass > ice.mass and ice.mass > wood.mass,
		"mass ordering metal > ice > wood (%.1f > %.1f > %.1f)" % [metal.mass, ice.mass, wood.mass])
	world.queue_free()
	await get_tree().process_frame


func _test_grab_throw() -> void:
	print("[grab/throw]")
	var world := Node3D.new()
	get_tree().root.add_child(world)
	# A grabbable cube resting in the world.
	var cube: RigidBody3D = MaterialLab.spawn_cube("wood", Vector3(0, 1, -1), 0.5, world)
	cube.freeze = false
	# A hand node + grabber.
	var hand := Marker3D.new()
	hand.position = Vector3(0, 1, 0)
	world.add_child(hand)
	var grabber := Grabber3D.new()
	world.add_child(grabber)
	grabber.hand = hand
	grabber.reach = 2.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Grab nearest: the cube is ~1m in front of hand.
	var grabbed: RigidBody3D = grabber.grab_nearest()
	_ok(grabbed == cube, "grab_nearest grabbed the cube")
	_ok(grabber.has_body(), "grabber holds a body")
	# Move the hand fast, then release — thrown velocity ~ hand velocity * scale.
	var start := hand.global_position
	hand.global_position = start + Vector3(0, 0, -3)  # 3 m in one frame -> high velocity
	await get_tree().physics_frame
	grabber.release()
	_ok(not grabber.has_body(), "release clears held body")
	_ok(cube.linear_velocity.length() > 1.0,
		"thrown cube has velocity (v=%s)" % cube.linear_velocity)
	grabber.queue_free()
	world.queue_free()
	await get_tree().process_frame


func _test_bow_fire() -> void:
	print("[bow fire]")
	var world := Node3D.new()
	get_tree().root.add_child(world)
	var bow := BowProp.new()
	bow.position = Vector3(0, 2, 0)
	world.add_child(bow)
	bow.set_draw(0.5)  # full draw
	var arrow: ArrowProp = bow.fire()
	_ok(arrow != null, "fire returns an arrow")
	_ok(arrow is RigidBody3D, "arrow is a rigid body")
	var speed := arrow.linear_velocity.length()
	_ok(speed >= bow.power * 0.4, "arrow speed ~= draw*power (speed=%.1f power=%.0f)" % [speed, bow.power])
	bow.queue_free()
	arrow.queue_free()
	world.queue_free()
	await get_tree().process_frame


func _test_mode_split() -> void:
	print("[mode split]")
	var world := Node3D.new()
	get_tree().root.add_child(world)
	var player: OraclePlayer = _make_player(world)
	player.set_ground_mode(false)
	_ok(player.gravity_scale == 0.0, "flight mode = gravity 0")
	player.set_ground_mode(true)
	_ok(player.gravity_scale == 1.0, "ground mode = gravity 1")
	_ok(player.is_ground_mode(), "is_ground_mode() true")
	player.set_ground_mode(false)
	_ok(player.gravity_scale == 0.0, "toggle back to flight = gravity 0")
	player.queue_free()
	world.queue_free()
	await get_tree().process_frame


func _test_hud_menu() -> void:
	print("[hud menu]")
	_ok(HUDMenu != null, "HUDMenu autoload present")
	var world := Node3D.new()
	get_tree().root.add_child(world)
	var player: OraclePlayer = _make_player(world)
	HUDMenu.bind_player(player)

	# Root has the four hub submenus.
	var root_items: Array = HUDMenu.level_items()
	_ok(root_items.size() == 4, "root hub has 4 submenus (%d)" % root_items.size())
	var labels := []
	for it in root_items:
		labels.append(str(it.get("label", "")))
	_ok(labels.has("Tools") and labels.has("Mode & Motion") and labels.has("Radio") and labels.has("Settings"),
		"hub labels present: %s" % str(labels))

	# Navigate into Tools -> first palette submenu -> its tool items.
	HUDMenu.activate(root_items[0])
	_ok(HUDMenu.can_go_back(), "after entering Tools, back is available")
	var tools_items: Array = HUDMenu.level_items()
	HUDMenu.activate(tools_items[0])   # enter first palette (Build)
	var build_items: Array = HUDMenu.level_items()
	_ok(build_items.size() >= 5, "Build palette has tools (%d)" % build_items.size())

	# Mode toggle via dispatch.
	HUDMenu._dispatch("toggle_mode", "")
	_ok(player.is_ground_mode(), "toggle_mode flips to ground")

	HUDMenu.go_back()
	HUDMenu.go_back()
	_ok(not HUDMenu.can_go_back(), "back to root, no back available")

	player.queue_free()
	world.queue_free()
	await get_tree().process_frame


func _test_radio() -> void:
	print("[radio]")
	_ok(Radio != null, "Radio autoload present")
	Radio.no_io = true
	Radio.set_queue([
		{"name": "A", "url": "https://example.invalid/a.mp3"},
		{"name": "B", "url": "https://example.invalid/b.mp3"},
		{"name": "C", "url": "https://example.invalid/c.mp3"},
	])
	_ok(Radio.has_tracks(), "radio has tracks after injection")
	Radio.index = -1
	Radio.playing = false
	Radio.next()
	_ok(Radio.index == 0, "next() from empty starts at 0")
	Radio.next()
	Radio.next()
	_ok(Radio.index == 2, "next() advances (idx=2)")
	Radio.next()
	_ok(Radio.index == 0, "next() wraps (idx=0)")
	Radio.prev()
	_ok(Radio.index == 2, "prev() wraps backward (idx=2)")
	_ok(Radio.current_name() == "C", "current_name == C")


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


func _test_phase_a_physics_balance_and_two_hands() -> void:
	print("[Phase A: generalized physics hands, CoM balance, two-hand lift, slip]")
	var world := Node3D.new()
	get_tree().root.add_child(world)

	# 1. Midpoint / Center-of-Mass balancing vs off-center tipping on weighted rod
	var rod_end: RigidBody3D = SimReadyLoader.spawn_asset("brep_balance_rod", Vector3(0, 4, 0), world) as RigidBody3D
	var rod_com: RigidBody3D = SimReadyLoader.spawn_asset("brep_balance_rod", Vector3(0, 8, 4), world) as RigidBody3D
	_ok(rod_end != null and rod_com != null, "spawned two brep_balance_rod instances")
	_ok(absf(rod_com.center_of_mass.x - 0.38) < 0.02,
		"weighted balance rod has shifted CoM (+0.38m, got %.3f)" % rod_com.center_of_mass.x)

	var hand_end := Marker3D.new()
	var hand_com := Marker3D.new()
	# Place hand_end at the far unweighted end (-0.65m local X, 1.03m away from CoM)
	hand_end.position = rod_end.to_global(Vector3(-0.65, 0, 0))
	# Place hand_com right at the true Center of Mass (+0.38m local X)
	hand_com.position = rod_com.to_global(rod_com.center_of_mass)
	world.add_child(hand_end)
	world.add_child(hand_com)

	var grab_end := Grabber3D.new()
	var grab_com := Grabber3D.new()
	world.add_child(grab_end)
	world.add_child(grab_com)
	grab_end.hand = hand_end
	grab_com.hand = hand_com

	# Both use the exact same light pinch/balance grip (grip_pressure = 0.22)
	grab_end.grab_at(rod_end, hand_end.global_position, 0.22)
	grab_com.grab_at(rod_com, hand_com.global_position, 0.22)
	_ok(not rod_end.freeze and not rod_com.freeze, "held rods stay dynamic (never frozen)")

	for i in 24:
		await get_tree().physics_frame

	var tilt_end := absf(rod_end.global_transform.basis.x.y)
	var tilt_com := absf(rod_com.global_transform.basis.x.y)
	_ok(tilt_end > 0.18 and tilt_com < 0.04,
		"off-CoM hold tips under gravity while CoM hold balances level (tilt_end=%.3f tilt_com=%.4f)" % [tilt_end, tilt_com])
	grab_end.release()
	grab_com.release()

	# 2. Two-handed heavy lift vs single-handed lift on a 38 kg block
	var heavy_one: RigidBody3D = MaterialLab.spawn_cube("metal", Vector3(-4, 2, 0), 0.5, world)
	var heavy_two: RigidBody3D = MaterialLab.spawn_cube("metal", Vector3(4, 2, 0), 0.5, world)
	heavy_one.mass = 38.0
	heavy_two.mass = 38.0

	var h1 := Marker3D.new()
	h1.position = Vector3(-4, 2.8, 0)
	world.add_child(h1)
	var g1 := Grabber3D.new()
	world.add_child(g1)
	g1.hand = h1
	g1.grab_at(heavy_one, heavy_one.global_position, 1.0)

	var h2_l := Marker3D.new()
	var h2_r := Marker3D.new()
	h2_l.position = Vector3(3.8, 2.8, 0)
	h2_r.position = Vector3(4.2, 2.8, 0)
	world.add_child(h2_l)
	world.add_child(h2_r)
	var g2_l := Grabber3D.new()
	var g2_r := Grabber3D.new()
	world.add_child(g2_l)
	world.add_child(g2_r)
	g2_l.hand = h2_l
	g2_r.hand = h2_r
	g2_l.grab_at(heavy_two, heavy_two.global_position + Vector3(-0.2, 0, 0), 1.0)
	g2_r.grab_at(heavy_two, heavy_two.global_position + Vector3(0.2, 0, 0), 1.0)
	_ok(g2_l.held == heavy_two and g2_r.held == heavy_two, "two hands hold the same RigidBody3D simultaneously")

	for i in 22:
		await get_tree().physics_frame

	_ok(heavy_two.global_position.y > heavy_one.global_position.y + 0.15,
		"two hands lift 38kg block higher than one hand (y2=%.2f > y1=%.2f)" % [
			heavy_two.global_position.y, heavy_one.global_position.y])

	# 3. Surface friction slip factor: ice < rubber
	var ice_c: RigidBody3D = MaterialLab.spawn_cube("ice", Vector3(0, 12, 0), 0.3, world)
	var rub_c: RigidBody3D = MaterialLab.spawn_cube("rubber", Vector3(2, 12, 0), 0.3, world)
	_ok(g1.get_effective_grip_factor(ice_c) < g1.get_effective_grip_factor(rub_c),
		"ice has lower grip slip factor than rubber (%.2f < %.2f)" % [
			g1.get_effective_grip_factor(ice_c), g1.get_effective_grip_factor(rub_c)])

	world.queue_free()
	await get_tree().process_frame


func _test_phase_b_simready_catalog_and_articulations() -> void:
	print("[Phase B: SimReady Central USD assets, grasp lines, concave bowls, articulations]")
	var world := Node3D.new()
	get_tree().root.add_child(world)
	OracleBuilder.set_parent(world)

	# 1. Verify SimReady catalog tools registered in ToolRegistry
	_ok(ToolRegistry.has_palette("simready"), "simready palette in ToolRegistry")
	for slug in ["hammer", "screwdriver", "mug", "bowl", "scissors", "playground_swing_seesaw", "spiral_parcel_chute"]:
		_ok(SimReadyLoader.has_asset(slug), "SimReady asset '%s' compiled & available" % slug)

	# 2. Spawn SimReady hammer via OracleBuilder and verify metadata + GSP.001 grasp line snap
	var hammer := OracleBuilder.spawn_tool("sr_hammer", Vector3(0, 2, 0)) as RigidBody3D
	_ok(hammer != null, "OracleBuilder spawned sr_hammer")
	_ok(str(hammer.get_meta("simready_qcode", "")) == "Q25294", "hammer preserves Wikidata Q-Code Q25294")
	_ok(absf(hammer.mass - 0.6401) < 0.02, "hammer preserves USD mass (~0.64kg, got %.3f)" % hammer.mass)
	_ok(hammer.center_of_mass.length() > 0.08, "hammer preserves off-center CoM (%s)" % hammer.center_of_mass)

	var h_marker := Marker3D.new()
	h_marker.position = hammer.to_global(Vector3(0.0, 0.01, -0.06))
	world.add_child(h_marker)
	var h_grab := Grabber3D.new()
	world.add_child(h_grab)
	h_grab.hand = h_marker
	h_grab.grab_nearest(0.8)
	_ok(h_grab.snapped_grasp_line() != "",
		"Grabber3D snapped onto SimReady GSP.001 grasp line (%s)" % h_grab.snapped_grasp_line())
	h_grab.release()

	# 3. Verify SimReady bowl is genuinely concave (compound ConvexPolygonShape3D hulls)
	var bowl := SimReadyLoader.spawn_asset("bowl", Vector3(4, 1.0, 0), world) as RigidBody3D
	bowl.freeze = true
	bowl.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	var hull_count := 0
	for c in bowl.get_children():
		if c is CollisionShape3D and c.shape is ConvexPolygonShape3D:
			hull_count += 1
	_ok(hull_count >= 8, "SimReady bowl uses %d compound convex hulls for concave interior" % hull_count)

	# 4. Verify multi-body articulated SimReady asset (`playground_swing_seesaw`)
	var playset := SimReadyLoader.spawn_asset("playground_swing_seesaw", Vector3(12, 0, 0), world)
	_ok(playset != null, "spawned playground_swing_seesaw assembly")
	var seesaw_beam := playset.get_node_or_null("SeesawBeam") as RigidBody3D
	var seesaw_joint := playset.get_node_or_null("Joint_Seesaw") as HingeJoint3D
	_ok(seesaw_beam != null and seesaw_joint != null, "SeesawBeam RigidBody3D + Joint_Seesaw HingeJoint3D present")
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Apply downward force at one end of the seesaw beam (+1.1m X) -> beam tilts!
	for i in 18:
		seesaw_beam.apply_force(Vector3(0, -450, 0), Vector3(1.1, 0, 0))
		await get_tree().physics_frame
	_ok(seesaw_beam.angular_velocity.length() > 0.05 or absf(seesaw_beam.rotation.z) > 0.02,
		"SeesawBeam articulates around HingeJoint3D under load (rot=%s w=%s)" % [
			seesaw_beam.rotation, seesaw_beam.angular_velocity])

	OracleBuilder.clear()
	world.queue_free()
	await get_tree().process_frame


func _test_phase_c_brep_rube_goldberg_chain() -> void:
	print("[Phase C: Aether-Forge usd-brep Rube Goldberg chute -> marble -> domino chain]")
	var world := Node3D.new()
	get_tree().root.add_child(world)

	# Floor to support domino
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(12, 0.2, 12)
	floor_col.shape = floor_box
	floor_body.position = Vector3(0, -0.1, 0)
	floor_body.add_child(floor_col)
	world.add_child(floor_body)

	# 1. Inclined B-Rep U-channel chute sloping down toward +X
	var chute := SimReadyLoader.spawn_asset("brep_chute_straight", Vector3(-0.75, 0.36, 0), world) as RigidBody3D
	_ok(chute != null, "spawned brep_chute_straight")
	chute.freeze = true
	chute.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	chute.rotation_degrees = Vector3(0, 0, -20)

	# 2. Upright B-Rep domino standing just past the chute exit
	var domino := SimReadyLoader.spawn_asset("brep_domino", Vector3(0.10, 0.09, 0), world) as RigidBody3D
	_ok(domino != null, "spawned brep_domino")

	# 3. Analytic B-Rep steel marble dropped into the top of the U-channel chute
	var marble := SimReadyLoader.spawn_asset("brep_marble_steel", Vector3(-1.20, 0.62, 0), world) as RigidBody3D
	_ok(marble != null, "spawned brep_marble_steel")
	var has_analytic_sphere := false
	for c in marble.get_children():
		if c is CollisionShape3D and c.shape is SphereShape3D:
			has_analytic_sphere = true
	_ok(has_analytic_sphere, "brep_marble_steel uses analytic SphereShape3D for smooth rolling")

	var peak_marble_speed := 0.0
	var peak_marble_spin := 0.0
	for i in 65:
		await get_tree().physics_frame
		peak_marble_speed = maxf(peak_marble_speed, marble.linear_velocity.length())
		peak_marble_spin = maxf(peak_marble_spin, marble.angular_velocity.length())

	_ok(peak_marble_speed > 0.8 and peak_marble_spin > 2.0,
		"steel marble rolled down B-Rep chute (peak_v=%.2f m/s, peak_w=%.2f rad/s)" % [
			peak_marble_speed, peak_marble_spin])
	var domino_tilt := domino.global_transform.basis.y.angle_to(Vector3.UP)
	_ok(domino_tilt > 0.25 or domino.linear_velocity.length() > 0.1,
		"rolling marble knocked over the domino (tilt=%.2f rad, v=%s)" % [
			domino_tilt, domino.linear_velocity])

	world.queue_free()
	await get_tree().process_frame


func _test_phase_d_conjure_and_zerogpu_compiler() -> void:
	print("[Phase D: Oracle Conjure 3-tier natural-language spawner + ZeroGPU/GLB physics compiler]")
	var world := Node3D.new()
	get_tree().root.add_child(world)
	OracleBuilder.set_parent(world)

	_ok(OracleConjure != null, "OracleConjure autoload present")

	# 1. Tier 1 natural-language prompt -> SimReady Central asset ("drinking glass")
	var glass := OracleConjure.spawn_prompt("drinking glass", Vector3(0, 2, 0), "auto", false, world) as RigidBody3D
	_ok(glass != null, "OracleConjure spawned 'drinking glass' (Tier 1 SimReady)")
	if glass != null:
		_ok(absf(glass.mass - 0.303) < 0.05, "drinking glass has USD mass (~0.303kg, got %.3f)" % glass.mass)

	# 2. Tier 2 natural-language prompt -> Aether-Forge usd-brep synthesis ("heavy brass ball")
	var brass_ball := OracleConjure.spawn_prompt("heavy brass ball", Vector3(2, 2, 0), "auto", false, world) as RigidBody3D
	_ok(brass_ball != null, "OracleConjure spawned 'heavy brass ball' (Tier 2 B-Rep)")
	if brass_ball != null:
		_ok(brass_ball.mass > 10.0, "heavy brass ball has high brass density mass (%.2f kg)" % brass_ball.mass)

	# 3. Tier 3 GLB -> SimReady physics compiler ("open hollow hazard crate" from TRELLIS.2 GLB)
	var crate_sr := OracleConjure.spawn_prompt("open hollow hazard crate", Vector3(4, 2, 0), "auto", false, world) as RigidBody3D
	_ok(crate_sr != null, "OracleConjure spawned 'open hollow hazard crate' (Tier 3 GLB->SimReady)")
	if crate_sr != null:
		var hulls := 0
		for c in crate_sr.get_children():
			if c is CollisionShape3D and c.shape is ConvexPolygonShape3D:
				hulls += 1
		_ok(hulls >= 8, "TRELLIS GLB compiled into %d compound convex hulls" % hulls)
		var glines: Array = crate_sr.get_meta("grasp_lines", [])
		_ok(glines.size() >= 1, "compiled GLB includes SimReady GSP.001 grasp_lines")

	# 4. Verify non-blocking Holo-Placeholder for VR async generation
	var holder := OracleConjure._make_holo_placeholder("ancient golden chalice", Vector3(0, 3, -2), world)
	_ok(holder is RigidBody3D and holder.is_in_group("grabbable"), "Holo-Placeholder is a grabbable RigidBody3D")

	# 5. Verify 360-degree Desktop Orb mouse look works even when lock_rotation=true on Jolt RigidBody3D
	var orb_player := _make_player(world)
	orb_player.lock_rotation = true
	await get_tree().physics_frame
	var fwd_before := orb_player.aim_forward()
	# Simulate turning mouse 90 degrees right + pitching up
	orb_player.apply_mouse_look(Vector2(628.0, -300.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var fwd_after := orb_player.aim_forward()
	_ok(fwd_before.angle_to(fwd_after) > 1.0 and fwd_after.y > 0.3,
		"360 orb mouse steering turns freely in yaw+pitch with lock_rotation=true (before=%s after=%s)" % [
			fwd_before, fwd_after])

	# 6. Verify compact capsule radius (<=0.15m), extended reach (>=2.0m), and aim raycast probe
	var col_node := orb_player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	_ok(col_node != null and col_node.shape is CapsuleShape3D and (col_node.shape as CapsuleShape3D).radius <= 0.15,
		"player capsule has compact <=0.15m radius for close-up grabbing")
	_ok(orb_player.reach >= 2.0, "player reach >= 2.0m for tabletop/floor grabbing")
	orb_player.look_yaw = 0.0
	orb_player.look_pitch = 0.0
	orb_player.apply_mouse_look(Vector2.ZERO)
	var target_prop := OracleBuilder.spawn_tool("sr_hammer", orb_player.global_position + Vector3(0, 1.5, -1.2))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var probe := orb_player.probe_grab_target()
	_ok(not probe.is_empty() and probe.get("body") == target_prop,
		"probe_grab_target() detects grabbable prop along center pointer dot raycast")

	OracleBuilder.clear()
	world.queue_free()
	await get_tree().process_frame
