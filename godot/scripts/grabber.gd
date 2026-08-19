extends Node3D
class_name Grabber3D
## Per-hand grab/throw component. Pure physics — the player reads input and
## calls grab_nearest()/release(); this node measures hand velocity and holds
## the grabbed body at a fixed hand-local offset (kinematic-style via freeze
## + per-frame transform) so throwing inherits controller motion.

@export var reach := 0.75                 # max grab distance from hand
@export var throw_scale := 1.0            # multiplier on hand velocity at release
@export var velocity_smooth := 0.25       # lerp factor toward instantaneous vel

var hand: Node3D = null                   # tracked hand (XRController3D / marker)
var held: RigidBody3D = null              # currently grabbed body

var _offset := Transform3D.IDENTITY       # hand-local transform of held body
var _v := Vector3.ZERO                    # smoothed hand linear velocity
var _w := Vector3.ZERO                    # smoothed hand angular velocity
var _prev_pos := Vector3.ZERO
var _prev_basis := Basis.IDENTITY
var _has_prev := false


func _physics_process(delta: float) -> void:
	if hand == null:
		return
	_measure(delta)
	if held != null:
		_apply_hold()


func _measure(delta: float) -> void:
	var p := hand.global_position
	var b := hand.global_transform.basis
	if _has_prev and delta > 0.0:
		var inst := (p - _prev_pos) / delta
		_v = _v.lerp(inst, velocity_smooth)
		# Angular velocity from rotation delta (small-angle axis).
		var rdelta := b * _prev_basis.inverse()
		var axis := rdelta.get_rotation_quaternion().get_axis()
		var angle := rdelta.get_rotation_quaternion().get_angle()
		var inst_w := axis * (angle / delta) if (axis.length() > 0.001 and delta > 0.0) else Vector3.ZERO
		_w = _w.lerp(inst_w, velocity_smooth)
	_prev_pos = p
	_prev_basis = b
	_has_prev = true


func grab_nearest() -> RigidBody3D:
	if hand == null:
		return null
	var best: RigidBody3D = null
	var best_d := reach
	for node in get_tree().get_nodes_in_group("grabbable"):
		if not (node is RigidBody3D) or node == get_parent():
			continue
		if not is_instance_valid(node):
			continue
		var d := hand.global_position.distance_to(node.global_position)
		if d <= best_d:
			best_d = d
			best = node
	if best == null:
		return null
	begin_hold(best)
	return best


func begin_hold(body: RigidBody3D) -> void:
	held = body
	# Store hand-local offset so the body keeps its exact grasp pose.
	var hi := hand.global_transform.affine_inverse()
	_offset = hi * body.global_transform
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	# Vanish hand velocity so the first frame of hold doesn't snap.
	_v = Vector3.ZERO
	_w = Vector3.ZERO


func _apply_hold() -> void:
	if held == null or not is_instance_valid(held):
		held = null
		return
	var target := hand.global_transform * _offset
	held.global_position = target.origin
	held.global_transform.basis = target.basis


func release() -> RigidBody3D:
	var body := held
	held = null
	if body == null or not is_instance_valid(body):
		return body
	body.freeze = false
	body.linear_velocity = _v * throw_scale
	body.angular_velocity = _w * 0.15
	return body


func has_body() -> bool:
	return held != null and is_instance_valid(held)