extends RigidBody3D
class_name BowProp
## A grabbable bow. Draw distance scales arrow launch speed.
## Basic arrow only; piercing/splitting/flaming/explosive are payload params later.

const ArrowScript := preload("res://scripts/arrow.gd")

@export var power := 60.0          # m/s per meter of draw
@export var max_draw := 0.5        # meters
@export var nock_offset := 0.15    # arrow spawn distance in front of grip

var _draw := 0.0                   # 0..max_draw, driven by whichever hand holds it


func _ready() -> void:
	mass = 1.5
	continuous_cd = true
	collision_layer = 4             # props layer (grabbable)
	collision_mask = 5


func set_draw(d: float) -> void:
	_draw = clampf(d, 0.0, max_draw)


func draw_fraction() -> float:
	return _draw / max_draw if max_draw > 0.0 else 0.0


func fire() -> ArrowProp:
	## Creates + launches an arrow along the bow's forward (-Z), speed ~ draw*power.
	var fwd := -global_transform.basis.z.normalized()
	var arrow := ArrowScript.new()
	arrow.position = global_transform.origin + fwd * nock_offset
	arrow.mass = 0.08
	get_parent().add_child(arrow)
	# Arrow's _ready orients it along velocity; here we just set velocity and let
	# the arrow align itself once armed. Add bow's own velocity (walker may be moving).
	var speed := draw_fraction() * power
	arrow.linear_velocity = fwd * speed + linear_velocity
	return arrow