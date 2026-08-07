# GState

GState is a lightweight, hierarchical, event-driven state machine addon for
Godot 4. Each StateMachine Node references a portable
`StateMachineResource` that stores context, the complete state tree, and graph
layout. Each State owns a small event-to-target transition map. Save the
resource as `.tres` to reuse the same definition across scenes.

- Nested and compound states
- Multiple independent state machines per manager
- Event-driven transitions with parent-scope fallback
- Dictionary context shared by states in one machine
- State lifecycle hooks and active-path queries
- Graph editing with Undo/Redo support
- Inspector transition rows with Event fields and same-scope Target dropdowns

## Documentation

- [English documentation](docs/en/README.md)
- [Traditional Chinese documentation](docs/zh-TW/README.md)

The addon is located in `addons/gstate/`. Enable **GState** from
**Project > Project Settings > Plugins** after copying it into a Godot project.
