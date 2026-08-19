extends Node3D
class_name HermesWaterBody
## Copied from HermesForge — keep wave math in lockstep with water_surface.gdshader.

signal body_entered_water(body)

@export var wave_height := 0.25
@export var wave_scale := 0.6
@export var wave_speed := 1.0
@export var buoyancy := 9.8
@export var water_drag := 0.6
@export var float_offset := 0.5
@export var radius := 10.0

var _floaters: Array = []
var _time := 0.0


func _physics_process(delta: float) -> void:
	_time += delta
	_auto_register()
	for body in _floaters.duplicate():
		if not is_instance_valid(body):
			_floaters.erase(body)
			continue
		_apply_buoyancy(body, delta)


func register_floater(body: RigidBody3D) -> void:
	if body and not _floaters.has(body):
		_floaters.append(body)
		body_entered_water.emit(body)


func unregister_floater(body: RigidBody3D) -> void:
	_floaters.erase(body)


func get_wave_height_at(world_pos: Vector3) -> float:
	var p := Vector2(world_pos.x, world_pos.z) * wave_scale
	var t := _time * wave_speed
	var h := 0.0
	h += sin(p.dot(Vector2(1.0, 0.3).normalized()) * 1.0 + t) * 0.5
	h += sin(p.dot(Vector2(-0.7, 1.0).normalized()) * 1.7 + t * 1.3) * 0.3
	h += sin(p.dot(Vector2(0.4, -1.0).normalized()) * 2.6 + t * 1.7) * 0.2
	return global_position.y + h * wave_height


func _apply_buoyancy(body: RigidBody3D, delta: float) -> void:
	var xz := Vector2(body.global_position.x - global_position.x, body.global_position.z - global_position.z)
	if xz.length() > radius:
		return
	var surface_y: float = get_wave_height_at(body.global_position)
	var depth: float = surface_y - body.global_position.y + float_offset
	if depth > 0.0:
		var force: Vector3 = Vector3.UP * buoyancy * clampf(depth, 0.0, 2.0) * body.mass
		body.apply_central_force(force)
		body.linear_velocity = body.linear_velocity.lerp(
			body.linear_velocity * (1.0 - water_drag), delta * 8.0)


func _auto_register() -> void:
	var space := get_tree().current_scene
	if space == null:
		space = get_parent()
	if space == null:
		return
	for node in space.get_children():
		if node is RigidBody3D and not _floaters.has(node):
			var xz := Vector2(node.global_position.x - global_position.x, node.global_position.z - global_position.z)
			if xz.length() <= radius and node.global_position.y < global_position.y + 2.0:
				register_floater(node)
