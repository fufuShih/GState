@tool
@icon("res://addons/gstate/icons/state.svg")
class_name State
extends Resource

## Serializable definition. StateMachine deep-copies it before runtime use.

@export_storage var stable_id: StringName = &""
@export var name: StringName = &"State":
	set(value):
		if name != value:
			name = value
			emit_changed()
@export var initial_child_id: StringName = &"":
	set(value):
		if initial_child_id != value:
			initial_child_id = value
			emit_changed()
@export var enabled := true:
	set(value):
		if enabled != value:
			enabled = value
			emit_changed()
@export var children: Array[State] = []:
	set(value):
		children = value
		emit_changed()

var actor: Node
var state_machine: StateMachine
var parent_state: State
var active := false


func _init() -> void:
	if stable_id.is_empty():
		stable_id = StringName("state_%x" % ResourceUID.create_id())


func enter(_previous_state: State, _payload: Variant = null) -> void:
	pass


func exit(_next_state: State) -> void:
	pass


func update(_delta: float) -> void:
	pass


func physics_update(_delta: float) -> void:
	pass


func get_state_children() -> Array[State]:
	return children.duplicate()


func add_child_state(state: State) -> bool:
	if state == null or children.has(state):
		return false
	children.append(state)
	emit_changed()
	return true


func remove_child_state(state: State) -> bool:
	if not children.has(state):
		return false
	children.erase(state)
	if initial_child_id == state.stable_id:
		initial_child_id = &""
	emit_changed()
	return true


func is_compound() -> bool:
	return not children.is_empty()


func get_context() -> StateContext:
	return state_machine.get_context() if state_machine != null else null


func _set_runtime_context(
		machine: StateMachine,
		parent: State,
		context_actor: Node
) -> void:
	state_machine = machine
	parent_state = parent
	actor = context_actor
	active = false


func _set_active(value: bool) -> void:
	active = value
