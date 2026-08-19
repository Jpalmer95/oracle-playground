extends RigidBody3D
class_name ArrowProp
## A physics arrow: slim shaft + tip, sticks where it lands.
## Launched by BowProp.fire(); speed = draw distance * bow power.

@export var stick_threshold := 3.0    # m/s; below this on impact, embed
@export var lifetime := 12.0          # seconds before despawn if unrecovered

var _armed := false                   # ignores self/spawn collisions until armed
var _age := 0.0


func _ready() -> void:
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	collision_layer = 8                # arrows: own layer so they hit props/world
	collision_mask = 1 | 4             # world + props (not the player layer 2)
	body_entered.connect(_on_impact)
	# Arm after one frame so spawning inside the bow doesn't self-collide.
	await get_tree().physics_frame
	_armed = true


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > lifetime:
		queue_free()
		return
	if not _armed:
		return
	# Always point the arrow along its velocity so flight looks right.
	if linear_velocity.length() > 2.0:
		var dir := linear_velocity.normalized()
		var up := dir.cross(Vector3.RIGHT).normalized()
		if up.length() < 0.1:
			up = Vector3.UP
		var x := up.cross(dir).normalized()
		global_transform.basis = Basis(x, up, dir)


func _on_impact(other: Node) -> void:
	if not _armed or _age > lifetime:
		return
	if other is ArrowProp:
		return
	# Sticks into whatever it hit: kill sleep + heavily damp.
	if linear_velocity.length() < stick_threshold * 2.0:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		continuous_cd = false
		can_sleep = true
		# clip lifetime shorter once embedded so arrows don't pile up
		_age = lifetime - 4.0