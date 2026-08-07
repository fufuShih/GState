# Architecture

[Documentation index](README.md) | [Traditional Chinese](../zh-Hant/architecture.md)

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

## Context

`StateMachine.context` is a Dictionary edited directly in the Inspector.
When a stopped machine starts, it creates a deep runtime copy. Every State in
the machine receives that same live Dictionary through `get_context()`, while
different machines remain isolated.

## Transition actions

A transition may store one optional Action name. After matching an event, the
source State receives that name through perform_action(). The order is:

    Exit source path → perform optional action → enter target path

The Action remains a simple StringName; no Action Resource, array, or extra
scene node is required.
