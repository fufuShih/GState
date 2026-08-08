extends Node2D

@onready var status_label: Label = $StatusLabel
@onready var action_label: Label = $ActionLabel
@onready var state_manager: StateManager = $StateManager
@onready var machine: StateMachine = $StateManager/ActionDemo


func _enter_tree() -> void:
	var manager := get_node_or_null("StateManager") as StateManager
	if manager != null:
		manager.autostart = false


func _ready() -> void:
	machine.transitioned.connect(_on_transitioned)
	if not state_manager.start():
		status_label.text = "GState failed to start — check Issues or Output"
		return
	_refresh_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_accept"):
		return
	machine.send(&"toggle", {&"input": &"ui_accept"})
	get_viewport().set_input_as_handled()


func _on_transitioned(
		_previous_state: State,
		_current_state: State,
		_event: StringName,
		_payload: Variant
) -> void:
	_refresh_ui()


func _refresh_ui() -> void:
	var current := machine.get_current_state()
	var current_name := str(current.name) if current != null else "None"
	var context := machine.get_context()
	status_label.text = (
			"Current: %s\nPress Space or Enter to toggle" % current_name
	)
	action_label.text = (
			"Last Action: %s\nCount: %d\n%s → %s"
			% [
				context[&"last_action"],
				context[&"action_count"],
				context[&"last_source"],
				context[&"last_target"],
			]
	)
