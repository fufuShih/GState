# Runtime Debug Panel

[English](../en/debug-panel.md) | 繁體中文

`StateDebugPanel` 是開發期間選用的遊戲內除錯面板，可顯示每台 Machine
的執行狀態、Active Path、最近一次 Transition、Context，以及最近成功或
被拒絕的 Events。

## 設定

1. 實例化 `res://addons/gstate/debug/state_debug_panel.tscn`。
2. 在 Inspector 將 StateManager 指派給 `state_manager`。
3. 執行遊戲，按 `F8` 顯示或隱藏面板。

若沒有指派，面板可以自動尋找第一個 StateManager；明確指派則能讓場景行為
更容易預測。

按減號可將面板縮成一列標題，拖曳 `GState` 標題列即可移動。按鈕與
Machine 選單不會保留鍵盤焦點，因此不會攔截遊戲按鍵。選用的 Event
輸入欄只會在點擊後取得焦點，送出或按 Escape 後會立即釋放。

啟用 `allow_send_events` 後會顯示 Event 輸入欄。此功能預設關閉，讓面板
只負責觀察。預設啟用的 `debug_build_only` 會在非 Debug 匯出中移除面板。

面板只監聽既有 runtime signals，不會改變狀態機行為。完整範例請參考
`examples/example5/example.tscn`。
