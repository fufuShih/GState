# Architecture

[Documentation index](README.md) | [Traditional Chinese](../zh-TW/architecture.md)

GState uses three levels of nodes:

```text
StateManager
├── Movement (StateMachine)
│   ├── Grounded (State)
│   │   ├── Idle (State)
│   │   └── Run (State)
│   └── Airborne (State)
└── Combat (StateMachine)
    ├── Peaceful (State)
    └── Attacking (State)
```

## StateManager

`StateManager` is the central entry point and only manages its direct
`StateMachine` children:

- Provides the default shared actor.
- Coordinates autostart, start, restart, and stop.
- Finds machines by name and forwards events.
- Does not store states, transitions, or active paths.

## StateMachine

Each `StateMachine` is fully independent:

- It owns its graph, initial state, active path, and runtime context.
- Events are not automatically forwarded to other StateMachines.
- It can be started, stopped, and assigned an actor independently.

A StateMachine cannot contain another StateMachine. Use nested states for
hierarchy. To model another state axis that runs at the same time, add another
StateMachine directly under the StateManager.

## State

A `State` is the node that actually enters, exits, and receives updates. A
State containing child States automatically becomes a compound state.

A simple rule of thumb:

```text
Only one state may be selected at a time → use one StateMachine
Two state groups may coexist             → use two StateMachines
A state needs internal substates         → use nested states
```

## StateContext

`initial_context` is an optional typed Resource derived from `StateContext`.
When a stopped machine starts, it duplicates that Resource into a runtime
instance. Every State in the machine receives the same runtime instance through
`get_context()`, while different machines remain isolated.
