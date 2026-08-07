@tool
@icon("res://addons/gstate/icons/state.svg")
class_name State
extends Node

## A state may be a leaf or a compound state containing direct State children.

@export_storage var stable_id: StringName = &""
@export_storage var initial_child_id: StringName = &""
@export var enabled: bool = true

var actor: Node
var state_machine: StateMachine
var parent_state: State
var active: bool = false


func _init() -> void:
	if stable_id.is_empty():
		stable_id = _generate_stable_id()


## Override in a state script. Compound states enter before their active child.
func enter(_previous_state: State, _payload: Variant = null) -> void:
	pass


## Override in a state script. Children exit before their compound parent.
func exit(_next_state: State) -> void:
	pass


## Override in a state script. Only active states are updated.
func update(_delta: float) -> void:
	pass


## Override in a state script. Only active states are physics-updated.
func physics_update(_delta: float) -> void:
	pass


func get_state_children() -> Array[State]:
	var result: Array[State] = []
	for child: Node in get_children():
		if child is State:
			result.append(child as State)
	return result


func is_compound() -> bool:
	return not get_state_children().is_empty()


## Every State in a StateMachine reads and writes the same runtime context.
func get_context() -> Dictionary:
	return state_machine.get_context() if state_machine != null else {}


func _set_runtime_context(
		machine: StateMachine,
		parent: State,
		context_actor: Node
) -> void:
	state_machine = machine
	parent_state = parent
	actor = context_actor


func _set_active(value: bool) -> void:
	active = value


static func _generate_stable_id() -> StringName:
	return StringName("state_%x" % ResourceUID.create_id())
