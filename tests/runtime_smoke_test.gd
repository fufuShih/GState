extends SceneTree

const RecordingState := preload("res://tests/recording_state.gd")
const StateMachineEditorScene := preload(
		"res://addons/gstate/editor/state_machine_editor.tscn"
)

var _failures: Array[String] = []
var _calls: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RecordingState.calls = _calls
	var session_definition := load(
			"res://examples/sample3/session_machine.tres"
	) as StateMachineResource
	var serialized_playing := session_definition.find_state(&"Playing")
	_expect(
		session_definition.initial_state == &"Idle"
		and serialized_playing != null
		and serialized_playing.transitions[&"finish"] == &"Result",
		"serialized resources use readable State names"
	)
	var host := Node.new()
	host.name = &"Player"
	var manager := StateManager.new()
	manager.name = &"StateManager"
	manager.autostart = false
	host.add_child(manager)
	var machine := StateMachine.new()
	machine.name = &"Movement"
	machine.autostart = false
	var movement_context: Dictionary = {
		&"speed": 120.0,
		&"stats": {&"energy": 3},
	}
	machine.definition.context = movement_context
	manager.add_child(machine)

	var ui_machine := StateMachine.new()
	ui_machine.name = &"UI"
	ui_machine.autostart = false
	var ui_context: Dictionary = {&"screen": &"menu"}
	ui_machine.definition.context = ui_context
	manager.add_child(ui_machine)
	var menu_closed := State.new()
	menu_closed.name = &"Closed"
	menu_closed.editor_uid = &"editor_closed"
	ui_machine.definition.add_state(menu_closed)
	ui_machine.definition.initial_state = menu_closed.name

	var shared_machine := StateMachine.new()
	shared_machine.name = &"MovementCopy"
	shared_machine.autostart = false
	shared_machine.definition = machine.definition
	manager.add_child(shared_machine)

	var grounded := _add_state(machine, &"Grounded", &"grounded")
	var idle := _add_state(grounded, &"Idle", &"idle")
	var run := _add_state(grounded, &"Run", &"run")
	var airborne := _add_state(machine, &"Airborne", &"airborne")
	var jump := _add_state(airborne, &"Jump", &"jump")
	var fall := _add_state(airborne, &"Fall", &"fall")
	var dead := _add_state(machine, &"Dead", &"dead")

	machine.definition.initial_state = grounded.name
	grounded.initial_child = idle.name
	airborne.initial_child = jump.name

	_add_transition(machine, grounded, airborne, &"jump")
	_add_transition(machine, airborne, grounded, &"land")
	_add_transition(machine, grounded, dead, &"die")
	_add_transition(machine, airborne, dead, &"die")
	_add_transition(machine, idle, run, &"move", grounded)
	_add_transition(machine, run, idle, &"stop", grounded)
	_add_transition(machine, jump, fall, &"falling", airborne)
	idle.name = &"Resting"
	_expect(
		grounded.initial_child == &"Resting"
		and run.transitions[&"stop"] == &"Resting",
		"renaming a State updates initial and incoming same-scope references"
	)
	idle.name = &"Idle"

	get_root().add_child(host)
	await process_frame

	var valid_result: Dictionary = machine.validate()
	var valid_errors: PackedStringArray = valid_result["errors"]
	_expect(valid_errors.is_empty(), "valid graph must pass validation")
	_expect(manager.get_state_machines().size() == 3, "manager owns three machines")
	_expect(manager.get_machine(&"Movement") == machine, "manager finds machine")
	_expect(manager.get_machine(&"UI") == ui_machine, "manager finds second machine")
	_expect(machine.start(), "start() must succeed")
	_expect(ui_machine.start(), "second independent machine starts")
	_expect(shared_machine.start(), "shared definition starts independently")
	_expect(
		machine.get_current_state() != shared_machine.get_current_state()
		and not grounded.active,
		"shared .tres creates isolated runtime States"
	)
	_expect_path(machine, "Grounded/Idle")
	_expect(
		machine.get_state(&"Grounded").actor == host,
		"State actor defaults through StateManager"
	)
	_expect(
		ui_machine.get_state(&"Closed").actor == host,
		"manager shares its actor with child machines"
	)
	var runtime_context := machine.get_context()
	var state_context := machine.get_state(&"Grounded").get_context()
	var runtime_ui_context := ui_machine.get_context()
	var shared_context := shared_machine.get_context()
	_expect(
		runtime_context.get(&"speed") == 120.0,
		"start duplicates the definition context Dictionary"
	)
	_expect(
		state_context == runtime_context,
		"every State reads the same live context Resource"
	)
	_expect(
		runtime_ui_context.get(&"screen") == &"menu"
		and runtime_ui_context != runtime_context,
		"independent machines have isolated contexts"
	)

	runtime_context[&"speed"] = 240.0
	(runtime_context[&"stats"] as Dictionary)[&"energy"] = 7
	var run_context := machine.get_state("Grounded/Run").get_context()
	_expect(
		run_context[&"speed"] == 240.0
		and (run_context[&"stats"] as Dictionary)[&"energy"] == 7,
		"all States share direct runtime context writes"
	)
	_expect(
		movement_context[&"speed"] == 120.0
		and (movement_context[&"stats"] as Dictionary)[&"energy"] == 3,
		"runtime writes do not mutate the definition context Dictionary"
	)
	_expect(
		shared_context[&"speed"] == 120.0
		and (shared_context[&"stats"] as Dictionary)[&"energy"] == 3,
		"machines sharing one .tres keep isolated runtime contexts"
	)

	_calls.clear()
	machine._process(0.016)
	machine._physics_process(0.016)
	_expect_calls([
		"update:Grounded",
		"update:Idle",
		"physics:Grounded",
		"physics:Idle",
	], "active update order")

	_calls.clear()
	_expect(manager.send_to(&"Movement", &"move"), "manager routes an event")
	_expect_path(machine, "Grounded/Run")
	_expect_path(ui_machine, "Closed")
	_expect_calls(["exit:Idle", "enter:Run"], "sibling lifecycle order")

	_calls.clear()
	_expect(machine.send(&"jump", {"strength": 1.0}), "parent fallback jump")
	_expect_path(machine, "Airborne/Jump")
	_expect_calls(
		["exit:Run", "exit:Grounded", "enter:Airborne", "enter:Jump"],
		"parent transition lifecycle order"
	)

	_expect(machine.send(&"falling"), "Jump falling transition")
	_expect_path(machine, "Airborne/Fall")
	_expect(machine.send(&"land"), "Airborne land transition")
	_expect_path(machine, "Grounded/Idle")
	_expect(machine.send(&"die"), "Grounded die transition")
	_expect_path(machine, "Dead")

	_expect(machine.travel("Grounded/Run"), "travel to nested path")
	_expect_path(machine, "Grounded/Run")
	_expect(machine.is_in_state(grounded), "compound State reference is active")
	_expect(machine.is_in_state("Grounded"), "compound path is active")
	_expect(not machine.is_in_state("Grounded/Idle"), "inactive leaf is rejected")
	var previous_context := machine.get_context()
	_expect(machine.restart(), "restart with context must succeed")
	_expect_path(machine, "Grounded/Idle")
	var restarted_context := machine.get_context()
	_expect(
		restarted_context != previous_context
		and restarted_context[&"speed"] == 120.0
		and (restarted_context[&"stats"] as Dictionary)[&"energy"] == 3,
		"restart restores the definition context"
	)

	var graph_view: GStateMachineEditor = StateMachineEditorScene.instantiate()
	get_root().add_child(graph_view)
	graph_view.set_state_manager(manager)
	_expect(
		_count_graph_nodes(graph_view) == 3,
		"root graph view displays direct child states"
	)
	_expect(
		_get_graph_edit(graph_view).connections.size() == 4,
		"each root transition is displayed as one direct connection"
	)
	var grounded_graph_node := _find_graph_node(graph_view, grounded)
	var dead_graph_node := _find_graph_node(graph_view, dead)
	_expect(
		grounded_graph_node != null
		and grounded_graph_node.get_output_port_count() == 2,
		"State nodes expose one output port per transition"
	)
	_expect(
		dead_graph_node != null
		and dead_graph_node.get_input_port_count() == 2,
		"State nodes expose numbered incoming transition ports"
	)
	_expect(
		grounded_graph_node != null
		and grounded_graph_node.has_theme_stylebox_override(&"panel")
		and grounded_graph_node.has_theme_stylebox_override(&"titlebar")
		and grounded_graph_node.has_theme_stylebox_override(
				&"panel_selected"
		)
		and grounded_graph_node.has_theme_stylebox_override(
				&"titlebar_selected"
		),
		"State nodes provide normal and selected color overrides"
	)
	var grounded_second_port_row: HBoxContainer
	if grounded_graph_node != null and grounded_graph_node.get_child_count() > 3:
		grounded_second_port_row = (
				grounded_graph_node.get_child(3) as HBoxContainer
		)
	_expect(
		grounded_second_port_row != null
		and (grounded_second_port_row.get_child(1) as Label).text == "die",
		"State OUT rows display their transition event names"
	)
	var dead_first_port_row: HBoxContainer
	if dead_graph_node != null and dead_graph_node.get_child_count() > 2:
		dead_first_port_row = dead_graph_node.get_child(2) as HBoxContainer
	_expect(
		dead_first_port_row != null
		and (dead_first_port_row.get_child(0) as Label).text == "0",
		"State IN rows remain numbered"
	)
	var long_event := &"this_transition_event_name_must_stay_complete"
	var long_transition: Dictionary = {
		&"source": grounded,
		&"source_uid": grounded.editor_uid,
		&"target_uid": dead.editor_uid,
		&"target_name": dead.name,
		&"event": long_event,
	}
	var long_outgoing: Array[Dictionary] = [long_transition]
	var no_incoming: Array[Dictionary] = []
	var preview_node := GStateGraphNode.new()
	preview_node.setup(grounded, false, long_outgoing, no_incoming)
	var preview_port_row := preview_node.get_child(2) as HBoxContainer
	_expect(
		preview_port_row != null
		and (preview_port_row.get_child(1) as Label).text == str(long_event),
		"State OUT labels keep the complete transition event"
	)
	preview_node.free()
	graph_view._show_scope(grounded)
	_expect(
		_count_graph_nodes(graph_view) == 2,
		"nested graph view displays direct child states"
	)
	_expect(
		_get_graph_edit(graph_view).connections.size() == 2,
		"nested transitions are displayed as direct connections"
	)
	graph_view.queue_free()

	idle.transitions[&""] = run.name
	idle.transitions[&"launch"] = airborne.name
	var invalid_result: Dictionary = machine.validate()
	var invalid_errors: PackedStringArray = invalid_result["errors"]
	_expect(
		not invalid_errors.is_empty(),
		"empty transition event must fail validation"
	)
	_expect(
		invalid_errors.size() >= 2,
		"cross-scope transition must fail validation"
	)

	machine.stop()
	ui_machine.stop()
	shared_machine.stop()
	_expect(not machine.is_running(), "stop() clears running state")
	_expect(machine.get_active_path().is_empty(), "stop() clears active path")
	host.queue_free()
	await process_frame

	if _failures.is_empty():
		print("GState runtime smoke test: PASS")
		quit(0)
	else:
		for failure: String in _failures:
			push_error(failure)
		print(
			"GState runtime smoke test: FAIL (%d)"
			% _failures.size()
		)
		quit(1)


func _add_state(parent: Variant, state_name: StringName, id: StringName) -> State:
	var state: State = RecordingState.new()
	state.name = state_name
	state.editor_uid = StringName("editor_%s" % id)
	if parent is StateMachine:
		(parent as StateMachine).definition.add_state(state)
	elif parent is State:
		(parent as State).add_child_state(state)
	return state


func _add_transition(
		_machine: StateMachine,
		from_state: State,
		to_state: State,
		event: StringName,
		_scope: State = null
) -> void:
	_expect(
		from_state.add_transition(event, to_state.name),
		"transition must be added to its source State"
	)


func _expect_path(machine: StateMachine, expected: String) -> void:
	var names := PackedStringArray()
	for state: State in machine.get_active_path():
		names.append(state.name)
	_expect("/".join(names) == expected, "expected active path '%s'" % expected)


func _expect_calls(expected: Array[String], label: String) -> void:
	_expect(_calls == expected, "%s: got %s" % [label, _calls])


func _get_graph_edit(editor: GStateMachineEditor) -> GraphEdit:
	return editor.get_node("%GraphEdit") as GraphEdit


func _count_graph_nodes(editor: GStateMachineEditor) -> int:
	var count := 0
	for child: Node in _get_graph_edit(editor).get_children():
		if child is GStateGraphNode:
			count += 1
	return count


func _find_graph_node(
		editor: GStateMachineEditor,
		state: State
) -> GStateGraphNode:
	for child: Node in _get_graph_edit(editor).get_children():
		if child is GStateGraphNode and (child as GStateGraphNode).state == state:
			return child as GStateGraphNode
	return null
func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
