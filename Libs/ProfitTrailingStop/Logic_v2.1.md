# CProfitTrailingStop 模組邏輯說明

## 模組概述

`CProfitTrailingStop` 是一個獲利回跌停利模組，從 `Multi-Level_Grid_System v2.3.mq4` 提取而來。

核心功能：當浮動獲利達到設定閾值後啟動追蹤，當獲利從峰值回跌到指定百分比時自動平倉，實現「保護利潤」的目的。

**定位**：這是「平倉條件」，決定「何時平倉」。可搭配 `CHedgeClose` 作為「平倉方法」。

---

## 運作邏輯

### 狀態機流程

1. **待機狀態** → 獲利達閾值 → **追蹤狀態**
2. **追蹤狀態** → 持續更新峰值（獲利上升時）
3. **追蹤狀態** → 獲利回跌至門檻 → **觸發平倉**
4. **觸發平倉** → 自動重置 → **待機狀態**

### 詳細流程

1. **待機階段**
   - 持續監控指定 Magic Number 的訂單浮動獲利
   - 等待浮動獲利達到啟動閾值

2. **啟動追蹤**
   - 當浮動獲利 >= 閾值時，啟動追蹤機制
   - 記錄當前獲利為峰值

3. **追蹤階段**
   - 持續監控浮動獲利
   - 如果獲利上升，更新峰值（只會往上更新）
   - 計算平倉觸發價位 = 峰值 × 保留百分比

4. **觸發平倉**
   - 當浮動獲利 < 平倉觸發價位時
   - 自動平掉所有符合條件的訂單
   - 重置狀態，回到待機階段

---

## 參數說明

- **profitThreshold** (獲利閾值)
  - 類型：double
  - 說明：浮動獲利達到此金額時啟動追蹤
  - 範例：100.0 表示獲利達 $100 時啟動

- **drawdownPercent** (保留利潤百分比)
  - 類型：double
  - 範圍：0 ~ 100
  - 說明：獲利回跌到峰值的此百分比時觸發平倉
  - 範例：75.0 表示保留 75% 利潤

- **magicNumber** (魔術數字)
  - 類型：int
  - 說明：用於識別要管理的訂單

- **symbol** (交易商品)
  - 類型：string
  - 說明：空字串表示使用當前圖表商品

---

## 情境範例

設定：閾值 = $100, 保留 = 75%

- 浮動獲利 $80 → 未達閾值，不啟動
- 浮動獲利 $100 → 達到閾值，啟動追蹤，峰值 = $100
- 浮動獲利 $150 → 更新峰值 = $150
- 浮動獲利 $180 → 更新峰值 = $180
- 浮動獲利 $160 → 未觸發（$160 > $180 × 75% = $135）
- 浮動獲利 $130 → 觸發平倉（$130 < $135）

最終結果：保住 $130 利潤

---

## 類別介面

### 公開方法

- `Init()` - 初始化模組
- `Deinit()` - 清理資源
- `Check()` - 檢查並執行停利邏輯（會自動平倉）
- `ShouldClose()` - 只檢查是否應該平倉（不執行，讓外部決定平倉方式）
- `Reset()` - 重置追蹤狀態
- `IsActive()` - 查詢追蹤是否啟動
- `GetPeakProfit()` - 取得峰值獲利
- `GetDrawdownLevel()` - 取得當前平倉觸發價位

### 私有方法

- `CalculateFloatingProfit()` - 計算當前浮動獲利
- `CloseAllPositions()` - 平掉所有部位

---

## 呼叫方式

### 方式一：自動平倉（使用 Check）

```mql4
#include "../Libs/ProfitTrailingStop/CProfitTrailingStop.mqh"

CProfitTrailingStop g_profitTrailing;

// OnInit
g_profitTrailing.Init(100.0, 75.0, MagicNumber, Symbol());

// OnTick
if(g_profitTrailing.Check())
   Print("已觸發平倉");

// OnDeinit
g_profitTrailing.Deinit();
```

### 方式二：搭配對沖平倉（使用 ShouldClose）

```mql4
#include "../Libs/ProfitTrailingStop/CProfitTrailingStop.mqh"
#include "../Libs/HedgeClose/CHedgeClose.mqh"

CProfitTrailingStop g_profitTrailing;
CHedgeClose g_hedgeClose;

// OnInit
g_profitTrailing.Init(100.0, 75.0, MagicNumber, Symbol());
g_hedgeClose.Init(MagicNumber, 30, Symbol());

// OnTick
if(g_profitTrailing.ShouldClose())
  {
   g_hedgeClose.Execute();  // 使用對沖平倉
   g_profitTrailing.Reset();
  }

// OnDeinit
g_profitTrailing.Deinit();
g_hedgeClose.Deinit();
```

---

## 注意事項

1. **每 Tick 呼叫**：`Check()` 或 `ShouldClose()` 應在每個 Tick 呼叫
2. **Magic Number**：確保與交易訂單使用相同的 Magic Number
3. **搭配使用**：建議搭配 `CHedgeClose` 使用 `ShouldClose()` 方式

---

## 版本資訊

- 版本：1.00
- 來源：Multi-Level_Grid_System v2.3.mq4
- 提取日期：2025-12-14
- 搬移至 Libs：2025-12-19
