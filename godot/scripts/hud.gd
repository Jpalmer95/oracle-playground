extends CanvasLayer
## Minimal charcoal HUD: mode, speed, gear, fuel, control hints, and
## interactive Scribblenauts Prompt Bar (toggle with `/` or `P`).

var _player: OraclePlayer
var _label: Label
var _prompt_box: LineEdit


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(24, 20)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.91, 0.91, 0.9))
	add_child(_label)

	_prompt_box = LineEdit.new()
	_prompt_box.name = "ScribblenautsInput"
	_prompt_box.placeholder_text = "Scribblenauts prompt (e.g. 'drinking glass', 'heavy brass ball', 'ancient golden chalice') -> Enter"
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
		var fwd := -_player.global_transform.basis.z
		var pos := _player.global_position + Vector3.UP * 1.2 + fwd * 2.0
		Scribblenauts.spawn_prompt(clean, pos, "auto", true)


func _process(_delta: float) -> void:
	if _player == null:
		return
	var mode := "openxr" if _player.xr_active else "desktop"
	if DisplayServer.get_name() == "headless":
		mode = "headless"
	var stab := "on" if _player.stabilize_upright else "off"
	var pmode := "ground" if _player.is_ground_mode() else "flight"
	var scb := Scribblenauts.last_status if Scribblenauts != null else "Ready"
	_label.text = "ORACLE  %s / %s\nspeed  %.1f m/s\ngear   %d   fuel %.0f\nstabilize %s   scribblenauts: %s\n-- flight: triggers=thrust  grip=turbo  stick=turn  click=gear --\n-- ground: grip(G)=power-grab  pinch(B)=balance-grab  stick=move  A=jump --\nT/B-Y = mode/hub   P or / = Scribblenauts prompt bar\n1-5 mats  6 crate  7 hazard  8 hammer  9 bowl  0 marble  - chute  = staff  U undo  Bksp clear" % [
		mode,
		pmode,
		_player.linear_velocity.length(),
		_player.gear,
		_player.booster_fuel,
		stab,
		scb,
	]
