class_name StateDebugPanel
extends CanvasLayer

## Optional in-game overlay for inspecting StateManager machines during development.

@export var state_manager: StateManager
@export var visible_on_start: bool = false
@export var toggle_key: Key = KEY_F8
@export var show_context: bool = true
@export var show_event_log: bool = true
@export var allow_send_events: bool = false
@export_range(1, 100, 1) var max_log_entries: int = 20
@export_range(0.05, 2.0, 0.05) var refresh_interval: float = 0.25
@export var debug_build_only: bool = true

@onready var _panel: PanelContainer = %Panel
@onready var _header: HBoxContainer = %Header
@onready var _content: VBoxContainer = %Content
@onready var _machine_option: OptionButton = %MachineOption
@onready var _status_label: Label = %StatusLabel
@onready var _active_path_label: Label = %ActivePathLabel
@onready var _last_transition_label: Label = %LastTransitionLabel
@onready var _context_section: VBoxContainer = %ContextSection
@onready var _context_text: RichTextLabel = %ContextText
@onready var _event_log_section: VBoxContainer = %EventLogSection
@onready var _event_log_text: RichTextLabel = %EventLogText
@onready var _event_row: HBoxContainer = %EventRow
@onready var _event_edit: LineEdit = %EventEdit
@onready var _send_button: Button = %SendButton
@onready var _minimize_button: Button = %MinimizeButton
@onready var _close_button: Button = %CloseButton

var _machines: Array[StateMachine] = []
var _selected_machine: StateMachine
var _bound_manager: StateManager
var _event_log: Array[String] = []
var _last_transitions: Dictionary[int, String] = {}
var _refresh_elapsed: float = 0.0
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _expanded_panel_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	if debug_build_only and not OS.is_debug_build():
		queue_free()
		return

	_expanded_panel_size = _panel.size
	_panel.visible = visible_on_start
	_context_section.visible = show_context
	_event_log_section.visible = show_event_log
	_event_row.visible = allow_send_events
	_header.gui_input.connect(_on_header_gui_input)
	_machine_option.item_selected.connect(_on_machine_selected)
	_send_button.pressed.connect(_on_send_pressed)
	_event_edit.text_submitted.connect(_on_event_submitted)
	_event_edit.gui_input.connect(_on_event_edit_gui_input)
	_minimize_button.pressed.connect(_on_minimize_pressed)
	_close_button.pressed.connect(hide_panel)

	if state_manager == null:
		state_manager = _find_state_manager()
	_bind_state_manager()


func _exit_tree() -> void:
	_disconnect_machines()
	_disconnect_manager()


func _process(delta: float) -> void:
	if not is_panel_visible():
		return
	_refresh_elapsed += delta
	if _refresh_elapsed >= refresh_interval:
		_refresh_elapsed = 0.0
		refresh()


func _input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
		and not (event as InputEventMouseButton).pressed
	):
		_dragging = false
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if (
		key_event.pressed
		and not key_event.echo
		and key_event.keycode == toggle_key
	):
		set_panel_visible(not is_panel_visible())
		get_viewport().set_input_as_handled()


## Rebinds the overlay to a manager assigned at runtime.
func set_state_manager(manager: StateManager) -> void:
	state_manager = manager
	if is_node_ready():
		_bind_state_manager()


func show_panel() -> void:
	set_panel_visible(true)


func hide_panel() -> void:
	set_panel_visible(false)


func set_panel_visible(value: bool) -> void:
	if not is_node_ready():
		visible_on_start = value
		return
	_panel.visible = value
	if not value:
		_dragging = false
		_release_ui_focus()
	if value:
		refresh()


func is_panel_visible() -> bool:
	return _panel.visible if is_node_ready() else visible_on_start


func get_selected_machine() -> StateMachine:
	return _selected_machine


func get_event_log() -> PackedStringArray:
	return PackedStringArray(_event_log)


func is_minimized() -> bool:
	return is_node_ready() and not _content.visible


func set_minimized(value: bool) -> void:
	if not is_node_ready() or value == is_minimized():
		return
	_release_ui_focus()
	if value:
		_expanded_panel_size = _panel.size
		_content.hide()
		_minimize_button.text = "+"
		_minimize_button.tooltip_text = "Expand"
		# The container clamps this to the title row''s minimum height.
		_panel.size = Vector2(_expanded_panel_size.x, 1.0)
	else:
		_content.show()
		_minimize_button.text = "−"
		_minimize_button.tooltip_text = "Minimize"
		_panel.size = _expanded_panel_size
		_move_panel(_panel.position)


## Sends an event to the selected machine. The Inspector option only controls UI.
func send_event(event: StringName, payload: Variant = null) -> bool:
	if _selected_machine == null or event.is_empty():
		return false
	return _selected_machine.send(event, payload)


func refresh() -> void:
	if not is_node_ready():
		return
	if _selected_machine == null or not is_instance_valid(_selected_machine):
		_show_empty_state()
		return

	_status_label.text = (
		"Running" if _selected_machine.is_running() else "Stopped"
	)
	_active_path_label.text = "Active: %s" % _format_active_path(
		_selected_machine
	)
	_last_transition_label.text = "Last: %s" % _last_transitions.get(
			_selected_machine.get_instance_id(),
			"None"
	)
	_context_text.text = _format_context(_selected_machine.get_context())
	_event_log_text.text = (
		"No events yet" if _event_log.is_empty() else "\n".join(_event_log)
	)


func _find_state_manager() -> StateManager:
	return get_tree().get_first_node_in_group(&"_gstate_managers") as StateManager


func _bind_state_manager() -> void:
	_disconnect_machines()
	_disconnect_manager()
	_machines.clear()
	_selected_machine = null
	_machine_option.clear()
	if state_manager == null or not is_instance_valid(state_manager):
		_show_empty_state("No StateManager assigned")
		return

	_bound_manager = state_manager
	var children_changed := Callable(self, &"_on_manager_children_changed")
	if not _bound_manager.child_entered_tree.is_connected(children_changed):
		_bound_manager.child_entered_tree.connect(children_changed)
	if not _bound_manager.child_exiting_tree.is_connected(children_changed):
		_bound_manager.child_exiting_tree.connect(children_changed)
	_refresh_machines()


func _refresh_machines() -> void:
	if state_manager == null or not is_instance_valid(state_manager):
		_show_empty_state("No StateManager assigned")
		return

	var previous := _selected_machine
	_disconnect_machines()
	_machines = state_manager.get_state_machines()
	_machine_option.clear()
	for machine: StateMachine in _machines:
		_machine_option.add_item(str(machine.name))
		_connect_machine(machine)

	if _machines.is_empty():
		_selected_machine = null
		_show_empty_state("No StateMachine found")
		return

	var selected_index := _machines.find(previous)
	if selected_index < 0:
		selected_index = 0
	_machine_option.select(selected_index)
	_selected_machine = _machines[selected_index]
	refresh()


func _connect_machine(machine: StateMachine) -> void:
	_connect_signal(machine.started, _on_machine_started.bind(machine))
	_connect_signal(machine.stopped, _on_machine_stopped.bind(machine))
	_connect_signal(machine.transitioned, _on_transitioned.bind(machine))
	_connect_signal(
		machine.transition_rejected,
		_on_transition_rejected.bind(machine)
	)
	_connect_signal(
		machine.active_path_changed,
		_on_active_path_changed.bind(machine)
	)


func _disconnect_machines() -> void:
	for machine: StateMachine in _machines:
		if is_instance_valid(machine):
			_disconnect_machine(machine)


func _disconnect_machine(machine: StateMachine) -> void:
	_disconnect_signal(machine.started, _on_machine_started.bind(machine))
	_disconnect_signal(machine.stopped, _on_machine_stopped.bind(machine))
	_disconnect_signal(machine.transitioned, _on_transitioned.bind(machine))
	_disconnect_signal(
		machine.transition_rejected,
		_on_transition_rejected.bind(machine)
	)
	_disconnect_signal(
		machine.active_path_changed,
		_on_active_path_changed.bind(machine)
	)


func _disconnect_manager() -> void:
	if _bound_manager == null or not is_instance_valid(_bound_manager):
		_bound_manager = null
		return
	var children_changed := Callable(self, &"_on_manager_children_changed")
	if _bound_manager.child_entered_tree.is_connected(children_changed):
		_bound_manager.child_entered_tree.disconnect(children_changed)
	if _bound_manager.child_exiting_tree.is_connected(children_changed):
		_bound_manager.child_exiting_tree.disconnect(children_changed)
	_bound_manager = null


func _connect_signal(target_signal: Signal, callback: Callable) -> void:
	if not target_signal.is_connected(callback):
		target_signal.connect(callback)


func _disconnect_signal(target_signal: Signal, callback: Callable) -> void:
	if target_signal.is_connected(callback):
		target_signal.disconnect(callback)


func _show_empty_state(message: String = "No StateMachine selected") -> void:
	_status_label.text = message
	_active_path_label.text = "Active: None"
	_last_transition_label.text = "Last: None"
	_context_text.text = "Empty"
	_event_log_text.text = (
		"No events yet" if _event_log.is_empty() else "\n".join(_event_log)
	)


func _format_active_path(machine: StateMachine) -> String:
	var names := PackedStringArray()
	for state: State in machine.get_active_path():
		names.append(str(state.name))
	return "None" if names.is_empty() else " -> ".join(names)


func _format_context(context: Dictionary) -> String:
	if context.is_empty():
		return "Empty"
	var keys: Array = context.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	var lines := PackedStringArray()
	for key: Variant in keys:
		lines.append("%s: %s" % [key, context[key]])
	return "\n".join(lines)


func _find_transition_action(
		machine: StateMachine,
		previous_state: State,
		event: StringName
) -> StringName:
	if machine.graph == null or previous_state == null or event.is_empty():
		return &""
	var source := previous_state
	while source != null:
		var scope_id := StateTransition.ROOT_SCOPE_ID
		if source.parent_state != null:
			scope_id = source.parent_state.stable_id
		var transition := machine.graph.find_transition(
			scope_id,
			source.stable_id,
			event
		)
		if transition != null:
			return transition.action
		source = source.parent_state
	return &""


func _append_log(message: String) -> void:
	_event_log.append(message)
	while _event_log.size() > max_log_entries:
		_event_log.pop_front()
	refresh()


func _on_machine_selected(index: int) -> void:
	if index < 0 or index >= _machines.size():
		return
	_selected_machine = _machines[index]
	refresh()


func _on_header_gui_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	):
		var mouse_button := event as InputEventMouseButton
		_dragging = mouse_button.pressed
		if _dragging:
			_drag_offset = get_viewport().get_mouse_position() - _panel.position
			_release_ui_focus()
		_header.accept_event()
		return
	if event is InputEventMouseMotion and _dragging:
		_move_panel(get_viewport().get_mouse_position() - _drag_offset)
		_header.accept_event()


func _move_panel(wanted_position: Vector2) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var max_position := Vector2(
		maxf(0.0, viewport_size.x - _panel.size.x),
		maxf(0.0, viewport_size.y - _panel.size.y)
	)
	_panel.position = wanted_position.clamp(Vector2.ZERO, max_position)


func _release_ui_focus() -> void:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if (
		focus_owner != null
		and (
			focus_owner == _panel
			or _panel.is_ancestor_of(focus_owner)
		)
	):
		focus_owner.release_focus()


func _on_manager_children_changed(_node: Node) -> void:
	_refresh_machines.call_deferred()


func _on_machine_started(_initial_state: State, machine: StateMachine) -> void:
	_append_log("[%s] STARTED: %s" % [machine.name, _format_active_path(machine)])


func _on_machine_stopped(previous_state: State, machine: StateMachine) -> void:
	var previous := str(previous_state.name) if previous_state != null else "None"
	_append_log("[%s] STOPPED: %s" % [machine.name, previous])


func _on_transitioned(
		previous_state: State,
		current_state: State,
		event: StringName,
		_payload: Variant,
		machine: StateMachine
) -> void:
	var previous := str(previous_state.name) if previous_state != null else "None"
	var current := str(current_state.name) if current_state != null else "None"
	var summary := "%s --%s--> %s" % [previous, event, current]
	var action := _find_transition_action(machine, previous_state, event)
	if not action.is_empty():
		summary += " (action: %s)" % action
	_last_transitions[machine.get_instance_id()] = summary
	_append_log("[%s] OK: %s" % [machine.name, summary])


func _on_transition_rejected(
		event: StringName,
		_payload: Variant,
		machine: StateMachine
) -> void:
	_append_log("[%s] REJECTED: %s" % [machine.name, event])


func _on_active_path_changed(
		_path: Array[State],
		machine: StateMachine
) -> void:
	if machine == _selected_machine:
		refresh()


func _on_send_pressed() -> void:
	_send_from_edit()


func _on_minimize_pressed() -> void:
	set_minimized(not is_minimized())


func _on_event_submitted(_text: String) -> void:
	_send_from_edit()


func _on_event_edit_gui_input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and (event as InputEventKey).pressed
		and (event as InputEventKey).keycode == KEY_ESCAPE
	):
		_event_edit.release_focus()
		_event_edit.accept_event()


func _send_from_edit() -> void:
	var event_text := _event_edit.text.strip_edges()
	if event_text.is_empty():
		return
	_event_edit.clear()
	_event_edit.release_focus()
	send_event(StringName(event_text))
