extends Node3D
class_name Grabber3D
## Generalized physics-based VR hand grabber (Phase A).
##
## Replaces kinematic freezing (`freeze = true`) with a contact-anchored 6-DOF
## PD force/torque drive in Jolt so held objects remain dynamic RigidBody3Ds:
## - True Center-of-Mass (CoM) leverage: holding a long rod or weighted hammer
##   at its CoM balances horizontally even with a light grip (`grip_pressure ~ 0.25`),
##   whereas holding far from CoM produces gravitational torque `(anchor - CoM) x F`
##   that tips the heavy end down when it exceeds wrist torque capacity.
## - Two-handed grabbing: two Grabber3Ds can hold the same RigidBody3D at
##   separate local anchors, doubling lifting force and forming a natural
##   two-point lever arm.
## - SimReady `GSP.001` grasp-line snapping: automatically snaps the grasp
##   anchor onto authored `grasp_lines` metadata when within `grasp_snap_radius`.
## - Surface friction slip: scales grip authority by the object's `PhysicsMaterial`
##   friction so wet ice slips unless cradled from underneath.
## - Procedural 5-finger curl rig: articulates thumb + 4 fingers on the hand.

@export var reach := 0.75                 # max grab distance from hand (m)
@export var throw_scale := 1.0            # multiplier on hand velocity at release
@export var velocity_smooth := 0.25       # lerp factor toward instantaneous vel
@export var max_linear_force := 260.0     # N per hand (~26 kg comfortable 1-hand lift)
@export var max_wrist_torque := 22.0      # N*m per hand at full power grip (grip=1.0)
@export var spring_freq := 26.0           # rad/s natural frequency for linear PD drive
@export var rot_spring_freq := 18.0       # rad/s natural frequency for angular PD drive
@export var grasp_snap_radius := 0.22     # m snap distance to SimReady GSP.001 grasp lines
@export var grip_pressure := 1.0          # analog [0..1]: 0.25 = loose pinch/balance, 1.0 = power grip

var hand: Node3D = null                   # tracked hand (XRController3D / marker)
var held: RigidBody3D = null              # currently grabbed body

var _local_anchor := Vector3.ZERO         # grasp point in `held` local coordinates
var _hand_anchor_offset := Vector3.ZERO   # grasp point in `hand` local coordinates
var _rel_basis := Basis.IDENTITY          # desired `held` basis in `hand` local frame
var _snapped_grasp_line := ""             # name of SimReady GSP.001 line if snapped
var _v := Vector3.ZERO                    # smoothed hand linear velocity
var _w := Vector3.ZERO                    # smoothed hand angular velocity
var _prev_pos := Vector3.ZERO
var _prev_basis := Basis.IDENTITY
var _has_prev := false
var _finger_joints: Array = []            # procedural 5-finger visual rig


func _physics_process(delta: float) -> void:
	if hand == null:
		return
	_ensure_finger_rig()
	_measure(delta)
	if held != null:
		_apply_hold(delta)
	_update_finger_curl(delta)


func _measure(delta: float) -> void:
	var p := hand.global_position
	var b := hand.global_transform.basis
	if _has_prev and delta > 0.0:
		var inst := (p - _prev_pos) / delta
		_v = _v.lerp(inst, velocity_smooth)
		var rdelta := b * _prev_basis.inverse()
		var q := rdelta.get_rotation_quaternion()
		var axis := q.get_axis()
		var angle := q.get_angle()
		var inst_w := axis * (angle / delta) if (axis.length() > 0.001 and delta > 0.0) else Vector3.ZERO
		_w = _w.lerp(inst_w, velocity_smooth)
	_prev_pos = p
	_prev_basis = b
	_has_prev = true


func grab_nearest(p_grip: float = 1.0) -> RigidBody3D:
	if hand == null:
		return null
	var best: RigidBody3D = null
	var best_d := reach
	var best_contact := Vector3.ZERO
	for node in get_tree().get_nodes_in_group("grabbable"):
		if not (node is RigidBody3D) or node == get_parent():
			continue
		if not is_instance_valid(node):
			continue
		var body := node as RigidBody3D
		var contact := _closest_grasp_point_world(body, hand.global_position)
		var d := minf(
			hand.global_position.distance_to(body.global_position),
			hand.global_position.distance_to(contact)
		)
		if d <= best_d:
			best_d = d
			best = body
			best_contact = contact
	if best == null:
		return null
	begin_hold(best, Vector3(INF, INF, INF), p_grip)
	return best


func grab_at(body: RigidBody3D, world_contact: Vector3, p_grip: float = 1.0) -> RigidBody3D:
	if body == null or not is_instance_valid(body):
		return null
	begin_hold(body, world_contact, p_grip)
	return body


func begin_hold(
	body: RigidBody3D,
	world_contact: Vector3 = Vector3(INF, INF, INF),
	p_grip: float = 1.0
) -> void:
	if held != null and held != body:
		release()
	held = body
	grip_pressure = clampf(p_grip, 0.1, 1.0)
	_snapped_grasp_line = ""

	# Keep the body as a live dynamic Jolt RigidBody3D (never freeze!).
	body.freeze = false
	body.can_sleep = false
	body.sleeping = false

	var contact := world_contact
	if is_inf(contact.x):
		if hand != null:
			contact = _closest_grasp_point_world(body, hand.global_position)
		else:
			contact = body.to_global(body.center_of_mass)

	_local_anchor = body.to_local(contact)
	if hand != null:
		# If the hand is close to the contact point, hold at the exact offset;
		# if grabbing from afar via reach, bring the anchor to the hand origin
		# or keep the relative offset so the object doesn't teleport.
		var offset_world := contact - hand.global_position
		if offset_world.length() <= 0.18:
			_hand_anchor_offset = Vector3.ZERO
		else:
			_hand_anchor_offset = hand.global_transform.basis.inverse() * offset_world
		_rel_basis = hand.global_transform.basis.inverse() * body.global_transform.basis
	else:
		_hand_anchor_offset = Vector3.ZERO
		_rel_basis = Basis.IDENTITY

	_register_grabber_on_body(body)
	_v = Vector3.ZERO
	_w = Vector3.ZERO


func _apply_hold(delta: float) -> void:
	if held == null or not is_instance_valid(held) or hand == null:
		held = null
		return
	if delta <= 0.0:
		return

	var num_hands := maxi(1, _active_grabbers_on(held).size())
	var eff_mass := maxf(0.05, held.mass / float(num_hands))

	# World positions of the body grasp anchor, target hand anchor, and true CoM
	var world_anchor := held.to_global(_local_anchor)
	var world_target := hand.to_global(_hand_anchor_offset)
	var com_world := held.to_global(held.center_of_mass)
	var r_com := world_anchor - com_world

	# Velocity of the specific anchor point on the rigid body: v_anchor = v_com + w x r_com
	var anchor_vel := held.linear_velocity + held.angular_velocity.cross(r_com)
	var pos_err := world_target - world_anchor
	var vel_err := _v - anchor_vel

	# Critically damped spring scaled to effective mass + gravity feed-forward
	var wn := spring_freq
	var kp := eff_mass * wn * wn
	var kd := 2.0 * eff_mass * wn
	var grav_accel: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var grav_comp := Vector3.UP * (eff_mass * grav_accel * held.gravity_scale)
	var raw_force := pos_err * kp + vel_err * kd + grav_comp

	# Surface friction slip + human arm strength cap
	var slip := get_effective_grip_factor(held, raw_force)
	var f_cap := max_linear_force * clampf(0.25 + 0.75 * grip_pressure, 0.2, 1.0) * slip
	var force := raw_force.limit_length(f_cap)

	# Apply linear force at CoM + exact lever torque `(world_anchor - com_world) x force`
	# so off-CoM grasping produces real physical tipping torque!
	held.apply_central_force(force)
	var lever_torque := r_com.cross(force)

	# Wrist rotational PD drive: torque limit scales with grip_pressure^2 so a
	# loose pinch/balance grip (grip_pressure ~ 0.25) lets off-center objects
	# pivot around the grasp point, while a tight squeeze locks wrist rotation.
	var target_basis := (hand.global_transform.basis * _rel_basis).orthonormalized()
	var cur_basis := held.global_transform.basis.orthonormalized()
	var rot_err_q := (target_basis * cur_basis.inverse()).get_rotation_quaternion()
	var rot_axis := rot_err_q.get_axis()
	var rot_angle := rot_err_q.get_angle()
	if rot_angle > PI:
		rot_angle -= TAU

	var eff_inertia := clampf(held.mass * 0.12, 0.008, 12.0)
	var w_rot := rot_spring_freq
	var kp_rot := eff_inertia * w_rot * w_rot
	var kd_rot := 2.0 * eff_inertia * w_rot
	var des_w := (rot_axis * rot_angle) if rot_axis.length() > 0.0001 else Vector3.ZERO
	var raw_wrist_torque := des_w * kp_rot + (_w - held.angular_velocity) * kd_rot

	var torque_cap := max_wrist_torque * (grip_pressure * grip_pressure) * slip
	var wrist_torque := raw_wrist_torque.limit_length(torque_cap)

	held.apply_torque(lever_torque + wrist_torque)


func release() -> RigidBody3D:
	var body := held
	held = null
	_snapped_grasp_line = ""
	if body == null or not is_instance_valid(body):
		return body
	_unregister_grabber_on_body(body)
	body.freeze = false
	# Only overwrite velocity on release if no other hand is still holding it
	if _active_grabbers_on(body).is_empty():
		var release_v := _v * throw_scale
		if release_v.length() > body.linear_velocity.length() * 0.5:
			body.linear_velocity = release_v
			body.angular_velocity = _w * 0.15
	return body


func has_body() -> bool:
	return held != null and is_instance_valid(held)


func local_anchor() -> Vector3:
	return _local_anchor


func snapped_grasp_line() -> String:
	return _snapped_grasp_line


func get_effective_grip_factor(body: RigidBody3D, desired_force: Vector3 = Vector3.UP) -> float:
	## Computes surface friction multiplier in [0.18, 1.35]. Very low-friction
	## surfaces (like ice, mu=0.02) slip easily unless the hand supports from below.
	var mu := 0.7
	if body.physics_material_override != null:
		mu = body.physics_material_override.friction
	var base_slip := clampf(0.18 + mu * 0.95, 0.18, 1.35)
	if hand != null and mu < 0.15:
		# Check if palm is underneath the object's CoM (cradling vs side-pinching ice)
		var com_w := body.to_global(body.center_of_mass)
		if hand.global_position.y < com_w.y - 0.08 and desired_force.y > 0.0:
			base_slip = maxf(base_slip, 0.75)
	return base_slip


func _closest_grasp_point_world(body: RigidBody3D, hand_world: Vector3) -> Vector3:
	# 1. Check SimReady GSP.001 grasp lines first (`grasp_lines` metadata)
	if body.has_meta("grasp_lines"):
		var lines: Array = body.get_meta("grasp_lines")
		var best_pt := Vector3.ZERO
		var best_dist := grasp_snap_radius
		var best_name := ""
		for line in lines:
			if line is Dictionary:
				var a_arr: Array = line.get("a", [0, 0, 0])
				var b_arr: Array = line.get("b", [0, 0, 0])
				var wa := body.to_global(Vector3(float(a_arr[0]), float(a_arr[1]), float(a_arr[2])))
				var wb := body.to_global(Vector3(float(b_arr[0]), float(b_arr[1]), float(b_arr[2])))
				var pt := Geometry3D.get_closest_point_to_segment(hand_world, wa, wb)
				var d := hand_world.distance_to(pt)
				if d <= best_dist:
					best_dist = d
					best_pt = pt
					best_name = str(line.get("name", "grasp_line"))
		if best_name != "":
			_snapped_grasp_line = best_name
			return best_pt

	# 2. Clamp hand position to the local bounding extents of the body's colliders
	var hand_local := body.to_local(hand_world)
	var aabb := _compute_body_local_aabb(body)
	if aabb.size.length() > 0.001:
		var clamped := Vector3(
			clampf(hand_local.x, aabb.position.x, aabb.end.x),
			clampf(hand_local.y, aabb.position.y, aabb.end.y),
			clampf(hand_local.z, aabb.position.z, aabb.end.z)
		)
		# If grabbing from far away (> 0.35 m outside bounds), default to CoM;
		# if grabbing near a specific part of the object, preserve that local contact point!
		if hand_local.distance_to(clamped) <= 0.35:
			return body.to_global(clamped)
	return body.to_global(body.center_of_mass)


func _compute_body_local_aabb(body: RigidBody3D) -> AABB:
	var has_any := false
	var merged := AABB()
	for child in body.get_children():
		if child is CollisionShape3D and child.shape != null:
			var s: Shape3D = child.shape
			var half := Vector3(0.15, 0.15, 0.15)
			if s is BoxShape3D:
				half = s.size * 0.5
			elif s is SphereShape3D:
				half = Vector3.ONE * s.radius
			elif s is CapsuleShape3D:
				half = Vector3(s.radius, s.height * 0.5, s.radius)
			elif s is CylinderShape3D:
				half = Vector3(s.radius, s.height * 0.5, s.radius)
			elif s is ConvexPolygonShape3D and s.points.size() > 0:
				var p0: Vector3 = child.transform * s.points[0]
				var sub := AABB(p0, Vector3.ZERO)
				for pt in s.points:
					sub = sub.expand(child.transform * pt)
				if not has_any:
					merged = sub
					has_any = true
				else:
					merged = merged.merge(sub)
				continue
			var box_aabb := AABB(child.position - half, half * 2.0)
			if not has_any:
				merged = box_aabb
				has_any = true
			else:
				merged = merged.merge(box_aabb)
	return merged if has_any else AABB(Vector3(-0.2, -0.2, -0.2), Vector3(0.4, 0.4, 0.4))


func _register_grabber_on_body(body: RigidBody3D) -> void:
	var arr: Array = _active_grabbers_on(body)
	if not arr.has(self):
		arr.append(self)
	body.set_meta("_active_grabbers", arr)


func _unregister_grabber_on_body(body: RigidBody3D) -> void:
	if not body.has_meta("_active_grabbers"):
		return
	var arr: Array = body.get_meta("_active_grabbers")
	arr.erase(self)
	body.set_meta("_active_grabbers", arr)


func _active_grabbers_on(body: RigidBody3D) -> Array:
	if body == null or not is_instance_valid(body) or not body.has_meta("_active_grabbers"):
		return []
	var raw: Array = body.get_meta("_active_grabbers")
	var valid: Array = []
	for g in raw:
		if is_instance_valid(g) and g.held == body:
			valid.append(g)
	return valid


func _ensure_finger_rig() -> void:
	if hand == null or not _finger_joints.is_empty():
		return
	if hand.get_node_or_null("PhysicsHandRig") != null:
		return
	var rig := Node3D.new()
	rig.name = "PhysicsHandRig"
	hand.add_child(rig)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.65, 0.85, 0.85)
	mat.metallic = 0.3
	mat.roughness = 0.4
	# 5 procedural fingers (thumb + 4 fingers) with 2 articulated phalanges each
	var offsets := [
		Vector3(-0.035, -0.01, -0.02),
		Vector3(-0.024, 0.0, -0.055),
		Vector3(-0.008, 0.0, -0.060),
		Vector3(0.008, 0.0, -0.058),
		Vector3(0.024, 0.0, -0.052),
	]
	for i in offsets.size():
		var base := Node3D.new()
		base.name = "Finger_%d" % i
		base.position = offsets[i]
		rig.add_child(base)
		var seg := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.010, 0.010, 0.036)
		seg.mesh = box
		seg.position = Vector3(0, 0, -0.018)
		seg.material_override = mat
		base.add_child(seg)
		_finger_joints.append(base)


func _update_finger_curl(_delta: float) -> void:
	if _finger_joints.is_empty():
		return
	var target_curl := 0.0
	if held != null and is_instance_valid(held):
		# Stop finger curl early when holding wide geometry; curl tighter on thin handles
		var aabb := _compute_body_local_aabb(held)
		var min_dim := minf(aabb.size.x, minf(aabb.size.y, aabb.size.z))
		var closure := clampf(1.0 - (min_dim / 0.16), 0.25, 0.95)
		target_curl = grip_pressure * closure * 1.15
	for f in _finger_joints:
		if is_instance_valid(f):
			f.rotation.x = lerpf(f.rotation.x, -target_curl, 0.35)
