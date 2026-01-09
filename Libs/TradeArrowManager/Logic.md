# CTradeArrowManager 模組邏輯說明

## 模組概述

`CTradeArrowManager` 是一個交易箭頭管理模組，用於在圖表上繪製開倉與歷史交易的箭頭標記。

核心功能：將 MT4 原生交易箭頭替換為代碼 108 的圓圈樣式，支援自訂顏色、回溯天數、更新頻率等設定。

---

## 功能特點

- 自動修改 MT4 原生箭頭樣式和顏色
- 支援開倉/歷史訂單不同顏色
- 支援回溯天數設定
- 支援更新間隔設定
- 回測模式自動優化（每根 K 棒更新一次）

---

## 參數說明

- **symbol** - 交易商品（空字串 = 當前圖表商品）
- **prefix** - 物件名稱前綴
- **enable** - 是否啟用
- **days** - 回溯天數
- **magic** - 魔術數字（0 = 全部）
- **interval** - 更新間隔（秒），0 = 每根 K 棒更新
- **openBuy** - 開倉買單顏色（預設 clrOrangeRed）
- **openSell** - 開倉賣單顏色（預設 clrLawnGreen）
- **histBuy** - 歷史買單顏色（預設 clrDarkRed）
- **histSell** - 歷史賣單顏色（預設 clrDarkGreen）

---

## 類別介面

### 初始化方法

- `Init(symbol, prefix)` - 基本初始化
- `InitFull(...)` - 完整初始化（一次設定所有參數）
- `ArrowOnInit(enable)` - 啟動箭頭管理器
- `ArrowOnDeinit()` - 清理箭頭管理器

### 主要功能

- `ArrowOnTick()` - 在 OnTick 中呼叫
- `ArrowOnTimer()` - 在 OnTimer 中呼叫
- `Update()` - 強制立即更新
- `Cleanup()` - 清理所有箭頭

### 設定方法

- `SetDays(int)` - 設定回溯天數
- `SetMagicNumber(int)` - 設定魔術數字過濾
- `SetUpdateInterval(int)` - 設定更新間隔
- `SetColors(...)` - 設定四種顏色

---

## 呼叫方式

### 完整範例

```mql4
#include "../Libs/TradeArrowManager/CTradeArrowManager.mqh"

CTradeArrowManager arrowManager;

// 外部參數
input bool     AR_EnableArrows     = true;           // 啟用交易箭頭
input int      AR_ArrowDays        = 5;              // 箭頭回溯天數
input int      AR_ArrowInterval    = 10;             // 箭頭更新間隔(秒)
input color    AR_OpenBuyColor     = clrOrangeRed;   // 開倉買單顏色
input color    AR_OpenSellColor    = clrLawnGreen;   // 開倉賣單顏色
input color    AR_HistoryBuyColor  = clrDarkRed;     // 歷史買單顏色
input color    AR_HistorySellColor = clrDarkGreen;   // 歷史賣單顏色

int OnInit()
  {
   arrowManager.InitFull(Symbol(), "MyEA_Arrow_", AR_EnableArrows,
                         AR_ArrowDays, MagicNumber, AR_ArrowInterval,
                         AR_OpenBuyColor, AR_OpenSellColor,
                         AR_HistoryBuyColor, AR_HistorySellColor);

   if(AR_EnableArrows && AR_ArrowInterval > 0)
      EventSetTimer(1);

   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   arrowManager.ArrowOnDeinit();
   EventKillTimer();
  }

void OnTick()
  {
   if(AR_EnableArrows)
      arrowManager.ArrowOnTick();
  }

void OnTimer()
  {
   if(AR_EnableArrows)
      arrowManager.ArrowOnTimer();
  }
```

---

## 更新頻率說明

- **回測模式**：自動改為每根新 K 棒更新一次（提高效率）
- **即時交易**：按 interval 設定的秒數更新
- **interval = 0**：每根新 K 棒更新

---

## 版本資訊

- 版本：1.00
- 搬移至 Libs：2025-12-19
