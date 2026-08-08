# GState Documentation

English | [Traditional Chinese](../zh-Hant/README.md)

GState is a hierarchical, event-driven state machine addon for Godot. The
Scene Tree owns the state hierarchy, while transitions and graph layout are
saved with the scene automatically.

## Documentation

- [Node2D quick start](getting-started.md)
- [Architecture](architecture.md)
- [Nested states](nested-states.md)
- [Runtime API](runtime-api.md)
- [Runtime Debug Panel](debug-panel.md)

## Currently supported

- `StateManager`, `StateMachine`, and `State` nodes
- Multiple independent StateMachines under one manager
- Nested states at any depth
- One active child per scope
- Transitions between direct states in the same scope
- Event lookup from the deepest active state toward its parents
- Initial children for compound states
- Parent-scope exit events displayed inside child scopes
- One optional action per transition
- Dictionary context shared by states in one machine
- `enter()`, `exit()`, `update()`, and `physics_update()`
- Optional in-game Runtime Debug Panel
- Graph Editor operations with Undo/Redo

## Not yet supported

- Parallel states
- History states
- Guards and conditions
- Any State
- Direct graph connections across scopes
