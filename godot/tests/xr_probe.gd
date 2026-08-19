extends SceneTree
## Print OpenXR interface state. Used to diagnose desktop-fallback.
## godot --path godot --script res://tests/xr_probe.gd [--xr-mode on]


func _initialize() -> void:
	print("XR_PROBE display=", DisplayServer.get_name())
	print("XR_PROBE ORACLE_XR=", OS.get_environment("ORACLE_XR"))
	print("XR_PROBE cmdline=", OS.get_cmdline_args())
	print("XR_PROBE user_args=", OS.get_cmdline_user_args())
	print("XR_PROBE interface_count=", XRServer.get_interface_count())
	for i in XRServer.get_interface_count():
		var iface: XRInterface = XRServer.get_interface(i)
		print("XR_PROBE iface[%d] name=%s class=%s init=%s primary=%s" % [
			i, iface.get_name(), iface.get_class(), iface.is_initialized(), iface.is_primary()
		])
	var oxr := XRServer.find_interface("OpenXR")
	print("XR_PROBE find_interface(OpenXR)=", oxr)
	if oxr:
		print("XR_PROBE before initialize: init=", oxr.is_initialized())
		if not oxr.is_initialized():
			var ok := oxr.initialize()
			print("XR_PROBE initialize()=", ok, " now_init=", oxr.is_initialized())
	quit(0)
