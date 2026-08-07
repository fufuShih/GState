@tool
class_name StateMachineResource
extends Resource

## Portable definition. Save this Resource as .tres for reuse.

@export var initial_state_id: StringName = &"":
	set(value):
		if initial_state_id != value:
			initial_state_id = value
			emit_changed()
@export var states: Array[State] = []:
	set(value):
		states = value
		emit_changed()
@export var transitions: Array[StateTransition] = []:
	set(value):
		transitions = value
		emit_changed()
@export_storage var editor_positions: Dictionary = {}
@export_storage var editor_scroll := Vector2.ZERO
@export_storage var editor_zoom := 1.0


func add_state(state: State, parent: State = null) -> bool:
	if state == null or contains_state(state):
		return false
	if parent == null:
		states.append(state)
	elif contains_state(parent):
		parent.children.append(state)
		parent.emit_changed()
	else:
		return false
	if get_direct_states(parent).size() == 1:
		if parent == null:
			initial_state_id = state.stable_id
		else:
			parent.initial_child_id = state.stable_id
	emit_changed()
	return true


func contains_state(state: State) -> bool:
	return state != null and find_state(state.stable_id) == state


func find_state(state_id: StringName) -> State:
	for state: State in get_all_states():
		if state != null and state.stable_id == state_id:
			return state
	return null


func find_parent_state(wanted: State) -> State:
	var visited: Dictionary[int, bool] = {}
	for root: State in states:
		var found := _find_parent(root, wanted, visited)
		if found != null:
			return found
	return null


func get_direct_states(parent: State = null) -> Array[State]:
	return states.duplicate() if parent == null else parent.get_state_children()


func get_all_states() -> Array[State]:
	var result: Array[State] = []
	var visited: Dictionary[int, bool] = {}
	for state: State in states:
		if state != null:
			_append_tree(state, result, visited)
	return result


func get_structure_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var visited: Dictionary[int, bool] = {}
	for state: State in states:
		_validate_tree(state, visited, errors)
	return errors


func add_transition(transition: StateTransition) -> bool:
	if transition == null:
		return false
	if transition.id.is_empty():
		transition.id = StringName("transition_%x" % ResourceUID.create_id())
	for existing: StateTransition in transitions:
		if existing == transition or existing.id == transition.id:
			return false
	transitions.append(transition)
	emit_changed()
	return true


func remove_transition(transition_or_id: Variant) -> bool:
	var target_id: StringName = (
		(transition_or_id as StateTransition).id
		if transition_or_id is StateTransition
		else StringName(str(transition_or_id))
	)
	for index: int in range(transitions.size()):
		var transition := transitions[index]
		if transition == transition_or_id or transition.id == target_id:
			transitions.remove_at(index)
			emit_changed()
			return true
	return false


func get_transitions_for_scope(scope_id: StringName) -> Array[StateTransition]:
	var result: Array[StateTransition] = []
	for transition: StateTransition in transitions:
		if transition != null and transition.scope_id == scope_id:
			result.append(transition)
	return result


func find_transition(
		scope_id: StringName,
		from_state_id: StringName,
		event: StringName
) -> StateTransition:
	for transition: StateTransition in transitions:
		if (
			transition != null
			and transition.scope_id == scope_id
			and transition.from_state_id == from_state_id
			and transition.event == event
		):
			return transition
	return null


func set_state_position(state_or_id: Variant, position: Vector2) -> void:
	var state_id := _get_state_id(state_or_id)
	if state_id.is_empty():
		return
	editor_positions[state_id] = position
	emit_changed()


func get_state_position(
		state_or_id: Variant,
		default_position: Vector2 = Vector2.ZERO
) -> Vector2:
	var stored: Variant = editor_positions.get(
			_get_state_id(state_or_id),
			default_position
	)
	return stored if stored is Vector2 else default_position


func remove_state_position(state_or_id: Variant) -> bool:
	if not editor_positions.erase(_get_state_id(state_or_id)):
		return false
	emit_changed()
	return true


func _find_parent(
		parent: State,
		wanted: State,
		visited: Dictionary[int, bool]
) -> State:
	if parent == null:
		return null
	var instance_id := parent.get_instance_id()
	if visited.has(instance_id):
		return null
	visited[instance_id] = true
	for child: State in parent.children:
		if child == wanted:
			return parent
		var found := _find_parent(child, wanted, visited)
		if found != null:
			return found
	return null


func _append_tree(
		state: State,
		result: Array[State],
		visited: Dictionary[int, bool]
) -> void:
	var instance_id := state.get_instance_id()
	if visited.has(instance_id):
		return
	visited[instance_id] = true
	result.append(state)
	for child: State in state.children:
		if child != null:
			_append_tree(child, result, visited)


func _validate_tree(
		state: State,
		visited: Dictionary[int, bool],
		errors: PackedStringArray
) -> void:
	if state == null:
		errors.append("Definition contains a null State.")
		return
	var instance_id := state.get_instance_id()
	if visited.has(instance_id):
		errors.append(
				"State '%s' is reused or creates a children cycle." % state.name
		)
		return
	visited[instance_id] = true
	for child: State in state.children:
		_validate_tree(child, visited, errors)


static func _get_state_id(state_or_id: Variant) -> StringName:
	return (
		(state_or_id as State).stable_id
		if state_or_id is State
		else StringName(str(state_or_id))
	)
