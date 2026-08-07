extends State

var calls: Array[String] = []


func enter(_previous_state: State, _payload: Variant = null) -> void:
	calls.append("enter:%s" % name)


func exit(_next_state: State) -> void:
	calls.append("exit:%s" % name)


func perform_action(
		action: StringName,
		_target_state: State,
		_payload: Variant = null
) -> void:
	calls.append("action:%s:%s" % [name, action])


func update(_delta: float) -> void:
	calls.append("update:%s" % name)


func physics_update(_delta: float) -> void:
	calls.append("physics:%s" % name)
