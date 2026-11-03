extends Node3D
## Boot: environment, arena, player, HUD, imported props.

const PlayerScript := preload("res://scripts/player.gd")
const ArenaScript := preload("res://scripts/arena.gd")
const HudScript := preload("res://scripts/hud.gd")
const ImportScript := preload("res://scripts/imported_props.gd")


func _ready() -> void:
	print("Oracle Playground boot")
	_world()
	var arena := Node3D.new()
	arena.set_script(ArenaScript)
	arena.name = "Arena"
	add_child(arena)
	arena.build()
	var player := RigidBody3D.new()
	player.set_script(PlayerScript)
	player.name = "Player"
	player.position = Vector3(0, 1.2, 8)
	add_child(player)
	var hud := CanvasLayer.new()
	hud.set_script(HudScript)
	hud.name = "HUD"
	add_child(hud)
	hud.bind_player(player)
	var imports := Node3D.new()
	imports.set_script(ImportScript)
	imports.name = "Imported"
	add_child(imports)
	imports.load_folder()

	# Builder: desktop keys and XR palette both resolve through OracleBuilder.
	OracleBuilder.set_parent(self)
	OracleBuilder.set_glb_wrapper(imports)
	# System hub: HUDMenu needs the player for mode/settings dispatch.
	HUDMenu.bind_player(player)


func _world() -> void:
	var env := WorldEnvironment.new()
	var we := Environment.new()
	we.background_mode = Environment.BG_COLOR
	we.background_color = Color(0.08, 0.08, 0.09)
	we.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.ambient_light_color = Color(0.35, 0.36, 0.4)
	we.ambient_light_energy = 0.55
	we.tonemap_mode = Environment.TONE_MAPPER_ACES
	we.glow_enabled = true
	we.glow_intensity = 0.25
	env.environment = we
	env.name = "WorldEnvironment"
	add_child(env)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var hud := get_node_or_null("HUD")
		if hud and hud.has_method("is_prompt_open") and hud.is_prompt_open():
			if event.physical_keycode == KEY_ESCAPE:
				hud.toggle_prompt_bar()
			return
		var player := get_node_or_null("Player") as OraclePlayer
		match event.physical_keycode:
			KEY_P, KEY_SLASH:
				if hud and hud.has_method("toggle_prompt_bar"):
					hud.toggle_prompt_bar()
			KEY_1:
				OracleBuilder.spawn_tool("cube_ice", _front_of(player))
			KEY_2:
				OracleBuilder.spawn_tool("cube_rubber", _front_of(player))
			KEY_3:
				OracleBuilder.spawn_tool("cube_metal", _front_of(player))
			KEY_4:
				OracleBuilder.spawn_tool("cube_wood", _front_of(player))
			KEY_5:
				OracleBuilder.spawn_tool("cube_glass", _front_of(player))
			KEY_6:
				OracleBuilder.spawn_tool("crate_wood", _front_of(player))
			KEY_7:
				OracleBuilder.spawn_tool("hazard_crate", _front_of(player))
			KEY_8:
				OracleBuilder.spawn_tool("sr_hammer", _front_of(player))
			KEY_9:
				OracleBuilder.spawn_tool("sr_bowl", _front_of(player))
			KEY_0:
				OracleBuilder.spawn_tool("brep_marble_steel", _front_of(player))
			KEY_MINUS:
				OracleBuilder.spawn_tool("brep_chute_straight", _front_of(player))
			KEY_EQUAL:
				OracleBuilder.spawn_tool("brep_balance_rod", _front_of(player))
			KEY_U:
				OracleBuilder.undo()
			KEY_BACKSPACE:
				OracleBuilder.clear()
			KEY_I:
				var imported := get_node_or_null("Imported")
				if imported and imported.has_method("load_folder"):
					imported.load_folder()


func _front_of(player: Node3D) -> Vector3:
	if player == null:
		return Vector3(0, 1.5, 0)
	var forward := -player.global_transform.basis.z
	if player.has_method("aim_forward"):
		forward = player.aim_forward()
	return player.global_position + Vector3.UP * 1.2 + forward * 2.0
