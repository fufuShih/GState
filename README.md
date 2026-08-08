# GState

GState is a lightweight, hierarchical, event-driven state machine addon for
Godot 4. Its state hierarchy lives in the Scene Tree, while transitions are
edited through a scope-based graph editor.

- Nested and compound states
- Multiple independent state machines per manager
- Event-driven transitions with parent-scope fallback
- One optional action per transition
- Dictionary context shared by states in one machine
- State lifecycle hooks and active-path queries
- Graph editing with Undo/Redo support

## Documentation

- [English documentation](docs/en/README.md)
- [Traditional Chinese documentation](docs/zh-Hant/README.md)
- [Examples](examples/README.md)

The addon is located in `addons/gstate/`. Enable **GState** from
**Project > Project Settings > Plugins** after copying it into a Godot project.
