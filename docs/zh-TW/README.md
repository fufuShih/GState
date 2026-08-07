# GState 文件

[English](../en/README.md) | 繁體中文

GState 是 Godot 的階層式、事件驅動狀態機插件。狀態階層由 Scene Tree
管理，Transition 與 Graph 版面會自動隨場景儲存。

## 文件索引

- [Node2D 快速入門](getting-started.md)
- [架構](architecture.md)
- [Nested State](nested-states.md)
- [Runtime API](runtime-api.md)

## 目前支援

- `StateManager`、`StateMachine` 與 `State` Node
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

## 尚未支援

- Parallel State
- History State
- Guard 與 Condition
- Transition Action
- Any State
- 跨 Scope 的直接 Graph 連線
