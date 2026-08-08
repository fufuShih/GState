# Runtime Debug Panel

English | [Traditional Chinese](../zh-Hant/debug-panel.md)

`StateDebugPanel` is an optional in-game overlay for development builds. It
shows each machine''s running status, active path, last transition, context, and
recent accepted or rejected events.

## Setup

1. Instantiate `res://addons/gstate/debug/state_debug_panel.tscn`.
2. Assign your `StateManager` to `state_manager` in the Inspector.
3. Run the game and press `F8` to show or hide the panel.

The panel can find the first StateManager automatically when the property is
empty, but assigning it explicitly keeps scenes predictable.

Use the minus button to collapse the panel to one title row. Drag the `GState`
header to move it. Its buttons and machine selector
do not keep keyboard focus, so gameplay keys continue working. The optional
event field only takes focus when clicked and releases it after submission or
when pressing Escape.

Enable `allow_send_events` to display a small event input. This is disabled by
default so the panel remains observation-only. `debug_build_only` is enabled by
default and removes the panel from non-debug exports.

The panel only listens to existing runtime signals and does not change state
machine behavior. See `examples/example5/example.tscn` for a complete example.
