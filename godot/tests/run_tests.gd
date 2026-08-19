extends SceneTree
## Headless Oracle Playground tests. Exit 0 on pass.
## godot --headless --path godot --script res://tests/run_tests.gd


func _initialize() -> void:
	var runner := Node.new()
	runner.set_script(load("res://tests/test_runner.gd"))
	root.add_child(runner)
