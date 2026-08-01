@tool
@icon("res://addons/gstate/icons/state_manager.svg")
class_name StateManager
extends Node

## Owns multiple independent StateMachine children.

signal started
signal stopped
signal machine_started(machine: StateMachine)
signal machine_stopped(machine: StateMachine)

@export var active: bool = true
@export var autostart: bool = true
@export var actor: Node

func _enter_tree() -> void:
	add_to_group(&"_gstate_managers")


func _ready() -> void:
	_register_state_machines()
	if Engine.is_editor_hint():
		return
	if active and autostart:
		_start_machines(true)


## Explicitly starts every active child machine.
func start() -> bool:
	return _start_machines(false)


func restart() -> bool:
	stop()
	return start()


func stop() -> void:
	for machine: StateMachine in get_state_machines():
		if machine.is_running():
			machine.stop()
			machine_stopped.emit(machine)
	stopped.emit()


func get_state_machines() -> Array[StateMachine]:
	var result: Array[StateMachine] = []
	for child: Node in get_children():
		if child is StateMachine:
			result.append(child as StateMachine)
	return result


func get_machine(machine_or_name: Variant) -> StateMachine:
	if machine_or_name is StateMachine:
		var machine := machine_or_name as StateMachine
		return machine if machine.get_parent() == self else null
	var wanted_name := StringName(str(machine_or_name))
	for machine: StateMachine in get_state_machines():
		if machine.name == wanted_name:
			return machine
	return null


func send_to(
		machine_or_name: Variant,
		event: StringName,
		payload: Variant = null
) -> bool:
	var machine := get_machine(machine_or_name)
	return machine != null and machine.send(event, payload)


func is_running() -> bool:
	for machine: StateMachine in get_state_machines():
		if machine.is_running():
			return true
	return false


func get_actor() -> Node:
	return actor if actor != null else get_parent()


func _register_state_machines() -> void:
	for machine: StateMachine in get_state_machines():
		_register_machine(machine)


func _register_machine(machine: StateMachine) -> void:
	if machine != null and machine.get_parent() == self:
		machine._set_state_manager(self)


func _start_machines(autostart_only: bool) -> bool:
	if not active:
		return false
	_register_state_machines()
	var success := true
	for machine: StateMachine in get_state_machines():
		if not machine.active or (autostart_only and not machine.autostart):
			continue
		if machine.start():
			machine_started.emit(machine)
		else:
			success = false
	started.emit()
	return success
