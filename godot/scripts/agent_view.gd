extends Node
## Viewport dump so a Linux agent can see what the player sees.
## F12 or ORACLE_AGENT_VIEW=1. Writes user://agent_view.png.

const DUMP_PATH := "user://agent_view.png"

var _auto := false
var _accum := 0.0
@export var auto_interval := 2.0


func _ready() -> void:
	_auto = OS.get_environment("ORACLE_AGENT_VIEW") == "1"


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_text_completion_replace"):
		# unused — we poll F12 below
		pass
	if Input.is_key_pressed(KEY_F12) and _edge_f12():
		capture()
	if _auto:
		_accum += delta
		if _accum >= auto_interval:
			_accum = 0.0
			capture()


var _f12_was := false

func _edge_f12() -> bool:
	var down := Input.is_physical_key_pressed(KEY_F12)
	var edge := down and not _f12_was
	_f12_was = down
	return edge


func capture(path: String = DUMP_PATH) -> String:
	var img: Image = null
	var vp := get_viewport()
	if vp and DisplayServer.get_name() != "headless":
		var tex := vp.get_texture()
		if tex:
			img = tex.get_image()
	if img == null:
		# Dummy/headless renderer has no swapchain — still emit a file so agents have a hook.
		img = Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.12, 0.12, 0.14))
		print("AgentView: no live viewport (headless), wrote placeholder")
	var err := img.save_png(path)
	if err != OK:
		push_warning("AgentView: save failed %s" % err)
		return ""
	var abs_path := ProjectSettings.globalize_path(path)
	print("AgentView wrote ", abs_path)
	return abs_path
