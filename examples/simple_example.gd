extends Node2D

@onready var status_label: Label = $StatusLabel
@onready var state_manager: StateManager = $StateManager
@onready var toggle: StateMachine = get_node_or_null(
		"StateManager/Toggle"
) as StateMachine


func _enter_tree() -> void:
	# The parent enters the tree before its children, so this disables Manager
	# autostart before StateManager._ready() runs.
	var manager := get_node_or_null("StateManager") as StateManager
	if manager != null:
		manager.autostart = false


func _ready() -> void:
	if toggle == null:
		status_label.text = "Missing StateManager/Toggle"
		push_error(
				"SimpleExample requires a StateMachine at "
				+ "'StateManager/Toggle'."
		)
		return

	toggle.active_path_changed.connect(_update_status)
	toggle.transition_rejected.connect(_on_transition_rejected)

	if not state_manager.start():
		status_label.text = "GState failed to start — check Issues or Output"
		return

	_update_status(toggle.get_active_path())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_accept"):
		toggle.send(&"toggle")
		get_viewport().set_input_as_handled()


func _update_status(path: Array[State]) -> void:
	var state_names := PackedStringArray()
	for state: State in path:
		state_names.append(str(state.name))
	status_label.text = (
			"Current: %s\nPress Space or Enter to toggle"
			% "/".join(state_names)
	)


func _on_transition_rejected(
		event: StringName,
		_payload: Variant
) -> void:
	status_label.text = (
			"Current: %s\nEvent '%s' was rejected"
			% [_get_current_state_name(), event]
	)


func _get_current_state_name() -> String:
	var current := toggle.get_current_state()
	return str(current.name) if current != null else "None"
