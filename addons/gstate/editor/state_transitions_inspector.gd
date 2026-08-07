@tool
extends EditorInspectorPlugin

const StateTransitionsPropertyScript := preload(
		"res://addons/gstate/editor/state_transitions_property.gd"
)


func _can_handle(object: Object) -> bool:
	return object is State


func _parse_property(
		object: Object,
		_type: Variant.Type,
		name: String,
		_hint_type: PropertyHint,
		_hint_string: String,
		_usage_flags: int,
		_wide: bool
) -> bool:
	if not object is State or name != "transitions":
		return false
	var property_editor: EditorProperty = StateTransitionsPropertyScript.new()
	add_property_editor(name, property_editor)
	return true
