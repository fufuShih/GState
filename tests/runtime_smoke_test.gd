extends SceneTree

const RecordingState := preload("res://tests/recording_state.gd")
const RecordingContext := preload("res://tests/recording_context.gd")
const StateMachineEditorScene := preload(
		"res://addons/gstate/editor/state_machine_editor.tscn"
)

var _failures: Array[String] = []
var _calls: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var host := Node.new()
	host.name = &"Player"
	var manager := StateManager.new()
	manager.name = &"StateManager"
	manager.autostart = false
	host.add_child(manager)
	var machine := StateMachine.new()
	machine.name = &"Movement"
	machine.autostart = false
	var movement_context := RecordingContext.new()
	movement_context.speed = 120.0
	movement_context.stats = {&"energy": 3}
	machine.initial_context = movement_context
	manager.add_child(machine)

	var ui_machine := StateMachine.new()
	ui_machine.name = &"UI"
	ui_machine.autostart = false
	var ui_context := RecordingContext.new()
	ui_context.screen = &"menu"
	ui_machine.initial_context = ui_context
	manager.add_child(ui_machine)
	var menu_closed := State.new()
	menu_closed.name = &"Closed"
	menu_closed.stable_id = &"closed"
	ui_machine.add_child(menu_closed)
	ui_machine.initial_state_id = menu_closed.stable_id

	var grounded := _add_state(machine, &"Grounded", &"grounded")
	var idle := _add_state(grounded, &"Idle", &"idle")
	var run := _add_state(grounded, &"Run", &"run")
	var airborne := _add_state(machine, &"Airborne", &"airborne")
	var jump := _add_state(airborne, &"Jump", &"jump")
	var fall := _add_state(airborne, &"Fall", &"fall")
	var dead := _add_state(machine, &"Dead", &"dead")

	machine.initial_state_id = grounded.stable_id
	grounded.initial_child_id = idle.stable_id
	airborne.initial_child_id = jump.stable_id

	_add_transition(machine, grounded, airborne, &"jump")
	_add_transition(machine, airborne, grounded, &"land")
	_add_transition(machine, grounded, dead, &"die")
	_add_transition(machine, airborne, dead, &"die")
	_add_transition(machine, idle, run, &"move", grounded)
	_add_transition(machine, run, idle, &"stop", grounded)
	_add_transition(machine, jump, fall, &"falling", airborne)

	get_root().add_child(host)
	await process_frame

	var valid_result: Dictionary = machine.validate()
	var valid_errors: PackedStringArray = valid_result["errors"]
	_expect(valid_errors.is_empty(), "valid graph must pass validation")
	_expect(manager.get_state_machines().size() == 2, "manager owns two machines")
	_expect(manager.get_machine(&"Movement") == machine, "manager finds machine")
	_expect(manager.get_machine(&"UI") == ui_machine, "manager finds second machine")
	_expect(machine.start(), "start() must succeed")
	_expect(ui_machine.start(), "second independent machine starts")
	_expect_path(machine, "Grounded/Idle")
	_expect(grounded.actor == host, "State actor defaults through StateManager")
	_expect(menu_closed.actor == host, "manager shares its actor with child machines")
	var runtime_context := machine.get_context() as RecordingContext
	var state_context := grounded.get_context() as RecordingContext
	var runtime_ui_context := ui_machine.get_context() as RecordingContext
	_expect(
		runtime_context != null
		and runtime_context.speed == 120.0
		and runtime_context != movement_context,
		"start duplicates the initial context Resource"
	)
	_expect(
		state_context == runtime_context,
		"every State reads the same live context Resource"
	)
	_expect(
		runtime_ui_context != null
		and runtime_ui_context.screen == &"menu"
		and runtime_ui_context != runtime_context,
		"independent machines have isolated contexts"
	)

	runtime_context.speed = 240.0
	runtime_context.stats[&"energy"] = 7
	var run_context := run.get_context() as RecordingContext
	_expect(
		run_context.speed == 240.0
		and run_context.stats[&"energy"] == 7,
		"all States share direct runtime context writes"
	)
	_expect(
		movement_context.speed == 120.0
		and movement_context.stats[&"energy"] == 3,
		"runtime writes do not mutate the initial context Resource"
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
	var restarted_context := machine.get_context() as RecordingContext
	_expect(
		restarted_context != previous_context
		and restarted_context.speed == 120.0
		and restarted_context.stats[&"energy"] == 3,
		"restart restores the initial context"
	)

	var graph_view: GStateMachineEditor = StateMachineEditorScene.instantiate()
	get_root().add_child(graph_view)
	graph_view.set_state_manager(manager)
	_expect(
		_count_graph_nodes(graph_view) == 3,
		"root graph view displays direct child states"
	)
	_expect(
		_count_transition_graph_nodes(graph_view) == 4,
		"root graph view displays one node per scoped transition"
	)
	_expect(
		_get_graph_edit(graph_view).connections.size() == 8,
		"each root transition is displayed with two connections"
	)
	var grounded_graph_node := _find_graph_node(graph_view, grounded)
	var dead_graph_node := _find_graph_node(graph_view, dead)
	_expect(
		grounded_graph_node != null
		and grounded_graph_node.get_output_port_count() == 2,
		"State nodes expose numbered outgoing transition ports"
	)
	_expect(
		dead_graph_node != null
		and dead_graph_node.get_input_port_count() == 2,
		"State nodes expose numbered incoming transition ports"
	)
	var jump_transition_node := _find_transition_graph_node(
			graph_view,
			&"jump"
	)
	var land_transition_node := _find_transition_graph_node(
			graph_view,
			&"land"
	)
	_expect(
		jump_transition_node != null
		and jump_transition_node.get_input_port_count() == 1
		and jump_transition_node.get_output_port_count() == 1,
		"Transition nodes expose one input and one output port"
	)
	_expect(
		jump_transition_node != null
		and jump_transition_node.title == "Transition →"
		and (jump_transition_node.get_child(0) as Label).text == "jump",
		"Transition nodes use a fixed title and show the event in the body"
	)
	var grounded_second_port_row: HBoxContainer
	if grounded_graph_node != null and grounded_graph_node.get_child_count() > 3:
		grounded_second_port_row = (
				grounded_graph_node.get_child(3) as HBoxContainer
		)
	_expect(
		grounded_second_port_row != null
		and (grounded_second_port_row.get_child(1) as Label).text == "1",
		"State port rows display indexes without event names"
	)
	_expect(
		jump_transition_node != null
		and land_transition_node != null
		and jump_transition_node.position_offset
		!= land_transition_node.position_offset,
		"opposite transitions receive distinct default positions"
	)
	graph_view._show_scope(grounded)
	_expect(
		_count_graph_nodes(graph_view) == 2,
		"nested graph view displays direct child states"
	)
	_expect(
		_count_transition_graph_nodes(graph_view) == 2,
		"nested graph displays scoped transition nodes"
	)
	_expect(
		_get_graph_edit(graph_view).connections.size() == 4,
		"nested transitions are displayed with two connections each"
	)
	graph_view.queue_free()

	var duplicate := StateTransition.new(
			idle.stable_id,
			run.stable_id,
			&"move",
			grounded.stable_id
	)
	machine.graph.add_transition(duplicate)
	var cross_scope := StateTransition.new(
			run.stable_id,
			airborne.stable_id,
			&"launch",
			grounded.stable_id
	)
	machine.graph.add_transition(cross_scope)
	var invalid_result: Dictionary = machine.validate()
	var invalid_errors: PackedStringArray = invalid_result["errors"]
	_expect(
		not invalid_errors.is_empty(),
		"duplicate source event must fail validation"
	)
	_expect(
		invalid_errors.size() >= 2,
		"cross-scope transition must fail validation"
	)

	machine.stop()
	ui_machine.stop()
	_expect(not machine.is_running(), "stop() clears running state")
	_expect(machine.get_active_path().is_empty(), "stop() clears active path")
	host.queue_free()

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


func _add_state(parent: Node, state_name: StringName, id: StringName) -> State:
	var state: State = RecordingState.new()
	state.name = state_name
	state.stable_id = id
	state.calls = _calls
	parent.add_child(state)
	return state


func _add_transition(
		machine: StateMachine,
		from_state: State,
		to_state: State,
		event: StringName,
		scope: State = null
) -> void:
	var scope_id := StateTransition.ROOT_SCOPE_ID
	if scope != null:
		scope_id = scope.stable_id
	var transition := StateTransition.new(
			from_state.stable_id,
			to_state.stable_id,
			event,
			scope_id
	)
	_expect(machine.graph.add_transition(transition), "transition must be added")


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


func _count_transition_graph_nodes(editor: GStateMachineEditor) -> int:
	var count := 0
	for child: Node in _get_graph_edit(editor).get_children():
		if child is GStateTransitionGraphNode:
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


func _find_transition_graph_node(
		editor: GStateMachineEditor,
		event: StringName
) -> GStateTransitionGraphNode:
	for child: Node in _get_graph_edit(editor).get_children():
		if (
			child is GStateTransitionGraphNode
			and (child as GStateTransitionGraphNode).transition.event == event
		):
			return child as GStateTransitionGraphNode
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
