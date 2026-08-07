# 架構

[文件索引](README.md) | [English](../en/architecture.md)

GState 使用兩層場景 Node，加上一份可攜的 Resource 定義：

```text
StateManager
├── Movement (StateMachine) → movement.tres
└── Combat (StateMachine)   → combat.tres
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

State 是 `StateMachineResource` 中真正會進入、離開及更新的 Resource。
State 的 `children` 包含其他 State 時會自動成為 Compound State。
StateMachine 啟動時會深複製定義樹，所以多台 Machine 可以安全共用同一
份 `.tres`。

簡單判斷方式：

```text
同一時間只能選一個狀態 → 放在同一台 StateMachine
兩組狀態可以同時存在   → 建立兩台獨立 StateMachine
一個狀態內還有細分狀態 → 使用 Nested State
```
