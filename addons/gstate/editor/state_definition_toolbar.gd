@tool
class_name GStateDefinitionToolbar
extends HBoxContainer

## Owns the Definition resource workflow shown above the graph.

signal definition_replaced(definition: StateMachineResource)

@onready var _definition_path: Label = %DefinitionPath
@onready var _inspect_button: Button = %InspectDefinitionButton
@onready var _new_button: Button = %NewDefinitionButton
@onready var _save_button: Button = %SaveDefinitionButton
@onready var _make_unique_button: Button = %MakeUniqueButton
@onready var _replace_dialog: ConfirmationDialog = %ReplaceDefinitionDialog
@onready var _error_dialog: AcceptDialog = %ResourceErrorDialog

var _state_machine: StateMachine
var _editor_interface: EditorInterface
var _undo_redo: EditorUndoRedoManager
var _save_dialog: EditorFileDialog


func _ready() -> void:
	_inspect_button.pressed.connect(_inspect_definition)
	_new_button.pressed.connect(_request_new_definition)
	_save_button.pressed.connect(_open_save_dialog)
	_make_unique_button.pressed.connect(_make_definition_unique)
	_replace_dialog.confirmed.connect(_replace_with_new_definition)
	if Engine.is_editor_hint():
		_save_dialog = EditorFileDialog.new()
		_save_dialog.title = "Save State Machine Definition"
		add_child(_save_dialog)
		_save_dialog.file_selected.connect(_save_definition_as)
		_configure_save_dialog()
	_update_controls()


func setup(
		editor_interface: EditorInterface,
		undo_redo: EditorUndoRedoManager
) -> void:
	_editor_interface = editor_interface
	_undo_redo = undo_redo
	if is_node_ready():
		_update_controls()


func set_state_machine(machine: StateMachine) -> void:
	_state_machine = machine
	if is_node_ready():
		_update_controls()


func _configure_save_dialog() -> void:
	if _save_dialog == null:
		return
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_save_dialog.clear_filters()
	_save_dialog.add_filter("*.tres", "GState Definition")


func _inspect_definition() -> void:
	if (
		_editor_interface == null
		or _state_machine == null
		or _state_machine.definition == null
	):
		return
	_editor_interface.edit_resource(_state_machine.definition)


func _request_new_definition() -> void:
	if _state_machine == null:
		return
	var definition := _state_machine.definition
	if definition == null or not _definition_has_content(definition):
		_replace_with_new_definition()
		return
	_replace_dialog.dialog_text = (
		"The current saved Resource will remain on disk."
		if not definition.resource_path.is_empty() and not definition.is_built_in()
		else (
			"The current embedded definition contains data. "
			+ "Replacing it can only be undone while this editor session is open."
		)
	)
	_replace_dialog.popup_centered()


func _replace_with_new_definition() -> void:
	_assign_definition(
			StateMachineResource.new(),
			"GState: New Definition"
	)


func _make_definition_unique() -> void:
	if _state_machine == null or _state_machine.definition == null:
		return
	var unique_definition := (
			_state_machine.definition.duplicate(true) as StateMachineResource
	)
	if unique_definition == null:
		_show_error("Could not duplicate the current definition.")
		return
	_assign_definition(
			unique_definition,
			"GState: Make Definition Unique"
	)


func _assign_definition(
		definition: StateMachineResource,
		action_name: String
) -> void:
	if _state_machine == null or definition == null:
		return
	var previous := _state_machine.definition
	if previous == definition:
		return
	if _undo_redo == null:
		_state_machine.definition = definition
		_after_definition_replaced(definition)
		return
	_undo_redo.create_action(action_name)
	_undo_redo.add_do_property(_state_machine, &"definition", definition)
	_undo_redo.add_do_reference(definition)
	_undo_redo.add_do_method(
			self,
			&"_after_definition_replaced",
			definition
	)
	_undo_redo.add_undo_property(_state_machine, &"definition", previous)
	_undo_redo.add_undo_method(
			self,
			&"_after_definition_replaced",
			previous
	)
	_undo_redo.commit_action()


func _after_definition_replaced(definition: StateMachineResource) -> void:
	_update_controls()
	definition_replaced.emit(definition)
	if _editor_interface != null and definition != null:
		_editor_interface.edit_resource(definition)


func _open_save_dialog() -> void:
	if (
		_save_dialog == null
		or _state_machine == null
		or _state_machine.definition == null
	):
		return
	var definition := _state_machine.definition
	var suggested_dir := "res://"
	var suggested_file := "%s_state_machine.tres" % (
			str(_state_machine.name).to_snake_case()
	)
	if not definition.resource_path.is_empty() and not definition.is_built_in():
		suggested_dir = definition.resource_path.get_base_dir()
		suggested_file = definition.resource_path.get_file()
	elif _editor_interface != null:
		var scene_root := _editor_interface.get_edited_scene_root()
		if scene_root != null and not scene_root.scene_file_path.is_empty():
			suggested_dir = scene_root.scene_file_path.get_base_dir()
	_save_dialog.current_dir = suggested_dir
	_save_dialog.current_file = suggested_file
	_save_dialog.popup_centered_ratio(0.7)


func _save_definition_as(selected_path: String) -> void:
	if _state_machine == null or _state_machine.definition == null:
		return
	var resource_path := selected_path.strip_edges()
	if resource_path.get_extension().to_lower() != "tres":
		resource_path += ".tres"
	var error := ResourceSaver.save(
			_state_machine.definition,
			resource_path,
			ResourceSaver.FLAG_CHANGE_PATH
	)
	if error != OK:
		_show_error(
			"Could not save '%s' (error %d)." % [resource_path, error]
		)
		return
	if _state_machine.definition.resource_path != resource_path:
		_state_machine.definition.take_over_path(resource_path)
	if _editor_interface != null:
		_editor_interface.set_object_edited(_state_machine.definition, false)
		_editor_interface.mark_scene_as_unsaved()
		_editor_interface.get_resource_filesystem().scan()
		_editor_interface.edit_resource(_state_machine.definition)
	_update_controls()


func _show_error(message: String) -> void:
	_error_dialog.dialog_text = message
	_error_dialog.popup_centered()


func _definition_has_content(definition: StateMachineResource) -> bool:
	return (
		not definition.states.is_empty()
		or not definition.context.is_empty()
		or not definition.initial_state.is_empty()
		or not definition.editor_positions.is_empty()
	)


func _update_controls() -> void:
	var definition := (
		_state_machine.definition if _state_machine != null else null
	)
	var can_use := definition != null and _editor_interface != null
	_inspect_button.disabled = not can_use
	_save_button.disabled = not can_use
	_make_unique_button.disabled = not can_use
	_new_button.disabled = (
		_state_machine == null
		or _editor_interface == null
	)
	if definition == null:
		_definition_path.text = (
			"No definition"
			if _state_machine != null
			else "No StateMachine selected"
		)
		_definition_path.tooltip_text = _definition_path.text
		return
	var is_embedded := (
		definition.resource_path.is_empty()
		or definition.is_built_in()
	)
	_definition_path.text = (
		"Embedded (saved in scene)"
		if is_embedded
		else definition.resource_path
	)
	_definition_path.tooltip_text = (
		"Use Save As... to create a reusable .tres Resource."
		if is_embedded
		else definition.resource_path
	)
