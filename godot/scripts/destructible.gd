extends RigidBody3D
class_name DestructibleProp
## Shatter into smaller Jolt cubes when impact impulse exceeds threshold.

@export var kind := "wood"
@export var shatter_impulse := 18.0
@export var shard_count := 6
@export var shard_size := 0.22

var _shattered := false


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 12
	body_entered.connect(_on_body_entered)
	if not has_meta("destructible"):
		set_meta("destructible", true)


func _on_body_entered(other: Node) -> void:
	if _shattered:
		return
	var speed := linear_velocity.length()
	if other is RigidBody3D:
		speed = maxf(speed, (other as RigidBody3D).linear_velocity.length())
	if speed * mass * 0.05 >= shatter_impulse or speed >= 12.0:
		shatter()


func shatter() -> Array:
	if _shattered:
		return []
	_shattered = true
	var shards: Array = []
	var parent := get_parent()
	var origin := global_position
	for i in shard_count:
		var piece: RigidBody3D = MaterialLab.spawn_cube(kind, origin, shard_size, parent)
		var dir := Vector3(randf() - 0.5, randf() * 0.8, randf() - 0.5).normalized()
		piece.linear_velocity = linear_velocity * 0.4 + dir * 4.0
		piece.angular_velocity = Vector3(randf(), randf(), randf()) * 8.0
		shards.append(piece)
	queue_free()
	return shards
