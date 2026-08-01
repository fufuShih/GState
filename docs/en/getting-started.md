# Node2D Quick Start

[Documentation index](README.md) | [Traditional Chinese](../zh-TW/getting-started.md)

## 1. Enable the addon

Open the following page in Godot:

```text
Project > Project Settings > Plugins
```

Enable `GState`. If `StateManager` or `StateMachine` still does not appear in
the Add Node dialog, disable and re-enable the addon or reopen the project.

## 2. Create the scene

Build this Scene Tree:

```text
Example (Node2D)
├── Status (Label)
└── StateManager
    └── Main (StateMachine)
        ├── Enabled
        │   ├── Idle
        │   └── Moving
        └── Disabled
```

Create a `StateManager` first. Select it, open the GState bottom panel, click
`+ Machine`, and rename the new machine to `Main`.

Select `Main` from the State Machine selector at the top of the panel:

1. In the root scope, click `+ State Here` and create `Enabled`.
2. Create `Disabled` in the root scope.
3. Select `Enabled`, then click `+ Child of Enabled` to create `Idle`.
4. Inside the `Enabled` scope, click `+ State Here` to create `Moving`.
5. Double-click a compound state to enter its child scope.
6. Use `Back` or the breadcrumb to return to a parent scope.

The first State in each scope automatically becomes its initial state. You can
select another State and click `Set Initial` to change it.

## 3. Create transitions

Create these transitions in the `Enabled` scope:

```text
Idle --move--> Moving
Moving --stop--> Idle
```

Create these transitions in the root scope:

```text
Enabled --disable--> Disabled
Disabled --enable--> Enabled
```

Drag from the green `OUT` port on the right to the blue `IN` port on the left,
then enter the event name.

The editor displays the result as `State -> [event] -> State`. Drag the small
event node to adjust the layout, double-click it to edit the event, or select it
and press `Delete` to remove the transition.

When you enter a child scope, the summary above the graph displays exit events
available from the parent scope. Leaving a nested state does not require a
special node. Return to the parent scope and create a transition from the
compound state. For example, `Enabled --disable--> Disabled` applies to every
active child below `Enabled`.

## 4. Attach a test script

Disable `StateManager.autostart`, then attach this script to `Example`:

```gdscript
extends Node2D

@onready var state_manager: StateManager = $StateManager
@onready var state_machine: StateMachine = $StateManager/Main
@onready var status: Label = $Status


func _ready() -> void:
	state_machine.active_path_changed.connect(_update_status)
	if not state_manager.start():
		status.text = "StateManager failed to start"
		return
	_update_status(state_machine.get_active_path())


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	match key_event.keycode:
		KEY_SPACE:
			if state_machine.is_in_state("Enabled/Idle"):
				state_machine.send(&"move")
			elif state_machine.is_in_state("Enabled/Moving"):
				state_machine.send(&"stop")
		KEY_D:
			if state_machine.is_in_state("Disabled"):
				state_machine.send(&"enable")
			else:
				state_machine.send(&"disable")


func _update_status(path: Array[State]) -> void:
	var names := PackedStringArray()
	for state: State in path:
		names.append(str(state.name))
	status.text = "Current: %s" % "/".join(names)
```

## 5. Expected result

```text
Start       → Enabled/Idle
Space       → Enabled/Moving
Space again → Enabled/Idle
D           → Disabled
D again     → Enabled/Idle
```
