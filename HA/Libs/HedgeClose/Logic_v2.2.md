# CHedgeClose 模組邏輯說明

## 模組概述

`CHedgeClose` 是一個對沖平倉模組，從 `Multi-Level_Grid_System v2.3.mq4` 提取而來。

核心功能：先下對沖單讓多空手數相等（鎖住），再使用 `OrderCloseBy` 互相平倉，減少點差損失。

**重要：這是「平倉方法」，不是「平倉條件」。平倉條件由其他模組（如 CProfitTrailingStop）決定。**

---

## 運作邏輯

### 執行流程

1. **呼叫 Execute()**
   - 主入口函數，執行完整的對沖平倉流程

2. **PlaceHedge() - 下對沖單**
   - 計算多空手數差
   - Buy 單為正，Sell 單為負
   - 手數差 > 0：多單較多，下 Sell 單對沖
   - 手數差 < 0：空單較多，下 Buy 單對沖
   - 手數差 = 0：已平衡，無需對沖

3. **MultCloseBy() - 對沖平倉**
   - 遍歷所有訂單，找到一對多空單
   - 使用 `OrderCloseBy()` 互相平倉
   - 遞迴處理直到所有訂單都平倉完畢
   - **如果發生錯誤，返回 false，改用備用方案**

4. **CloseAllOrders() - 備用平倉（雙重保險）**
   - 當對沖平倉失敗時自動啟用
   - 逐一平倉所有符合條件的訂單
   - 確保平倉一定會完成

### 範例說明

情境：持有 Buy 0.5 手 + Sell 0.2 手

- 步驟 1：計算手數差 = 0.5 - 0.2 = 0.3（多單較多）
- 步驟 2：下 Sell 0.3 手對沖單
- 步驟 3：現在持有 Buy 0.5 手 + Sell 0.5 手
- 步驟 4：執行 OrderCloseBy，互相平倉
- 結果：所有訂單平倉完畢

---

## 優點

- **減少點差損失**：OrderCloseBy 不需要再次支付點差
- **快速平倉**：一次操作平掉一對多空單
- **雙重保險**：對沖平倉失敗時自動改用一般平倉
- **平倉最重要**：確保訂單一定會被平掉
- **適合緊急出場**：趨勢反轉或風險控制時使用

---

## 參數說明

- **magicNumber** (魔術數字)
  - 類型：int
  - 說明：用於識別要管理的訂單
  - 特殊值：0 = 所有訂單（不限 Magic）

- **slippage** (滑點容許值)
  - 類型：int
  - 說明：下單時的滑點容許值（點）
  - 預設值：30

- **symbol** (交易商品)
  - 類型：string
  - 說明：空字串表示使用當前圖表商品

---

## 類別介面

### 公開方法

- `Init()` - 初始化模組
- `Deinit()` - 清理資源
- `Execute()` - 執行對沖平倉（主入口）

### 私有方法

- `MagicNoCheck()` - 檢查 MagicNumber 是否匹配
- `PlaceHedge()` - 下對沖單鎖住持倉
- `MultCloseBy()` - 對沖平倉子程序
- `CloseAllOrders()` - 一般平倉（備用方案）
- `CountRemainingOrders()` - 檢查剩餘訂單數量

---

## 呼叫方式

### 方式一：快速呼叫（一行完成）

```mql4
#include "../Libs/HedgeClose/CHedgeClose.mqh"

// 需要平倉時，一行搞定
CHedgeClose::CloseAll(MagicNumber);
CHedgeClose::CloseAll(MagicNumber, 30, Symbol());
```

### 方式二：標準用法（重複使用）

```mql4
#include "../Libs/HedgeClose/CHedgeClose.mqh"

CHedgeClose g_hedgeClose;

// OnInit 中初始化
g_hedgeClose.Init(MagicNumber, 30, Symbol());

// 需要平倉時呼叫
g_hedgeClose.Execute();

// OnDeinit 中清理
g_hedgeClose.Deinit();
```

---

## 使用情境

- **獲利達標平倉**：當整體獲利達到目標時
- **趨勢反轉平倉**：當趨勢反轉時緊急出場
- **風險控制平倉**：當回撤達到警戒線時

---

## 注意事項

1. **會平掉所有符合條件的訂單**：呼叫前請確認這是你要的行為
2. **MagicNumber = 0**：表示平掉所有訂單（不限 Magic）
3. **雙重保險**：如果對沖或對沖平倉失敗，會自動改用一般平倉

---

## 版本資訊

- 版本：1.10
- 來源：Multi-Level_Grid_System v2.3.mq4
- 提取日期：2025-12-14
- 搬移至 Libs：2025-12-19
