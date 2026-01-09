# TradeCore 交易核心模組

## 模組概述

TradeCore 是交易相關功能的統一管理模組，整合訂單管理、風險控制、持倉查詢、對沖平倉、獲利追蹤等核心交易功能。

## 檔案結構

```
Libs/TradeCore/
├── CTradeCore.mqh          ← 主入口，整合所有子模組
├── COrderManager.mqh       ← 訂單管理（開單/平倉/修改）
├── CRiskManager.mqh        ← 風險控制（回撤/手數/點差）
├── CPositionManager.mqh    ← 持倉管理（計數/統計/查詢）
├── CTradeUtils.mqh         ← 工具函數（靜態方法）
├── CHedgeClose.mqh         ← 對沖平倉模組
├── CProfitTrailingStop.mqh ← 獲利回跌停利模組
└── Logic.md                ← 本文件
```

## 快速使用

### 方式一：使用 CTradeCore（推薦）

```mql4
#include "../Libs/TradeCore/CTradeCore.mqh"

CTradeCore g_trade;

int OnInit()
{
   g_trade.Init(12345, Symbol(), 30);
   return INIT_SUCCEEDED;
}

void OnTick()
{
   // 風險檢查
   if(!g_trade.CheckDrawdown(20.0))
      return;
   
   // 開單
   if(g_trade.CountOrders() == 0)
      g_trade.OpenOrder(OP_BUY, 0.01, "首單");
   
   // 查詢盈虧
   double profit = g_trade.GetFloatingProfit();
}

void OnDeinit(const int reason)
{
   g_trade.Deinit();
}
```

### 方式二：單獨使用子模組

```mql4
#include "../Libs/TradeCore/COrderManager.mqh"
#include "../Libs/TradeCore/CTradeUtils.mqh"

COrderManager g_orders;

int OnInit()
{
   g_orders.Init(12345, Symbol(), 30);
   return INIT_SUCCEEDED;
}

void OnTick()
{
   // 驗證手數
   double lots = CTradeUtils::ValidateLotSize(0.015);
   
   // 開單
   int ticket = g_orders.OpenOrder(OP_BUY, lots, "測試");
}
```

## 模組說明

### CTradeCore - 交易核心

整合所有子模組的主入口類別。

**主要方法**：
- `Init(magic, symbol, slippage)` - 初始化
- `OpenOrder(type, lots, comment)` - 開單
- `CloseAllOrders()` - 平倉所有訂單
- `CountOrders(type)` - 計算訂單數
- `GetFloatingProfit()` - 取得浮動盈虧
- `CheckDrawdown(maxPercent)` - 檢查回撤
- `CheckSpread(maxSpread)` - 檢查點差

### COrderManager - 訂單管理

處理所有訂單操作。

**主要方法**：
- `OpenOrder(type, lots, comment)` - 開單
- `OpenOrderWithSLTP(type, lots, sl, tp, comment)` - 開單含停損停利
- `CloseOrder(ticket)` - 平倉指定訂單
- `CloseAllOrders()` - 平倉所有訂單
- `ModifyOrder(ticket, sl, tp)` - 修改訂單

### CRiskManager - 風險管理

處理所有風險控制邏輯。

**主要方法**：
- `CheckDrawdown(maxPercent, profit)` - 檢查回撤
- `CheckMaxLots(maxLots, currentLots)` - 檢查手數
- `CheckSpread(maxSpread)` - 檢查點差
- `CheckMargin(lots)` - 檢查保證金
- `CheckMaxOrders(max, current)` - 檢查訂單數

### CPositionManager - 持倉管理

處理持倉查詢和統計。

**主要方法**：
- `CountOrders(type)` - 計算訂單數
- `GetTotalLots(type)` - 取得總手數
- `GetFloatingProfit()` - 取得浮動盈虧
- `GetAveragePrice(type)` - 取得平均價格
- `GetOrderTickets(tickets[], type)` - 取得訂單票號

### CTradeUtils - 工具函數

提供靜態工具方法。

**主要方法**：
- `ValidateLotSize(lots, symbol)` - 驗證手數
- `NormalizePrice(price, symbol)` - 標準化價格
- `PointsToPrice(points, symbol)` - 點數轉價格
- `PriceToPoints(diff, symbol)` - 價格轉點數
- `IsNewBar(symbol, timeframe)` - 檢查新 K 棒
- `GetErrorDescription(code)` - 取得錯誤描述
- `IsRetryableError(code)` - 檢查可重試錯誤

### CHedgeClose - 對沖平倉

先下對沖單鎖住持倉，再使用 OrderCloseBy 互相平倉。

**主要方法**：
- `Init(magicNumber, slippage, symbol)` - 初始化
- `Execute()` - 執行對沖平倉，返回實際平倉獲利
- `Deinit()` - 清理資源
- `CloseAll(magicNumber, slippage, symbol)` - 靜態快速呼叫

**快速用法**：
```mql4
#include "../Libs/TradeCore/CHedgeClose.mqh"

// 一行完成對沖平倉
double profit = CHedgeClose::CloseAll(MagicNumber);
```

**標準用法**：
```mql4
CHedgeClose g_hedgeClose;

// OnInit
g_hedgeClose.Init(MagicNumber, 30, Symbol());

// 需要平倉時
double profit = g_hedgeClose.Execute();

// OnDeinit
g_hedgeClose.Deinit();
```

### CProfitTrailingStop - 獲利回跌停利

當浮動獲利達到閾值後啟動追蹤，獲利回跌到指定百分比時觸發平倉。

**主要方法**：
- `Init(profitThreshold, drawdownPercent, magicNumber, symbol)` - 初始化
- `Check()` - 檢查並執行停利邏輯（會自動平倉）
- `ShouldClose()` - 只檢查是否應該平倉（不執行）
- `Reset()` - 重置追蹤狀態
- `Deinit()` - 清理資源

**標準用法**：
```mql4
#include "../Libs/TradeCore/CProfitTrailingStop.mqh"

CProfitTrailingStop g_profitTrailing;

// OnInit - 參數：閾值, 保留%, Magic, 商品
g_profitTrailing.Init(100.0, 75.0, MagicNumber, Symbol());

// OnTick - 自動平倉模式
if(g_profitTrailing.Check())
   Print("已觸發平倉");

// OnDeinit
g_profitTrailing.Deinit();
```

**搭配對沖平倉**：
```mql4
// OnTick - 搭配 CHedgeClose
if(g_profitTrailing.ShouldClose())
{
   double profit = CHedgeClose::CloseAll(MagicNumber);
   g_profitTrailing.Reset();
}
```

## 與其他模組的關係

TradeCore 是基礎交易功能模組，可被以下模組使用：

- **CEACore** - EA 中樞類別，整合 TradeCore 提供交易功能
- **CGridsCore** - 網格交易，可使用 CPositionManager

## 設計原則

1. **單一職責** - 每個子模組只負責一類功能
2. **緩存優化** - 減少重複的 MarketInfo 和訂單遍歷
3. **錯誤處理** - 所有交易操作都有錯誤處理和日誌
4. **靈活組合** - 可單獨使用子模組或整合使用

## 版本紀錄

- v1.0 (2025-12-31) - 初版建立
- v1.1 (2025-12-31) - 整合 CHedgeClose 和 CProfitTrailingStop
