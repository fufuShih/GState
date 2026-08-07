@tool
class_name StateMachineResource
extends Resource

## Portable definition. Save this Resource as .tres for reuse.

@export var context: Dictionary = {}:
	set(value):
		context = value
		emit_changed()
@export var initial_state: StringName = &"":
	set(value):
		if initial_state != value:
			initial_state = value
			emit_changed()
@export var states: Array[State] = []:
	set(value):
		states = value
		_bind_all_states()
		emit_changed()
@export_storage var editor_positions: Dictionary = {}
@export_storage var editor_scroll := Vector2.ZERO
@export_storage var editor_zoom := 1.0

var _bound_states: Array[State] = []


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
			initial_state = state.name
		else:
			parent.initial_child = state.name
	_bind_state_tree(state)
	emit_changed()
	return true


func contains_state(state: State) -> bool:
	return state != null and get_all_states().has(state)


func find_state(state_path: Variant) -> State:
	var text: String = str(state_path).strip_edges().trim_prefix("/").trim_suffix("/")
	if text.is_empty():
		return null
	var candidates: Array[State] = states
	var found: State
	for segment: String in text.split("/", false):
		found = find_direct_state(candidates, StringName(segment))
		if found == null:
			return null
		candidates = found.get_state_children()
	return found


func find_direct_state(
		candidates: Array[State],
		state_name: StringName
) -> State:
	for state: State in candidates:
		if state != null and state.name == state_name:
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
	_bind_all_states()
	var result: Array[State] = []
	var visited: Dictionary[int, bool] = {}
	for state: State in states:
		if state != null:
			_append_tree(state, result, visited)
	return result


func get_structure_errors() -> PackedStringArray:
	_bind_all_states()
	var errors := PackedStringArray()
	var visited: Dictionary[int, bool] = {}
	for state: State in states:
		_validate_tree(state, visited, errors)
	return errors


func set_state_position(state_or_id: Variant, position: Vector2) -> void:
	var editor_uid := _get_editor_uid(state_or_id)
	if editor_uid.is_empty():
		return
	editor_positions[editor_uid] = position
	emit_changed()


func get_state_position(
		state_or_id: Variant,
		default_position: Vector2 = Vector2.ZERO
) -> Vector2:
	var stored: Variant = editor_positions.get(
			_get_editor_uid(state_or_id),
			default_position
	)
	return stored if stored is Vector2 else default_position


func remove_state_position(state_or_id: Variant) -> bool:
	if not editor_positions.erase(_get_editor_uid(state_or_id)):
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


static func _get_editor_uid(state_or_id: Variant) -> StringName:
	return (
		(state_or_id as State).editor_uid
		if state_or_id is State
		else StringName(str(state_or_id))
	)


func _bind_all_states() -> void:
	var previously_bound: Array[State] = _bound_states.duplicate()
	_bound_states.clear()
	var visited: Dictionary[int, bool] = {}
	for state: State in states:
		if state != null:
			_bind_state_tree_recursive(state, visited)
	for state: State in previously_bound:
		if state == null or _bound_states.has(state):
			continue
		state._set_definition_owner(null)


func _bind_state_tree(state: State) -> void:
	var visited: Dictionary[int, bool] = {}
	_bind_state_tree_recursive(state, visited)


func _bind_state_tree_recursive(
		state: State,
		visited: Dictionary[int, bool]
) -> void:
	if state == null:
		return
	var instance_id := state.get_instance_id()
	if visited.has(instance_id):
		return
	visited[instance_id] = true
	if not _bound_states.has(state):
		_bound_states.append(state)
	state._set_definition_owner(self)
	for child: State in state.children:
		_bind_state_tree_recursive(child, visited)


func _on_state_name_changed(
		state: State,
		previous_name: StringName,
		new_name: StringName
) -> void:
	if previous_name == new_name:
		return
	var parent := find_parent_state(state)
	if parent == null:
		if initial_state == previous_name:
			initial_state = new_name
	else:
		if parent.initial_child == previous_name:
			parent.initial_child = new_name
	for sibling: State in get_direct_states(parent):
		if sibling == null:
			continue
		var updated: Dictionary[StringName, StringName] = (
				sibling.transitions.duplicate(true)
		)
		var changed := false
		for event: StringName in updated:
			if updated[event] == previous_name:
				updated[event] = new_name
				changed = true
		if changed:
			sibling.transitions = updated
	emit_changed()
