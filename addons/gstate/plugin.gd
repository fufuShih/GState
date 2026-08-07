@tool
extends EditorPlugin

const StateMachineEditorScene := preload(
		"res://addons/gstate/editor/state_machine_editor.tscn"
)

var _state_machine_editor: GStateMachineEditor
var _bottom_panel_button: Button


func _enter_tree() -> void:
	_state_machine_editor = StateMachineEditorScene.instantiate()
	_state_machine_editor.setup_editor(
			get_undo_redo(),
			get_editor_interface()
	)
	_bottom_panel_button = add_control_to_bottom_panel(
			_state_machine_editor,
			"GState"
	)
	_bottom_panel_button.hide()


func _exit_tree() -> void:
	if _state_machine_editor != null:
		remove_control_from_bottom_panel(_state_machine_editor)
		_state_machine_editor.queue_free()
	_state_machine_editor = null
	_bottom_panel_button = null


func _handles(object: Object) -> bool:
	return (
		object is StateManager
		or object is StateMachine
		or object is StateMachineResource
		or object is State
		or object is StateTransition
	)


func _edit(object: Object) -> void:
	if _state_machine_editor == null:
		return
	if object is StateManager:
		_state_machine_editor.set_state_manager(object as StateManager)
	elif object is StateMachine:
		_state_machine_editor.set_state_machine(object as StateMachine)
	elif object is Resource:
		_state_machine_editor.edit_resource_object(object as Resource)


func _make_visible(visible: bool) -> void:
	if _state_machine_editor == null or _bottom_panel_button == null:
		return
	_bottom_panel_button.visible = visible
	if visible:
		make_bottom_panel_item_visible(_state_machine_editor)
	else:
		_state_machine_editor.clear_editor()
		hide_bottom_panel()
