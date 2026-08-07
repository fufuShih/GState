# Runtime API

[文件索引](README.md) | [English](../en/runtime-api.md)

## StateManager

```gdscript
@onready var state_manager: StateManager = $StateManager

state_manager.start()
state_manager.restart()
state_manager.stop()

var movement := state_manager.get_machine(&"Movement")
state_manager.send_to(&"Movement", &"move")
```

StateManager 管理直接子節點中的 StateMachine。Machine 之間彼此獨立。
Manager 的 `actor` 沒有設定時預設使用自己的父 Node；個別 StateMachine
有設定 actor 時則優先使用自己的設定。

- Manager 自動啟動時，只啟動 `autostart` 開啟的 Machine。
- 明確呼叫 `state_manager.start()` 時，啟動所有 active Machine。
- 仍可直接呼叫某一台 Machine 的 `start()` 或 `stop()`。

## StateMachine

### 控制

```gdscript
state_machine.start()
state_machine.restart()
state_machine.stop()
```

`start()` 與 `restart()` 回傳 `bool`。啟動前會執行驗證；存在嚴重錯誤時
不會進入任何狀態。

### 事件與切換

```gdscript
state_machine.send(&"move")
state_machine.send(&"damage", {"amount": 10})
state_machine.travel("Grounded/Run")
state_machine.travel($StateManager/Movement/Grounded/Run)
```

- `send()` 根據目前 Active Path 搜尋 Event Transition。
- `payload` 只在本次切換中傳給 `enter()` 與 Signal。
- `travel()` 不需要 Transition，會直接前往 State 或 State Path。
- 進入 Compound State 時會自動展開 Initial Child。

### Context

Context 直接使用 `Dictionary`，可以在 StateMachine 的 Inspector 中設定初始值：

```gdscript
context = {
	"speed": 120.0,
	"direction": Vector2.ZERO,
}
```

State script 取得後即可直接讀寫：

```gdscript
extends State


func enter(_previous_state: State, payload: Variant = null) -> void:
	var machine_context := get_context()
	machine_context["speed"] = 240.0
	machine_context["direction"] = Vector2.RIGHT
```

- 同一個 StateMachine 的所有 State 取得同一個 runtime Dictionary。
- 從 stopped 狀態成功 `start()` 或呼叫 `restart()` 時，StateMachine
  會深層複製 `context`，不會修改 Inspector 中的初始值。
- 不需要 context 時保持空 Dictionary 即可。
- `reset_context()` 可在執行中明確建立一份新的初始 context。
- 不同 StateMachine 的 runtime context 彼此隔離。

### 查詢

```gdscript
var current: State = state_machine.get_current_state()
var run: State = state_machine.get_state("Grounded/Run")
var path: Array[State] = state_machine.get_active_path()
var running: bool = state_machine.is_running()

state_machine.is_in_state("Grounded")
state_machine.is_in_state("Grounded/Run")
state_machine.is_in_state($StateManager/Movement/Grounded)
```

`get_state()` 可用易讀的 State 名稱或巢狀路徑取得節點，不需要接觸內部
ID。`get_current_state()` 回傳 Active Path 最深層的 State；沒有 Active
State 時回傳 `null`。

### 驗證

```gdscript
var result: Dictionary = state_machine.validate()
var errors: PackedStringArray = result["errors"]
var warnings: PackedStringArray = result["warnings"]
```

## State lifecycle

State 腳本可以覆寫：

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

呼叫順序：

```text
Enter／Update／Physics → 父到子
Exit                   → 子到父
```

State 不需要自行啟用 `_process()`；只有 Active Path 上的 State 會由
StateMachine 驅動。

## Signals

```gdscript
state_machine.started.connect(_on_started)
state_machine.stopped.connect(_on_stopped)
state_machine.transitioned.connect(_on_transitioned)
state_machine.transition_rejected.connect(_on_rejected)
state_machine.state_entered.connect(_on_state_entered)
state_machine.state_exited.connect(_on_state_exited)
state_machine.active_path_changed.connect(_on_active_path_changed)
```

需要顯示完整 Nested Path 時，建議使用 `active_path_changed`：

```gdscript
func _on_active_path_changed(path: Array[State]) -> void:
	var names := PackedStringArray()
	for state: State in path:
		names.append(str(state.name))
	print("/".join(names))
```
