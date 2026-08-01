@tool
class_name GStateGraphNode
extends GraphNode

signal scope_requested(state: State)
signal rename_requested(state: State)
signal position_drag_started
signal position_drag_finished

const IN_PORT_COLOR := Color(0.38, 0.64, 0.95)
const OUT_PORT_COLOR := Color(0.35, 0.82, 0.65)
const COLUMN_GAP := 24
const PORT_ROW_HEIGHT := 34.0
const DRAG_THRESHOLD := 6.0
const FALLBACK_TITLEBAR_HEIGHT := 32.0

var state: State
var _outgoing_transitions: Array[StateTransition] = []
var _incoming_transitions: Array[StateTransition] = []
var _drag_candidate: bool = false
var _dragging: bool = false
var _press_global_position: Vector2
var _position_before_drag: Vector2


func setup(
		state_value: State,
		is_initial: bool,
		outgoing: Array[StateTransition],
		incoming: Array[StateTransition]
) -> void:
	state = state_value
	_outgoing_transitions = outgoing
	_incoming_transitions = incoming
	# GraphElement's built-in dragging begins too eagerly over the whole card.
	# GState implements a titlebar-only drag with a movement threshold instead.
	draggable = false
	resizable = false
	selectable = true
	custom_minimum_size = Vector2(380.0, 0.0)
	title = ("%s  %s" % ["●" if is_initial else "", state.name]).strip_edges()
	tooltip_text = _build_tooltip(is_initial)

	var kind_label := Label.new()
	kind_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kind_label.text = _get_kind_text(is_initial)
	kind_label.modulate = Color(0.72, 0.75, 0.8)
	add_child(kind_label)

	var column_header := _create_column_header()
	add_child(column_header)

	var port_row_count: int = maxi(
			1,
			maxi(incoming.size(), outgoing.size())
	)
	for port_index: int in range(port_row_count):
		var port_row := _create_port_row(
				port_index,
				incoming,
				outgoing
		)
		add_child(port_row)
		var slot_index: int = port_index + 2
		set_slot(
				slot_index,
				port_index < maxi(1, incoming.size()),
				0,
				IN_PORT_COLOR,
				port_index < maxi(1, outgoing.size()),
				0,
				OUT_PORT_COLOR
		)
	gui_input.connect(_on_gui_input)


func get_transition_output_port(transition: StateTransition) -> int:
	var index: int = _outgoing_transitions.find(transition)
	return index if index >= 0 else 0


func get_transition_input_port(transition: StateTransition) -> int:
	var index: int = _incoming_transitions.find(transition)
	return index if index >= 0 else 0


func _create_column_header() -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", COLUMN_GAP)

	var input_header := Label.new()
	input_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	input_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_header.text = "IN"
	input_header.modulate = IN_PORT_COLOR
	row.add_child(input_header)

	var output_header := Label.new()
	output_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	output_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	output_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	output_header.text = "OUT"
	output_header.modulate = OUT_PORT_COLOR
	row.add_child(output_header)
	return row


func _create_port_row(
		index: int,
		incoming: Array[StateTransition],
		outgoing: Array[StateTransition]
) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(0.0, PORT_ROW_HEIGHT)
	row.add_theme_constant_override(&"separation", COLUMN_GAP)

	var input_label := Label.new()
	input_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	input_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	input_label.tooltip_text = _get_transition_event_text(index, incoming)
	input_label.text = input_label.tooltip_text
	input_label.modulate = IN_PORT_COLOR
	if index >= incoming.size():
		input_label.text = "Drop IN" if index == 0 else ""
		input_label.modulate = Color(0.48, 0.56, 0.67)
	row.add_child(input_label)

	var output_label := Label.new()
	output_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	output_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	output_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	output_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	output_label.tooltip_text = _get_transition_event_text(index, outgoing)
	output_label.text = output_label.tooltip_text
	output_label.modulate = OUT_PORT_COLOR
	if index >= outgoing.size():
		output_label.text = "Drag OUT" if index == 0 else ""
		output_label.modulate = Color(0.46, 0.62, 0.55)
	row.add_child(output_label)
	return row


func _get_transition_event_text(
		index: int,
		transitions: Array[StateTransition]
) -> String:
	if index < transitions.size():
		var event_name := str(transitions[index].event)
		return event_name if not event_name.is_empty() else "(empty event)"
	return ""


func _get_kind_text(is_initial: bool) -> String:
	var parts := PackedStringArray()
	if is_initial:
		parts.append("Initial")
	if state.is_compound():
		var child_count: int = state.get_state_children().size()
		parts.append(
				"Compound · %d %s"
				% [child_count, "child" if child_count == 1 else "children"]
		)
		parts.append("Double-click to open")
	else:
		parts.append("Leaf")
	return "  ·  ".join(parts)


func _build_tooltip(is_initial: bool) -> String:
	var lines := PackedStringArray([
		"State: %s" % state.name,
		"Stable ID: %s" % state.stable_id,
	])
	if is_initial:
		lines.append("Initial state in this scope")
	if state.is_compound():
		lines.append("Double-click to enter this scope")
	return "\n".join(lines)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed and event.double_click and state != null:
		_cancel_drag()
		if state.is_compound():
			scope_requested.emit(state)
		else:
			rename_requested.emit(state)
		accept_event()
		return
	if event.pressed:
		_drag_candidate = event.position.y <= _get_titlebar_height()
		_dragging = false
		_press_global_position = event.global_position
		_position_before_drag = position_offset
		return
	if _dragging:
		position_drag_finished.emit()
		accept_event()
	_cancel_drag()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if (
		not _drag_candidate
		or (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0
	):
		return
	var movement: Vector2 = event.global_position - _press_global_position
	if not _dragging and movement.length() < DRAG_THRESHOLD:
		return
	if not _dragging:
		_dragging = true
		position_drag_started.emit()
	var graph_edit := get_parent() as GraphEdit
	var graph_zoom: float = graph_edit.zoom if graph_edit != null else 1.0
	position_offset = _position_before_drag + movement / graph_zoom
	accept_event()


func _get_titlebar_height() -> float:
	var titlebar: HBoxContainer = get_titlebar_hbox()
	if titlebar != null and titlebar.size.y > 0.0:
		return titlebar.size.y
	return FALLBACK_TITLEBAR_HEIGHT


func _cancel_drag() -> void:
	_drag_candidate = false
	_dragging = false
