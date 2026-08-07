@tool
class_name GStateGraphCanvas
extends GraphEdit

## Owns the visual State nodes and their GraphEdit-only lookup data.

const StateGraphNodeScript := preload(
		"res://addons/gstate/editor/state_graph_node.gd"
)
const FALLBACK_ORIGIN := Vector2(80.0, 70.0)
const FALLBACK_SPACING := Vector2(460.0, 190.0)
const FALLBACK_COLUMNS := 3

signal state_scope_requested(state: State)
signal state_rename_requested(state: State)
signal state_position_drag_started
signal state_position_drag_finished

var _node_names_by_state_uid: Dictionary[StringName, StringName] = {}
var _states_by_node_name: Dictionary[StringName, State] = {}
var _graph_nodes_by_state_uid: Dictionary[StringName, GStateGraphNode] = {}


func _ready() -> void:
	minimap_enabled = false
	show_minimap_button = false
	show_arrange_button = true
	show_grid_buttons = true
	snapping_enabled = true
	right_disconnects = false
	connection_lines_antialiased = true
	connection_lines_thickness = 3.0


func rebuild(
		states: Array[State],
		initial_name: StringName,
		transitions: Array[Dictionary],
		editor_positions: Dictionary
) -> void:
	clear_state_graph()
	var outgoing_by_state: Dictionary = {}
	var incoming_by_state: Dictionary = {}
	for transition: Dictionary in transitions:
		var source_uid: StringName = transition[&"source_uid"]
		var target_uid: StringName = transition[&"target_uid"]
		_append_transition(outgoing_by_state, source_uid, transition)
		if not target_uid.is_empty():
			_append_transition(incoming_by_state, target_uid, transition)

	for index: int in range(states.size()):
		var state: State = states[index]
		if state == null:
			continue
		var graph_node: GStateGraphNode = StateGraphNodeScript.new()
		var graph_node_name := StringName("state_node_%d" % index)
		graph_node.name = graph_node_name
		graph_node.setup(
				state,
				state.name == initial_name,
				_get_state_transitions(
						outgoing_by_state,
						state.editor_uid
				),
				_get_state_transitions(
						incoming_by_state,
						state.editor_uid
				)
		)
		graph_node.position_offset = _get_state_position(
				state,
				index,
				editor_positions
		)
		graph_node.scope_requested.connect(state_scope_requested.emit)
		graph_node.rename_requested.connect(state_rename_requested.emit)
		graph_node.position_drag_started.connect(
				state_position_drag_started.emit
		)
		graph_node.position_drag_finished.connect(
				state_position_drag_finished.emit
		)
		add_child(graph_node)
		_node_names_by_state_uid[state.editor_uid] = graph_node_name
		_states_by_node_name[graph_node_name] = state
		_graph_nodes_by_state_uid[state.editor_uid] = graph_node

	for transition: Dictionary in transitions:
		_connect_transition(transition)


func clear_state_graph() -> void:
	clear_connections()
	_node_names_by_state_uid.clear()
	_states_by_node_name.clear()
	_graph_nodes_by_state_uid.clear()
	for child: Node in get_children():
		if child is GraphNode:
			child.free()


func get_state_for_node(node_name: StringName) -> State:
	return _states_by_node_name.get(node_name) as State


func get_canvas_center() -> Vector2:
	return scroll_offset + size * 0.5 / zoom


func collect_state_positions(base: Dictionary = {}) -> Dictionary:
	var positions := base.duplicate(true)
	for graph_node: GStateGraphNode in _graph_nodes_by_state_uid.values():
		if is_instance_valid(graph_node) and graph_node.state != null:
			positions[graph_node.state.editor_uid] = graph_node.position_offset
	return positions


func select_state(state: State) -> void:
	if (
		state == null
		or not _node_names_by_state_uid.has(state.editor_uid)
	):
		return
	var node_name: StringName = _node_names_by_state_uid[state.editor_uid]
	var graph_node := get_node_or_null(NodePath(str(node_name)))
	if graph_node != null:
		set_selected(graph_node)


func _append_transition(
		grouped: Dictionary,
		state_uid: StringName,
		transition: Dictionary
) -> void:
	if not grouped.has(state_uid):
		grouped[state_uid] = []
	grouped[state_uid].append(transition)


func _get_state_transitions(
		grouped: Dictionary,
		state_uid: StringName
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not grouped.has(state_uid):
		return result
	for transition: Dictionary in grouped[state_uid]:
		result.append(transition)
	return result


func _get_state_position(
		state: State,
		index: int,
		editor_positions: Dictionary
) -> Vector2:
	var column: int = index % FALLBACK_COLUMNS
	var row: int = floori(float(index) / float(FALLBACK_COLUMNS))
	var fallback := FALLBACK_ORIGIN + Vector2(
			column * FALLBACK_SPACING.x,
			row * FALLBACK_SPACING.y
	)
	var stored: Variant = editor_positions.get(state.editor_uid, fallback)
	return stored if stored is Vector2 else fallback


func _connect_transition(transition: Dictionary) -> void:
	var source_uid: StringName = transition[&"source_uid"]
	var target_uid: StringName = transition[&"target_uid"]
	if (
		not _graph_nodes_by_state_uid.has(source_uid)
		or not _graph_nodes_by_state_uid.has(target_uid)
	):
		return
	var source_node: GStateGraphNode = _graph_nodes_by_state_uid[source_uid]
	var target_node: GStateGraphNode = _graph_nodes_by_state_uid[target_uid]
	connect_node(
			source_node.name,
			source_node.get_transition_output_port(transition),
			target_node.name,
			target_node.get_transition_input_port(transition)
	)
