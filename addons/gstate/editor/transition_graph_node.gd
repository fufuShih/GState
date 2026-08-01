@tool
class_name GStateTransitionGraphNode
extends GraphNode

signal edit_requested(transition: StateTransition)

const IN_PORT_COLOR := Color(0.38, 0.64, 0.95)
const OUT_PORT_COLOR := Color(0.35, 0.82, 0.65)
const PORT_ROW_HEIGHT := 28.0
const MAX_EVENT_LENGTH := 28

var transition: StateTransition


func setup(transition_value: StateTransition) -> void:
	transition = transition_value
	draggable = true
	resizable = false
	selectable = true
	custom_minimum_size = Vector2(170.0, 0.0)
	title = "Transition →"
	tooltip_text = _build_tooltip()

	var event_label := Label.new()
	event_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	event_label.custom_minimum_size = Vector2(0.0, PORT_ROW_HEIGHT)
	event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	event_label.text = _get_display_event()
	add_child(event_label)
	set_slot(0, true, 0, IN_PORT_COLOR, true, 0, OUT_PORT_COLOR)
	gui_input.connect(_on_gui_input)


func _get_display_event() -> String:
	if transition == null or transition.event.is_empty():
		return "(empty event)"
	var event_name := str(transition.event)
	if event_name.length() <= MAX_EVENT_LENGTH:
		return event_name
	return event_name.left(MAX_EVENT_LENGTH - 3) + "..."


func _build_tooltip() -> String:
	if transition == null:
		return "Transition"
	return "Event: %s\n%s -> %s\nDouble-click to edit" % [
		transition.event,
		transition.from_state_id,
		transition.to_state_id,
	]


func _on_gui_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
		and (event as InputEventMouseButton).pressed
		and (event as InputEventMouseButton).double_click
		and transition != null
	):
		edit_requested.emit(transition)
		accept_event()
