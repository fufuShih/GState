extends SceneTree

const StateMachineEditorScene := preload(
		"res://addons/gstate/editor/state_machine_editor.tscn"
)
const TEST_RESOURCE_PATH := "res://tests/.gstate_definition_save_test.tres"

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect(Engine.is_editor_hint(), "test must run with --editor")
	var machine := StateMachine.new()
	machine.name = &"SaveTest"
	var state := State.new()
	state.name = &"Idle"
	machine.definition.add_state(state)

	var editor: GStateMachineEditor = StateMachineEditorScene.instantiate()
	get_root().add_child(editor)
	editor.set_state_machine(machine)
	var definition_toolbar := editor.get_node("%DefinitionRow")
	_expect(
		definition_toolbar._save_dialog != null,
		"Editor creates the Definition save dialog"
	)

	definition_toolbar._save_definition_as(TEST_RESOURCE_PATH)
	_expect(
		FileAccess.file_exists(TEST_RESOURCE_PATH),
		"Save As writes a .tres Resource"
	)
	_expect(
		machine.definition.resource_path == TEST_RESOURCE_PATH,
		"Save As changes the Resource path"
	)
	_expect(
		ResourceLoader.load(TEST_RESOURCE_PATH) is StateMachineResource,
		"saved definition loads as StateMachineResource"
	)
	var saved_definition := machine.definition
	definition_toolbar._make_definition_unique()
	_expect(
		machine.definition != saved_definition
		and machine.definition.resource_path.is_empty(),
		"Make Unique turns an external definition into an embedded copy"
	)

	editor.free()
	machine.free()
	var absolute_path := ProjectSettings.globalize_path(TEST_RESOURCE_PATH)
	if FileAccess.file_exists(TEST_RESOURCE_PATH):
		DirAccess.remove_absolute(absolute_path)

	if _failures.is_empty():
		print("GState editor smoke test: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("GState editor smoke test: FAIL (%d)" % _failures.size())
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
