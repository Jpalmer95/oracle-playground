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
@export var apply_at_hands := true
@export var stabilize_upright := true
@export var stabilize_strength := 40.0
@export var look_sensitivity := 0.0025
@export var max_speed := 80.0
@export var max_gear := 5
@export var max_booster_fuel := 100.0
@export var booster_drain := 28.0
@export var booster_recharge := 18.0

var gear := 2
var booster_fuel := 100.0
var xr_active := false
var look_yaw := 0.0
var look_pitch := 0.0
var spawn_xform := Transform3D.IDENTITY

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
	angular_damp = 0.0
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
		add_child(_desktop_cam)

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
	if _desktop_cam:
		_desktop_cam.current = false
	if _body_mesh:
		_body_mesh.visible = false
	mode_changed.emit("openxr")
	print("Oracle mode: openxr")


func _set_desktop_mode() -> void:
	xr_active = false
	if _desktop_cam:
		_desktop_cam.current = true
	if not DisplayServer.get_name() == "headless":
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
	if event is InputEventMouseMotion and _mouse_captured:
		look_yaw -= event.relative.x * look_sensitivity
		look_pitch = clampf(look_pitch - event.relative.y * look_sensitivity, -1.2, 1.2)
		_desktop_cam.rotation = Vector3(look_pitch, 0, 0)
		rotation = Vector3(0, look_yaw, 0)
		angular_velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	_handle_meta_keys()
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

	# SuperSonic drag: velocity *= (1 - 2*dt). Exponential, rate velocity_damp/s.
	# Gives the halo-to-hover feel; without it you coast indefinitely.
	linear_velocity *= clampf(1.0 - velocity_damp * delta, 0.0, 1.0)

	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.limit_length(max_speed)

	if stabilize_upright:
		_stabilize(delta)

	# XR: move the tracked rig with the body, position only (never rotation).
	if xr_active and _xr_origin:
		_xr_origin.global_position = global_position


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
	var up := global_transform.basis.y
	var correction := up.cross(Vector3.UP)
	apply_torque(correction * stabilize_strength * mass)


func left_trigger() -> float:
	if xr_active and _xr_left:
		return _xr_axis(_xr_left, "trigger")
	if DisplayServer.get_name() == "headless":
		return 0.0
	var key := Input.is_physical_key_pressed(KEY_Q)
	var mouse := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	return 1.0 if (key or mouse) else 0.0


func right_trigger() -> float:
	if xr_active and _xr_right:
		return _xr_axis(_xr_right, "trigger")
	if DisplayServer.get_name() == "headless":
		return 0.0
	var key := Input.is_physical_key_pressed(KEY_E)
	var mouse := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	return 1.0 if (key or mouse) else 0.0


func _turbo_held() -> bool:
	if xr_active:
		var g := 0.0
		if _xr_left:
			g = maxf(g, _xr_axis(_xr_left, "grip"))
		if _xr_right:
			g = maxf(g, _xr_axis(_xr_right, "grip"))
		return g > 0.6
	return Input.is_physical_key_pressed(KEY_SHIFT)


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


func _handle_meta_keys() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if Input.is_physical_key_pressed(KEY_R):
		reset_pose()
	if Input.is_physical_key_pressed(KEY_F) and _edge("f"):
		stabilize_upright = not stabilize_upright
		print("stabilize_upright=", stabilize_upright)
	if Input.is_physical_key_pressed(KEY_BRACKETLEFT) and _edge("gdown"):
		gear = maxi(1, gear - 1)
	if Input.is_physical_key_pressed(KEY_BRACKETRIGHT) and _edge("gup"):
		gear = mini(max_gear, gear + 1)


var _edges: Dictionary = {}

func _edge(name: String) -> bool:
	# one-shot per physics tick group — caller already gated on pressed
	if _edges.get(name, false):
		return false
	_edges[name] = true
	# clear next frame
	get_tree().create_timer(0.25).timeout.connect(func(): _edges[name] = false)
	return true
