extends Node3D
## WristPalette — the in-VR tool menu. Renders a panel of buttons on the left
## wrist, one per tool in the active palette (read from ToolRegistry at build
## time, so a tools.json edit shows up on next boot). Point the right-hand
## beam at a button and pull trigger to spawn/execute that tool in the world.
##
## Scalability contract (matches ToolRegistry): this node knows nothing about
## what a tool *does*. It just (1) reads tool id+name+palette from the
## registry, (2) renders buttons, (3) calls OracleBuilder.spawn_tool(id, at).
## Adding a tool or a palette is a JSON edit — no palette code changes.

const BUTTON_LAYER := 8
const RAY_MASK := 8
const BEAM_LENGTH := 10.0
const SPACING := 0.045
const BUTTON_SIZE := Vector2(0.09, 0.032)

@export var palette_id := "build"

var _xr_origin: XROrigin3D
var _left: XRController3D
var _right: XRController3D
var _beam: MeshInstance3D
var _buttons: Array = []          # {area: Area3D, id: String}
var _hover: Area3D = null
var _hover_mat: StandardMaterial3D
var _base_mat: StandardMaterial3D
var _trigger_was := false


func setup(p_origin: XROrigin3D, p_left: XRController3D, p_right: XRController3D) -> void:
	_xr_origin = p_origin
	_left = p_left
	_right = p_right
	_build_panel()
	_build_beam()


func _build_panel() -> void:
	# Attach to the left wrist: reparent under the left controller and offset it
	# so the panel floats just above/inside the wrist.
	var holder := Node3D.new()
	holder.name = "PaletteHolder"
	_left.add_child(holder)
	holder.position = Vector3(0.0, -0.06, 0.09)
	# Rotate so the panel faces the user (controller aim -Z points forward);
	# we want the buttons readable: flat panel roughly facing inward.
	var panel := Node3D.new()
	panel.name = "PalettePanel"
	holder.add_child(panel)

	_hover_mat = StandardMaterial3D.new()
	_hover_mat.albedo_color = Color(0.30, 0.75, 0.95)
	_hover_mat.emission_enabled = true
	_hover_mat.emission = Color(0.10, 0.30, 0.45)
	_base_mat = StandardMaterial3D.new()
	_base_mat.albedo_color = Color(0.13, 0.14, 0.16)
	_base_mat.metallic = 0.2
	_base_mat.roughness = 0.6

	var ids: Array = ToolRegistry.palette_tool_ids(palette_id)
	var y := 0.0
	for id in ids:
		var name: String = ToolRegistry.tool_name(id)
		var button := _make_button(id, name, Vector3(0.0, -y, 0.0))
		panel.add_child(button)
		_buttons.append({"area": button, "id": id})
		y += SPACING


func _make_button(id: String, label_text: String, at: Vector3) -> Area3D:
	var area := Area3D.new()
	area.name = "Btn_%s" % id
	area.collision_layer = BUTTON_LAYER
	area.collision_mask = 0
	area.position = at
	area.set_meta("tool_id", id)

	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(BUTTON_SIZE.x, BUTTON_SIZE.y, 0.01)
	cs.shape = box
	area.add_child(cs)

	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(BUTTON_SIZE.x, BUTTON_SIZE.y, 0.008)
	mesh.mesh = bm
	mesh.material_override = _base_mat
	mesh.name = "Visual"
	area.add_child(mesh)

	var lbl := Label3D.new()
	lbl.name = "Label"
	lbl.text = label_text
	lbl.font_size = 48
	lbl.pixel_size = 0.0006
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color(0.95, 0.95, 0.93)
	lbl.position = Vector3(0.0, 0.0, -0.008)
	lbl.outline_size = 8
	area.add_child(lbl)

	return area


func _build_beam() -> void:
	_beam = MeshInstance3D.new()
	_beam.name = "PaletteBeam"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.004
	cyl.bottom_radius = 0.004
	cyl.height = BEAM_LENGTH
	_beam.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.8, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.5, 0.7)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam.material_override = mat
	_right.add_child(_beam)
	# A cylinder's center is its midpoint; offset so it extends forward from the hand.
	_beam.position = Vector3(0.0, 0.0, -BEAM_LENGTH * 0.5)


func _physics_process(_delta: float) -> void:
	if _right == null:
		return
	var origin := _right.global_position
	var dir := -_right.global_transform.basis.z.normalized()

	# Raycast against palette buttons only.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * BEAM_LENGTH, RAY_MASK)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := space.intersect_ray(q)
	var hovered: Area3D = null
	if not hit.is_empty():
		var c = hit.get("collider")
		if c is Area3D and c.get_meta("tool_id", "") != "":
			hovered = c

	_set_hover(hovered)

	var trigger := _trigger_value()
	if trigger > 0.6 and not _trigger_was:
		_activate(hovered, origin, dir)
	_trigger_was = trigger > 0.6


func _trigger_value() -> float:
	if _right == null:
		return 0.0
	var v := _right.get_float("trigger")
	if v <= 0.0 and _right.is_button_pressed("trigger_click"):
		return 1.0
	return clampf(v, 0.0, 1.0)


func _set_hover(area: Area3D) -> void:
	if area == _hover:
		return
	if _hover != null and is_instance_valid(_hover):
		var vm := _hover.get_node_or_null("Visual") as MeshInstance3D
		if vm:
			vm.material_override = _base_mat
	_hover = area
	if _hover != null:
		var vm := _hover.get_node_or_null("Visual") as MeshInstance3D
		if vm:
			vm.material_override = _hover_mat


func _activate(hovered: Area3D, _origin: Vector3, _dir: Vector3) -> void:
	if hovered == null:
		return
	var id: String = hovered.get_meta("tool_id", "")
	# Spawn 1.8 m in front of the player's view (the beam origin + look dir).
	var cam: Vector3 = _xr_origin.global_position
	var fwd := -_xr_origin.global_transform.basis.z.normalized()
	var at := cam + fwd * 1.8
	OracleBuilder.spawn_tool(id, at)


func set_palette(id: String) -> void:
	palette_id = id
	# Simplest correct refresh: rebuild children. (Live palette editing will
	# replace this with a diff update in the palette-editor phase.)
	var holder := _left.get_node_or_null("PaletteHolder")
	if holder:
		var panel := holder.get_node_or_null("PalettePanel")
		if panel:
			panel.free()
	_build_panel()