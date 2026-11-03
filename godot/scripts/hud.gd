extends CanvasLayer
## Minimal charcoal HUD: mode, speed, gear, fuel, control hints,
## center-screen grab pointer dot + live target readout, and
## interactive Oracle Conjure Prompt Bar (toggle with `/` or `P`).

var _player: OraclePlayer
var _label: Label
var _reticle_dot: ColorRect
var _reticle_label: Label
var _prompt_box: LineEdit


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(24, 20)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.91, 0.91, 0.9))
	add_child(_label)

	# Center-screen pointer dot for Desktop aiming & grab feedback
	_reticle_dot = ColorRect.new()
	_reticle_dot.name = "ReticleDot"
	_reticle_dot.size = Vector2(8, 8)
	_reticle_dot.color = Color(0.9, 0.9, 0.9, 0.65)
	_reticle_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_reticle_dot)

	_reticle_label = Label.new()
	_reticle_label.name = "ReticleFeedback"
	_reticle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reticle_label.add_theme_font_size_override("font_size", 16)
	_reticle_label.add_theme_color_override("font_color", Color(0.3, 0.95, 1.0))
	_reticle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_reticle_label)

	_prompt_box = LineEdit.new()
	_prompt_box.name = "ConjureInput"
	_prompt_box.placeholder_text = "Oracle Conjure prompt (e.g. 'drinking glass', 'heavy brass ball', 'ancient golden chalice') -> Enter"
	_prompt_box.position = Vector2(24, 210)
	_prompt_box.size = Vector2(680, 38)
	_prompt_box.visible = false
	_prompt_box.text_submitted.connect(_on_prompt_submitted)
	add_child(_prompt_box)


func bind_player(p: OraclePlayer) -> void:
	_player = p


func toggle_prompt_bar() -> void:
	if _prompt_box == null:
		return
	_prompt_box.visible = not _prompt_box.visible
	if _prompt_box.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_prompt_box.grab_focus()
		_prompt_box.select_all()
	else:
		_prompt_box.release_focus()
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func is_prompt_open() -> bool:
	return _prompt_box != null and _prompt_box.visible


func _on_prompt_submitted(text: String) -> void:
	var clean := text.strip_edges()
	_prompt_box.clear()
	toggle_prompt_bar()
	if clean != "" and _player != null:
		var fwd := _player.aim_forward() if _player.has_method("aim_forward") else -_player.global_transform.basis.z
		var pos := _player.global_position + Vector3.UP * 1.2 + fwd * 2.0
		OracleConjure.spawn_prompt(clean, pos, "auto", true)


func _process(_delta: float) -> void:
	if _player == null:
		return
	var mode := "openxr" if _player.xr_active else "desktop"
	if DisplayServer.get_name() == "headless":
		mode = "headless"
	var stab := "on" if _player.stabilize_upright else "off"
	var pmode := "ground" if _player.is_ground_mode() else "flight"
	var cnj := OracleConjure.last_status if OracleConjure != null else "Ready"
	_label.text = "ORACLE  %s / %s\nspeed  %.1f m/s\ngear   %d   fuel %.0f\nstabilize %s   conjure: %s\n-- desktop flight: WASD=fly/strafe  Space/C=up/down  Shift=turbo  Wheel=gear/pull --\n-- grab hands: LMB=Left Hand   RMB=Right Hand   LMB+RMB or G=Both Hands   B=Balance Pinch --\nT/B-Y = flight/ground/hub   P or / = Oracle Conjure prompt bar   R = reset\n1-5 mats  6 crate  7 hazard  8 hammer  9 bowl  0 marble  - chute  = staff  U undo  Bksp clear" % [
		mode,
		pmode,
		_player.linear_velocity.length(),
		_player.gear,
		_player.booster_fuel,
		stab,
		cnj,
	]

	_update_reticle()


func _update_reticle() -> void:
	if _reticle_dot == null or _reticle_label == null:
		return
	if _player.xr_active:
		_reticle_dot.visible = false
		_reticle_label.visible = false
		return

	_reticle_dot.visible = true
	_reticle_label.visible = true
	var vp_size := get_viewport().get_visible_rect().size
	var center := vp_size * 0.5

	var gstate := _player.get_grab_hud_state() if _player.has_method("get_grab_hud_state") else {}
	var l_held: RigidBody3D = gstate.get("left_held")
	var r_held: RigidBody3D = gstate.get("right_held")
	var probe: Dictionary = gstate.get("probe", {})

	if l_held != null or r_held != null:
		var held_body := l_held if l_held != null else r_held
		var hands_str := "Left + Right Hands (2-Hand Power)" if (l_held != null and r_held != null) else ("Left Hand" if l_held != null else "Right Hand")
		var grip_val := maxf(float(gstate.get("grip_l", 0.0)), float(gstate.get("grip_r", 0.0)))
		var mode_tag := "Balance Pinch %.0f%%" % (grip_val * 100.0) if grip_val < 0.5 else "Power Grip"
		_reticle_dot.size = Vector2(12, 12)
		_reticle_dot.position = center - Vector2(6, 6)
		_reticle_dot.color = Color(1.0, 0.85, 0.25, 0.95)
		_reticle_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
		_reticle_label.text = "HOLDING: %s (%.2f kg)  •  %s [%s]\nMouse Wheel: Pull / Push (%.2fm)  •  Hold B for Balance Pinch" % [
			held_body.name,
			held_body.mass,
			hands_str,
			mode_tag,
			float(gstate.get("hold_distance", 0.95)),
		]
	elif not probe.is_empty():
		var com_off := float(probe.get("com_offset", 1.0))
		var gline := String(probe.get("grasp_line", ""))
		var balance_tag := "  [BALANCE POINT / CoM!]" if com_off < 0.08 else ("  [CoM offset: %.2fm]" % com_off)
		if gline != "":
			balance_tag += "  [Snap: %s]" % gline
		_reticle_dot.size = Vector2(10, 10)
		_reticle_dot.position = center - Vector2(5, 5)
		_reticle_dot.color = Color(0.25, 1.0, 0.55, 0.95) if com_off < 0.08 else Color(0.25, 0.95, 1.0, 0.95)
		_reticle_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.65) if com_off < 0.08 else Color(0.3, 0.95, 1.0))
		_reticle_label.text = "[GRAB READY]  %s  (%.2f kg  •  %.2fm)%s\nLMB: Left Hand  |  RMB: Right Hand  |  LMB+RMB or G: Both Hands  |  B: Balance Pinch" % [
			String(probe.get("name", "Prop")),
			float(probe.get("mass", 1.0)),
			float(probe.get("distance", 1.0)),
			balance_tag,
		]
	else:
		_reticle_dot.size = Vector2(6, 6)
		_reticle_dot.position = center - Vector2(3, 3)
		_reticle_dot.color = Color(0.9, 0.9, 0.9, 0.55)
		_reticle_label.text = ""

	_reticle_label.size = Vector2(760, 56)
	_reticle_label.position = Vector2(center.x - 380, center.y + 16)
