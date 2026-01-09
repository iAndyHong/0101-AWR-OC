# AI Todo List - Grids 2.0

## 專案狀態總覽
- **版本**：1.21
- **建立日期**：2026-01-01
- **最後更新**：2026-01-01
- **進度回報**：已完成核心功能，待進行優化項目。

---

## 任務清單

### 1. 核心架構 [ARCH]
- [x] **TASK-ARCH-001：CEACore 整合**
  - 需求：REQ-GRID, REQ-RISK, REQ-PROFIT
  - 完成：引入 CEACore.mqh, 設定參數, 啟用模組 (Hedge, ProfitTrailing, Arrows, Panel)
- [x] **TASK-ARCH-002：CGridsCore 整合**
  - 需求：REQ-GRID, REQ-SIGNAL
  - 完成：引入 CGridsCore.mqh, 初始化網格核心, 設定回調
- [x] **TASK-ARCH-003：回調機制實作**
  - 需求：REQ-PROFIT-002
  - 完成：實作 OnRequestHedgeClose, OnGridClose

### 2. 網格交易功能 [GRID]
- [x] **TASK-GRID-001：網格模式實作**
  - 完成：支援 TREND 與 COUNTER 模式
- [x] **TASK-GRID-002：網格間距計算**
  - 完成：支援獨立縮放 (CalculateCumulativeDistance)
- [x] **TASK-GRID-003：手數管理**
  - 完成：支援獨立縮放 (CalculateScaledLots), 最大手數驗證
- [x] **TASK-GRID-004：層級控制**
  - 完成：買賣籃子獨立層級追蹤與重置
- [x] **TASK-GRID-005：止盈機制**
  - 完成：金額判斷與平倉回調
- [x] **TASK-GRID-006：獨立縮放設定**
  - 完成：PG_CounterGridScaling, PG_CounterLotScaling, PG_TrendGridScaling, PG_TrendLotScaling

### 3. 信號過濾功能 [SIGNAL]
- [x] **TASK-SIGNAL-001：過濾模式框架**
  - 完成：ENUM_FILTER_MODE, GetTrendSignal 分發
- [x] **TASK-SIGNAL-002：BullsBears 信號**
  - 完成：多空力量計算與閾值判斷
- [x] **TASK-SIGNAL-003：SuperTrend 信號**
  - 完成：ATR 趨勢方向判斷, 趨勢反轉檢測, 趨勢線繪製
- [x] **TASK-SIGNAL-004：首單/加倉過濾**
  - 完成：AllowFirstOrder, AllowAveraging 實作

### 4. 交易控制功能 [TRADE]
- [x] **TASK-TRADE-001：交易方向控制**
  - 完成：ENUM_TRADE_DIRECTION 買賣方向過濾
- [x] **TASK-TRADE-002：訂單保護**
  - 完成：每 K 線一單, 滑點設定, 最大單數限制
- [x] **TASK-TRADE-003：組別管理**
  - 完成：GroupID, MagicNumber 設定

### 5. 風險控制功能 [RISK]
- [x] **TASK-RISK-001：回撤控制**
  - 完成：CEACore MaxDrawdown 整合
- [x] **TASK-RISK-002：手數限制**
  - 完成：SetMaxLots 檢查
- [x] **TASK-RISK-003：點差過濾**
  - 完成：SetMaxSpread 檢查

### 6. 獲利保護功能 [PROFIT]
- [x] **TASK-PROFIT-001：獲利回跌停利**
  - 完成：CEACore ProfitTrailing 整合
- [x] **TASK-PROFIT-002：對沖平倉**
  - 完成：CEACore HedgeClose 整合

### 7. 效能與視覺化 [PERF/UI]
- [x] **TASK-PERF-001：計時器分層**
  - 完成：Timer1 (盈虧), Timer2 (UI) 分開更新
- [x] **TASK-PERF-002：緩存機制**
  - 完成：市場資訊與訂單統計緩存
- [x] **TASK-UI-001：交易箭頭**
  - 完成：CEACore Arrows 整合
- [x] **TASK-UI-002：SuperTrend 趨勢線**
  - 完成：動態顏色趨勢線繪製
- [x] **TASK-UI-003：資訊面板**
  - 完成：CEACore ChartPanel 整合

### 8. 除錯功能 [DEBUG]
- [x] **TASK-DEBUG-001：除錯日誌**
  - 完成：WriteLog, WriteDebugLog 檔案輸出

### 9. 待辦優化項目 [OPT]
- [ ] **TASK-OPT-001：動態參數調整**
  - 說明：支援運行時動態調整網格間距與止盈
- [ ] **TASK-OPT-002：多籃子支援**
  - 說明：支援同時運行多個獨立 MagicNumber 籃子
- [ ] **TASK-OPT-003：進階風控**
  - 說明：新聞時間避開、波動率過濾

---

## 變更紀錄
- 2026-01-01 (v1.20): 根據原始碼重建任務清單。
- 2026-01-01 (v1.21): 新增獨立縮放設定 (TASK-GRID-006)。
- 2026-01-06: 轉換為 OPENCODE 專案結構。
