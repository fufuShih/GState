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
const PORT_ROW_HEIGHT := 22.0
const DRAG_THRESHOLD := 6.0
const FALLBACK_TITLEBAR_HEIGHT := 32.0
const STATE_PANEL_TINT := Color(0.10, 0.22, 0.34)
const STATE_TITLE_TINT := Color(0.12, 0.34, 0.54)
const STATE_SELECTED_BORDER := Color(0.42, 0.72, 1.0)
const PANEL_TINT_STRENGTH := 0.22
const TITLE_TINT_STRENGTH := 0.42

var state: State
var _outgoing_transitions: Array[StateTransition] = []
var _incoming_transitions: Array[StateTransition] = []
var _drag_candidate: bool = false
var _dragging: bool = false
var _press_global_position: Vector2
var _position_before_drag: Vector2


func _ready() -> void:
	_apply_state_style()


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
	custom_minimum_size = Vector2(230.0, 0.0)
	title = ("%s  %s" % ["●" if is_initial else "", state.name]).strip_edges()
	tooltip_text = _build_tooltip(is_initial)

	var kind_label := Label.new()
	kind_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kind_label.text = _get_kind_text(is_initial)
	kind_label.modulate = Color(0.72, 0.75, 0.8)
	add_child(kind_label)

	add_child(_create_port_header())

	var port_row_count := maxi(
			1,
			maxi(incoming.size(), outgoing.size())
	)
	for port_index: int in range(port_row_count):
		add_child(_create_port_row(port_index, incoming, outgoing))
		set_slot(
				port_index + 2,
				port_index < maxi(1, incoming.size()),
				0,
				IN_PORT_COLOR,
				port_index < maxi(1, outgoing.size()),
				0,
				OUT_PORT_COLOR
		)
	gui_input.connect(_on_gui_input)


func _apply_state_style() -> void:
	_override_state_style(
			&"panel",
			STATE_PANEL_TINT,
			PANEL_TINT_STRENGTH
	)
	_override_state_style(
			&"titlebar",
			STATE_TITLE_TINT,
			TITLE_TINT_STRENGTH
	)
	_override_state_style(
			&"panel_selected",
			STATE_PANEL_TINT,
			PANEL_TINT_STRENGTH + 0.08,
			true
	)
	_override_state_style(
			&"titlebar_selected",
			STATE_TITLE_TINT,
			TITLE_TINT_STRENGTH + 0.08,
			true
	)


func _override_state_style(
		theme_name: StringName,
		tint: Color,
		strength: float,
		selected_style: bool = false
) -> void:
	var source := get_theme_stylebox(theme_name)
	if not source is StyleBoxFlat:
		return
	var style := source.duplicate() as StyleBoxFlat
	style.bg_color = style.bg_color.lerp(tint, strength)
	if selected_style:
		style.border_color = STATE_SELECTED_BORDER
		style.set_border_width_all(2)
	add_theme_stylebox_override(theme_name, style)


func get_transition_output_port(transition: StateTransition) -> int:
	var index := _outgoing_transitions.find(transition)
	return index if index >= 0 else 0


func get_transition_input_port(transition: StateTransition) -> int:
	var index := _incoming_transitions.find(transition)
	return index if index >= 0 else 0


func _create_port_header() -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", COLUMN_GAP)
	row.add_child(_create_port_label("IN", IN_PORT_COLOR, false))
	row.add_child(_create_port_label("OUT", OUT_PORT_COLOR, true))
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

	var input_text := (
			str(index) if index < maxi(1, incoming.size()) else ""
	)
	var output_text := (
			str(outgoing[index].event) if index < outgoing.size() else ""
	)
	row.add_child(_create_port_label(input_text, IN_PORT_COLOR, false))
	row.add_child(_create_port_label(output_text, OUT_PORT_COLOR, true))
	return row


func _create_port_label(
		text: String,
		color: Color,
		align_right: bool
) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_RIGHT
			if align_right
			else HORIZONTAL_ALIGNMENT_LEFT
	)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = text
	label.modulate = color
	return label


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
