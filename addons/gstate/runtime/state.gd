@tool
@icon("res://addons/gstate/icons/state.svg")
class_name State
extends Resource

## Serializable definition. StateMachine deep-copies it before runtime use.

@export_storage var editor_uid: StringName = &""
@export var name: StringName = &"State":
	set(value):
		if name != value:
			var previous_name := name
			name = value
			emit_changed()
			var definition_owner := _get_definition_owner()
			if definition_owner != null:
				definition_owner._on_state_name_changed(
						self,
						previous_name,
						value
				)
@export var initial_child: StringName = &"":
	set(value):
		if initial_child != value:
			initial_child = value
			emit_changed()
@export var enabled := true:
	set(value):
		if enabled != value:
			enabled = value
			emit_changed()
@export var children: Array[State] = []:
	set(value):
		children = value
		var definition_owner := _get_definition_owner()
		if definition_owner != null:
			definition_owner._bind_all_states()
		emit_changed()
@export var transitions: Dictionary[StringName, StringName] = {}:
	set(value):
		transitions = value
		emit_changed()

var actor: Node
var state_machine: StateMachine
var parent_state: State
var active := false
var _definition_owner: WeakRef


func _init() -> void:
	if editor_uid.is_empty():
		editor_uid = StringName("editor_%x" % ResourceUID.create_id())


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
	var definition_owner := _get_definition_owner()
	if definition_owner != null:
		definition_owner._bind_all_states()
	emit_changed()
	return true


func remove_child_state(state: State) -> bool:
	if not children.has(state):
		return false
	children.erase(state)
	var definition_owner := _get_definition_owner()
	if definition_owner != null:
		definition_owner._bind_all_states()
	if initial_child == state.name:
		initial_child = &""
	emit_changed()
	return true


func add_transition(event: StringName, target_name: StringName) -> bool:
	if event.is_empty() or target_name.is_empty() or transitions.has(event):
		return false
	transitions[event] = target_name
	emit_changed()
	return true


func remove_transition(event: StringName) -> bool:
	if not transitions.erase(event):
		return false
	emit_changed()
	return true


func get_transition_target(event: StringName) -> StringName:
	return transitions.get(event, &"")


func is_compound() -> bool:
	return not children.is_empty()


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
	active = false


func _set_definition_owner(owner: StateMachineResource) -> void:
	_definition_owner = weakref(owner) if owner != null else null


func _get_definition_owner() -> StateMachineResource:
	return (
		_definition_owner.get_ref() as StateMachineResource
		if _definition_owner != null
		else null
	)


func _set_active(value: bool) -> void:
	active = value
