extends State

static var calls: Array[String] = []


func enter(_previous_state: State, _payload: Variant = null) -> void:
	calls.append("enter:%s" % name)


func exit(_next_state: State) -> void:
	calls.append("exit:%s" % name)


func update(_delta: float) -> void:
	calls.append("update:%s" % name)


func physics_update(_delta: float) -> void:
	calls.append("physics:%s" % name)
