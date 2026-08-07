# GState

See the [English documentation](../../docs/en/README.md) or
[Traditional Chinese documentation](../../docs/zh-Hant/README.md).

Graph nodes use separate, color-coded `IN` and `OUT` columns. Each transition
occupies its own taller row and shows only its event name; the connection itself
communicates the source and target states.

Nested editing is scope based. Select a State and use the toolbar's
`+ Child State` action to create a child, then double-click a compound State to
edit its child scope. The first state in every scope becomes initial
automatically; use `Back` or the breadcrumb to return to a parent scope. A scope
summary shows its Initial State and the parent-level events that can exit it.
To leave a nested scope, create an outgoing transition from its compound State
in the parent scope. No End or Final node is required.

GState is a hierarchical, event-driven state machine plugin for Godot, inspired
by XState. Its runtime and Graph Editor currently use GDScript. The public nodes
are `StateManager`, `StateMachine`, and `State`; transitions live in the
`StateMachineGraph` resource.

## Scene structure

```text
Player
└── StateManager
	├── Movement (StateMachine)
	│   ├── Grounded
	│   │   ├── Idle
	│   │   └── Run
	│   ├── Airborne
	│   │   ├── Jump
	│   │   └── Fall
	└── Combat (StateMachine)
		├── Peaceful
		└── Attacking
```

StateManager owns direct, independent StateMachine children. StateMachine nodes
cannot contain other StateMachine nodes. Use Nested State for hierarchy inside
one machine.

Create States, choose the initial State, and connect transitions in the GState
panel. Internal IDs and graph storage are maintained automatically and stay
hidden from the Inspector. Runtime code can use readable names such as
`"Grounded/Run"`.

## Runtime API

```gdscript
state_machine.start()
state_machine.send(&"move")
state_machine.send(&"jump", {"strength": 1.0})
state_machine.travel("Grounded/Run")

var leaf: State = state_machine.get_current_state()
var run: State = state_machine.get_state("Grounded/Run")
var path: Array[State] = state_machine.get_active_path()
var grounded_is_active := state_machine.is_in_state("Grounded")
var context: Dictionary = state_machine.get_context()
```

Edit `StateMachine.context` directly as a Dictionary in the Inspector. Every
State in that machine receives the same live runtime copy through
`get_context()`. Starting a stopped machine or calling `restart()` creates a
fresh deep copy, so the Inspector defaults stay unchanged.

Each transition can have one optional Action name. The source State handles it
after exit hooks and before target entry:

    func perform_action(
            action: StringName,
            _target_state: State,
            payload: Variant = null
    ) -> void:
        match action:
            &"apply_jump":
                actor.velocity.y = payload.get("velocity", 5.0)

Override any lifecycle hooks needed by a State script:

```gdscript
extends State

func enter(previous_state: State, payload: Variant = null) -> void:
	pass

func exit(next_state: State) -> void:
	pass

func perform_action(
		action: StringName,
		_target_state: State,
		_payload: Variant = null
) -> void:
	pass

func update(delta: float) -> void:
	pass

func physics_update(delta: float) -> void:
	pass
```

Hooks run parent-to-child on enter/update and child-to-parent on exit.
Transition order is exit, optional action, then enter.
`StateMachine.validate()` returns `errors` and `warnings` as
`PackedStringArray`s. `start()` validates the complete state tree and safely
refuses to run when errors are present.

## Graph Editor

Enable the `GState` plugin, then select a `StateManager`, `StateMachine`, or
`State` in the Scene Tree. A small selector chooses the active machine; the graph
below it displays only that machine's current State scope:

- Use the machine selector to switch between independent machines.
- `+ Machine` creates a StateMachine directly under StateManager.
- Root shows direct children of `StateMachine`.
- Double-click a compound state to inspect its direct children.
- Use the breadcrumb to return to any parent scope.
- Initial states are marked with a dot.
- Transition events and connections are shown for the current scope.
- `+ State Here` creates a State in the current scope.
- `+ Child State` creates a child under the selected State.
- `Rename` renames the selected State; double-clicking a leaf does the same.
- `Set Initial` marks the selected State as the scope's initial State.
- Drag an output port to an input port, then enter the transition event and an
  optional action name.
- Every saved incoming and outgoing transition gets its own port row, so
  multiple transitions on one State no longer overlap on a single point.
- Edit the event or optional action of the selected transition, or delete it.
- Delete selected States and their descendant graph data.
- Dragging nodes saves their positions in `StateMachineGraph`.
- Nodes only begin dragging from the titlebar after a short movement threshold.
- State, transition, initial, and position edits support Undo/Redo.
- Selecting a graph node also selects it in the Scene Tree and Inspector.
- Selecting a State in the Scene Tree opens its parent graph scope.
- Scene Tree rename, add, remove, and reorder operations refresh automatically.
- Validation issues can be opened from the `Issues` button.

The Refresh button reloads state names and hierarchy changes from the Scene
Tree. Scene hierarchy remains the source of truth; graph transitions and view
metadata are serialized in `StateMachineGraph`.
