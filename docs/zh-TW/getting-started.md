# Node2D 快速入門

[文件索引](README.md) | [English](../en/getting-started.md)

## 1. 啟用插件

在 Godot 開啟：

```text
Project > Project Settings > Plugins
```

啟用 `GState`。如果 Add Node 視窗仍找不到 `StateManager` 或
`StateMachine`，重新啟用插件或重新開啟專案。

## 2. 建立場景

建立以下 Scene Tree：

```text
Example (Node2D)
├── Status (Label)
└── StateManager
	└── Main (StateMachine)
		└── definition = main_state_machine.tres
```

先建立 `StateManager`。選取它後，在底部 GState 面板點
`+ Machine`，將新 Machine 命名為 `Main`。

使用面板上方的 State Machine 選擇器選擇 `Main`：

1. 在 Root 點 `+ State Here` 建立 `Enabled`。
2. 再建立 `Disabled`。
3. 選取 `Enabled`，點工具列的 `+ Child of Enabled` 建立 `Idle`。
4. 在 `Enabled` Scope 點 `+ State Here` 建立 `Moving`。
5. 雙擊 Compound State 可進入子 Scope。
6. 使用 `Back` 或 Breadcrumb 返回父 Scope。

每個 Scope 的第一個 State 會自動成為 Initial State，也可以選取 State
後按 `Set Initial` 修改。

所有操作都會寫入 `StateMachine.definition`，不會在 Main 底下建立
State 子節點。Graph 上方的 Definition 列會顯示目前是內嵌資源或外部
`.tres`；按 **Save As...** 可存成 `main_state_machine.tres`。其他場景
只要把同一份資源指派給 StateMachine，就能共用相同定義；若只想修改
其中一台，先按 **Make Unique**。每台 Machine 的 runtime State 仍會
各自複製，不會互相污染。

在 Graph 選取 State 時，Godot 原生 Inspector 會直接開啟該資源；選取
Transition 時則會開啟它的來源 State，因為 Transition 就存放在該
State 的 `transitions` 欄位。

State 的 `Transitions` 屬性會為每條連線顯示 Event 欄位、同 Scope
Target 下拉選單與刪除按鈕；使用 `+ Add Transition` 就能新增，不需要
複製任何內部 ID。

## 3. 建立 Transition

在 `Enabled` Scope 建立：

```text
Idle --move--> Moving
Moving --stop--> Idle
```

在 Root Scope 建立：

```text
Enabled --disable--> Disabled
Disabled --enable--> Enabled
```

從右側綠色 `OUT` 拖到左側藍色 `IN`，然後輸入 Event 名稱。

建立後，Event 名稱會完整顯示在來源 State 的綠色 `OUT` 旁；目標 State
的藍色 `IN` 維持數字編號。若要修改或刪除 Transition，使用 Graph 上方的
Transition 選擇器。

進入子 Scope 時，上方摘要會顯示父層可用的 Exit events。離開 Nested
State 不需要特殊節點；回到父 Scope，從 Compound State 建立 Transition
即可。例如 `Enabled --disable--> Disabled` 對 `Enabled` 底下所有 Child
都有效。

## 4. 掛上測試腳本

將 `StateManager.autostart` 關閉，然後把以下腳本掛在 `Example`：

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

## 5. 預期結果

```text
啟動       → Enabled/Idle
Space      → Enabled/Moving
再次 Space → Enabled/Idle
D          → Disabled
再次 D     → Enabled/Idle
```
