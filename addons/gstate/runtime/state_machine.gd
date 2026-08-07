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
signal definition_changed

@export var active: bool = true
@export var autostart: bool = true
@export var actor: Node
@export_category("State Machine Resource")
@export var definition: StateMachineResource = StateMachineResource.new():
	set(value):
		if definition == value:
			return
		_disconnect_definition()
		definition = value
		_connect_definition()
		update_configuration_warnings()
		definition_changed.emit()

## Compatibility accessors for code using the previous API.
var graph: StateMachineResource:
	get:
		return definition
	set(value):
		definition = value
var states_by_uid: Dictionary[StringName, State] = {}
var active_path: Array[State] = []
var state_manager: Node

var _runtime_root_states: Array[State] = []
var _running: bool = false
var _transitioning: bool = false
var _context: Dictionary = {}


func _ready() -> void:
	_connect_definition()
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


func _exit_tree() -> void:
	if _running:
		stop()
	_disconnect_definition()


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

	var validation: Dictionary = validate()
	if not _report_validation(validation):
		return false

	reset_context()
	_rebuild_state_registry()
	var initial: State = _find_direct_state_by_name(
			_runtime_root_states,
			definition.initial_state
	)
	if initial == null:
		return false

	var target_path: Array[State] = _expand_initial_children(
			_resolve_target_path(initial)
	)
	if target_path.is_empty() or not _is_path_enabled(target_path):
		return false

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
		var target_name: StringName = source.get_transition_target(event)
		if not target_name.is_empty():
			var siblings: Array[State] = (
				source.parent_state.get_state_children()
				if source.parent_state != null
				else _runtime_root_states
			)
			var target := _find_direct_state_by_name(siblings, target_name)
			if target == null or not target.enabled:
				break
			return _change_state(target, payload, event)

	transition_rejected.emit(event, payload)
	return false


func travel(state_path: Variant, payload: Variant = null) -> bool:
	if not active or not _running or _transitioning:
		return false
	var target: State = _resolve_state_reference(state_path)
	if target == null or not target.enabled:
		return false
	return _change_state(target, payload, &"")


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


## Creates a fresh runtime copy of the definition's context template.
func reset_context() -> Dictionary:
	_context = (
		definition.context.duplicate(true)
		if definition != null
		else {}
	)
	return _context


func _set_state_manager(manager: Node) -> void:
	state_manager = manager


func _find_state_manager() -> Node:
	var parent := get_parent()
	if parent != null and parent.is_in_group(&"_gstate_managers"):
		return parent
	return null
## Returns {"errors": PackedStringArray, "warnings": PackedStringArray}.
func validate() -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	if definition == null:
		errors.append("StateMachine has no definition resource.")
		return {"errors": errors, "warnings": warnings}
	errors.append_array(definition.get_structure_errors())
	var all_states: Array[State] = definition.get_all_states()
	var uids_seen: Dictionary[StringName, State] = {}
	var scoped_names: Dictionary[String, State] = {}

	if get_parent() is StateMachine:
		errors.append(
				"StateMachine cannot be a child of another StateMachine."
		)

	for state: State in all_states:
		if state == null:
			errors.append("Definition contains a null State.")
			continue
		if state.editor_uid.is_empty():
			errors.append("State '%s' has no internal editor UID." % state.name)
		elif uids_seen.has(state.editor_uid):
			errors.append(
					"Duplicate internal editor UID on '%s' and '%s'."
					% [
						(uids_seen[state.editor_uid] as State).name,
						state.name,
					]
			)
		else:
			uids_seen[state.editor_uid] = state
		if state.name.is_empty():
			errors.append("Definition contains a State with an empty name.")
		elif "/" in str(state.name):
			errors.append("State name '%s' cannot contain '/'." % state.name)
		var parent := definition.find_parent_state(state)
		var scope_uid := parent.editor_uid if parent != null else &"root"
		var scoped_key := "%s/%s" % [scope_uid, state.name]
		if scoped_names.has(scoped_key):
			errors.append(
					"Scope contains more than one State named '%s'."
					% state.name
			)
		else:
			scoped_names[scoped_key] = state

	if definition.initial_state.is_empty():
		errors.append("Definition has no initial State.")
	elif not _is_direct_child_name(null, definition.initial_state, false):
		errors.append(
				"Root initial state '%s' is not a root State."
				% definition.initial_state
		)

	for state: State in all_states:
		var children: Array[State] = state.get_state_children()
		if not children.is_empty():
			if state.initial_child.is_empty():
				errors.append(
						"Compound state '%s' has no initial child."
						% state.name
				)
			elif not _is_direct_child_name(
					state,
					state.initial_child,
					false
			):
				errors.append(
						"Initial child '%s' is not a direct child of '%s'."
						% [state.initial_child, state.name]
				)
		elif not state.initial_child.is_empty():
			warnings.append(
					"Leaf state '%s' has an unused initial child."
					% state.name
			)

	_validate_transitions(errors, warnings)
	return {"errors": errors, "warnings": warnings}


func _change_state(
		target: State,
		payload: Variant,
		event: StringName
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
		var initial_child := _find_direct_state_by_name(
				cursor.get_state_children(),
				cursor.initial_child
		)
		if initial_child == null:
			return []
		result.append(initial_child)
		cursor = initial_child
	return result


func _resolve_state_reference(reference: Variant) -> State:
	if reference is State:
		var candidate := reference as State
		if candidate.state_machine == self:
			return candidate
		return states_by_uid.get(candidate.editor_uid)

	var text: String = str(reference).strip_edges().trim_prefix("/").trim_suffix("/")
	if text.is_empty():
		return null
	var segments: PackedStringArray = text.split("/", false)
	var candidates: Array[State] = _runtime_root_states
	var found: State = null
	for segment: String in segments:
		found = _find_direct_state_by_name(candidates, StringName(segment))
		if found == null:
			return null
		candidates = found.get_state_children()
	return found


func _rebuild_state_registry() -> void:
	states_by_uid.clear()
	_runtime_root_states.clear()
	if definition == null:
		return
	var context_actor: Node = actor
	if (
		context_actor == null
		and state_manager != null
		and state_manager.has_method(&"get_actor")
	):
		context_actor = state_manager.call(&"get_actor") as Node
	if context_actor == null:
		context_actor = get_parent()
	for root_definition: State in definition.states:
		if root_definition == null:
			continue
		var runtime_root := (
				root_definition.duplicate_deep(
						Resource.DEEP_DUPLICATE_ALL
				) as State
		)
		if runtime_root == null:
			continue
		_runtime_root_states.append(runtime_root)
		_register_state_tree(runtime_root, null, context_actor)


func _register_state_tree(
		state: State,
		parent: State,
	context_actor: Node
) -> void:
	state._set_runtime_context(self, parent, context_actor)
	if not state.editor_uid.is_empty() and not states_by_uid.has(state.editor_uid):
		states_by_uid[state.editor_uid] = state
	for child: State in state.get_state_children():
		if child != null:
			_register_state_tree(child, state, context_actor)


func _get_all_states() -> Array[State]:
	return definition.get_all_states() if definition != null else []


func _append_state_tree(state: State, result: Array[State]) -> void:
	result.append(state)
	for child: State in state.get_state_children():
		_append_state_tree(child, result)


func _is_direct_child_name(
		scope: State,
		state_name: StringName,
		runtime: bool = true
) -> bool:
	var children: Array[State]
	if scope != null:
		children = scope.get_state_children()
	elif runtime:
		children = _runtime_root_states
	elif definition != null:
		children = definition.get_direct_states()
	for child: State in children:
		if child != null and child.name == state_name:
			return true
	return false


func _find_direct_state_by_name(
		states: Array[State],
		state_name: StringName
) -> State:
	for state: State in states:
		if state != null and state.name == state_name:
			return state
	return null


func _is_path_enabled(path: Array[State]) -> bool:
	for state: State in path:
		if not state.enabled:
			return false
	return true


func _validate_transitions(
		errors: PackedStringArray,
		_warnings: PackedStringArray
) -> void:
	for from_state: State in definition.get_all_states():
		if from_state == null:
			continue
		var scope: State = definition.find_parent_state(from_state)
		var siblings := definition.get_direct_states(scope)
		for event: StringName in from_state.transitions:
			var target_name: StringName = from_state.transitions[event]
			if event.is_empty():
				errors.append(
						"State '%s' contains a transition with an empty event."
						% from_state.name
				)
			if target_name.is_empty():
				errors.append(
						"Transition '%s' from '%s' has no target."
						% [event, from_state.name]
				)
				continue
			var to_state := _find_direct_state_by_name(siblings, target_name)
			if to_state == null:
				errors.append(
						"Transition '%s' from '%s' references missing target '%s'."
						% [event, from_state.name, target_name]
				)


func _report_validation(validation: Dictionary) -> bool:
	var warnings: PackedStringArray = validation["warnings"]
	var errors: PackedStringArray = validation["errors"]
	for warning: String in warnings:
		push_warning("[StateMachine] %s" % warning)
	for error: String in errors:
		push_error("[StateMachine] %s" % error)
	return errors.is_empty()


func _ensure_definition() -> void:
	if definition == null:
		definition = StateMachineResource.new()


func _connect_definition() -> void:
	if (
		definition != null
		and not definition.changed.is_connected(_on_definition_changed)
	):
		definition.changed.connect(_on_definition_changed)


func _disconnect_definition() -> void:
	if (
		definition != null
		and definition.changed.is_connected(_on_definition_changed)
	):
		definition.changed.disconnect(_on_definition_changed)


func _on_definition_changed() -> void:
	update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	var validation := validate()
	var result: PackedStringArray = validation["errors"]
	result.append_array(validation["warnings"])
	return result
