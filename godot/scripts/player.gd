extends RigidBody3D
class_name OraclePlayer
## Dual independent hand thrusters (SuperSonic → Jolt).
## Each trigger fires along that hand's -Z. Grip is turbo.

signal mode_changed(mode: String)

@export var flight_mode := true
@export var thrust_accel := 15.0          # m/s^2 per gear point (SuperSonic baseSpeed)
@export var throttle_scale := 2.0         # SuperSonic's x2 on thrust
@export var velocity_damp := 2.0          # 1/s exponential drag (halo-to-hover)
@export var turbo_multiplier := 3.8
@export var turn_rate := 2.0              # rad/s at full stick (SuperSonic dolly.rotation.y -= axes[2]*2*dt)
@export var vertical_accel := 12.0         # m/s^2 at full left-stick up/down
@export var apply_at_hands := false       # true = offset torque (independent-thruster turn); false = central force (SuperSonic-smooth)
@export var stabilize_upright := true
@export var stabilize_strength := 60.0    # 1/s^2 angular spring rate (natural freq = sqrt)
@export var look_sensitivity := 0.0025
@export var max_speed := 80.0
@export var max_gear := 5
@export var max_booster_fuel := 100.0
@export var booster_drain := 28.0
@export var booster_recharge := 18.0
# Ground mode (throw/grab/bow). Separate from flight — no shared inputs.
@export var walk_speed := 3.5
@export var jump_impulse := 5.0
@export var reach := 0.7

var gear := 2
var booster_fuel := 100.0
var xr_active := false
var look_yaw := 0.0
var look_pitch := 0.0
var _bank_roll := 0.0
var _yaw_rate := 0.0
var spawn_xform := Transform3D.IDENTITY
var _gear_cooldown := 0.0
var _left_click_was := false
var _right_click_was := false
var _ground_mode := false
var _left_grabber: Grabber3D
var _right_grabber: Grabber3D
var _mode_edge_was := false
var _jump_was := false

var _left: Node3D
var _right: Node3D
var _xr_left: XRController3D
var _xr_right: XRController3D
var _xr_origin: XROrigin3D
var _desktop_cam: Camera3D
var _body_mesh: MeshInstance3D
var _mouse_captured := false


func _ready() -> void:
	spawn_xform = global_transform
	mass = 80.0
	continuous_cd = true
	can_sleep = false
	# SuperSonic flight is gravity-free + velocity-damped (halo-to-hover).
	# Hangar doors stay shut when flight_mode is off (walk/fly toggle later).
	gravity_scale = 0.0 if flight_mode else 1.0
	linear_damp = 0.0
	# Collision spin must decay fast (impact wobble), even with stabilizer off.
	# Time constant ~1/angular_damp s; 5.0 => residual spin gone in ~0.2s.
	angular_damp = 5.0
	collision_layer = 2
	collision_mask = 5
	_ensure_rig()
	_try_start_xr()
	if not xr_active:
		_set_desktop_mode()


func _ensure_rig() -> void:
	# XR rule: XROrigin3D lives at scene root, NOT under the physics body.
	# If parented under this RigidBody, tracked camera + hands inherit the
	# body's tumble rotation -> nausea + "rotational force" feel. We keep the
	# origin as a sibling and copy only the body's *position* into it each frame.
	_xr_origin = get_parent().get_node_or_null("XROrigin3D") as XROrigin3D
	if _xr_origin == null:
		_xr_origin = XROrigin3D.new()
		_xr_origin.name = "XROrigin3D"
		get_parent().add_child(_xr_origin)
		var cam := XRCamera3D.new()
		cam.name = "XRCamera3D"
		_xr_origin.add_child(cam)
		_xr_left = XRController3D.new()
		_xr_left.name = "LeftHand"
		_xr_left.tracker = &"left_hand"
		_xr_left.pose = &"aim"
		_xr_origin.add_child(_xr_left)
		_xr_right = XRController3D.new()
		_xr_right.name = "RightHand"
		_xr_right.tracker = &"right_hand"
		_xr_right.pose = &"aim"
		_xr_origin.add_child(_xr_right)
	else:
		_xr_left = _xr_origin.get_node_or_null("LeftHand") as XRController3D
		_xr_right = _xr_origin.get_node_or_null("RightHand") as XRController3D

	_desktop_cam = get_node_or_null("DesktopCamera") as Camera3D
	if _desktop_cam == null:
		_desktop_cam = Camera3D.new()
		_desktop_cam.name = "DesktopCamera"
		_desktop_cam.position = Vector3(0, 1.5, 0)
		_desktop_cam.rotation_order = EULER_ORDER_YXZ
		add_child(_desktop_cam)
	else:
		_desktop_cam.rotation_order = EULER_ORDER_YXZ

	# Virtual hands for desktop / tests (always present).
	_left = get_node_or_null("VirtualLeft")
	if _left == null:
		_left = Marker3D.new()
		_left.name = "VirtualLeft"
		_desktop_cam.add_child(_left)
		_left.position = Vector3(-0.25, -0.15, -0.4)
	_right = get_node_or_null("VirtualRight")
	if _right == null:
		_right = Marker3D.new()
		_right.name = "VirtualRight"
		_desktop_cam.add_child(_right)
		_right.position = Vector3(0.25, -0.15, -0.4)

	if get_node_or_null("CollisionShape3D") == null:
		var col := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.28
		cap.height = 1.6
		col.shape = cap
		col.position = Vector3(0, 0.8, 0)
		add_child(col)
	_body_mesh = get_node_or_null("BodyMesh") as MeshInstance3D
	if _body_mesh == null:
		_body_mesh = MeshInstance3D.new()
		_body_mesh.name = "BodyMesh"
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.26
		mesh.height = 1.55
		_body_mesh.mesh = mesh
		_body_mesh.position = Vector3(0, 0.8, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.12, 0.12, 0.14)
		mat.metallic = 0.4
		mat.roughness = 0.45
		_body_mesh.material_override = mat
		add_child(_body_mesh)

	# Grabbers (ground mode only) — one per hand.
	if _left_grabber == null:
		_left_grabber = Grabber3D.new()
		_left_grabber.name = "LeftGrabber"
		add_child(_left_grabber)
		_left_grabber.reach = reach
	if _right_grabber == null:
		_right_grabber = Grabber3D.new()
		_right_grabber.name = "RightGrabber"
		add_child(_right_grabber)
		_right_grabber.reach = reach


func _try_start_xr() -> void:
	# OpenXR must be initialized by the engine at startup (Vulkan).
	# play-vr.sh passes --xr-mode on. Headless / desktop pass --xr-mode off.
	if DisplayServer.get_name() == "headless":
		print("Oracle XR: skip (headless)")
		return
	var iface := XRServer.find_interface("OpenXR")
	if iface == null:
		push_warning("Oracle XR: OpenXR interface missing")
		return
	print("Oracle XR: found OpenXR initialized=", iface.is_initialized())
	if not iface.is_initialized():
		# Runtime initialize only works if the project enabled OpenXR before boot.
		var ok := iface.initialize()
		print("Oracle XR: initialize()=", ok)
		if not ok:
			push_warning("Oracle XR: SteamVR session not attached. Start Steam Link first, then tools/play-vr.sh")
			return
	_enter_xr()


func _enter_xr() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.physics_ticks_per_second = 90
	get_viewport().use_xr = true
	xr_active = true
	lock_rotation = true
	if _desktop_cam:
		_desktop_cam.current = false
	if _body_mesh:
		_body_mesh.visible = false
	_setup_wrist_palette()
	mode_changed.emit("openxr")
	print("Oracle mode: openxr")


func _setup_wrist_palette() -> void:
	var existing := _xr_origin.get_node_or_null("WristPalette")
	if existing:
		return
	if _xr_left == null or _xr_right == null or _xr_origin == null:
		return
	var palette := Node3D.new()
	palette.name = "WristPalette"
	palette.set_script(preload("res://scripts/wrist_palette.gd"))
	_xr_origin.add_child(palette)
	palette.setup(_xr_origin, _xr_left, _xr_right)
	print("WristPalette attached (palette=%s)" % palette.palette_id)


func _set_desktop_mode() -> void:
	xr_active = false
	if _desktop_cam:
		_desktop_cam.current = true
	if DisplayServer.get_name() != "headless":
		# Lock physics body angular axes in interactive play so collisions
		# never tip/roll/spiral the camera (SuperSonic-style horizon lock).
		lock_rotation = not apply_at_hands
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_mouse_captured = true
	mode_changed.emit("desktop")
	print("Oracle mode: desktop")


func _unhandled_input(event: InputEvent) -> void:
	if xr_active:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_mouse_captured = not _mouse_captured
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _mouse_captured else Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.pressed and _mouse_captured:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			gear = mini(max_gear, gear + 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			gear = maxi(1, gear - 1)
	if event is InputEventMouseMotion and _mouse_captured:
		apply_mouse_look(event.relative)


func apply_mouse_look(relative: Vector2) -> void:
	## Free 360-degree 3D orb look applied directly to DesktopCamera (YXZ order)
	## so Jolt's RigidBody3D rotation lock never blocks or snaps horizontal turning.
	var dyaw := -relative.x * look_sensitivity
	look_yaw = wrapf(look_yaw + dyaw, -PI, PI)
	look_pitch = clampf(look_pitch - relative.y * look_sensitivity, -1.52, 1.52)
	_yaw_rate = clampf(_yaw_rate + dyaw * 8.0, -0.45, 0.45)
	if _desktop_cam:
		_desktop_cam.rotation_order = EULER_ORDER_YXZ
		_desktop_cam.rotation = Vector3(look_pitch, look_yaw, _bank_roll)


func aim_forward() -> Vector3:
	if xr_active and _xr_origin:
		var xrcam := _xr_origin.get_node_or_null("XRCamera3D") as Node3D
		if xrcam:
			return -xrcam.global_transform.basis.z.normalized()
	if _desktop_cam:
		return -_desktop_cam.global_transform.basis.z.normalized()
	return -global_transform.basis.z.normalized()


func _physics_process(delta: float) -> void:
	_handle_meta_keys(delta)
	if _ground_mode:
		_ground_physics(delta)
	else:
		_flight_physics(delta)


func _flight_physics(delta: float) -> void:
	var left_amt := left_trigger()
	var right_amt := right_trigger()
	var turbo := _turbo_held()
	var boost := 1.0
	if turbo and booster_fuel > 5.0:
		boost = turbo_multiplier
		booster_fuel = maxf(0.0, booster_fuel - booster_drain * delta)
	else:
		booster_fuel = minf(max_booster_fuel, booster_fuel + booster_recharge * delta)

	if left_amt > 0.02:
		_fire_hand(_active_left(), left_amt * boost)
	if right_amt > 0.02:
		_fire_hand(_active_right(), right_amt * boost)
	if (left_amt > 0.02 or right_amt > 0.02) and not xr_active and DisplayServer.get_name() != "headless":
		var spd := linear_velocity.length()
		if spd > 0.5:
			linear_velocity = linear_velocity.lerp(aim_forward() * spd, clampf(8.0 * delta, 0.0, 1.0))

	# SuperSonic handleDesktopInput + Oracle Orb 3D velocity vectoring on desktop!
	if not xr_active and DisplayServer.get_name() != "headless":
		_desktop_flight_move(boost, delta)
		# Allow grabbing/balancing props while hovering in desktop flight mode too
		_left_grabber.hand = _active_left()
		_right_grabber.hand = _active_right()
		_handle_grab(_left_grabber, _grip_left())
		_handle_grab(_right_grabber, _grip_right())

	# Smoothly bleed off visual bank roll toward level and update camera basis
	_yaw_rate = lerpf(_yaw_rate, 0.0, clampf(10.0 * delta, 0.0, 1.0))
	var target_bank := _yaw_rate * 0.55 if not _ground_mode else 0.0
	_bank_roll = lerpf(_bank_roll, target_bank, clampf(12.0 * delta, 0.0, 1.0))
	if not xr_active and _desktop_cam:
		_desktop_cam.rotation_order = EULER_ORDER_YXZ
		_desktop_cam.rotation = Vector3(look_pitch, look_yaw, _bank_roll)

	# Joystick yaw turn + vertical (SuperSonic-style, VR sticks).
	var yaw := _yaw_axis()
	if absf(yaw) > 0.15:
		var turn := -yaw * turn_rate * delta
		if xr_active:
			_xr_origin.rotate_y(turn)
		else:
			look_yaw = wrapf(look_yaw + turn, -PI, PI)
			if _desktop_cam:
				_desktop_cam.rotation = Vector3(look_pitch, look_yaw, _bank_roll)

	var vert := _vertical_axis()
	if absf(vert) > 0.15:
		apply_central_force(Vector3.UP * vertical_accel * mass * vert)

	_handle_gear_clicks()

	# SuperSonic drag: velocity *= (1 - 2*dt). Exponential, rate velocity_damp/s.
	# Gives the halo-to-hover feel; without it you coast indefinitely.
	linear_velocity *= clampf(1.0 - velocity_damp * delta, 0.0, 1.0)

	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.limit_length(max_speed)

	if stabilize_upright:
		if lock_rotation:
			angular_velocity = Vector3.ZERO
		else:
			_stabilize(delta)

	# XR: move the tracked rig with the body, position only (never rotation).
	if xr_active and _xr_origin:
		_xr_origin.global_position = global_position


func _desktop_flight_move(boost: float, delta: float = 0.016) -> void:
	## Oracle Orb 3D flight: W/S fly along full 3D camera vector (dive/climb/turn
	## in any direction), A/D strafe, Space/C ascend/descend, and steering the
	## mouse smoothly redirects existing velocity along the new look direction!
	if _desktop_cam == null:
		return
	var forward := -_desktop_cam.global_transform.basis.z.normalized()
	var right := _desktop_cam.global_transform.basis.x.normalized()
	var move_dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		move_dir += forward
	if Input.is_physical_key_pressed(KEY_S):
		move_dir -= forward
	if Input.is_physical_key_pressed(KEY_D):
		move_dir += right
	if Input.is_physical_key_pressed(KEY_A):
		move_dir -= right
	if Input.is_physical_key_pressed(KEY_SPACE):
		move_dir += Vector3.UP
	if Input.is_physical_key_pressed(KEY_C) or Input.is_physical_key_pressed(KEY_CTRL):
		move_dir -= Vector3.UP
	if move_dir.length_squared() > 0.001:
		var wish := move_dir.normalized()
		var accel := thrust_accel * float(gear) * throttle_scale * boost * 0.75
		apply_central_force(wish * accel * mass)
		# Velocity vectoring: smoothly steer current momentum into the new 3D aim direction
		var speed := linear_velocity.length()
		if speed > 0.5:
			linear_velocity = linear_velocity.lerp(wish * speed, clampf(8.0 * delta, 0.0, 1.0))


func _ground_physics(delta: float) -> void:
	# Ground mode owns grab/throw + bow. No thrusters, no gear, no flight drag.
	_left_grabber.hand = _active_left()
	_right_grabber.hand = _active_right()

	# Locomotion: walk via stick, turn via stick, jump via button.
	_move_walk(delta)
	_turn_walk(delta)
	_handle_jump()

	# Grab/throw: grip to hold, release to throw.
	_handle_grab(_left_grabber, _grip_left())
	_handle_grab(_right_grabber, _grip_right())

	# Bow draw + fire.
	_handle_bow()

	# A grounded body must settle; keep it upright and damp spin lightly.
	if stabilize_upright:
		if lock_rotation:
			angular_velocity = Vector3.ZERO
		else:
			_stabilize(delta)
	if not xr_active and _desktop_cam:
		_desktop_cam.rotation_order = EULER_ORDER_YXZ
		_desktop_cam.rotation = Vector3(look_pitch, look_yaw, 0.0)

	if xr_active and _xr_origin:
		_xr_origin.global_position = global_position


func _move_walk(_delta: float) -> void:
	var stick := _move_axis()
	if stick.length() < 0.15:
		return
	var cam_basis := global_transform.basis
	if xr_active and _xr_origin:
		cam_basis = _xr_origin.global_transform.basis
	elif _desktop_cam:
		cam_basis = _desktop_cam.global_transform.basis
	var flat_fwd := Vector3(-cam_basis.z.x, 0.0, -cam_basis.z.z).normalized()
	var flat_right := Vector3(cam_basis.x.x, 0.0, cam_basis.x.z).normalized()
	var dir := (flat_right * stick.x - flat_fwd * stick.y).normalized()
	# Replace horizontal velocity while preserving gravity-driven vertical.
	linear_velocity = Vector3(dir.x * walk_speed, linear_velocity.y, dir.z * walk_speed)


func _turn_walk(_delta: float) -> void:
	var yaw := _yaw_axis()
	if absf(yaw) <= 0.15:
		return
	# Ground turning is frame-rate independent but applied as a direct yaw.
	var turn := -yaw * turn_rate * get_physics_process_delta_time()
	if xr_active:
		_xr_origin.rotate_y(turn)
	else:
		look_yaw = wrapf(look_yaw + turn, -PI, PI)
		if _desktop_cam:
			_desktop_cam.rotation_order = EULER_ORDER_YXZ
			_desktop_cam.rotation = Vector3(look_pitch, look_yaw, 0.0)


func _move_axis() -> Vector2:
	if xr_active and _xr_left:
		return _xr_left.get_vector2("primary")
	if DisplayServer.get_name() == "headless":
		return Vector2.ZERO
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		v.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		v.x += 1.0
	return v


func _handle_jump() -> void:
	var down := _jump_pressed()
	var edge := down and not _jump_was
	_jump_was = down
	if edge and _is_grounded():
		linear_velocity.y = jump_impulse


func _jump_pressed() -> bool:
	if xr_active:
		return _xr_left != null and _xr_left.is_button_pressed("ax_button")
	if DisplayServer.get_name() == "headless":
		return false
	return Input.is_physical_key_pressed(KEY_SPACE)


func _is_grounded() -> bool:
	# Ray down a short distance from the capsule bottom.
	var from := global_position + Vector3(0, 0.1, 0)
	var to := from + Vector3.DOWN * 0.9
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = [get_rid()]
	return not space.intersect_ray(q).is_empty()


func _handle_grab(grabber: Grabber3D, wanted: float) -> void:
	if wanted > 0.2 and not grabber.has_body():
		grabber.grab_nearest(wanted)
	elif wanted > 0.2 and grabber.has_body():
		grabber.grip_pressure = wanted
	elif wanted <= 0.2 and grabber.has_body():
		grabber.release()


func _grip_left() -> float:
	if xr_active and _xr_left:
		return _xr_axis(_xr_left, "grip")
	if DisplayServer.get_name() == "headless":
		return 0.0
	if Input.is_physical_key_pressed(KEY_B) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return 0.25
	return 1.0 if (Input.is_physical_key_pressed(KEY_G) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) else 0.0


func _grip_right() -> float:
	if xr_active and _xr_right:
		return _xr_axis(_xr_right, "grip")
	if DisplayServer.get_name() == "headless":
		return 0.0
	if Input.is_physical_key_pressed(KEY_B) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return 0.25
	return 1.0 if (Input.is_physical_key_pressed(KEY_G) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) else 0.0


func _handle_bow() -> void:
	# If a hand holds a bow, that hand's trigger pull scales draw; releasing the
	# trigger past the halfway point (a quick pull-then-release) fires the arrow.
	var bow := _held_bow()
	if bow == null:
		return
	var draw_hand: Node3D = null
	if _left_grabber.held == bow:
		draw_hand = _active_left()
	elif _right_grabber.held == bow:
		draw_hand = _active_right()
	if draw_hand == null:
		return
	var trig := _trigger_of(draw_hand)
	bow.set_draw(trig * bow.max_draw)
	if trig < 0.5 and _bow_was_drawn >= 0.5:
		bow.fire()
	_bow_was_drawn = trig


var _bow_was_drawn := 0.0


func _held_bow() -> BowProp:
	if _left_grabber.held is BowProp:
		return _left_grabber.held
	if _right_grabber.held is BowProp:
		return _right_grabber.held
	return null


func _trigger_of(hand: Node3D) -> float:
	if hand == _xr_left:
		return _xr_axis(_xr_left, "trigger")
	if hand == _xr_right:
		return _xr_axis(_xr_right, "trigger")
	return 0.0


func _fire_hand(hand: Node3D, amount: float) -> void:
	if hand == null:
		return
	var dir := -hand.global_transform.basis.z.normalized()
	apply_thruster(dir, amount, hand.global_position)


func apply_thruster(world_dir: Vector3, amount: float, at_world: Vector3 = Vector3.ZERO) -> void:
	# SuperSonic accel = baseSpeed(15) * gear * 2.0 * boost, integrated over dt.
	# As Jolt force: F = m * a. One hand only = torque + turn; both = go.
	var dir := world_dir.normalized()
	var accel := thrust_accel * float(gear) * throttle_scale * amount
	var force := dir * accel * mass
	if apply_at_hands and at_world != Vector3.ZERO:
		apply_force(force, at_world - global_position)
	else:
		apply_central_force(force)


func _stabilize(_delta: float) -> void:
	# PD controller to upright: torque = I * (-kp*angle - kd*angvel).
	# Pure proportional (old code) is an UNDAMPED spring -> oscillates forever
	# after a collision. The -kd*angular_velocity term is velocity feedback that
	# bleeds oscillation off. Critical damping: kd = 2*sqrt(kp). Capsule inertia
	# about its horizontal axis ≈ (1/12)m(3r^2 + h^2) ≈ 0.23m.
	var up := global_transform.basis.y
	var angle := up.cross(Vector3.UP)              # axis * sin(tilt), ~0 upright
	var inertia := mass * 0.23                        # capsule, horizontal axis
	var kp := stabilize_strength                      # 1/s^2
	var kd := 2.0 * sqrt(stabilize_strength)          # 1/s, critical damping
	var torque := (-angle * kp - angular_velocity * kd) * inertia
	apply_torque(torque)


func left_trigger() -> float:
	if xr_active and _xr_left:
		return _xr_axis(_xr_left, "trigger")
	if DisplayServer.get_name() == "headless":
		return 0.0
	return 1.0 if Input.is_physical_key_pressed(KEY_Q) else 0.0


func right_trigger() -> float:
	if xr_active and _xr_right:
		return _xr_axis(_xr_right, "trigger")
	if DisplayServer.get_name() == "headless":
		return 0.0
	return 1.0 if Input.is_physical_key_pressed(KEY_E) else 0.0


func _turbo_held() -> bool:
	if xr_active:
		var g := 0.0
		if _xr_left:
			g = maxf(g, _xr_axis(_xr_left, "grip"))
		if _xr_right:
			g = maxf(g, _xr_axis(_xr_right, "grip"))
		return g > 0.6
	return Input.is_physical_key_pressed(KEY_SHIFT)


func _yaw_axis() -> float:
	# VR sticks steer yaw. SuperSonic uses axes[2] (right stick).
	if xr_active:
		var x := 0.0
		if _xr_right:
			x += _xr_right.get_vector2("primary").x
		if _xr_left:
			x += _xr_left.get_vector2("primary").x
		return clampf(x, -1.0, 1.0)
	return 0.0


func _vertical_axis() -> float:
	# VR Left stick Y = ascend (up) / descend (down).
	if xr_active and _xr_left:
		return _xr_left.get_vector2("primary").y
	return 0.0


func _handle_gear_clicks() -> void:
	# SuperSonic: joystick click = gear shift. Left click down, right click up.
	_gear_cooldown = maxf(0.0, _gear_cooldown - get_physics_process_delta_time())
	if _gear_cooldown > 0.0:
		return
	var left_down := false
	var right_down := false
	if xr_active:
		left_down = _xr_left and _xr_left.is_button_pressed("primary_click")
		right_down = _xr_right and _xr_right.is_button_pressed("primary_click")
	else:
		left_down = Input.is_physical_key_pressed(KEY_BRACKETLEFT)
		right_down = Input.is_physical_key_pressed(KEY_BRACKETRIGHT)
	var left_edge := left_down and not _left_click_was
	var right_edge := right_down and not _right_click_was
	_left_click_was = left_down
	_right_click_was = right_down
	if left_edge:
		gear = maxi(1, gear - 1)
		_gear_cooldown = 0.25
		print("gear=", gear)
	if right_edge:
		gear = mini(max_gear, gear + 1)
		_gear_cooldown = 0.25
		print("gear=", gear)


func _xr_axis(ctrl: XRController3D, action: String) -> float:
	if ctrl == null:
		return 0.0
	var v := ctrl.get_float(action)
	if v <= 0.0 and ctrl.is_button_pressed(action + "_click"):
		return 1.0
	return clampf(v, 0.0, 1.0)


func _active_left() -> Node3D:
	if xr_active and _xr_left:
		return _xr_left
	return _left


func _active_right() -> Node3D:
	if xr_active and _xr_right:
		return _xr_right
	return _right


func reset_pose() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = spawn_xform
	look_yaw = spawn_xform.basis.get_euler().y
	look_pitch = 0.0


func _handle_meta_keys(_delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if Input.is_physical_key_pressed(KEY_R):
		reset_pose()
	if Input.is_physical_key_pressed(KEY_F) and _edge("f"):
		stabilize_upright = not stabilize_upright
		print("stabilize_upright=", stabilize_upright)
	# Mode toggle: desktop only (T). In XR the toggle lives in the wrist hub,
	# because OpenXR's menu_button is reserved for the SteamVR system menu and
	# never reaches the app. (See MASTER_PLAN Phase 5.)
	var toggle_pressed := false
	if not xr_active:
		toggle_pressed = Input.is_physical_key_pressed(KEY_T)
	var edge := toggle_pressed and not _mode_edge_was
	_mode_edge_was = toggle_pressed
	if edge:
		set_ground_mode(not _ground_mode)


func set_ground_mode(on: bool) -> void:
	if _ground_mode == on:
		return
	_ground_mode = on
	gravity_scale = 1.0 if on else 0.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	# Release any held props when switching modes so nothing stays frozen.
	if _left_grabber:
		_left_grabber.release()
	if _right_grabber:
		_right_grabber.release()
	mode_changed.emit("ground" if on else "flight")
	print("Oracle mode: ground" if on else "Oracle mode: flight")


func is_ground_mode() -> bool:
	return _ground_mode


var _edges: Dictionary = {}

func _edge(name: String) -> bool:
	# one-shot per physics tick group — caller already gated on pressed
	if _edges.get(name, false):
		return false
	_edges[name] = true
	# clear next frame
	get_tree().create_timer(0.25).timeout.connect(func(): _edges[name] = false)
	return true
