# Grids 2.0 需求文件

## 文件資訊

- 版本：1.21
- 建立日期：2026-01-01
- 最後更新：2026-01-01

---

## 1. 系統概述

### 1.1 產品定位

Grids 2.0 是一個基於 MT4 平台的網格交易 EA，採用模組化架構設計，整合 CEACore 中樞框架與 CGridsCore 網格核心，提供靈活的網格交易策略。

### 1.2 核心價值

- 模組化設計：核心邏輯與輔助功能分離
- 多種信號模式：支援 SuperTrend、BullsBears、Simple 三種過濾模式
- 雙向網格：支援順向網格（趨勢跟隨）與逆向網格（均值回歸）
- 獨立縮放：順向/逆向網格各有獨立的間距與手數縮放參數
- 完整風控：回撤控制、手數限制、點差過濾
- 獲利保護：獲利回跌停利機制
- 對沖平倉：減少點差損失的平倉方式

---

## 2. 功能需求

### 2.1 網格交易核心 [REQ-GRID]

#### REQ-GRID-001：網格模式選擇
- 支援順向網格（GRID_MODE_TREND）：順勢加倉
- 支援逆向網格（GRID_MODE_COUNTER）：逆勢加倉
- 可透過外部參數 `PG_GridMode` 切換

#### REQ-GRID-002：網格間距設定
- 基礎間距：`PG_GridStep`（點數）
- 累積間距計算：根據縮放參數動態調整

#### REQ-GRID-003：手數管理
- 起始手數：`PG_InitialLots`
- 最大手數限制：`PG_MaxLots`
- 手數驗證：符合市場最小/最大手數與步長限制

#### REQ-GRID-004：網格層級控制
- 最大層級：`PG_MaxGridLevels`
- 獨立追蹤買入/賣出籃子層級
- 層級重置：平倉後自動重置

#### REQ-GRID-005：止盈機制
- 止盈金額：`PG_TakeProfit`
- 達到止盈時觸發平倉
- 支援對沖平倉方式

#### REQ-GRID-006：獨立縮放設定
- 逆向間距縮放：`PG_CounterGridScaling`（%，0=不縮放，正值=擴張，負值=收縮）
- 逆向手數縮放：`PG_CounterLotScaling`（%，0=不縮放）
- 順向間距縮放：`PG_TrendGridScaling`（%，0=不縮放）
- 順向手數縮放：`PG_TrendLotScaling`（%，0=不縮放）
- 根據網格模式自動選擇對應的縮放參數

### 2.2 信號過濾系統 [REQ-SIGNAL]

#### REQ-SIGNAL-001：過濾模式選擇
- BullsBears Candles（FILTER_BULLSBEARS）
- Super Trend（FILTER_SUPERTREND）
- Simple Grids（FILTER_SIMPLE）：無過濾

#### REQ-SIGNAL-002：BullsBears 參數
- 回看 K 線數量：`BB_LookbackBars`
- 力量差異閾值：`BB_Threshold`

#### REQ-SIGNAL-003：SuperTrend 參數
- ATR 週期：`ST_ATR_Period`
- ATR 乘數：`ST_Multiplier`
- 首單模式：`ST_SignalMode`
  - SIGNAL_MODE_TREND：趨勢方向內持續開單
  - SIGNAL_MODE_REVERSAL：只在趨勢反轉時開單
  - SIGNAL_MODE_DISABLED：不使用趨勢過濾
- 加倉模式：`ST_AveragingMode`
  - AVERAGING_ANY：任意方向加倉
  - AVERAGING_TREND：僅順勢時加倉
  - AVERAGING_DISABLED：不使用趨勢過濾
- 趨勢線顯示：`ST_ShowLine`
- 顏色設定：`ST_BullColor`、`ST_BearColor`

#### REQ-SIGNAL-004：時間框架設定
- 分析時間框架：`TF_Timeframe`
- 支援自動驗證時間框架有效性

### 2.3 交易控制 [REQ-TRADE]

#### REQ-TRADE-001：交易方向控制
- 雙向交易（TRADE_BOTH）
- 只買（TRADE_BUY_ONLY）
- 只賣（TRADE_SELL_ONLY）

#### REQ-TRADE-002：訂單保護
- 每根 K 線只開一單：`OP_OneOrderPerBar`
- 滑點容許值：`OP_Slippage`
- 最大訂單數量：`OP_MaxOrdersInWork`

#### REQ-TRADE-003：組別管理
- 組別 ID：`PG_GroupID`
- Magic Number：`PG_MagicNumber`
- 支援多組 EA 同時運行

### 2.4 風險控制 [REQ-RISK]

#### REQ-RISK-001：回撤控制
- 最大回撤百分比：`PG_MaxDrawdown`
- 超過回撤時暫停交易

#### REQ-RISK-002：手數限制
- 最大總手數：`PG_MaxLots`
- 超過限制時停止加倉

#### REQ-RISK-003：點差過濾
- 最大點差：`PG_MaxSpread`
- 點差過大時暫停開單

### 2.5 獲利保護 [REQ-PROFIT]

#### REQ-PROFIT-001：獲利回跌停利
- 啟用開關：`PT_EnableTrailing`
- 獲利閾值：`PT_ProfitThreshold`
- 保留利潤百分比：`PT_DrawdownPercent`
- 達到閾值後追蹤峰值，回跌到指定百分比時平倉

#### REQ-PROFIT-002：對沖平倉
- 自動啟用對沖平倉機制
- 先下對沖單鎖住持倉，再用 OrderCloseBy 互相平倉
- 減少點差損失

### 2.6 運行模式 [REQ-MODE]

#### REQ-MODE-001：獨立運行模式
- 啟用開關：`PG_StandaloneMode`
- YES：獨立運行，不與 Recovery EA 通訊
- NO：協作模式，與 Recovery EA 進行獲利通訊

### 2.7 效能優化 [REQ-PERF]

#### REQ-PERF-001：計時器分層
- Timer1：盈虧掃描間隔（`PF_Timer1`，預設 3 秒）
- Timer2：UI/箭頭更新間隔（`PF_Timer2`，預設 10 秒）

#### REQ-PERF-002：緩存機制
- 市場資訊緩存（點差、手數限制等）
- 訂單統計緩存（訂單數、浮動盈虧等）
- 減少重複查詢提升效能

### 2.8 視覺化功能 [REQ-UI]

#### REQ-UI-001：交易箭頭
- 啟用開關：`AR_EnableArrows`
- 箭頭回溯天數：`AR_ArrowDays`
- 顏色設定：開倉/歷史買入賣出各有獨立顏色

#### REQ-UI-002：SuperTrend 趨勢線
- 在圖表上繪製 SuperTrend 線
- 根據趨勢方向顯示不同顏色

#### REQ-UI-003：資訊面板
- 顯示 EA 狀態、交易資訊、累積獲利
- 自動更新（依 Timer2 間隔）

### 2.9 除錯功能 [REQ-DEBUG]

#### REQ-DEBUG-001：除錯日誌
- 啟用開關：`PG_ShowDebugLogs`
- 日誌檔案：`PG_LogFile`（空字串表示不建立檔案）

---

## 3. 非功能需求

### 3.1 效能需求

- 每個 Tick 處理時間 < 10ms
- 支援同時運行多組 EA
- 記憶體使用穩定，無洩漏

### 3.2 可靠性需求

- 訂單操作失敗時記錄錯誤並重試
- 異常狀態自動恢復
- 支援 EA 重啟後狀態恢復

### 3.3 相容性需求

- 支援 MT4 Build 1000+
- 支援所有貨幣對和 CFD
- 支援策略測試器

---

## 4. 變更紀錄

| 日期 | 版本 | 變更說明 |
|------|------|----------|
| 2026-01-01 | 1.20 | 根據 Grids 1.20.mq4 重建需求文件 |
| 2026-01-01 | 1.21 | 移除 PG_StepMultiplier、PG_LotMultiplier，新增獨立縮放參數 REQ-GRID-006 |
