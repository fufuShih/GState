extends State


func perform_action(
		action: StringName,
		target_state: State,
		_payload: Variant = null
) -> void:
	if action != &"record_toggle":
		return
	var context := get_context()
	context[&"action_count"] += 1
	context[&"last_action"] = action
	context[&"last_source"] = name
	context[&"last_target"] = target_state.name
