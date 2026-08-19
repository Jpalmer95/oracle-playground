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
		var player := get_node_or_null("Player") as OraclePlayer
		match event.physical_keycode:
			KEY_1:
				MaterialLab.spawn_cube("ice", _front_of(player), 0.55, self)
			KEY_2:
				MaterialLab.spawn_cube("rubber", _front_of(player), 0.55, self)
			KEY_3:
				MaterialLab.spawn_cube("metal", _front_of(player), 0.55, self)
			KEY_4:
				MaterialLab.spawn_cube("wood", _front_of(player), 0.55, self)
			KEY_5:
				MaterialLab.spawn_cube("glass", _front_of(player), 0.55, self)
			KEY_6:
				var crate: RigidBody3D = MaterialLab.spawn_cube("wood", _front_of(player), 0.6, self)
				crate.set_script(preload("res://scripts/destructible.gd"))
				crate.kind = "wood"
			KEY_I:
				var imported := get_node_or_null("Imported")
				if imported and imported.has_method("load_folder"):
					imported.load_folder()


func _front_of(player: Node3D) -> Vector3:
	if player == null:
		return Vector3(0, 1.5, 0)
	var forward := -player.global_transform.basis.z
	return player.global_position + Vector3.UP * 1.2 + forward * 2.0
