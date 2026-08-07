@tool
class_name GStateMachineEditor
extends Control

## Editable, scope-based GraphEdit for a StateMachine scene tree.

@onready var _breadcrumb: HBoxContainer = %Breadcrumb
@onready var _machine_row: HBoxContainer = %MachineRow
@onready var _machine_option: OptionButton = %MachineOption
@onready var _add_machine_button: Button = %AddMachineButton
@onready var _definition_toolbar = %DefinitionRow
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
@onready var _graph_edit = %GraphEdit
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
var _pending_from_state: State
var _pending_to_state: State
var _editing_transition: Dictionary = {}
var _renaming_state: State
var _undo_redo: EditorUndoRedoManager
var _editor_interface: EditorInterface
var _positions_before_move: Dictionary = {}
var _observed_scene_nodes: Array[Node] = []
var _observed_state_resources: Array[State] = []
var _observed_definition: StateMachineResource
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
	_definition_toolbar.definition_replaced.connect(
			_on_definition_toolbar_replaced
	)
	_definition_toolbar.setup(_editor_interface, _undo_redo)
	_configure_graph_edit()
	_show_placeholder()
	_update_action_buttons()


func _exit_tree() -> void:
	_disconnect_graph_resource()
	_disconnect_scene_observers()


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
		_definition_toolbar.setup(_editor_interface, _undo_redo)
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
	_definition_toolbar.set_state_machine(machine)
	_scope = null
	_selected_state = null
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
	_scope = machine.definition.find_parent_state(state)
	_selected_state = state
	refresh()


func edit_resource_object(resource: Resource) -> void:
	if _state_machine == null or _state_machine.definition == null:
		return
	if resource == _state_machine.definition:
		_selected_state = null
	elif resource is State and _belongs_to_machine(resource as State):
		var state := resource as State
		_scope = _get_state_parent(state)
		_selected_state = state
	else:
		return
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
		or _get_state_parent(_selected_state) != _scope
	):
		_selected_state = null

	var states: Array[State] = _get_scope_states()
	var initial_name: StringName = _get_initial_name()
	var transitions: Array[Dictionary] = _get_scope_transitions()
	var state_names: Dictionary[StringName, String] = {}
	for state: State in states:
		state_names[state.editor_uid] = str(state.name)
	var editor_positions: Dictionary = (
		_state_machine.graph.editor_positions
		if _state_machine.graph != null
		else {}
	)
	_graph_edit.rebuild(
			states,
			initial_name,
			transitions,
			editor_positions
	)

	_rebuild_transition_options(transitions, state_names)
	_restore_graph_view()
	_restore_graph_selection()
	_update_status(states.size(), transitions.size())
	_update_scope_summary(states)
	_update_empty_hint(states)
	_update_action_buttons()
	_rebuild_scene_observers()
	_connect_graph_resource()
	_refreshing = false


func _configure_graph_edit() -> void:
	_graph_edit.connection_request.connect(_request_transition)
	_graph_edit.delete_nodes_request.connect(_on_delete_nodes_requested)
	_graph_edit.node_selected.connect(_on_graph_node_selected)
	_graph_edit.node_deselected.connect(_on_graph_node_deselected)
	_graph_edit.begin_node_move.connect(_on_begin_node_move)
	_graph_edit.end_node_move.connect(_on_end_node_move)
	_graph_edit.scroll_offset_changed.connect(_on_scroll_offset_changed)
	_graph_edit.state_scope_requested.connect(_show_scope)
	_graph_edit.state_rename_requested.connect(_open_state_rename)
	_graph_edit.state_position_drag_started.connect(_on_begin_node_move)
	_graph_edit.state_position_drag_finished.connect(_on_end_node_move)


func _clear_graph() -> void:
	_graph_edit.clear_state_graph()


func _on_definition_toolbar_replaced(
		definition: StateMachineResource
) -> void:
	_scope = null
	_selected_state = null
	refresh()
	if definition != null:
		_select_state_in_editor.call_deferred(definition)


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


func _create_state(parent: Variant, enter_child_scope: bool) -> void:
	if _state_machine == null or _undo_redo == null:
		return
	_ensure_graph()
	var state := State.new()
	state.name = &"NewState"
	var state_owner: Object = (
			parent as State
			if parent is State
			else _state_machine.definition
	)
	var states_property := &"children" if parent is State else &"states"
	var old_states: Array[State] = _get_direct_state_children(parent)
	var new_states: Array[State] = old_states.duplicate()
	new_states.append(state)
	var initial_owner: Object = state_owner
	var initial_property := (
			&"initial_state"
			if parent == null
			else &"initial_child"
	)
	var old_initial: StringName = initial_owner.get(initial_property)
	var should_set_initial := old_states.is_empty()
	var position: Vector2 = _graph_edit.get_canvas_center()

	_undo_redo.create_action("GState: Add State")
	_undo_redo.add_do_property(state_owner, states_property, new_states)
	_undo_redo.add_do_reference(state)
	if should_set_initial:
		_undo_redo.add_do_property(
				initial_owner,
				initial_property,
				state.name
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
			parent as State if enter_child_scope and parent is State else null
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
	_undo_redo.add_undo_property(state_owner, states_property, old_states)
	_undo_redo.add_undo_method(
			self,
			&"_after_added_state_removed",
			state,
			parent as State if parent is State else null
	)
	_undo_redo.commit_action()
	call_deferred(&"_open_state_rename", state)


func _after_state_added(state: State, child_scope: State) -> void:
	if child_scope != null:
		_scope = child_scope
	_selected_state = state
	refresh()


func _after_added_state_removed(state: State, parent: State) -> void:
	if (
		_scope == parent
		and parent != null
		and not parent.is_compound()
	):
		_scope = _get_state_parent(parent)
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
		var parent := _get_state_parent(_renaming_state)
		for child: State in _get_direct_state_children(parent):
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
	var owner: Object = (
			_state_machine.definition if _scope == null else _scope
	)
	var property := (
			&"initial_state" if _scope == null else &"initial_child"
	)
	var old_value: StringName = owner.get(property)
	if old_value == state.name:
		return
	_undo_redo.create_action("GState: Set Initial State")
	_undo_redo.add_do_property(owner, property, state.name)
	_undo_redo.add_do_method(self, &"refresh")
	_undo_redo.add_undo_property(owner, property, old_value)
	_undo_redo.add_undo_method(self, &"refresh")
	_undo_redo.commit_action()


func _delete_selected_state() -> void:
	if not is_instance_valid(_selected_state) or _undo_redo == null:
		return
	var state: State = _selected_state
	var parent := _get_state_parent(state)
	var state_owner: Object = (
			parent if parent != null else _state_machine.definition
	)
	var states_property := &"children" if parent != null else &"states"
	var old_states := _get_direct_state_children(parent)
	var new_states: Array[State] = old_states.duplicate()
	new_states.erase(state)
	_ensure_graph()
	var removed_uids: Dictionary[StringName, bool] = {}
	_collect_state_uids(state, removed_uids)

	var transition_changes: Array[Dictionary] = []
	for candidate: State in old_states:
		if candidate == null or candidate == state:
			continue
		var old_map: Dictionary = candidate.transitions.duplicate(true)
		var new_map: Dictionary = old_map.duplicate(true)
		for event: StringName in old_map:
			var target_name: StringName = old_map[event]
			if target_name == state.name:
				new_map.erase(event)
		if new_map != old_map:
			transition_changes.append({
				&"state": candidate,
				&"old": old_map,
				&"new": new_map,
			})

	var old_positions: Dictionary = (
			_state_machine.graph.editor_positions.duplicate(true)
	)
	var new_positions: Dictionary = old_positions.duplicate(true)
	for uid: StringName in removed_uids:
		new_positions.erase(uid)

	var initial_owner: Object = (
			parent if parent != null else _state_machine.definition
	)
	var initial_property := (
			&"initial_state"
			if parent == null
			else &"initial_child"
	)
	var old_initial: StringName = initial_owner.get(initial_property)
	var new_initial: StringName = old_initial
	if old_initial == state.name:
		new_initial = new_states[0].name if not new_states.is_empty() else &""

	_undo_redo.create_action("GState: Delete State")
	_undo_redo.add_do_property(state_owner, states_property, new_states)
	for change: Dictionary in transition_changes:
		_undo_redo.add_do_property(
				change[&"state"],
				&"transitions",
				change[&"new"]
		)
	_undo_redo.add_do_property(
			_state_machine.graph,
			&"editor_positions",
			new_positions
	)
	_undo_redo.add_do_property(initial_owner, initial_property, new_initial)
	_undo_redo.add_do_method(self, &"_after_state_deleted", state, parent)
	_undo_redo.add_do_method(self, &"refresh")

	_undo_redo.add_undo_property(state_owner, states_property, old_states)
	_undo_redo.add_undo_property(initial_owner, initial_property, old_initial)
	_undo_redo.add_undo_property(
			_state_machine.graph,
			&"editor_positions",
			old_positions
	)
	for change: Dictionary in transition_changes:
		_undo_redo.add_undo_property(
				change[&"state"],
				&"transitions",
				change[&"old"]
		)
	_undo_redo.add_undo_method(self, &"refresh")
	_undo_redo.add_undo_reference(state)
	_undo_redo.commit_action()


func _after_state_deleted(state: State, parent: State) -> void:
	if _scope == state or _is_ancestor_state(state, _scope):
		_scope = parent
	if _selected_state == state or _is_ancestor_state(state, _selected_state):
		_selected_state = null


func _request_transition(
		from_node: StringName,
		_from_port: int,
		to_node: StringName,
		_to_port: int
) -> void:
	var from_state: State = _graph_edit.get_state_for_node(from_node)
	var to_state: State = _graph_edit.get_state_for_node(to_node)
	if not is_instance_valid(from_state) or not is_instance_valid(to_state):
		return
	_pending_from_state = from_state
	_pending_to_state = to_state
	_editing_transition.clear()
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
		is_instance_valid(_pending_from_state)
		and _pending_from_state.transitions.has(event_name)
		and (
			_editing_transition.is_empty()
			or _editing_transition.get(&"event", &"") != event_name
		)
	):
		error = "This source already has a '%s' transition." % event_name
	_transition_error.text = error
	_transition_dialog.get_ok_button().disabled = not error.is_empty()


func _confirm_transition_dialog() -> void:
	if not _editing_transition.is_empty():
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
	var old_transitions: Dictionary = (
			_pending_from_state.transitions.duplicate(true)
	)
	var new_transitions: Dictionary = old_transitions.duplicate(true)
	new_transitions[event_name] = _pending_to_state.name
	_selected_state = null
	_undo_redo.create_action("GState: Add Transition")
	_undo_redo.add_do_property(
			_pending_from_state,
			&"transitions",
			new_transitions
	)
	_undo_redo.add_undo_property(
			_pending_from_state,
			&"transitions",
			old_transitions
	)
	_undo_redo.commit_action()


func _edit_selected_transition() -> void:
	if _transition_option.selected < 0 or _transition_option.item_count == 0:
		return
	var transition: Dictionary = _transition_option.get_item_metadata(
			_transition_option.selected
	)
	if transition.is_empty():
		return
	_selected_state = null
	_editing_transition = transition.duplicate()
	_pending_from_state = transition[&"source"] as State
	_pending_to_state = _find_scope_state_by_name(transition[&"target_name"])
	_transition_dialog.title = "Edit Transition"
	_transition_dialog.ok_button_text = "Save"
	_event_edit.text = str(transition[&"event"])
	_validate_pending_event(_event_edit.text)
	_transition_dialog.popup_centered(Vector2i(380, 150))
	_event_edit.select_all()
	_event_edit.call_deferred(&"grab_focus")


func _update_transition_event() -> void:
	if _editing_transition.is_empty() or _undo_redo == null:
		return
	var new_event := StringName(_event_edit.text.strip_edges())
	var old_event: StringName = _editing_transition[&"event"]
	if new_event.is_empty():
		return
	if new_event == old_event:
		_editing_transition.clear()
		return
	var source := _editing_transition[&"source"] as State
	if not is_instance_valid(source):
		_editing_transition.clear()
		return
	var old_transitions: Dictionary = source.transitions.duplicate(true)
	var new_transitions: Dictionary = old_transitions.duplicate(true)
	var target_name: StringName = new_transitions.get(old_event, &"")
	new_transitions.erase(old_event)
	new_transitions[new_event] = target_name
	_undo_redo.create_action("GState: Edit Transition")
	_undo_redo.add_do_property(source, &"transitions", new_transitions)
	_undo_redo.add_undo_property(source, &"transitions", old_transitions)
	_undo_redo.commit_action()
	_editing_transition.clear()


func _delete_selected_transition() -> void:
	if (
		_undo_redo == null
		or _transition_option.selected < 0
		or _transition_option.item_count == 0
	):
		return
	var transition: Dictionary = _transition_option.get_item_metadata(
			_transition_option.selected
	)
	if transition.is_empty():
		return
	var source := transition[&"source"] as State
	if not is_instance_valid(source):
		return
	var event: StringName = transition[&"event"]
	var old_transitions: Dictionary = source.transitions.duplicate(true)
	var new_transitions: Dictionary = old_transitions.duplicate(true)
	new_transitions.erase(event)
	_undo_redo.create_action("GState: Delete Transition")
	_undo_redo.add_do_property(source, &"transitions", new_transitions)
	_undo_redo.add_undo_property(source, &"transitions", old_transitions)
	_undo_redo.commit_action()


func _on_delete_nodes_requested(nodes: Array[StringName]) -> void:
	for node_name: StringName in nodes:
		var state: State = _graph_edit.get_state_for_node(node_name)
		if is_instance_valid(state):
			_selected_state = state
			_delete_selected_state()
			return


func _on_graph_node_selected(node: Node) -> void:
	if _refreshing:
		return
	if node is GStateGraphNode:
		_selected_state = (node as GStateGraphNode).state
		_update_action_buttons()
		_select_state_in_editor.call_deferred(_selected_state)


func _on_graph_node_deselected(node: Node) -> void:
	if _refreshing:
		return
	if (
		node is GStateGraphNode
		and _selected_state == (node as GStateGraphNode).state
	):
		_selected_state = null
		_update_action_buttons()


func _select_state_in_editor(object: Object) -> void:
	if (
		_editor_interface == null
		or not is_instance_valid(object)
		or _syncing_editor_selection
	):
		return
	_syncing_editor_selection = true
	if object is Node:
		var selection: EditorSelection = _editor_interface.get_selection()
		selection.clear()
		selection.add_node(object as Node)
		_editor_interface.edit_node(object as Node)
	elif object is Resource:
		_editor_interface.edit_resource(object as Resource)
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
			_graph_edit.collect_state_positions(
					_state_machine.graph.editor_positions
			)
	)
	if new_positions == _positions_before_move:
		return
	if _undo_redo == null:
		_state_machine.graph.editor_positions = new_positions
		_mark_scene_unsaved()
		return
	_undo_redo.create_action("GState: Move States")
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
	var changed: bool = (
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
	refresh()


func _go_to_parent_scope() -> void:
	if _scope == null:
		return
	_show_scope(_get_state_parent(_scope))


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
	var cursor: State = _scope
	while cursor is State:
		scope_path.push_front(cursor as State)
		cursor = _get_state_parent(cursor as State)
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
		transitions: Array[Dictionary],
		state_names: Dictionary
) -> void:
	_transition_option.clear()
	for transition: Dictionary in transitions:
		var source_uid: StringName = transition[&"source_uid"]
		var target_uid: StringName = transition[&"target_uid"]
		var target_name: StringName = transition[&"target_name"]
		var event: StringName = transition[&"event"]
		var from_name: String = state_names.get(
				source_uid,
				str((transition[&"source"] as State).name)
		)
		var to_name: String = state_names.get(
				target_uid,
				str(target_name)
		)
		_transition_option.add_item(
				"%s: %s → %s" % [event, from_name, to_name]
		)
		_transition_option.set_item_metadata(
				_transition_option.item_count - 1,
				transition
		)
	_delete_transition_button.disabled = _transition_option.item_count == 0
	_edit_transition_button.disabled = _transition_option.item_count == 0


func _on_transition_selected(_index: int) -> void:
	_delete_transition_button.disabled = _transition_option.item_count == 0
	_edit_transition_button.disabled = _transition_option.item_count == 0
	_selected_state = null
	var transition: Dictionary = (
		_transition_option.get_item_metadata(_transition_option.selected)
		if _transition_option.item_count > 0
		else {}
	)
	_update_action_buttons()
	if not transition.is_empty():
		var source := transition.get(&"source") as State
		if is_instance_valid(source):
			_select_state_in_editor.call_deferred(source)


func _get_scope_states() -> Array[State]:
	return _get_direct_state_children(_get_scope_parent())


func _get_direct_state_children(parent: Variant) -> Array[State]:
	if _state_machine == null or _state_machine.definition == null:
		return []
	if parent is State:
		return (parent as State).get_state_children()
	return _state_machine.definition.get_direct_states()


func _get_scope_parent() -> Variant:
	return _scope


func _get_initial_name() -> StringName:
	return (
			_scope.initial_child
			if _scope != null
			else _state_machine.definition.initial_state
	)


func _get_scope_transitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for source: State in _get_scope_states():
		if source == null:
			continue
		for event: StringName in source.transitions:
			var target_name: StringName = source.transitions[event]
			var target := _find_scope_state_by_name(target_name)
			result.append({
				&"source": source,
				&"source_uid": source.editor_uid,
				&"target_uid": target.editor_uid if target != null else &"",
				&"target_name": target_name,
				&"event": event,
			})
	return result


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
	if _selected_state != null:
		_graph_edit.select_state(_selected_state)


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
	var wanted_initial: StringName = _get_initial_name()
	for state: State in states:
		if state.name == wanted_initial:
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
	if _scope == null:
		return result
	for event: StringName in _scope.transitions:
		result.append(str(event))
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
	if _state_machine.definition == null:
		_state_machine.definition = StateMachineResource.new()
		_connect_graph_resource()
		_mark_scene_unsaved()


func _mark_scene_unsaved() -> void:
	if _editor_interface == null:
		return
	if _state_machine != null and _state_machine.definition != null:
		_editor_interface.set_object_edited(_state_machine.definition, true)
	if (
		_state_machine == null
		or _state_machine.definition == null
		or _state_machine.definition.is_built_in()
	):
		_editor_interface.mark_scene_as_unsaved()


func _find_scope_state_by_name(state_name: StringName) -> State:
	for state: State in _get_scope_states():
		if state != null and state.name == state_name:
			return state
	return null


func _collect_state_uids(
		state: State,
		result: Dictionary[StringName, bool]
) -> void:
	result[state.editor_uid] = true
	for child: State in state.get_state_children():
		_collect_state_uids(child, result)


func _is_ancestor_state(ancestor: State, state: State) -> bool:
	if not is_instance_valid(ancestor) or not is_instance_valid(state):
		return false
	var cursor: State = _get_state_parent(state)
	while cursor is State:
		if cursor == ancestor:
			return true
		cursor = _get_state_parent(cursor)
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
	if node is StateMachine and not node.definition_changed.is_connected(
			_on_machine_definition_changed
	):
		node.definition_changed.connect(_on_machine_definition_changed)


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
		if node is StateMachine and node.definition_changed.is_connected(
				_on_machine_definition_changed
		):
			node.definition_changed.disconnect(_on_machine_definition_changed)
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
	return (
		_state_machine != null
		and _state_machine.definition != null
		and _state_machine.definition.contains_state(state)
	)


func _get_state_parent(state: State) -> State:
	if _state_machine == null or _state_machine.definition == null:
		return null
	return _state_machine.definition.find_parent_state(state)


func _connect_graph_resource() -> void:
	_observed_definition = (
			_state_machine.definition if _state_machine != null else null
	)
	if (
		_observed_definition != null
		and not _observed_definition.changed.is_connected(
				_on_graph_resource_changed
		)
	):
		_observed_definition.changed.connect(_on_graph_resource_changed)
	if _state_machine != null and _state_machine.definition != null:
		for state: State in _state_machine.definition.get_all_states():
			if state != null and not state.changed.is_connected(_on_state_changed):
				state.changed.connect(_on_state_changed)
				_observed_state_resources.append(state)


func _disconnect_graph_resource() -> void:
	for state: State in _observed_state_resources:
		if is_instance_valid(state) and state.changed.is_connected(_on_state_changed):
			state.changed.disconnect(_on_state_changed)
	_observed_state_resources.clear()
	if (
		_observed_definition != null
		and _observed_definition.changed.is_connected(
				_on_graph_resource_changed
		)
	):
		_observed_definition.changed.disconnect(_on_graph_resource_changed)
	_observed_definition = null


func _on_state_changed() -> void:
	_mark_scene_unsaved()
	_queue_scene_refresh()


func _on_graph_resource_changed() -> void:
	_mark_scene_unsaved()
	_queue_scene_refresh()


func _on_machine_definition_changed() -> void:
	_disconnect_graph_resource()
	_connect_graph_resource()
	_definition_toolbar.set_state_machine(_state_machine)
	_queue_scene_refresh()
