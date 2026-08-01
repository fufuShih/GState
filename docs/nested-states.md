# Nested State

State 底下包含其他 State 時，它就是 Compound State：

```text
StateMachine
├── Grounded
│   ├── Idle
│   └── Run
└── Airborne
	├── Jump
	└── Fall
```

## Active Path

每一層只能有一個 Active Child。目前位於 `Run` 時，完整 Active Path 是：

```text
Grounded/Run
```

可以使用：

```gdscript
var leaf: State = state_machine.get_current_state()
var path: Array[State] = state_machine.get_active_path()

state_machine.is_in_state("Grounded")
state_machine.is_in_state("Grounded/Run")
```

## Initial State

每個 Compound State 都需要 Initial Child。進入 `Grounded` 時，GState
會自動展開至 Initial Child：

```text
Grounded → Grounded/Idle
```

Graph Editor 的 Scope 摘要會顯示：

```text
Initial: Idle
```

## Exit

GState 不使用會成為 Active State 的 Final State。Compound State 在父
Scope 的 outgoing Transition 就是整個 Scope 共用的 Exit：

```text
Root:
Grounded --jump--> Airborne
```

即使目前位於 `Grounded/Run`，`send(&"jump")` 仍會由 `Run` 往父層搜尋，
找到 `Grounded` 的 Transition。

呼叫順序為：

```text
Run.exit()
Grounded.exit()
Airborne.enter()
Jump.enter()
```

不需要建立 `End`、`Exit` 或 `Final` 節點。離開 Compound State 時，一律
回到父 Scope，從 Compound State 建立 Transition。子 Scope 上方會唯讀
顯示這些父層 Exit events，方便確認哪些事件可以離開目前 Scope。

如果只有某個 Child 應該允許離開，第一版建議由遊戲程式決定何時送出
該事件；Graph 規則仍保持單純，不加入跨 Scope 連線或特殊節點。

## Scope 規則

Transition 只能連接同一 Scope 的直接子 State：

```text
Root:
Grounded → Airborne

Grounded:
Idle → Run
```

也不建立 Child 到父層兄弟的跨 Scope 連線：

```text
Grounded/Run → Airborne
```

應改在 Root Scope 建立 `Grounded → Airborne`；進入後 GState 會自動
前往 `Airborne` 的 Initial Child。
