extends SceneTree

const EXAMPLE_PATHS := [
	"res://examples/example1/example.tscn",
	"res://examples/example2/example.tscn",
	"res://examples/example3/example.tscn",
	"res://examples/example4/example.tscn",
]

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for path: String in EXAMPLE_PATHS:
		var packed := load(path) as PackedScene
		_expect(packed != null, "loads %s" % path)
		if packed == null:
			continue
		var example := packed.instantiate()
		get_root().add_child(example)
		await process_frame
		_expect(
			example.get_node_or_null("StateManager") != null,
			"%s has a StateManager" % path
		)
		if path.contains("example4"):
			_test_transition_action(example)
		example.queue_free()
		await process_frame

	if _failures.is_empty():
		print("GState examples smoke test: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("GState examples smoke test: FAIL (%d)" % _failures.size())
	quit(1)


func _test_transition_action(example: Node) -> void:
	var machine := example.get_node(
			"StateManager/ActionDemo"
	) as StateMachine
	_expect(machine.is_in_state("Idle"), "example4 starts in Idle")
	_expect(machine.send(&"toggle"), "example4 accepts toggle")
	_expect(machine.is_in_state("Active"), "example4 enters Active")
	var context := machine.get_context()
	_expect(context[&"action_count"] == 1, "example4 executes its Action")
	_expect(
		context[&"last_source"] == &"Idle"
		and context[&"last_target"] == &"Active",
		"example4 Action receives source and target"
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
