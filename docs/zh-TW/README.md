# GState 文件

[English](../en/README.md) | 繁體中文

GState 是 Godot 的階層式、事件驅動狀態機插件。場景中只需要
`StateManager` 與 `StateMachine` Node；Context、完整 State 階層與
Graph Editor 資料都儲存在可重用的 `StateMachineResource`（`.tres`）。
每個 State 自己保存 Event 到目標 State 的 Transition Dictionary。

## 文件索引

- [Node2D 快速入門](getting-started.md)
- [架構](architecture.md)
- [Nested State](nested-states.md)
- [Runtime API](runtime-api.md)

## 目前支援

- `StateManager`、`StateMachine` Node 與 `State` Resource
- 可跨場景與專案複用的 `.tres` 狀態機定義
- 一個 Manager 管理多台獨立 StateMachine
- 任意深度的 Nested State
- 每層一個 Active Child
- 同一 Scope 內的 Transition
- 事件由最深層往父層搜尋
- Compound State 的 Initial Child
- 子 Scope 顯示父層可用的 Exit events
- 同一台 Machine 內共用的 Context Dictionary
- `enter()`、`exit()`、`update()` 與 `physics_update()`
- Graph Editor 與 Undo/Redo
- Graph 選取項目與 Godot 原生 Inspector 整合
- Definition 的 New、Inspect、Save As 與 Make Unique 操作
- Inspector 的 Event 欄位與同 Scope Target 下拉選單

## 尚未支援

- Parallel State
- History State
- Guard 與 Condition
- Transition Action
- Any State
- 跨 Scope 的直接 Graph 連線
