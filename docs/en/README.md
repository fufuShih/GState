# GState Documentation

English | [Traditional Chinese](../zh-TW/README.md)

GState is a hierarchical, event-driven state machine addon for Godot. Each
`StateMachine` Node references a portable `StateMachineResource` containing
context, State resources, and Graph Editor metadata. Each State stores its own
outgoing event-to-target transition map.

## Documentation

- [Node2D quick start](getting-started.md)
- [Architecture](architecture.md)
- [Nested states](nested-states.md)
- [Runtime API](runtime-api.md)

## Currently supported

- `StateManager` and `StateMachine` nodes with `State` resources
- Reusable `.tres` state-machine definitions
- Multiple independent StateMachines under one manager
- Nested states at any depth
- One active child per scope
- Transitions between direct states in the same scope
- Event lookup from the deepest active state toward its parents
- Initial children for compound states
- Parent-scope exit events displayed inside child scopes
- Dictionary context shared by states in one machine
- `enter()`, `exit()`, `update()`, and `physics_update()`
- Graph Editor operations with Undo/Redo
- Godot Inspector integration for graph selections
- Definition New, Inspect, Save As, and Make Unique actions
- Inspector transition rows with same-scope Target dropdowns

## Not yet supported

- Parallel states
- History states
- Guards and conditions
- Transition actions
- Any State
- Direct graph connections across scopes
