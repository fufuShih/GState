extends Node2D

const SCORE_GAIN := 10

@onready var title_label: Label = $TitleLabel
@onready var state_label: Label = $StateLabel
@onready var context_label: Label = $ContextLabel
@onready var help_label: Label = $HelpLabel
@onready var state_manager: StateManager = $StateManager
@onready var session: StateMachine = $StateManager/Session


func _enter_tree() -> void:
	# Connect the UI before the StateManager starts its machines.
	var manager := get_node_or_null("StateManager") as StateManager
	if manager != null:
		manager.autostart = false


func _ready() -> void:
	title_label.text = "GState Resource Context Example"
	help_label.text = (
			"Space: start round / +%d score\n" % SCORE_GAIN
			+ "Enter: finish round · N: next round · R: restart"
	)

	session.active_path_changed.connect(_update_state_label)

	if not state_manager.start():
		state_label.text = "GState failed to start — check Issues or Output"
		return
	if _get_session_context().is_empty():
		state_label.text = "Session context is missing"
		push_error("Example requires context entries in session_machine.tres.")
		return

	_refresh_ui()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	var handled := false
	match key_event.keycode:
		KEY_SPACE:
			if session.is_in_state("Idle"):
				handled = _start_round()
			elif session.is_in_state("Playing"):
				handled = _add_score(SCORE_GAIN)
		KEY_ENTER:
			if session.is_in_state("Playing"):
				handled = session.send(&"finish")
		KEY_N:
			if session.is_in_state("Result"):
				handled = session.send(&"next_round")
		KEY_R:
			handled = session.restart()
			if handled:
				_refresh_ui()
		_:
			return

	if handled:
		get_viewport().set_input_as_handled()


func _start_round() -> bool:
	if not session.send(&"start"):
		return false
	var context := _get_session_context()
	if context.is_empty():
		return false
	context[&"round"] = int(context.get(&"round", 0)) + 1
	context[&"round_score"] = 0
	context[&"last_gain"] = 0
	_update_context_label(context)
	return true


func _add_score(amount: int) -> bool:
	if not session.send(&"score", {"amount": amount}):
		return false
	var context := _get_session_context()
	if context.is_empty():
		return false
	context[&"round_score"] = int(context.get(&"round_score", 0)) + amount
	context[&"total_score"] = int(context.get(&"total_score", 0)) + amount
	context[&"last_gain"] = amount
	_update_context_label(context)
	return true


func _refresh_ui() -> void:
	_update_state_label(session.get_active_path())
	var context := _get_session_context()
	if not context.is_empty():
		_update_context_label(context)
	_update_help_position.call_deferred()


func _get_session_context() -> Dictionary:
	return session.get_context()


func _update_state_label(path: Array[State]) -> void:
	var names := PackedStringArray()
	for state: State in path:
		names.append(str(state.name))
	state_label.text = "Current State: %s" % "/".join(names)


func _update_context_label(context: Dictionary) -> void:
	context_label.text = (
			"SessionContext\n"
			+ "round: %d\n"
			+ "round_score: %d\n"
			+ "total_score: %d\n"
			+ "last_gain: %d"
	) % [
		context.get(&"round", 0),
		context.get(&"round_score", 0),
		context.get(&"total_score", 0),
		context.get(&"last_gain", 0),
	]
	_update_help_position.call_deferred()


func _update_help_position() -> void:
	help_label.position.y = context_label.position.y + context_label.size.y + 16.0
