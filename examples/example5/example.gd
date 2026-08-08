extends Node2D

@onready var state_manager: StateManager = $StateManager
@onready var movement: StateMachine = $StateManager/Movement
@onready var mode: StateMachine = $StateManager/Mode


func _enter_tree() -> void:
	var manager := get_node_or_null("StateManager") as StateManager
	if manager != null:
		manager.autostart = false


func _ready() -> void:
	if not state_manager.start():
		push_error("GState Example 5 failed to start")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_accept"):
		movement.send(&"toggle")
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_A:
			mode.send(&"alert")
			get_viewport().set_input_as_handled()
