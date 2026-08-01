@tool
class_name GStateMachineEditor
extends Control

## Editable, scope-based GraphEdit for a StateMachine scene tree.

const StateGraphNodeScript := preload(
		"res://addons/gstate/editor/state_graph_node.gd"
)
const TransitionGraphNodeScript := preload(
		"res://addons/gstate/editor/transition_graph_node.gd"
)
const FALLBACK_ORIGIN := Vector2(80.0, 70.0)
const FALLBACK_SPACING := Vector2(460.0, 190.0)
const FALLBACK_COLUMNS := 3
const TRANSITION_NODE_SIZE := Vector2(170.0, 60.0)
const PARALLEL_TRANSITION_SPACING := 64.0
const SELF_TRANSITION_OFFSET := Vector2(270.0, -20.0)

@onready var _breadcrumb: HBoxContainer = %Breadcrumb
@onready var _machine_row: HBoxContainer = %MachineRow
@onready var _machine_option: OptionButton = %MachineOption
@onready var _add_machine_button: Button = %AddMachineButton
@onready var _back_button: Button = %BackButton
@onready var _status: Label = %Status
@onready var _scope_summary: Label = %ScopeSummary
@onready var _add_state_button: Button = %AddStateButton
@onready var _add_child_button: Button = %AddChildButton
@onready var _rename_state_button: Button = %RenameStateButton
@onready var _set_initial_button: Button = %SetInitialButton
@onready var _delete_state_button: Button = %DeleteStateButton
@onready var _transition_option: OptionButton = %TransitionOption
@onready var _edit_transition_button: Button = %EditTransitionButton
@onready var _delete_transition_button: Button = %DeleteTransitionButton
@onready var _issues_button: Button = %IssuesButton
@onready var _refresh_button: Button = %RefreshButton
@onready var _graph_edit: GraphEdit = %GraphEdit
@onready var _empty_hint: Label = %EmptyHint
@onready var _transition_dialog: ConfirmationDialog = %TransitionDialog
@onready var _event_edit: LineEdit = %EventEdit
@onready var _transition_error: Label = %TransitionError
@onready var _rename_dialog: ConfirmationDialog = %RenameDialog
@onready var _state_name_edit: LineEdit = %StateNameEdit
@onready var _rename_error: Label = %RenameError
@onready var _issues_dialog: AcceptDialog = %IssuesDialog
@onready var _issues_text: TextEdit = %IssuesText

var _state_manager: StateManager
var _state_machine: StateMachine
var _scope: State
var _selected_state: State
var _selected_transition: StateTransition
var _pending_from_state: State
var _pending_to_state: State
var _editing_transition: StateTransition
var _renaming_state: State
var _undo_redo: EditorUndoRedoManager
var _editor_interface: EditorInterface
var _node_names_by_state_id: Dictionary[StringName, StringName] = {}
var _states_by_node_name: Dictionary[StringName, State] = {}
var _graph_nodes_by_state_id: Dictionary[StringName, GStateGraphNode] = {}
var _transitions_by_node_name: Dictionary[StringName, StateTransition] = {}
var _graph_nodes_by_transition_id: Dictionary[StringName, GStateTransitionGraphNode] = {}
var _positions_before_move: Dictionary = {}
var _observed_scene_nodes: Array[Node] = []
var _refreshing: bool = false
var _refresh_queued: bool = false
var _syncing_editor_selection: bool = false


func _ready() -> void:
	_machine_option.item_selected.connect(_on_machine_selected)
	_add_machine_button.pressed.connect(_add_state_machine)
	_back_button.pressed.connect(_go_to_parent_scope)
	_add_state_button.pressed.connect(_add_state)
	_add_child_button.pressed.connect(_add_child_state)
	_rename_state_button.pressed.connect(_open_selected_state_rename)
	_set_initial_button.pressed.connect(_set_selected_initial)
	_delete_state_button.pressed.connect(_delete_selected_state)
	_transition_option.item_selected.connect(_on_transition_selected)
	_edit_transition_button.pressed.connect(_edit_selected_transition)
	_delete_transition_button.pressed.connect(_delete_selected_transition)
	_issues_button.pressed.connect(_show_validation_issues)
	_refresh_button.pressed.connect(refresh)
	_transition_dialog.confirmed.connect(_confirm_transition_dialog)
	_event_edit.text_changed.connect(_validate_pending_event)
	_rename_dialog.confirmed.connect(_confirm_state_rename)
	_state_name_edit.text_changed.connect(_validate_state_name)
	_configure_graph_edit()
	_show_placeholder()
	_update_action_buttons()


func _process(_delta: float) -> void:
	if (
		not _refreshing
		and _state_machine != null
		and _state_machine.graph != null
		and not is_equal_approx(
				_state_machine.graph.editor_zoom,
				_graph_edit.zoom
		)
	):
		_state_machine.graph.editor_zoom = _graph_edit.zoom
		_mark_scene_unsaved()


func setup_editor(
		undo_redo: EditorUndoRedoManager,
		editor_interface: EditorInterface
) -> void:
	_undo_redo = undo_redo
	_editor_interface = editor_interface
	if is_node_ready():
		_update_action_buttons()


func set_state_manager(manager: StateManager) -> void:
	_state_manager = manager
	var machines: Array[StateMachine] = []
	if manager != null:
		machines = manager.get_state_machines()
	_change_state_machine(machines[0] if not machines.is_empty() else null)


func set_state_machine(machine: StateMachine) -> void:
	_state_manager = _find_state_manager(machine)
	_change_state_machine(machine)


func clear_editor() -> void:
	_state_manager = null
	_change_state_machine(null)


func _change_state_machine(machine: StateMachine) -> void:
	if _state_machine == machine:
		_rebuild_machine_selector()
		refresh()
		return
	_save_graph_view()
	_disconnect_graph_resource()
	_disconnect_scene_observers()
	_state_machine = machine
	_scope = null
	_selected_state = null
	_selected_transition = null
	_connect_graph_resource()
	_rebuild_machine_selector()
	refresh()


func edit_state(machine: StateMachine, state: State) -> void:
	if _syncing_editor_selection:
		return
	if _state_machine != machine:
		set_state_machine(machine)
	if not _belongs_to_machine(state):
		return
	_scope = state.get_parent() as State
	_selected_state = state
	_selected_transition = null
	refresh()


func refresh() -> void:
	if not is_node_ready() or _refreshing:
		return
	_refreshing = true
	if is_instance_valid(_state_manager) and (
		not is_instance_valid(_state_machine)
		or _find_state_manager(_state_machine) != _state_manager
	):
		var machines := _state_manager.get_state_machines()
		if is_instance_valid(_state_machine):
			_disconnect_graph_resource()
		_state_machine = machines[0] if not machines.is_empty() else null
		_scope = null
		_selected_state = null
		_connect_graph_resource()
	_rebuild_machine_selector()
	_clear_graph()
	_rebuild_breadcrumb()

	if not is_instance_valid(_state_machine):
		_state_machine = null
		_scope = null
		_selected_state = null
		_show_placeholder()
		_update_action_buttons()
		_rebuild_scene_observers()
		_refreshing = false
		return
	if _scope != null and (
			not is_instance_valid(_scope) or not _belongs_to_machine(_scope)
	):
		_scope = null
		_rebuild_breadcrumb()
	if not is_instance_valid(_selected_state):
		_selected_state = null
	elif (
		not _belongs_to_machine(_selected_state)
		or _selected_state.get_parent() != _get_scope_parent()
	):
		_selected_state = null

	var states: Array[State] = _get_scope_states()
	var initial_id: StringName = _get_initial_id()
	var transitions: Array[StateTransition] = _get_scope_transitions()
	var state_names: Dictionary[StringName, String] = {}
	for state: State in states:
		state_names[state.stable_id] = str(state.name)
	if _selected_transition != null and not transitions.has(_selected_transition):
		_selected_transition = null

	var outgoing_by_state: Dictionary = {}
	var incoming_by_state: Dictionary = {}
	for transition: StateTransition in transitions:
		if transition == null:
			continue
		if not outgoing_by_state.has(transition.from_state_id):
			outgoing_by_state[transition.from_state_id] = []
		outgoing_by_state[transition.from_state_id].append(transition)
		if not incoming_by_state.has(transition.to_state_id):
			incoming_by_state[transition.to_state_id] = []
		incoming_by_state[transition.to_state_id].append(transition)

	for index: int in range(states.size()):
		var state: State = states[index]
		var graph_node: GStateGraphNode = StateGraphNodeScript.new()
		var graph_node_name := StringName("state_node_%d" % index)
		graph_node.name = graph_node_name
		graph_node.setup(
				state,
				state.stable_id == initial_id,
				_get_state_transitions(
						outgoing_by_state,
						state.stable_id
				),
				_get_state_transitions(
						incoming_by_state,
						state.stable_id
				)
		)
		graph_node.position_offset = _get_state_position(state, index)
		graph_node.scope_requested.connect(_show_scope)
		graph_node.rename_requested.connect(_open_state_rename)
		graph_node.position_drag_started.connect(_on_begin_node_move)
		graph_node.position_drag_finished.connect(_on_end_node_move)
		_graph_edit.add_child(graph_node)
		_node_names_by_state_id[state.stable_id] = graph_node_name
		_states_by_node_name[graph_node_name] = state
		_graph_nodes_by_state_id[state.stable_id] = graph_node

	for transition_index: int in range(transitions.size()):
		var transition: StateTransition = transitions[transition_index]
		if transition == null:
			continue
		if (
			not _node_names_by_state_id.has(transition.from_state_id)
			or not _node_names_by_state_id.has(transition.to_state_id)
		):
			continue
		var source_node: GStateGraphNode = _graph_nodes_by_state_id[
				transition.from_state_id
		]
		var target_node: GStateGraphNode = _graph_nodes_by_state_id[
				transition.to_state_id
		]
		var transition_node: GStateTransitionGraphNode = (
				TransitionGraphNodeScript.new()
		)
		var transition_node_name := StringName(
				"transition_node_%d" % transition_index
		)
		transition_node.name = transition_node_name
		transition_node.setup(transition)
		transition_node.position_offset = _get_transition_position(
				transition,
				transitions
		)
		transition_node.edit_requested.connect(_open_transition_edit)
		_graph_edit.add_child(transition_node)
		_transitions_by_node_name[transition_node_name] = transition
		_graph_nodes_by_transition_id[transition.id] = transition_node
		_graph_edit.connect_node(
				source_node.name,
				source_node.get_transition_output_port(transition),
				transition_node.name,
				0
		)
		_graph_edit.connect_node(
				transition_node.name,
				0,
				target_node.name,
				target_node.get_transition_input_port(transition)
		)

	_rebuild_transition_options(transitions, state_names)
	_restore_graph_view()
	_restore_graph_selection()
	_update_status(states.size(), transitions.size())
	_update_scope_summary(states)
	_update_empty_hint(states)
	_update_action_buttons()
	_rebuild_scene_observers()
	_refreshing = false


func _configure_graph_edit() -> void:
	_graph_edit.minimap_enabled = false
	_graph_edit.show_minimap_button = false
	_graph_edit.show_arrange_button = true
	_graph_edit.show_grid_buttons = true
	_graph_edit.snapping_enabled = true
	_graph_edit.right_disconnects = false
	_graph_edit.connection_lines_antialiased = true
	_graph_edit.connection_lines_thickness = 3.0
	_graph_edit.connection_request.connect(_request_transition)
	_graph_edit.delete_nodes_request.connect(_on_delete_nodes_requested)
	_graph_edit.node_selected.connect(_on_graph_node_selected)
	_graph_edit.node_deselected.connect(_on_graph_node_deselected)
	_graph_edit.begin_node_move.connect(_on_begin_node_move)
	_graph_edit.end_node_move.connect(_on_end_node_move)
	_graph_edit.scroll_offset_changed.connect(_on_scroll_offset_changed)


func _clear_graph() -> void:
	_graph_edit.clear_connections()
	_node_names_by_state_id.clear()
	_states_by_node_name.clear()
	_graph_nodes_by_state_id.clear()
	_transitions_by_node_name.clear()
	_graph_nodes_by_transition_id.clear()
	for child: Node in _graph_edit.get_children():
		if child is GraphNode:
			child.free()


func _rebuild_machine_selector() -> void:
	_machine_option.clear()
	_machine_row.visible = is_instance_valid(_state_manager)
	if not is_instance_valid(_state_manager):
		return
	for machine: StateMachine in _state_manager.get_state_machines():
		_machine_option.add_item(str(machine.name))
		_machine_option.set_item_metadata(
				_machine_option.item_count - 1,
				machine
		)
		if machine == _state_machine:
			_machine_option.select(_machine_option.item_count - 1)


func _on_machine_selected(index: int) -> void:
	if index < 0 or index >= _machine_option.item_count:
		return
	var machine := _machine_option.get_item_metadata(index) as StateMachine
	if machine != null:
		_change_state_machine(machine)
		_select_state_in_editor.call_deferred(machine)


func _add_state_machine() -> void:
	_create_state_machine(_state_manager)


func _create_state_machine(parent: Node) -> void:
	if (
		not is_instance_valid(parent)
		or not is_instance_valid(_state_manager)
		or _undo_redo == null
		or _editor_interface == null
	):
		return
	var machine := StateMachine.new()
	machine.name = &"StateMachine"
	var scene_root: Node = _editor_interface.get_edited_scene_root()
	if scene_root == null:
		return
	_undo_redo.create_action("GState: Add State Machine")
	_undo_redo.add_do_method(parent, &"add_child", machine, true)
	_undo_redo.add_do_property(machine, &"owner", scene_root)
	_undo_redo.add_do_reference(machine)
	_undo_redo.add_do_method(self, &"_after_machine_added", machine)
	_undo_redo.add_undo_method(
			self,
			&"_remove_added_machine",
			parent,
			machine,
			_state_manager
	)
	_undo_redo.add_undo_reference(machine)
	_undo_redo.commit_action()


func _after_machine_added(machine: StateMachine) -> void:
	_change_state_machine(machine)
	_select_state_in_editor.call_deferred(machine)


func _remove_added_machine(
		parent: Node,
		machine: StateMachine,
		manager: StateManager
) -> void:
	if machine.get_parent() == parent:
		parent.remove_child(machine)
	set_state_manager(manager)


func _find_state_manager(machine: StateMachine) -> StateManager:
	if machine == null:
		return null
	return machine.get_parent() as StateManager


func _add_state() -> void:
	_create_state(_get_scope_parent(), false)


func _add_child_state() -> void:
	if not is_instance_valid(_selected_state):
		return
	_create_state(_selected_state, true)


func _create_state(parent: Node, enter_child_scope: bool) -> void:
	if parent == null or _undo_redo == null or _editor_interface == null:
		return
	_ensure_graph()
	var state := State.new()
	state.name = &"NewState"
	var scene_root: Node = _editor_interface.get_edited_scene_root()
	if scene_root == null:
		return

	var initial_owner: Object = _state_machine if parent == _state_machine else parent
	var initial_property := (
			&"initial_state_id"
			if parent == _state_machine
			else &"initial_child_id"
	)
	var old_initial: StringName = initial_owner.get(initial_property)
	var should_set_initial: bool = _get_direct_state_children(parent).is_empty()
	var position := _graph_edit.scroll_offset + (
			_graph_edit.size * 0.5 / _graph_edit.zoom
	)

	_undo_redo.create_action("GState: Add State")
	_undo_redo.add_do_method(parent, &"add_child", state, true)
	_undo_redo.add_do_property(state, &"owner", scene_root)
	_undo_redo.add_do_reference(state)
	if should_set_initial:
		_undo_redo.add_do_property(
				initial_owner,
				initial_property,
				state.stable_id
		)
	_undo_redo.add_do_method(
			_state_machine.graph,
			&"set_state_position",
			state,
			position
	)
	_undo_redo.add_do_method(
			self,
			&"_after_state_added",
			state,
			parent if enter_child_scope else null
	)

	_undo_redo.add_undo_method(
			_state_machine.graph,
			&"remove_state_position",
			state
	)
	if should_set_initial:
		_undo_redo.add_undo_property(
				initial_owner,
				initial_property,
				old_initial
		)
	_undo_redo.add_undo_method(parent, &"remove_child", state)
	_undo_redo.add_undo_method(
			self,
			&"_after_added_state_removed",
			state,
			parent
	)
	_undo_redo.commit_action()
	call_deferred(&"_open_state_rename", state)


func _after_state_added(state: State, child_scope: State) -> void:
	if child_scope != null:
		_scope = child_scope
	_selected_state = state
	_selected_transition = null
	refresh()


func _after_added_state_removed(state: State, parent: Node) -> void:
	if (
		_scope == parent
		and parent is State
		and not (parent as State).is_compound()
	):
		_scope = parent.get_parent() as State
	if _selected_state == state or _is_ancestor_state(state, _selected_state):
		_selected_state = null
	refresh()


func _open_selected_state_rename() -> void:
	_open_state_rename(_selected_state)


func _open_state_rename(state: State) -> void:
	if not is_instance_valid(state) or _undo_redo == null:
		return
	_renaming_state = state
	_state_name_edit.text = str(state.name)
	_rename_error.text = ""
	_rename_dialog.get_ok_button().disabled = false
	_rename_dialog.popup_centered(Vector2i(380, 150))
	_state_name_edit.select_all()
	_state_name_edit.call_deferred(&"grab_focus")


func _validate_state_name(text: String) -> void:
	var state_name: String = text.strip_edges()
	var error := ""
	if state_name.is_empty():
		error = "State name is required."
	elif state_name.validate_node_name() != state_name:
		error = "The name contains characters that Godot does not allow."
	elif is_instance_valid(_renaming_state):
		var parent: Node = _renaming_state.get_parent()
		if parent != null:
			for child: Node in parent.get_children():
				if child != _renaming_state and str(child.name) == state_name:
					error = "A sibling already uses this name."
					break
	_rename_error.text = error
	_rename_dialog.get_ok_button().disabled = not error.is_empty()


func _confirm_state_rename() -> void:
	if not is_instance_valid(_renaming_state) or _undo_redo == null:
		return
	var new_name := StringName(_state_name_edit.text.strip_edges())
	var old_name: StringName = _renaming_state.name
	if new_name == old_name:
		return
	_undo_redo.create_action("GState: Rename State")
	_undo_redo.add_do_property(_renaming_state, &"name", new_name)
	_undo_redo.add_do_method(self, &"refresh")
	_undo_redo.add_undo_property(_renaming_state, &"name", old_name)
	_undo_redo.add_undo_method(self, &"refresh")
	_undo_redo.commit_action()


func _set_selected_initial() -> void:
	if not is_instance_valid(_selected_state) or _undo_redo == null:
		return
	_set_initial_state(_selected_state)


func _set_initial_state(state: State) -> void:
	if not is_instance_valid(state) or _undo_redo == null:
		return
	var owner: Object = _state_machine if _scope == null else _scope
	var property := (
			&"initial_state_id" if _scope == null else &"initial_child_id"
	)
	var old_value: StringName = owner.get(property)
	if old_value == state.stable_id:
		return
	_undo_redo.create_action("GState: Set Initial State")
	_undo_redo.add_do_property(owner, property, state.stable_id)
	_undo_redo.add_do_method(self, &"refresh")
	_undo_redo.add_undo_property(owner, property, old_value)
	_undo_redo.add_undo_method(self, &"refresh")
	_undo_redo.commit_action()


func _delete_selected_state() -> void:
	if not is_instance_valid(_selected_state) or _undo_redo == null:
		return
	var state: State = _selected_state
	var parent: Node = state.get_parent()
	if parent == null:
		return
	_ensure_graph()
	var scene_root: Node = _editor_interface.get_edited_scene_root()
	var state_index: int = state.get_index()
	var removed_ids: Dictionary[StringName, bool] = {}
	_collect_state_ids(state, removed_ids)

	var old_transitions: Array[StateTransition] = (
			_state_machine.graph.transitions.duplicate()
	)
	var new_transitions: Array[StateTransition] = []
	for transition: StateTransition in old_transitions:
		if (
			transition != null
			and not removed_ids.has(transition.scope_id)
			and not removed_ids.has(transition.from_state_id)
			and not removed_ids.has(transition.to_state_id)
		):
			new_transitions.append(transition)

	var old_positions: Dictionary = (
			_state_machine.graph.editor_positions.duplicate(true)
	)
	var new_positions: Dictionary = old_positions.duplicate(true)
	for id: StringName in removed_ids:
		new_positions.erase(id)
	for transition: StateTransition in old_transitions:
		if transition != null and not new_transitions.has(transition):
			new_positions.erase(
					StateMachineGraph.get_transition_position_key(transition)
			)

	var initial_owner: Object = (
			_state_machine if parent == _state_machine else parent
	)
	var initial_property := (
			&"initial_state_id"
			if parent == _state_machine
			else &"initial_child_id"
	)
	var old_initial: StringName = initial_owner.get(initial_property)
	var new_initial: StringName = old_initial
	if removed_ids.has(old_initial):
		new_initial = _find_replacement_initial(parent, state)

	_undo_redo.create_action("GState: Delete State")
	_undo_redo.add_do_property(
			_state_machine.graph,
			&"transitions",
			new_transitions
	)
	_undo_redo.add_do_property(
			_state_machine.graph,
			&"editor_positions",
			new_positions
	)
	_undo_redo.add_do_property(initial_owner, initial_property, new_initial)
	_undo_redo.add_do_method(self, &"_remove_existing_state", parent, state)
	_undo_redo.add_do_method(self, &"refresh")

	_undo_redo.add_undo_method(
			self,
			&"_restore_existing_state",
			parent,
			state,
			state_index,
			scene_root
	)
	_undo_redo.add_undo_property(initial_owner, initial_property, old_initial)
	_undo_redo.add_undo_property(
			_state_machine.graph,
			&"editor_positions",
			old_positions
	)
	_undo_redo.add_undo_property(
			_state_machine.graph,
			&"transitions",
			old_transitions
	)
	_undo_redo.add_undo_method(self, &"refresh")
	_undo_redo.add_undo_reference(state)
	_undo_redo.commit_action()


func _remove_existing_state(parent: Node, state: State) -> void:
	if _scope == state or _is_ancestor_state(state, _scope):
		_scope = parent as State
	if _selected_state == state or _is_ancestor_state(state, _selected_state):
		_selected_state = null
	if state.get_parent() == parent:
		parent.remove_child(state)


func _restore_existing_state(
		parent: Node,
		state: State,
		index: int,
		scene_root: Node
) -> void:
	if state.get_parent() == null:
		parent.add_child(state)
		parent.move_child(state, mini(index, parent.get_child_count() - 1))
	_set_owner_recursive(state, scene_root)


func _request_transition(
		from_node: StringName,
		_from_port: int,
		to_node: StringName,
		_to_port: int
) -> void:
	if (
		not _states_by_node_name.has(from_node)
		or not _states_by_node_name.has(to_node)
	):
		return
	_pending_from_state = _states_by_node_name[from_node]
	_pending_to_state = _states_by_node_name[to_node]
	_editing_transition = null
	_transition_dialog.title = "Create Transition"
	_transition_dialog.ok_button_text = "Create"
	_event_edit.clear()
	_transition_error.text = ""
	_transition_dialog.get_ok_button().disabled = true
	_transition_dialog.popup_centered(Vector2i(380, 150))
	_event_edit.call_deferred(&"grab_focus")


func _validate_pending_event(text: String) -> void:
	var event_name := StringName(text.strip_edges())
	var error := ""
	if event_name.is_empty():
		error = "Event is required."
	elif not is_instance_valid(_pending_from_state):
		error = "The transition source State no longer exists."
	elif (
		_state_machine != null
		and _state_machine.graph != null
		and _pending_from_state != null
		and _state_machine.graph.find_transition(
				_get_scope_id(),
				_pending_from_state.stable_id,
				event_name
		) != null
		and _state_machine.graph.find_transition(
				_get_scope_id(),
				_pending_from_state.stable_id,
				event_name
		) != _editing_transition
	):
		error = "This source already has a '%s' transition." % event_name
	_transition_error.text = error
	_transition_dialog.get_ok_button().disabled = not error.is_empty()


func _confirm_transition_dialog() -> void:
	if _editing_transition != null:
		_update_transition_event()
	else:
		_create_pending_transition()


func _create_pending_transition() -> void:
	if (
		_undo_redo == null
		or not is_instance_valid(_pending_from_state)
		or not is_instance_valid(_pending_to_state)
	):
		return
	var event_name := StringName(_event_edit.text.strip_edges())
	if event_name.is_empty():
		return
	_ensure_graph()
	var transition := StateTransition.new(
			_pending_from_state.stable_id,
			_pending_to_state.stable_id,
			event_name,
			_get_scope_id()
	)
	_selected_state = null
	_selected_transition = transition
	_undo_redo.create_action("GState: Add Transition")
	_undo_redo.add_do_method(
			_state_machine.graph,
			&"add_transition",
			transition
	)
	_undo_redo.add_undo_method(
			_state_machine.graph,
			&"remove_transition",
			transition
	)
	_undo_redo.commit_action()


func _edit_selected_transition() -> void:
	_open_transition_edit(_get_selected_transition())


func _open_transition_edit(transition: StateTransition) -> void:
	if transition == null:
		return
	_selected_state = null
	_selected_transition = transition
	_editing_transition = transition
	_pending_from_state = _find_state_by_id(transition.from_state_id)
	_pending_to_state = _find_state_by_id(transition.to_state_id)
	_transition_dialog.title = "Edit Transition"
	_transition_dialog.ok_button_text = "Save"
	_event_edit.text = str(transition.event)
	_validate_pending_event(_event_edit.text)
	_transition_dialog.popup_centered(Vector2i(380, 150))
	_event_edit.select_all()
	_event_edit.call_deferred(&"grab_focus")


func _update_transition_event() -> void:
	if _editing_transition == null or _undo_redo == null:
		return
	var new_event := StringName(_event_edit.text.strip_edges())
	var old_event: StringName = _editing_transition.event
	if new_event.is_empty():
		return
	if new_event == old_event:
		_editing_transition = null
		return
	_undo_redo.create_action("GState: Edit Transition")
	_undo_redo.add_do_property(_editing_transition, &"event", new_event)
	_undo_redo.add_do_method(_state_machine.graph, &"emit_changed")
	_undo_redo.add_undo_property(_editing_transition, &"event", old_event)
	_undo_redo.add_undo_method(_state_machine.graph, &"emit_changed")
	_undo_redo.commit_action()
	_editing_transition = null


func _delete_selected_transition() -> void:
	if _undo_redo == null:
		return
	var transition := _get_selected_transition()
	if transition == null:
		return
	var old_positions: Dictionary = (
			_state_machine.graph.editor_positions.duplicate(true)
	)
	var new_positions: Dictionary = old_positions.duplicate(true)
	new_positions.erase(
			StateMachineGraph.get_transition_position_key(transition)
	)
	_selected_transition = null
	_undo_redo.create_action("GState: Delete Transition")
	_undo_redo.add_do_method(
			_state_machine.graph,
			&"remove_transition",
			transition
	)
	_undo_redo.add_do_property(
			_state_machine.graph,
			&"editor_positions",
			new_positions
	)
	_undo_redo.add_undo_property(
			_state_machine.graph,
			&"editor_positions",
			old_positions
	)
	_undo_redo.add_undo_method(
			_state_machine.graph,
			&"add_transition",
			transition
	)
	_undo_redo.commit_action()


func _on_delete_nodes_requested(nodes: Array[StringName]) -> void:
	for node_name: StringName in nodes:
		if _transitions_by_node_name.has(node_name):
			_selected_state = null
			_selected_transition = _transitions_by_node_name[node_name]
			_delete_selected_transition()
			return
		if _states_by_node_name.has(node_name):
			_selected_transition = null
			_selected_state = _states_by_node_name[node_name]
			_delete_selected_state()
			return


func _on_graph_node_selected(node: Node) -> void:
	if _refreshing:
		return
	if node is GStateGraphNode:
		_selected_transition = null
		_selected_state = (node as GStateGraphNode).state
		_update_action_buttons()
		_select_state_in_editor.call_deferred(_selected_state)
	elif node is GStateTransitionGraphNode:
		_selected_state = null
		_selected_transition = (
				node as GStateTransitionGraphNode
		).transition
		_select_transition_option(_selected_transition)
		_update_action_buttons()


func _on_graph_node_deselected(node: Node) -> void:
	if _refreshing:
		return
	if (
		node is GStateGraphNode
		and _selected_state == (node as GStateGraphNode).state
	):
		_selected_state = null
		_update_action_buttons()
	elif (
		node is GStateTransitionGraphNode
		and _selected_transition
		== (node as GStateTransitionGraphNode).transition
	):
		_selected_transition = null
		_update_action_buttons()


func _select_state_in_editor(node: Node) -> void:
	if (
		_editor_interface == null
		or not is_instance_valid(node)
		or _syncing_editor_selection
	):
		return
	_syncing_editor_selection = true
	var selection: EditorSelection = _editor_interface.get_selection()
	selection.clear()
	selection.add_node(node)
	_editor_interface.edit_node(node)
	_syncing_editor_selection = false


func _on_begin_node_move() -> void:
	if _state_machine != null and _state_machine.graph != null:
		_positions_before_move = (
				_state_machine.graph.editor_positions.duplicate(true)
		)


func _on_end_node_move() -> void:
	if _state_machine == null or _state_machine.graph == null:
		return
	var new_positions: Dictionary = (
			_state_machine.graph.editor_positions.duplicate(true)
	)
	for child: Node in _graph_edit.get_children():
		if child is GStateGraphNode:
			var graph_node := child as GStateGraphNode
			new_positions[graph_node.state.stable_id] = graph_node.position_offset
		elif child is GStateTransitionGraphNode:
			var transition_node := child as GStateTransitionGraphNode
			new_positions[
					StateMachineGraph.get_transition_position_key(
							transition_node.transition
					)
			] = transition_node.position_offset
	if new_positions == _positions_before_move:
		return
	if _undo_redo == null:
		_state_machine.graph.editor_positions = new_positions
		_mark_scene_unsaved()
		return
	_undo_redo.create_action("GState: Move Graph Nodes")
	_undo_redo.add_do_property(
			_state_machine.graph,
			&"editor_positions",
			new_positions
	)
	_undo_redo.add_do_method(self, &"refresh")
	_undo_redo.add_undo_property(
			_state_machine.graph,
			&"editor_positions",
			_positions_before_move
	)
	_undo_redo.add_undo_method(self, &"refresh")
	_undo_redo.commit_action()


func _on_scroll_offset_changed(offset: Vector2) -> void:
	if _refreshing or _state_machine == null or _state_machine.graph == null:
		return
	_state_machine.graph.editor_scroll = offset
	_mark_scene_unsaved()


func _save_graph_view() -> void:
	if _state_machine == null or _state_machine.graph == null:
		return
	var changed := (
			_state_machine.graph.editor_scroll != _graph_edit.scroll_offset
			or not is_equal_approx(
					_state_machine.graph.editor_zoom,
					_graph_edit.zoom
			)
	)
	if not changed:
		return
	_state_machine.graph.editor_scroll = _graph_edit.scroll_offset
	_state_machine.graph.editor_zoom = _graph_edit.zoom
	_mark_scene_unsaved()


func _show_scope(state: State) -> void:
	if state != null and (not state.is_compound() or not _belongs_to_machine(state)):
		return
	_save_graph_view()
	_scope = state
	_selected_state = null
	_selected_transition = null
	refresh()


func _go_to_parent_scope() -> void:
	if _scope == null:
		return
	_show_scope(_scope.get_parent() as State)


func _rebuild_breadcrumb() -> void:
	for child: Node in _breadcrumb.get_children():
		child.free()
	var root_button := Button.new()
	root_button.text = "Root"
	root_button.flat = true
	root_button.disabled = _scope == null
	root_button.pressed.connect(_show_scope.bind(null))
	_breadcrumb.add_child(root_button)
	if _scope == null:
		return

	var scope_path: Array[State] = []
	var cursor: Node = _scope
	while cursor is State:
		scope_path.push_front(cursor as State)
		cursor = cursor.get_parent()
	for state: State in scope_path:
		var separator := Label.new()
		separator.text = "›"
		separator.modulate = Color(0.62, 0.65, 0.7)
		_breadcrumb.add_child(separator)
		var scope_button := Button.new()
		scope_button.text = str(state.name)
		scope_button.flat = true
		scope_button.disabled = state == _scope
		scope_button.pressed.connect(_show_scope.bind(state))
		_breadcrumb.add_child(scope_button)


func _rebuild_transition_options(
		transitions: Array[StateTransition],
		state_names: Dictionary
) -> void:
	_transition_option.clear()
	for transition: StateTransition in transitions:
		if transition == null:
			continue
		var from_name: String = state_names.get(
				transition.from_state_id,
				str(transition.from_state_id)
		)
		var to_name: String = state_names.get(
				transition.to_state_id,
				str(transition.to_state_id)
		)
		_transition_option.add_item(
				"%s: %s → %s" % [transition.event, from_name, to_name]
		)
		_transition_option.set_item_metadata(
				_transition_option.item_count - 1,
				transition
		)
		if transition == _selected_transition:
			_transition_option.select(_transition_option.item_count - 1)
	_delete_transition_button.disabled = _transition_option.item_count == 0
	_edit_transition_button.disabled = _transition_option.item_count == 0


func _on_transition_selected(index: int) -> void:
	if index >= 0 and index < _transition_option.item_count:
		_selected_state = null
		_selected_transition = _transition_option.get_item_metadata(index)
		if (
			_selected_transition != null
			and _graph_nodes_by_transition_id.has(_selected_transition.id)
		):
			_graph_edit.set_selected(
					_graph_nodes_by_transition_id[_selected_transition.id]
			)
	_delete_transition_button.disabled = _transition_option.item_count == 0
	_edit_transition_button.disabled = _transition_option.item_count == 0
	_update_action_buttons()


func _select_transition_option(transition: StateTransition) -> void:
	for index: int in range(_transition_option.item_count):
		if _transition_option.get_item_metadata(index) == transition:
			_transition_option.select(index)
			return


func _get_selected_transition() -> StateTransition:
	if _selected_transition != null:
		return _selected_transition
	if _transition_option.selected < 0 or _transition_option.item_count == 0:
		return null
	return _transition_option.get_item_metadata(_transition_option.selected)


func _get_scope_states() -> Array[State]:
	return _get_direct_state_children(_get_scope_parent())


func _get_direct_state_children(parent: Node) -> Array[State]:
	var states: Array[State] = []
	if parent == null:
		return states
	for child: Node in parent.get_children():
		if child is State:
			states.append(child as State)
	return states


func _get_scope_parent() -> Node:
	return _scope if _scope != null else _state_machine


func _get_scope_id() -> StringName:
	return (
			_scope.stable_id
			if _scope != null
			else StateTransition.ROOT_SCOPE_ID
	)


func _get_initial_id() -> StringName:
	return (
			_scope.initial_child_id
			if _scope != null
			else _state_machine.initial_state_id
	)


func _get_scope_transitions() -> Array[StateTransition]:
	if _state_machine.graph == null:
		return []
	return _state_machine.graph.get_transitions_for_scope(_get_scope_id())


func _get_state_transitions(
		transitions_by_state: Dictionary,
		state_id: StringName
) -> Array[StateTransition]:
	var result: Array[StateTransition] = []
	if not transitions_by_state.has(state_id):
		return result
	for transition: StateTransition in transitions_by_state[state_id]:
		result.append(transition)
	return result


func _get_state_position(state: State, index: int) -> Vector2:
	var column: int = index % FALLBACK_COLUMNS
	var row: int = floori(float(index) / float(FALLBACK_COLUMNS))
	var fallback := FALLBACK_ORIGIN + Vector2(
			column * FALLBACK_SPACING.x,
			row * FALLBACK_SPACING.y
	)
	if _state_machine.graph == null:
		return fallback
	return _state_machine.graph.get_state_position(state, fallback)


func _get_transition_position(
		transition: StateTransition,
		transitions: Array[StateTransition]
) -> Vector2:
	var fallback := _get_default_transition_position(
			transition,
			transitions
	)
	if _state_machine.graph == null:
		return fallback
	return _state_machine.graph.get_transition_position(
			transition,
			fallback
	)


func _get_default_transition_position(
		transition: StateTransition,
		transitions: Array[StateTransition]
) -> Vector2:
	var source_node: GStateGraphNode = _graph_nodes_by_state_id[
			transition.from_state_id
	]
	var target_node: GStateGraphNode = _graph_nodes_by_state_id[
			transition.to_state_id
	]
	var siblings: Array[StateTransition] = []
	var pair_key := _get_transition_pair_key(transition)
	for candidate: StateTransition in transitions:
		if (
			candidate != null
			and _get_transition_pair_key(candidate) == pair_key
		):
			siblings.append(candidate)
	var lane_index: int = siblings.find(transition)
	var lane_offset := (
			float(lane_index) - float(siblings.size() - 1) * 0.5
	) * PARALLEL_TRANSITION_SPACING

	if transition.from_state_id == transition.to_state_id:
		return (
				source_node.position_offset
				+ SELF_TRANSITION_OFFSET
				+ Vector2(0.0, lane_offset)
		)

	var source_center := (
			source_node.position_offset
			+ source_node.get_combined_minimum_size() * 0.5
	)
	var target_center := (
			target_node.position_offset
			+ target_node.get_combined_minimum_size() * 0.5
	)
	var direction := target_center - source_center
	var pair_ids := PackedStringArray([
		str(transition.from_state_id),
		str(transition.to_state_id),
	])
	pair_ids.sort()
	if str(transition.from_state_id) != pair_ids[0]:
		direction = -direction
	var normal := Vector2(-direction.y, direction.x).normalized()
	return (
			(source_center + target_center) * 0.5
			- TRANSITION_NODE_SIZE * 0.5
			+ normal * lane_offset
	)


func _get_transition_pair_key(transition: StateTransition) -> String:
	var ids := PackedStringArray([
		str(transition.from_state_id),
		str(transition.to_state_id),
	])
	ids.sort()
	return "%s|%s" % [ids[0], ids[1]]


func _restore_graph_view() -> void:
	if _state_machine.graph == null:
		_graph_edit.scroll_offset = Vector2.ZERO
		_graph_edit.zoom = 1.0
		return
	_graph_edit.scroll_offset = _state_machine.graph.editor_scroll
	_graph_edit.zoom = clampf(
			_state_machine.graph.editor_zoom,
			_graph_edit.zoom_min,
			_graph_edit.zoom_max
	)


func _restore_graph_selection() -> void:
	if (
		_selected_transition != null
		and _graph_nodes_by_transition_id.has(_selected_transition.id)
	):
		_graph_edit.set_selected(
				_graph_nodes_by_transition_id[_selected_transition.id]
		)
		return
	if (
		_selected_state != null
		and _node_names_by_state_id.has(_selected_state.stable_id)
	):
		var node: Node = _graph_edit.get_node(
				NodePath(str(_node_names_by_state_id[_selected_state.stable_id]))
		)
		_graph_edit.set_selected(node)


func _update_status(state_count: int, transition_count: int) -> void:
	var validation: Dictionary = _state_machine.validate()
	var errors: PackedStringArray = validation["errors"]
	var warnings: PackedStringArray = validation["warnings"]
	var scope_name := "Root" if _scope == null else str(_scope.name)
	var messages := PackedStringArray()
	for error: String in errors:
		messages.append("ERROR  %s" % error)
	for warning: String in warnings:
		messages.append("WARNING  %s" % warning)
	_issues_text.text = "\n\n".join(messages)
	_issues_button.visible = not messages.is_empty()
	_issues_button.text = "Issues (%d)" % messages.size()
	if errors.is_empty() and warnings.is_empty():
		_status.text = "%s · %d states · %d transitions" % [
			scope_name,
			state_count,
			transition_count,
		]
		_status.tooltip_text = "Graph is valid"
		return
	_status.text = "%s · ⚠ %d errors · %d warnings" % [
		scope_name,
		errors.size(),
		warnings.size(),
	]
	_status.tooltip_text = "\n".join(messages)


func _update_scope_summary(states: Array[State]) -> void:
	var initial_name := "Not set"
	var initial_id: StringName = _get_initial_id()
	for state: State in states:
		if state.stable_id == initial_id:
			initial_name = str(state.name)
			break

	if _scope == null:
		_scope_summary.text = "Initial: %s" % initial_name
		_scope_summary.tooltip_text = (
				"The StateMachine starts in this root State."
		)
		return

	var exit_events := _get_scope_exit_events()
	var exit_text := (
			", ".join(exit_events)
			if not exit_events.is_empty()
			else "None"
	)
	_scope_summary.text = "Initial: %s    ·    Exit events: %s" % [
		initial_name,
		exit_text,
	]
	_scope_summary.tooltip_text = (
			"This is the compound State's Initial Child.\n"
			+ "Exit events are outgoing transitions from %s in its parent scope."
			% _scope.name
	)


func _get_scope_exit_events() -> PackedStringArray:
	var result := PackedStringArray()
	if _scope == null or _state_machine.graph == null:
		return result
	var parent_state := _scope.get_parent() as State
	var parent_scope_id := (
			parent_state.stable_id
			if parent_state != null
			else StateTransition.ROOT_SCOPE_ID
	)
	var parent_transitions: Array[StateTransition] = (
			_state_machine.graph.get_transitions_for_scope(parent_scope_id)
	)
	for transition: StateTransition in parent_transitions:
		if (
			transition != null
			and transition.from_state_id == _scope.stable_id
			and not result.has(str(transition.event))
		):
			result.append(str(transition.event))
	return result


func _show_validation_issues() -> void:
	if _issues_text.text.is_empty():
		return
	_issues_dialog.popup_centered(Vector2i(620, 360))


func _show_placeholder() -> void:
	_status.text = (
			"Add or choose a StateMachine"
			if is_instance_valid(_state_manager)
			else "Select a StateManager or StateMachine"
	)
	_status.tooltip_text = ""
	_transition_option.clear()
	_issues_button.hide()
	_scope_summary.text = ""
	_scope_summary.tooltip_text = ""
	_empty_hint.hide()


func _update_empty_hint(states: Array[State]) -> void:
	_empty_hint.visible = states.is_empty()
	if not states.is_empty():
		return
	if _scope == null:
		_empty_hint.text = (
				"No states yet\n"
				+ "Click + State Here to create the initial state"
		)
	else:
		_empty_hint.text = (
				"%s has no child states yet\n"
				+ "Click + State Here to create its initial child"
		) % _scope.name


func _update_action_buttons() -> void:
	var can_edit: bool = (
			_state_machine != null
			and _undo_redo != null
			and _editor_interface != null
	)
	_add_machine_button.disabled = (
			not is_instance_valid(_state_manager)
			or _undo_redo == null
			or _editor_interface == null
	)
	_add_state_button.disabled = not can_edit
	_add_state_button.text = "+ State Here"
	_add_state_button.tooltip_text = (
			"Add a root State"
			if _scope == null
			else "Add a child State inside %s" % _scope.name
	)
	_add_child_button.disabled = not can_edit or _selected_state == null
	_add_child_button.text = (
			"+ Child of %s" % _selected_state.name
			if is_instance_valid(_selected_state)
			else "+ Child State"
	)
	_back_button.disabled = not can_edit or _scope == null
	_rename_state_button.disabled = not can_edit or _selected_state == null
	_set_initial_button.disabled = not can_edit or _selected_state == null
	_set_initial_button.tooltip_text = (
			"Set the selected State as initial in Root"
			if _scope == null
			else "Set the selected State as initial inside %s" % _scope.name
	)
	_delete_state_button.disabled = not can_edit or _selected_state == null
	_edit_transition_button.disabled = (
			not can_edit or _transition_option.item_count == 0
	)
	_delete_transition_button.disabled = (
			not can_edit or _transition_option.item_count == 0
	)


func _ensure_graph() -> void:
	if _state_machine.graph == null:
		_state_machine.graph = StateMachineGraph.new()
		_connect_graph_resource()
		_mark_scene_unsaved()


func _mark_scene_unsaved() -> void:
	if _editor_interface != null:
		_editor_interface.mark_scene_as_unsaved()


func _find_replacement_initial(parent: Node, removed: State) -> StringName:
	for child: Node in parent.get_children():
		if child is State and child != removed:
			return (child as State).stable_id
	return &""


func _find_state_by_id(state_id: StringName) -> State:
	if _state_machine == null:
		return null
	var pending: Array[Node] = [_state_machine]
	while not pending.is_empty():
		var parent: Node = pending.pop_back()
		for child: Node in parent.get_children():
			if child is State:
				var state := child as State
				if state.stable_id == state_id:
					return state
				pending.append(state)
	return null


func _collect_state_ids(
		state: State,
		result: Dictionary[StringName, bool]
) -> void:
	result[state.stable_id] = true
	for child: State in state.get_state_children():
		_collect_state_ids(child, result)


func _set_owner_recursive(node: Node, owner: Node) -> void:
	node.owner = owner
	for child: Node in node.get_children():
		_set_owner_recursive(child, owner)


func _is_ancestor_state(ancestor: State, state: State) -> bool:
	if not is_instance_valid(ancestor) or not is_instance_valid(state):
		return false
	var cursor: Node = state.get_parent()
	while cursor is State:
		if cursor == ancestor:
			return true
		cursor = cursor.get_parent()
	return false


func _rebuild_scene_observers() -> void:
	_disconnect_scene_observers()
	if is_instance_valid(_state_manager):
		_observe_scene_node(_state_manager)
		for machine: StateMachine in _state_manager.get_state_machines():
			_observe_scene_node(machine)
	if _state_machine == null:
		return
	_observe_scene_node(_state_machine)
	var pending: Array[Node] = [_state_machine]
	while not pending.is_empty():
		var parent: Node = pending.pop_back()
		for child: Node in parent.get_children():
			if child is State:
				_observe_scene_node(child)
				pending.append(child)


func _observe_scene_node(node: Node) -> void:
	if _observed_scene_nodes.has(node):
		return
	_observed_scene_nodes.append(node)
	if not node.renamed.is_connected(_queue_scene_refresh):
		node.renamed.connect(_queue_scene_refresh)
	if not node.child_order_changed.is_connected(_queue_scene_refresh):
		node.child_order_changed.connect(_queue_scene_refresh)
	if not node.tree_exiting.is_connected(_queue_scene_refresh):
		node.tree_exiting.connect(_queue_scene_refresh)


func _disconnect_scene_observers() -> void:
	for node: Node in _observed_scene_nodes:
		if not is_instance_valid(node):
			continue
		if node.renamed.is_connected(_queue_scene_refresh):
			node.renamed.disconnect(_queue_scene_refresh)
		if node.child_order_changed.is_connected(_queue_scene_refresh):
			node.child_order_changed.disconnect(_queue_scene_refresh)
		if node.tree_exiting.is_connected(_queue_scene_refresh):
			node.tree_exiting.disconnect(_queue_scene_refresh)
	_observed_scene_nodes.clear()


func _queue_scene_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_run_queued_refresh.call_deferred()


func _run_queued_refresh() -> void:
	_refresh_queued = false
	refresh()


func _belongs_to_machine(state: State) -> bool:
	var cursor: Node = state
	while cursor != null and cursor is State:
		cursor = cursor.get_parent()
	return cursor == _state_machine


func _connect_graph_resource() -> void:
	if (
		_state_machine != null
		and _state_machine.graph != null
		and not _state_machine.graph.changed.is_connected(refresh)
	):
		_state_machine.graph.changed.connect(refresh)


func _disconnect_graph_resource() -> void:
	if (
		_state_machine != null
		and _state_machine.graph != null
		and _state_machine.graph.changed.is_connected(refresh)
	):
		_state_machine.graph.changed.disconnect(refresh)
