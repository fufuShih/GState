@tool
class_name StateMachineGraph
extends Resource

## Runtime transition data plus editor metadata reserved for the GraphEdit phase.

@export var transitions: Array[StateTransition] = []
@export_storage var editor_positions: Dictionary = {}
@export_storage var editor_scroll: Vector2 = Vector2.ZERO
@export_storage var editor_zoom: float = 1.0


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
	var target_id: StringName = &""
	if transition_or_id is StateTransition:
		target_id = (transition_or_id as StateTransition).id
	else:
		target_id = StringName(str(transition_or_id))

	for index: int in range(transitions.size()):
		var transition: StateTransition = transitions[index]
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
	var state_id: StringName = _get_state_id(state_or_id)
	if state_id.is_empty():
		return
	editor_positions[state_id] = position
	emit_changed()


func get_state_position(
		state_or_id: Variant,
		default_position: Vector2 = Vector2.ZERO
) -> Vector2:
	var state_id: StringName = _get_state_id(state_or_id)
	var stored_position: Variant = editor_positions.get(state_id, default_position)
	if stored_position is Vector2:
		return stored_position
	return default_position


func remove_state_position(state_or_id: Variant) -> bool:
	var state_id: StringName = _get_state_id(state_or_id)
	if not editor_positions.erase(state_id):
		return false
	emit_changed()
	return true


static func _get_state_id(state_or_id: Variant) -> StringName:
	if state_or_id is State:
		return (state_or_id as State).stable_id
	return StringName(str(state_or_id))
