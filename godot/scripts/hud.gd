extends CanvasLayer
## Minimal charcoal HUD: mode, speed, gear, fuel, and control hints.

var _player: OraclePlayer
var _label: Label


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(24, 20)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.91, 0.91, 0.9))
	add_child(_label)


func bind_player(p: OraclePlayer) -> void:
	_player = p


func _process(_delta: float) -> void:
	if _player == null:
		return
	var mode := "openxr" if _player.xr_active else "desktop"
	if DisplayServer.get_name() == "headless":
		mode = "headless"
	var stab := "on" if _player.stabilize_upright else "off"
	var pmode := "ground" if _player.is_ground_mode() else "flight"
	_label.text = "ORACLE  %s / %s\nspeed  %.1f m/s\ngear   %d   fuel %.0f\nstabilize %s\n-- flight: triggers=thrust  grip=turbo  stick=turn  click=gear --\n-- ground: grip(G)=power-grab  pinch(B)=balance-grab  stick=move  A=jump --\nT/B-Y = mode/hub   Q/E LMB/RMB thrust   Shift turbo\n1-5 mats  6 crate  7 hazard  8 hammer  9 bowl  0 marble  - chute  = staff  U undo  Bksp clear" % [
		mode,
		pmode,
		_player.linear_velocity.length(),
		_player.gear,
		_player.booster_fuel,
		stab,
	]