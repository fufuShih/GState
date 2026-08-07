@tool
@icon("res://addons/gstate/icons/state_machine.svg")
class_name StateMachine
extends Node

signal started(initial_state: State)
signal stopped(previous_state: State)
signal transitioned(
		previous_state: State,
		current_state: State,
		event: StringName,
		payload: Variant
)
signal transition_rejected(event: StringName, payload: Variant)
signal state_entered(state: State)
signal state_exited(state: State)
signal active_path_changed(path: Array[State])

@export var active: bool = true
@export var autostart: bool = true
@export var actor: Node
@export var context: Dictionary = {}
@export_storage var initial_state_id: StringName = &""
@export_storage var graph: StateMachineGraph = StateMachineGraph.new()

var states_by_id: Dictionary[StringName, State] = {}
var active_path: Array[State] = []
var state_manager: Node

var _running: bool = false
var _transitioning: bool = false
var _context: Dictionary = {}


func _ready() -> void:
	_rebuild_state_registry()
	if Engine.is_editor_hint():
		set_process(false)
		set_physics_process(false)
		return
	if get_parent() is StateMachine:
		push_error(
				"[StateMachine] Child StateMachine nodes are not supported. "
				+ "Place both machines directly under a StateManager."
		)
		return
	var manager := _find_state_manager()
	if manager != null:
		manager.call(&"_register_machine", self)
		return
	if autostart and active:
		start()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not active or not _running:
		return
	var path_snapshot: Array[State] = active_path.duplicate()
	for state: State in path_snapshot:
		if state.active:
			state.update(delta)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not active or not _running:
		return
	var path_snapshot: Array[State] = active_path.duplicate()
	for state: State in path_snapshot:
		if state.active:
			state.physics_update(delta)


func start() -> bool:
	if _running:
		return true
	if not active:
		return false

	_rebuild_state_registry()
	var validation: Dictionary = validate()
	if not _report_validation(validation):
		return false

	var initial_state: State = states_by_id.get(initial_state_id)
	if initial_state == null:
		return false

	var target_path: Array[State] = _expand_initial_children(
			_resolve_target_path(initial_state)
	)
	if target_path.is_empty() or not _is_path_enabled(target_path):
		return false

	reset_context()
	_running = true
	_transitioning = true
	_enter_from_common_ancestor(target_path, 0, null, null)
	active_path = target_path
	_transitioning = false
	active_path_changed.emit(get_active_path())
	started.emit(get_current_state())
	return true


func restart() -> bool:
	stop()
	return start()


func stop() -> void:
	if not _running and active_path.is_empty():
		return
	var previous_state: State = get_current_state()
	_transitioning = true
	_exit_to_common_ancestor(0, null)
	active_path.clear()
	_running = false
	_transitioning = false
	active_path_changed.emit(get_active_path())
	stopped.emit(previous_state)


func send(event: StringName, payload: Variant = null) -> bool:
	if (
			not active
			or not _running
			or _transitioning
			or event.is_empty()
			or graph == null
	):
		transition_rejected.emit(event, payload)
		return false

	for index: int in range(active_path.size() - 1, -1, -1):
		var source: State = active_path[index]
		var scope_id: StringName = StateTransition.ROOT_SCOPE_ID
		if source.parent_state != null:
			scope_id = source.parent_state.stable_id
		var transition: StateTransition = graph.find_transition(
				scope_id,
				source.stable_id,
				event
		)
		if transition != null:
			var target: State = states_by_id.get(transition.to_state_id)
			if target == null or not target.enabled:
				break
			return _change_state(
					target,
					payload,
					event,
					source,
					transition.action
			)

	transition_rejected.emit(event, payload)
	return false


func travel(state_path: Variant, payload: Variant = null) -> bool:
	if not active or not _running or _transitioning:
		return false
	var target: State = _resolve_state_reference(state_path)
	if target == null or not target.enabled:
		return false
	return _change_state(target, payload, &"", null, &"")


func get_state(state_path: Variant) -> State:
	return _resolve_state_reference(state_path)


func get_current_state() -> State:
	if active_path.is_empty():
		return null
	return active_path.back()


func get_active_path() -> Array[State]:
	return active_path.duplicate()


func is_in_state(state_or_path: Variant) -> bool:
	var state: State = _resolve_state_reference(state_or_path)
	return state != null and active_path.has(state)


func is_running() -> bool:
	return _running


## Returns the live context shared by every State in this machine.
func get_context() -> Dictionary:
	return _context


## Creates a fresh runtime copy of the Inspector context Dictionary.
func reset_context() -> Dictionary:
	_context = context.duplicate(true)
	return _context


func _set_state_manager(manager: Node) -> void:
	state_manager = manager
	_rebuild_state_registry()


func _find_state_manager() -> Node:
	var parent := get_parent()
	if parent != null and parent.is_in_group(&"_gstate_managers"):
		return parent
	return null
## Returns {"errors": PackedStringArray, "warnings": PackedStringArray}.
func validate() -> Dictionary:
	_rebuild_state_registry()
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var all_states: Array[State] = _get_all_states()
	var ids_seen: Dictionary[StringName, State] = {}

	if get_parent() is StateMachine:
		errors.append(
				"StateMachine cannot be a child of another StateMachine."
		)

	for state: State in all_states:
		if state.stable_id.is_empty():
			errors.append("State '%s' has an empty stable_id." % state.get_path())
		elif ids_seen.has(state.stable_id):
			errors.append(
					"Duplicate stable_id '%s' on '%s' and '%s'."
					% [
						state.stable_id,
						(ids_seen[state.stable_id] as State).get_path(),
						state.get_path(),
					]
			)
		else:
			ids_seen[state.stable_id] = state

	if initial_state_id.is_empty():
		errors.append("StateMachine has no initial_state_id.")
	elif not _is_direct_child_id(self, initial_state_id):
		errors.append(
				"Root initial state '%s' is not a direct child State."
				% initial_state_id
		)

	for state: State in all_states:
		var children: Array[State] = state.get_state_children()
		if not children.is_empty():
			if state.initial_child_id.is_empty():
				errors.append(
						"Compound state '%s' has no initial_child_id."
						% state.get_path()
				)
			elif not _is_direct_child_id(state, state.initial_child_id):
				errors.append(
						"Initial child '%s' is not a direct child of '%s'."
						% [state.initial_child_id, state.get_path()]
				)
		elif not state.initial_child_id.is_empty():
			warnings.append(
					"Leaf state '%s' has an unused initial_child_id."
					% state.get_path()
			)

	_validate_transitions(errors, warnings)
	return {"errors": errors, "warnings": warnings}


func _change_state(
		target: State,
		payload: Variant,
		event: StringName,
		action_source: State,
		action_name: StringName
) -> bool:
	var target_path: Array[State] = _expand_initial_children(
			_resolve_target_path(target)
	)
	if target_path.is_empty() or not _is_path_enabled(target_path):
		return false

	var previous_state: State = get_current_state()
	var common_length: int = _find_common_prefix_length(
			active_path,
			target_path
	)
	# A leaf self-transition behaves as an external transition.
	if common_length == active_path.size() and common_length == target_path.size():
		common_length = maxi(0, common_length - 1)

	_transitioning = true
	_exit_to_common_ancestor(common_length, target_path.back())
	if action_source != null and not action_name.is_empty():
		action_source.perform_action(action_name, target, payload)
	_enter_from_common_ancestor(
			target_path,
			common_length,
			previous_state,
			payload
	)
	active_path = target_path
	_transitioning = false

	active_path_changed.emit(get_active_path())
	transitioned.emit(previous_state, get_current_state(), event, payload)
	return true


func _resolve_target_path(target: State) -> Array[State]:
	var result: Array[State] = []
	var cursor: State = target
	while cursor != null:
		result.push_front(cursor)
		cursor = cursor.parent_state
	return result


func _find_common_prefix_length(
		source_path: Array[State],
		target_path: Array[State]
) -> int:
	var length: int = mini(source_path.size(), target_path.size())
	var index: int = 0
	while index < length and source_path[index] == target_path[index]:
		index += 1
	return index


func _exit_to_common_ancestor(
		common_length: int,
		next_state: State
) -> void:
	for index: int in range(active_path.size() - 1, common_length - 1, -1):
		var state: State = active_path[index]
		state.exit(next_state)
		state._set_active(false)
		state_exited.emit(state)


func _enter_from_common_ancestor(
		target_path: Array[State],
		common_length: int,
		previous_state: State,
		payload: Variant
) -> void:
	for index: int in range(common_length, target_path.size()):
		var state: State = target_path[index]
		state._set_active(true)
		state.enter(previous_state, payload)
		state_entered.emit(state)


func _expand_initial_children(path: Array[State]) -> Array[State]:
	if path.is_empty():
		return path
	var result: Array[State] = path.duplicate()
	var cursor: State = result.back()
	while cursor.is_compound():
		var initial_child: State = null
		for child: State in cursor.get_state_children():
			if child.stable_id == cursor.initial_child_id:
				initial_child = child
				break
		if initial_child == null:
			return []
		result.append(initial_child)
		cursor = initial_child
	return result


func _resolve_state_reference(reference: Variant) -> State:
	if reference is State:
		var candidate := reference as State
		return candidate if candidate.state_machine == self else null

	var text: String = str(reference).strip_edges().trim_prefix("/").trim_suffix("/")
	if text.is_empty():
		return null
	var id := StringName(text)
	if states_by_id.has(id):
		return states_by_id[id]

	var segments: PackedStringArray = text.split("/", false)
	var scope: Node = self
	var found: State = null
	for segment: String in segments:
		found = null
		for child: Node in scope.get_children():
			if child is State and (
					child.name == StringName(segment)
					or (child as State).stable_id == StringName(segment)
			):
				found = child as State
				break
		if found == null:
			return null
		scope = found
	return found


func _rebuild_state_registry() -> void:
	states_by_id.clear()
	var context_actor: Node = actor
	if (
		context_actor == null
		and state_manager != null
		and state_manager.has_method(&"get_actor")
	):
		context_actor = state_manager.call(&"get_actor") as Node
	if context_actor == null:
		context_actor = get_parent()
	for child: Node in get_children():
		if child is State:
			_register_state_tree(child as State, null, context_actor)


func _register_state_tree(
		state: State,
		parent: State,
		context_actor: Node
) -> void:
	state._set_runtime_context(self, parent, context_actor)
	if not state.stable_id.is_empty() and not states_by_id.has(state.stable_id):
		states_by_id[state.stable_id] = state
	for child: State in state.get_state_children():
		_register_state_tree(child, state, context_actor)


func _get_all_states() -> Array[State]:
	var result: Array[State] = []
	for child: Node in get_children():
		if child is State:
			_append_state_tree(child as State, result)
	return result


func _append_state_tree(state: State, result: Array[State]) -> void:
	result.append(state)
	for child: State in state.get_state_children():
		_append_state_tree(child, result)


func _is_direct_child_id(scope: Node, state_id: StringName) -> bool:
	for child: Node in scope.get_children():
		if child is State and (child as State).stable_id == state_id:
			return true
	return false


func _is_path_enabled(path: Array[State]) -> bool:
	for state: State in path:
		if not state.enabled:
			return false
	return true


func _validate_transitions(
		errors: PackedStringArray,
		_warnings: PackedStringArray
) -> void:
	if graph == null:
		errors.append("StateMachine has no graph resource.")
		return

	var transition_keys: Dictionary[String, StateTransition] = {}
	for transition: StateTransition in graph.transitions:
		if transition == null:
			errors.append("Graph contains a null transition.")
			continue
		if transition.event.is_empty():
			errors.append("Transition '%s' has an empty event." % transition.id)

		var scope: Node = self
		if not transition.scope_id.is_empty():
			scope = states_by_id.get(transition.scope_id)
			if scope == null:
				errors.append(
						"Transition '%s' references missing scope '%s'."
						% [transition.id, transition.scope_id]
				)
				continue

		var from_state: State = states_by_id.get(transition.from_state_id)
		var to_state: State = states_by_id.get(transition.to_state_id)
		if from_state == null:
			errors.append(
					"Transition '%s' references missing source '%s'."
					% [transition.id, transition.from_state_id]
			)
		if to_state == null:
			errors.append(
					"Transition '%s' references missing target '%s'."
					% [transition.id, transition.to_state_id]
			)
		if from_state == null or to_state == null:
			continue

		if not _is_direct_child_id(scope, from_state.stable_id):
			errors.append(
					"Transition '%s' source '%s' is not a direct child of its scope."
					% [transition.id, from_state.stable_id]
			)
		if not _is_direct_child_id(scope, to_state.stable_id):
			errors.append(
					"Transition '%s' target '%s' is not a direct child of its scope."
					% [transition.id, to_state.stable_id]
			)

		var key: String = "%s|%s|%s" % [
			transition.scope_id,
			transition.from_state_id,
			transition.event,
		]
		if transition_keys.has(key):
			errors.append(
					"Duplicate event '%s' from state '%s' in scope '%s'."
					% [
						transition.event,
						transition.from_state_id,
						transition.scope_id,
					]
			)
		else:
			transition_keys[key] = transition


func _report_validation(validation: Dictionary) -> bool:
	var warnings: PackedStringArray = validation["warnings"]
	var errors: PackedStringArray = validation["errors"]
	for warning: String in warnings:
		push_warning("[StateMachine] %s" % warning)
	for error: String in errors:
		push_error("[StateMachine] %s" % error)
	return errors.is_empty()
