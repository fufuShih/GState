# Runtime API

[Documentation index](README.md) | [Traditional Chinese](../zh-TW/runtime-api.md)

## StateManager

```gdscript
@onready var state_manager: StateManager = $StateManager

state_manager.start()
state_manager.restart()
state_manager.stop()

var movement := state_manager.get_machine(&"Movement")
state_manager.send_to(&"Movement", &"move")
```

`StateManager` manages direct `StateMachine` children. Each machine is
independent. When the manager has no explicit `actor`, it uses its parent Node.
An actor assigned directly to a StateMachine takes precedence.

- Manager autostart only starts machines with `autostart` enabled.
- Calling `state_manager.start()` explicitly starts every active machine.
- A machine can still be started or stopped directly.

## StateMachine

### Control

```gdscript
state_machine.start()
state_machine.restart()
state_machine.stop()
```

`start()` and `restart()` return `bool`. The machine validates its complete
configuration before starting and does not enter any state when validation
contains errors.

### Events and transitions

```gdscript
state_machine.send(&"move")
state_machine.send(&"damage", {"amount": 10})
state_machine.travel("Grounded/Run")
state_machine.travel($StateManager/Movement/Grounded/Run)
```

- `send()` searches the current active path for an event transition.
- `payload` is passed to `enter()` and signals for that transition.
- `travel()` moves directly to a State or state path without a transition.
- Entering a compound state automatically follows its initial children.

### Context

Edit the `context` Dictionary directly in the StateMachine Inspector:

```gdscript
{
	&"speed": 120.0,
	&"direction": Vector2.ZERO,
}
```

A State reads and writes the runtime copy directly:

```gdscript
extends State


func enter(_previous_state: State, _payload: Variant = null) -> void:
	var context := get_context()
	context[&"speed"] = 240.0
	context[&"direction"] = Vector2.RIGHT
```

- Every State in one StateMachine receives the same runtime Dictionary.
- Starting a stopped machine or calling `restart()` deep-copies `context`,
  leaving the Inspector defaults unchanged.
- An empty `context` returns an empty Dictionary.
- `reset_context()` explicitly creates a fresh runtime copy.
- Runtime contexts are isolated between StateMachines.

### Queries

```gdscript
var current: State = state_machine.get_current_state()
var run: State = state_machine.get_state("Grounded/Run")
var path: Array[State] = state_machine.get_active_path()
var running: bool = state_machine.is_running()

state_machine.is_in_state("Grounded")
state_machine.is_in_state("Grounded/Run")
state_machine.is_in_state($StateManager/Movement/Grounded)
```

`get_state()` resolves a readable State name or nested path without exposing
internal IDs. `get_current_state()` returns the deepest State in the active
path, or `null` when the machine has no active State.

### Validation

```gdscript
var result: Dictionary = state_machine.validate()
var errors: PackedStringArray = result["errors"]
var warnings: PackedStringArray = result["warnings"]
```

## State lifecycle

A State script can override any lifecycle hook:

```gdscript
extends State


func enter(previous_state: State, payload: Variant = null) -> void:
	pass


func exit(next_state: State) -> void:
	pass


func update(delta: float) -> void:
	pass


func physics_update(delta: float) -> void:
	pass
```

Lifecycle order:

```text
Enter / Update / Physics → parent to child
Exit                     → child to parent
```

States do not need to enable `_process()` themselves. The StateMachine drives
only States on the active path.

## Signals

```gdscript
state_machine.started.connect(_on_started)
state_machine.stopped.connect(_on_stopped)
state_machine.transitioned.connect(_on_transitioned)
state_machine.transition_rejected.connect(_on_rejected)
state_machine.state_entered.connect(_on_state_entered)
state_machine.state_exited.connect(_on_state_exited)
state_machine.active_path_changed.connect(_on_active_path_changed)
```

Use `active_path_changed` when displaying a complete nested path:

```gdscript
func _on_active_path_changed(path: Array[State]) -> void:
	var names := PackedStringArray()
	for state: State in path:
		names.append(str(state.name))
	print("/".join(names))
```
