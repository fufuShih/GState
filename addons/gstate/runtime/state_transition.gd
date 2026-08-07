@tool
class_name StateTransition
extends Resource

## The empty scope ID represents the root StateMachine scope.
const ROOT_SCOPE_ID: StringName = &""

@export_storage var id: StringName = &""
@export var scope_id: StringName = ROOT_SCOPE_ID
@export var from_state_id: StringName = &""
@export var to_state_id: StringName = &""
@export var event: StringName = &""


func _init(
		from_id: StringName = &"",
		to_id: StringName = &"",
		event_name: StringName = &"",
		transition_scope_id: StringName = ROOT_SCOPE_ID
) -> void:
	id = StringName("transition_%x" % ResourceUID.create_id())
	from_state_id = from_id
	to_state_id = to_id
	event = event_name
	scope_id = transition_scope_id
