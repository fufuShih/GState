@tool
extends EditorProperty

var _content: VBoxContainer
var _rebuilding := false


func _init() -> void:
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_content)
	set_bottom_editor(_content)


func _update_property() -> void:
	_rebuild()


func _rebuild() -> void:
	if _rebuilding:
		return
	_rebuilding = true
	for child: Node in _content.get_children():
		child.queue_free()

	var state := get_edited_object() as State
	if state == null:
		_rebuilding = false
		return

	_content.add_child(_create_header())
	var siblings := _get_siblings(state)
	for event: StringName in state.transitions:
		_content.add_child(_create_transition_row(
				state,
				event,
				state.transitions[event],
				siblings
		))

	var add_button := Button.new()
	add_button.text = "+ Add Transition"
	add_button.tooltip_text = "Add an outgoing event from this State"
	add_button.disabled = siblings.is_empty()
	add_button.pressed.connect(_add_transition.bind(state, siblings))
	_content.add_child(add_button)
	_rebuilding = false


func _create_header() -> Control:
	var row := HBoxContainer.new()
	var event_label := Label.new()
	event_label.text = "Event"
	event_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var target_label := Label.new()
	target_label.text = "Target (same scope)"
	target_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(event_label)
	row.add_child(target_label)
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 30.0
	row.add_child(spacer)
	return row


func _create_transition_row(
		state: State,
		event: StringName,
		target_name: StringName,
		siblings: Array[State]
) -> Control:
	var row := HBoxContainer.new()
	var event_edit := LineEdit.new()
	event_edit.text = str(event)
	event_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_edit.tooltip_text = "Event sent to StateMachine.send()"
	event_edit.text_submitted.connect(_rename_event.bind(state, event))
	event_edit.focus_exited.connect(
			_rename_event_from_control.bind(state, event, event_edit)
	)
	row.add_child(event_edit)

	var target_option := OptionButton.new()
	target_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var target_found := false
	for sibling: State in siblings:
		target_option.add_item(str(sibling.name))
		target_option.set_item_metadata(
				target_option.item_count - 1,
				sibling.name
		)
		if sibling.name == target_name:
			target_option.select(target_option.item_count - 1)
			target_found = true
	if not target_found and not target_name.is_empty():
		target_option.add_item("Missing: %s" % target_name)
		target_option.set_item_metadata(
				target_option.item_count - 1,
				target_name
		)
		target_option.select(target_option.item_count - 1)
	target_option.item_selected.connect(
			_select_target.bind(state, event, target_option)
	)
	row.add_child(target_option)

	var delete_button := Button.new()
	delete_button.text = "×"
	delete_button.tooltip_text = "Delete this transition"
	delete_button.pressed.connect(_delete_transition.bind(state, event))
	row.add_child(delete_button)
	return row


func _get_siblings(state: State) -> Array[State]:
	var definition := state._get_definition_owner()
	if definition == null:
		return [state]
	var parent := definition.find_parent_state(state)
	return definition.get_direct_states(parent)


func _add_transition(state: State, siblings: Array[State]) -> void:
	if siblings.is_empty():
		return
	var event := &"event"
	var suffix := 2
	while state.transitions.has(event):
		event = StringName("event_%d" % suffix)
		suffix += 1
	var updated: Dictionary[StringName, StringName] = (
			state.transitions.duplicate(true)
	)
	updated[event] = siblings[0].name
	_apply(updated)


func _rename_event(
		new_text: String,
		state: State,
		old_event: StringName
) -> void:
	var new_event := StringName(new_text.strip_edges())
	if (
		new_event.is_empty()
		or new_event == old_event
		or state.transitions.has(new_event)
	):
		_rebuild.call_deferred()
		return
	var updated: Dictionary[StringName, StringName] = (
			state.transitions.duplicate(true)
	)
	var target_name: StringName = updated.get(old_event, &"")
	updated.erase(old_event)
	updated[new_event] = target_name
	_apply(updated)


func _rename_event_from_control(
		state: State,
		old_event: StringName,
		event_edit: LineEdit
) -> void:
	_rename_event(event_edit.text, state, old_event)


func _select_target(
		index: int,
		state: State,
		event: StringName,
		target_option: OptionButton
) -> void:
	if index < 0 or index >= target_option.item_count:
		return
	var updated: Dictionary[StringName, StringName] = (
			state.transitions.duplicate(true)
	)
	updated[event] = target_option.get_item_metadata(index)
	_apply(updated)


func _delete_transition(state: State, event: StringName) -> void:
	var updated: Dictionary[StringName, StringName] = (
			state.transitions.duplicate(true)
	)
	updated.erase(event)
	_apply(updated)


func _apply(value: Dictionary[StringName, StringName]) -> void:
	emit_changed(&"transitions", value)
	_rebuild.call_deferred()
