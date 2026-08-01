# 架構

GState 使用三層 Node：

```text
StateManager
├── Movement (StateMachine)
│   ├── Grounded (State)
│   │   ├── Idle (State)
│   │   └── Run (State)
│   └── Airborne (State)
└── Combat (StateMachine)
	├── Peaceful (State)
	└── Attacking (State)
```

## StateManager

StateManager 是集中入口，只管理直接子節點中的 StateMachine：

- 共用預設 actor。
- 協調 autostart、start、restart 與 stop。
- 依名稱取得 Machine 或轉送 Event。
- 不保存 State、Transition 或 Active Path。

## StateMachine

每個 StateMachine 都是完全獨立的：

- 有自己的 Graph、Initial State 與 Active Path。
- Event 不會自動傳到其他 StateMachine。
- 可以個別啟動、停止及設定 actor。

StateMachine 不可以包含另一台 StateMachine。需要階層狀態時使用
Nested State；需要另一條可以同時運作的狀態軸時，直接在 StateManager
下增加另一台 StateMachine。

## State

State 是 StateMachine 中真正會進入、離開及更新的節點。State 底下包含
State 時會自動成為 Compound State。

簡單判斷方式：

```text
同一時間只能選一個狀態 → 放在同一台 StateMachine
兩組狀態可以同時存在   → 建立兩台獨立 StateMachine
一個狀態內還有細分狀態 → 使用 Nested State
```
