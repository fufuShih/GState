extends SceneTree

const EXAMPLE_PATHS := [
	"res://examples/example1/example.tscn",
	"res://examples/example2/example.tscn",
	"res://examples/example3/example.tscn",
	"res://examples/example4/example.tscn",
	"res://examples/example5/example.tscn",
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
		if path.contains("example5"):
			_test_debug_panel(example)
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


func _test_debug_panel(example: Node) -> void:
	var movement := example.get_node(
			"StateManager/Movement"
	) as StateMachine
	var panel := example.get_node("StateDebugPanel") as StateDebugPanel
	_expect(panel != null, "example5 has a StateDebugPanel")
	if panel == null:
		return
	_expect(
		panel.get_selected_machine() == movement,
		"example5 selects its first machine"
	)
	_expect(
		(panel.get_node("%MachineOption") as Control).focus_mode
		== Control.FOCUS_NONE
		and (panel.get_node("%SendButton") as Control).focus_mode
		== Control.FOCUS_NONE
		and (panel.get_node("%EventEdit") as Control).focus_mode
		== Control.FOCUS_CLICK,
		"example5 panel does not capture gameplay keys"
	)
	panel.set_minimized(true)
	_expect(panel.is_minimized(), "example5 panel collapses to its title row")
	panel.set_minimized(false)
	_expect(not panel.is_minimized(), "example5 panel expands again")
	_expect(panel.send_event(&"toggle"), "example5 panel sends an event")
	_expect(movement.is_in_state("Running"), "example5 enters Running")
	_expect(
		"OK" in "\n".join(panel.get_event_log()),
		"example5 panel records a successful transition"
	)
	_expect(
		not panel.send_event(&"missing"),
		"example5 panel reports a rejected event"
	)
	_expect(
		"REJECTED" in "\n".join(panel.get_event_log()),
		"example5 panel records rejected events"
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
