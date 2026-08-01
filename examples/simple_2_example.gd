extends Node2D

@onready var status_label: Label = $StatusLabel
@onready var state_manager: StateManager = $StateManager
@onready var toggle: StateMachine = get_node_or_null(
		"StateManager/Toggle"
) as StateMachine


func _enter_tree() -> void:
	var manager := get_node_or_null("StateManager") as StateManager
	if manager != null:
		manager.autostart = false


func _ready() -> void:
	if toggle == null:
		status_label.text = "Missing StateManager/Toggle"
		push_error(
				"Simple2Example requires a StateMachine at "
				+ "'StateManager/Toggle'."
		)
		return

	toggle.active_path_changed.connect(_update_status)
	toggle.transition_rejected.connect(_on_transition_rejected)
	toggle.state_entered.connect(_on_state_entered)
	toggle.state_exited.connect(_on_state_exited)

	if not state_manager.start():
		status_label.text = "GState failed to start — check Issues or Output"
		return

	_update_status(toggle.get_active_path())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_accept"):
		_send_event(&"toggle")
		get_viewport().set_input_as_handled()
		return

	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	match key_event.keycode:
		KEY_A:
			_send_event(&"activate")
		KEY_I:
			_send_event(&"idle")
		KEY_L:
			_send_event(&"lock")
		KEY_U:
			_send_event(&"unlock")
		_:
			return
	get_viewport().set_input_as_handled()


func _send_event(event: StringName) -> void:
	toggle.send(event)


func _update_status(path: Array[State]) -> void:
	var state_names := PackedStringArray()
	for state: State in path:
		state_names.append(str(state.name))
	status_label.text = _build_status("/".join(state_names))


func _on_transition_rejected(
		event: StringName,
		_payload: Variant
) -> void:
	status_label.text = (
			"%s\nRejected: %s"
			% [_build_status(_get_active_path_text()), event]
	)


func _build_status(path: String) -> String:
	return (
			"Current: %s\n"
			+ "Space/Enter: toggle On/Off\n"
			+ "A: activate · I: idle · L: lock · U: unlock"
	) % path


func _on_state_entered(state: State) -> void:
	print("ENTER  ", state.name)


func _on_state_exited(state: State) -> void:
	print("EXIT   ", state.name)


func _get_active_path_text() -> String:
	var state_names := PackedStringArray()
	for state: State in toggle.get_active_path():
		state_names.append(str(state.name))
	return "/".join(state_names)
