# Nested States

[Documentation index](README.md) | [Traditional Chinese](../zh-TW/nested-states.md)

A State becomes a compound state when it contains other States:

```text
StateMachine
├── Grounded
│   ├── Idle
│   └── Run
└── Airborne
    ├── Jump
    └── Fall
```

## Active path

Each scope can have only one active child. When `Run` is active, the complete
active path is:

```text
Grounded/Run
```

Use the runtime API to query it:

```gdscript
var leaf: State = state_machine.get_current_state()
var path: Array[State] = state_machine.get_active_path()

state_machine.is_in_state("Grounded")
state_machine.is_in_state("Grounded/Run")
```

## Initial state

Every compound state needs an initial child. Entering `Grounded` automatically
expands the active path to its initial child:

```text
Grounded → Grounded/Idle
```

The Graph Editor scope summary displays:

```text
Initial: Idle
```

## Exit transitions

GState does not use a Final State that becomes active. An outgoing transition
from a compound state in its parent scope acts as the shared exit for that
entire child scope:

```text
Root:
Grounded --jump--> Airborne
```

Even when `Grounded/Run` is active, `send(&"jump")` searches from `Run` toward
its parents and finds the transition on `Grounded`.

The lifecycle order is:

```text
Run.exit()
Grounded.exit()
Airborne.enter()
Jump.enter()
```

You do not need `End`, `Exit`, or `Final` nodes. To leave a compound state,
return to the parent scope and create a transition from that compound state.
The child scope displays these parent-level exit events as read-only context.

If only one child should be allowed to leave, the initial version recommends
that game logic decides when to send the event. The graph remains simple and
does not add cross-scope edges or special nodes.

## Scope rules

A transition can only connect direct child States in the same scope:

```text
Root:
Grounded → Airborne

Grounded:
Idle → Run
```

Do not create a direct cross-scope edge from a child to its parent sibling:

```text
Grounded/Run → Airborne
```

Instead, create `Grounded → Airborne` in the root scope. After entering
`Airborne`, GState automatically follows its initial-child chain.
