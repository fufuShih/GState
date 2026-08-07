# GState

See the [English documentation](../../docs/en/README.md) or
[Traditional Chinese documentation](../../docs/zh-TW/README.md).

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
by XState. Its runtime and Graph Editor currently use GDScript. The public scene
nodes are `StateManager` and `StateMachine`; a portable
`StateMachineResource` stores State resources, transitions, and graph metadata.

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

Set `StateMachine.initial_state_id` to `Grounded.stable_id`,
`Grounded.initial_child_id` to `Idle.stable_id`, and so on. Transitions connect
direct children in one scope:

```gdscript
var transition := StateTransition.new(
	grounded.stable_id,
	airborne.stable_id,
	&"jump"
)
state_machine.graph.add_transition(transition)
```

Nested transitions use the compound state's ID as their scope:

```gdscript
var transition := StateTransition.new(
	idle.stable_id,
	run.stable_id,
	&"move",
	grounded.stable_id
)
state_machine.graph.add_transition(transition)
```

## Runtime API

```gdscript
state_machine.start()
state_machine.send(&"move")
state_machine.send(&"jump", {"strength": 1.0})
state_machine.travel("Grounded/Run")

var leaf: State = state_machine.get_current_state()
var path: Array[State] = state_machine.get_active_path()
var grounded_is_active := state_machine.is_in_state("Grounded")
var context: StateContext = state_machine.get_context()
```

Create a typed Resource that extends `StateContext`, then assign it to
`StateMachine.initial_context` in the Inspector. Every State in that machine
receives the same live runtime copy through `get_context()`. Starting a stopped
machine or calling `restart()` creates a fresh copy of the initial Resource.

Override any lifecycle hooks needed by a State script:

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

Hooks run parent-to-child on enter/update and child-to-parent on exit.
`StateMachine.validate()` returns `errors` and `warnings` as
`PackedStringArray`s. `start()` validates the complete state tree and safely
refuses to run when errors are present.

## Graph Editor

Enable the `GState` plugin, then select a `StateManager` or `StateMachine`
in the Scene Tree. A small selector chooses the active machine; the graph
below it displays only that machine's current State scope:

- Use the machine selector to switch between independent machines.
- `+ Machine` creates a StateMachine directly under StateManager.
- Root shows root State resources in `StateMachine.definition`.
- Double-click a compound state to inspect its direct children.
- Use the breadcrumb to return to any parent scope.
- Initial states are marked with a dot.
- Transition events and connections are shown for the current scope.
- `+ State Here` creates a State in the current scope.
- `+ Child State` creates a child under the selected State.
- `Rename` renames the selected State; double-clicking a leaf does the same.
- `Set Initial` marks the selected State as the scope's initial State.
- Drag an output port to an input port, then enter the transition event.
- Every saved incoming and outgoing transition gets its own port row, so
  multiple transitions on one State no longer overlap on a single point.
- Edit or delete the transition selected in the transition list.
- Delete selected States and their descendant graph data.
- Dragging nodes saves their positions in `StateMachineResource`.
- Nodes only begin dragging from the titlebar after a short movement threshold.
- State, transition, initial, and position edits support Undo/Redo.
- Selecting a graph node opens its Resource properties in the Inspector.
- The Graph-side Inspector shows State, Transition, and valid same-scope targets.
- Validation issues can be opened from the `Issues` button.

The complete hierarchy, transitions, and view metadata are serialized in
`StateMachineResource`. Save `StateMachine.definition` as `.tres` to share
it across scenes or projects.
