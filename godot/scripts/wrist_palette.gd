extends Node3D
## WristPalette — the in-VR system HUD. Renders HUDMenu's current menu level as
## a grid of buttons on the left wrist, plus a persistent Back/Close entry.
## Right-hand ray + trigger selects. Menu opens/closes on B/Y (by_button).
##
## This node renders whatever HUDMenu says the current level is; it knows nothing
## about tools, radio, or settings — new submenus (plugins) appear automatically
## when HUDMenu's tree changes. State changes bump HUDMenu.version, which this
## node watches to rebuild.

const BUTTON_LAYER := 8
const RAY_MASK := 8
const BEAM_LENGTH := 10.0
const SPACING := 0.030
const BUTTON_SIZE := Vector2(0.085, 0.024)
const MAX_ROWS := 7

var _xr_origin: XROrigin3D
var _left: XRController3D
var _right: XRController3D
var _beam: MeshInstance3D
var _holder: Node3D
var _panel: Node3D
var _entries: Array = []          # {area: Area3D, index: int} (index = -1 for back)
var _hover: Area3D = null
var _hover_mat: StandardMaterial3D
var _base_mat: StandardMaterial3D
var _select_mat: StandardMaterial3D
var _trigger_was := false
var _by_was := false
var _watched_version := -1


func setup(p_origin: XROrigin3D, p_left: XRController3D, p_right: XRController3D) -> void:
	_xr_origin = p_origin
	_left = p_left
	_right = p_right
	_build_beam()
	_build_panel_root()
	_refresh()  # starts hidden; HUDMenu bumps version on open


func _build_panel_root() -> void:
	_holder = Node3D.new()
	_holder.name = "PaletteHolder"
	_left.add_child(_holder)
	_holder.position = Vector3(-0.02, -0.09, 0.10)
	_holder.rotation_degrees = Vector3(12, 0, 0)
	_panel = Node3D.new()
	_panel.name = "PalettePanel"
	_holder.add_child(_panel)

	_hover_mat = StandardMaterial3D.new()
	_hover_mat.albedo_color = Color(0.30, 0.75, 0.95)
	_hover_mat.emission_enabled = true
	_hover_mat.emission = Color(0.10, 0.30, 0.45)
	_base_mat = StandardMaterial3D.new()
	_base_mat.albedo_color = Color(0.13, 0.14, 0.16)
	_base_mat.metallic = 0.2
	_base_mat.roughness = 0.6
	_select_mat = StandardMaterial3D.new()
	_select_mat.albedo_color = Color(0.16, 0.30, 0.20)
	_select_mat.metallic = 0.2
	_select_mat.roughness = 0.6

	_holder.visible = HUDMenu.is_open()


func _build_beam() -> void:
	_beam = MeshInstance3D.new()
	_beam.name = "PaletteBeam"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.003
	cyl.bottom_radius = 0.003
	cyl.height = BEAM_LENGTH
	_beam.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.8, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.5, 0.7)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam.material_override = mat
	_right.add_child(_beam)
	_beam.position = Vector3(0.0, 0.0, -BEAM_LENGTH * 0.5)
	_beam.visible = false


func _physics_process(_delta: float) -> void:
	if _right == null:
		return
	# B/Y toggles the hub.
	var by := _by_value()
	var by_edge := by and not _by_was
	_by_was = by
	if by_edge:
		HUDMenu.toggle_open()

	# Re-render when the menu state changed (open/close, nav, settings).
	if _watched_version != HUDMenu.version or _holder.visible != HUDMenu.is_open():
		_watched_version = HUDMenu.version
		_holder.visible = HUDMenu.is_open()
		_beam.visible = HUDMenu.is_open()
		if HUDMenu.is_open():
			_refresh()

	if not HUDMenu.is_open():
		return

	var origin := _right.global_position
	var dir := -_right.global_transform.basis.z.normalized()
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * BEAM_LENGTH, RAY_MASK)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := space.intersect_ray(q)
	var hovered: Area3D = null
	if not hit.is_empty():
		var c = hit.get("collider")
		if c is Area3D and c.has_meta("entry_index"):
			hovered = c

	_set_hover(hovered)

	var trigger := _trigger_value()
	if trigger > 0.6 and not _trigger_was:
		_activate(hovered)
	_trigger_was = trigger > 0.6


func _refresh() -> void:
	# Clear old buttons.
	_hover = null
	for child in _panel.get_children():
		child.queue_free()
	_entries.clear()

	var title := Label3D.new()
	title.name = "Title"
	title.text = HUDMenu.level_title()
	title.font_size = 40
	title.pixel_size = 0.0005
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.modulate = Color(0.55, 0.85, 1.0)
	title.position = Vector3(0.0, 0.05, -0.001)
	title.outline_size = 6
	_panel.add_child(title)

	var idx := 0
	for item in HUDMenu.level_items():
		var label: String = item.get("label", "?")
		var kind: int = item.get("kind", -1)
		# Show current option for select items.
		if kind == HUDMenu.ItemKind.SELECT:
			var opts: Array = item.get("options", [])
			var cur: int = item.get("current", 0)
			var cur_s: String = opts[cur] if (cur >= 0 and cur < opts.size()) else ""
			label = "%s: %s" % [label, cur_s]
		_make_button(label, idx, _item_offset(idx), kind)
		idx += 1

	# Persistent Back / Close entry at the bottom.
	_make_back_button(HUDMenu.back_button_label(), idx, _item_offset(idx))


func _item_offset(i: int) -> Vector3:
	# Single column, top-to-bottom. Clamp count so it fits the wrist panel.
	var y := -0.03 - float(i) * SPACING
	return Vector3(0.0, y, 0.0)


func _make_button(label_text: String, index: int, at: Vector3, kind: int = -1) -> Area3D:
	var area := Area3D.new()
	area.name = "Item_%d" % index
	area.collision_layer = BUTTON_LAYER
	area.collision_mask = 0
	area.position = at
	area.set_meta("entry_index", index)
	area.set_meta("is_back", false)
	area.set_meta("kind", kind)

	_attach_button_parts(area, label_text, _base_mat if kind != HUDMenu.ItemKind.SELECT else _select_mat)
	_panel.add_child(area)
	_entries.append({"area": area, "index": index})
	return area


func _make_back_button(label_text: String, index: int, at: Vector3) -> Area3D:
	var area := Area3D.new()
	area.name = "Back"
	area.collision_layer = BUTTON_LAYER
	area.collision_mask = 0
	area.position = at
	area.set_meta("entry_index", index)
	area.set_meta("is_back", true)

	_attach_button_parts(area, label_text, _base_mat)
	_panel.add_child(area)
	_entries.append({"area": area, "index": index})
	return area


func _attach_button_parts(area: Area3D, label_text: String, mat: StandardMaterial3D) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(BUTTON_SIZE.x, BUTTON_SIZE.y, 0.01)
	cs.shape = box
	area.add_child(cs)

	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(BUTTON_SIZE.x, BUTTON_SIZE.y, 0.008)
	mesh.mesh = bm
	mesh.material_override = mat
	mesh.name = "Visual"
	area.add_child(mesh)

	var lbl := Label3D.new()
	lbl.name = "Label"
	lbl.text = label_text
	lbl.font_size = 36
	lbl.pixel_size = 0.00055
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color(0.95, 0.95, 0.93)
	lbl.position = Vector3(0.0, 0.0, -0.008)
	lbl.outline_size = 8
	lbl.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	area.add_child(lbl)


func _by_value() -> bool:
	if _right and _right.is_button_pressed("by_button"):
		return true
	if _left and _left.is_button_pressed("by_button"):
		return true
	return false


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


func _activate(hovered: Area3D) -> void:
	if hovered == null:
		return
	if hovered.get_meta("is_back", false):
		if _can_go_back():
			HUDMenu.go_back()
		else:
			HUDMenu.set_open(false)
		return
	var index: int = hovered.get_meta("entry_index", -1)
	var items := HUDMenu.level_items()
	if index >= 0 and index < items.size():
		HUDMenu.activate(items[index])


func _can_go_back() -> bool:
	return HUDMenu.can_go_back()