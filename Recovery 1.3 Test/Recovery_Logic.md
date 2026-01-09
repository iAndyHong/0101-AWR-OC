# Recovery EA 交易邏輯 v1.34

## 概述

Recovery EA 是一個專門負責虧損管理與部分平倉的專家顧問。它透過全局變數 (GV) 與 Grids EA 協作，接收獲利並用於恢復虧損倉位。

### 鎖倉機制說明

Recovery EA 支援鎖倉功能（`RM_UseLocking = YES`）：
- **啟用鎖倉**：EA 會在啟動時平衡多空手數，使 Buy 手數 = Sell 手數。鎖倉後虧損金額固定，不會隨價格浮動。
- **停用鎖倉**：虧損訂單的盈虧會隨價格浮動，可能從虧損轉為獲利。
- **測試模式**：虛擬訂單沒有真正鎖倉，盈虧會隨價格浮動。

### 重要概念區分

**鎖倉（Locking）** vs **對沖平倉（Hedge Close）**：

| 概念 | 說明 | 相關參數 |
|------|------|----------|
| **鎖倉** | 開立對沖單使 Buy 手數 = Sell 手數，固定虧損金額 | `RM_UseLocking` |
| **對沖平倉** | 用 OrderCloseBy 把 Buy 和 Sell 配對平倉，是一種平倉方式 | `RM_EnableHedgeProfit` |

以下參數與「鎖倉」無關，是獨立的功能：
- `RM_EnableHedgeProfit` - 啟用對沖獲利平倉（Buy 獲利 + Sell 獲利配對平倉）
- `RM_SkipProfitOrders` - 跳過已轉盈訂單（優先處理虧損訂單）
- `RM_RecoverHedgeProfit` - 回收對沖獲利（將對沖平倉的獲利加回可消費額度）

**v1.34 更新**：統一平倉介面
- `ExecuteSingleClose()` 重構為使用統一訂單陣列
- `ExecutePartialClose()` 重構為使用統一訂單陣列
- 透過 `virtualIdx` 欄位判斷模式（>= 0 為測試模式，-1 為正常模式）
- 移除測試/正常模式的 if-else 分支，共用核心平倉邏輯
- 減少代碼重複，提高可維護性

**v1.33 更新**：統一訂單介面
- 新增 `UnifiedOrder` 結構，抽象化訂單存取
- `ScanAllOrders()` 同時建立統一訂單陣列 `g_unifiedOrders[]`
- `SelectBestOrder()` 使用統一陣列，移除測試/正常模式分支
- `CalculatePartialLoss()` 使用統一陣列
- `ExecuteHedgeProfitClose()` 使用統一陣列
- 測試模式和正常模式共用核心邏輯，減少代碼重複

**v1.32 更新**：效能優化 - 統一訂單掃描
- 新增 `ScanAllOrders()` 函數，一次遍歷完成所有統計
- 合併 `ScanLossPositions()` 和 `UpdateOrderStats()` 的遍歷邏輯
- `SelectBestOrder()` 重用已統計的數據，減少重複遍歷
- 每個 tick 從原本 4~5 次遍歷減少到 2 次（統計 + 選擇）

**v1.31 更新**：獲利訂單自動清倉
- 當所有虧損訂單都平完後，自動處理剩餘的獲利訂單
- 修正 `RM_SkipProfitOrders` 導致獲利訂單卡住的問題

**v1.30 更新**：獲利回收機制
- 平倉時檢查實際盈虧，將獲利加回可消費額度
- 對沖獲利平倉的利潤回收到 ACCUMULATED_PROFIT
- 日誌檔案開頭列印所有外部參數

**v1.20 更新**：動態盈虧回饋 + 對沖獲利平倉

**v1.11 更新**：測試模式 + 視覺化虛擬訂單

**v1.10 更新**：動態掃描 + 平衡保護機制

---

## 對應程式碼

**檔案名稱**: `Recovery.mq4`

---

## v1.34 核心改進：統一平倉介面

### 改進內容

將 `ExecuteSingleClose()` 和 `ExecutePartialClose()` 重構為使用統一訂單陣列：

**舊架構**（v1.33 之前）：
```mql4
bool ExecuteSingleClose()
{
   if(RM_TestMode == YES)
   {
      // 測試模式邏輯（約 30 行）
   }
   else
   {
      // 正常模式邏輯（約 30 行）
   }
}
```

**新架構**（v1.34）：
```mql4
bool ExecuteSingleClose()
{
   // 從統一訂單陣列取得訂單資訊
   int virtualIdx = g_unifiedOrders[targetIdx].virtualIdx;
   
   if(virtualIdx >= 0)
      CloseVirtualOrderPartial(virtualIdx, closeLots);  // 測試模式
   else
      OrderClose(ticket, closeLots, price, slippage);   // 正常模式
}
```

### 優點

1. **代碼精簡**：移除重複的測試/正常模式分支
2. **邏輯統一**：透過 `virtualIdx` 欄位自動判斷模式
3. **易於維護**：修改平倉邏輯只需改一處
4. **減少錯誤**：避免兩套邏輯不同步的問題

---

## v1.31 核心改進：獲利訂單自動清倉

### 問題背景

v1.30 之前，當 `RM_SkipProfitOrders = YES` 時：
- 虧損訂單會被優先處理
- 但當所有虧損訂單都平完後，剩餘的獲利訂單會被永遠跳過
- 導致獲利訂單卡住，Recovery 流程無法完成

### 解決方案

**智慧切換邏輯**

`RM_SkipProfitOrders` 的原意是「優先處理虧損訂單」，而非「永遠不平獲利訂單」。

修改後的邏輯：
- 當還有虧損訂單時 → 跳過獲利訂單（優先處理虧損）
- 當沒有虧損訂單時 → 自動切換成處理獲利訂單

---

## v1.31 修改的函數

### SelectBestVirtualOrder() - 測試模式

```mql4
// v1.31: 先統計虧損和獲利訂單數量
int lossCount = 0;
int profitCount = 0;
for(int i = 0; i < g_virtualOrderCount; i++)
  {
   if(g_virtualOrders[i].isClosed) continue;
   if(g_virtualOrders[i].profit < 0)
      lossCount++;
   else
      profitCount++;
  }

// v1.31: 只有在還有虧損訂單時才跳過獲利訂單
bool shouldSkipProfit = (RM_SkipProfitOrders == YES && lossCount > 0);

// 掃描訂單時使用 shouldSkipProfit 判斷
if(shouldSkipProfit && g_virtualOrders[i].profit >= 0)
   continue;

// v1.31: 記錄切換狀態
if(lossCount == 0 && profitCount > 0 && bestIdx >= 0)
  {
   WriteLog("[TEST] 虧損訂單已清空，開始處理剩餘 " + 
            IntegerToString(profitCount) + " 筆獲利訂單");
  }
```

### SelectBestOrder() - 正常模式

同樣的邏輯應用於正常模式：

```mql4
// v1.31: 先統計虧損和獲利訂單數量
int lossCount = 0;
int profitCount = 0;
for(int i = 0; i < OrdersTotal(); i++)
  {
   // ... 篩選條件 ...
   double profit = OrderProfit() + OrderSwap() + OrderCommission();
   if(profit < 0)
      lossCount++;
   else
      profitCount++;
  }

// v1.31: 只有在還有虧損訂單時才跳過獲利訂單
bool shouldSkipProfit = (RM_SkipProfitOrders == YES && lossCount > 0);
```

### GetVirtualOrderStats() - 測試模式統計

```mql4
// v1.31: 如果沒有虧損訂單但還有獲利訂單
// orderCount 應該是獲利訂單數量，避免 OnTick 提前結束
if(lossCount > 0)
   orderCount = lossCount;
else
   orderCount = profitCount;  // 沒有虧損訂單時，繼續處理獲利訂單
```

### ScanLossPositions() - 正常模式統計

```mql4
// v1.31: 如果沒有虧損訂單但還有獲利訂單
// g_lossOrderCount 應該是獲利訂單數量，避免 OnTick 提前結束
if(lossCount > 0)
   g_lossOrderCount = lossCount;
else
   g_lossOrderCount = profitCount;  // 沒有虧損訂單時，繼續處理獲利訂單
```

---

## v1.31 訂單處理流程

```
OnTick()
├─ ScanLossPositions()
│   ├─ 統計虧損訂單數量 (lossCount)
│   ├─ 統計獲利訂單數量 (profitCount)
│   └─ g_lossOrderCount = lossCount > 0 ? lossCount : profitCount
│
├─ 檢查 g_lossOrderCount == 0
│   └─ 只有當 lossCount 和 profitCount 都為 0 時才結束
│
└─ SelectBestOrder()
    ├─ 計算 shouldSkipProfit = (RM_SkipProfitOrders && lossCount > 0)
    ├─ 如果 shouldSkipProfit = true → 只選虧損訂單
    └─ 如果 shouldSkipProfit = false → 選擇獲利訂單
```

---

## v1.30 核心改進：獲利回收機制

### 問題背景

在以下情況下，平倉時可能產生獲利：
1. **停用鎖倉時**（`RM_UseLocking = NO`）：虧損訂單可能因價格波動而轉為獲利
2. **測試模式**：虛擬訂單沒有真正鎖倉，盈虧隨價格浮動
3. **對沖平倉**：Buy 獲利 + Sell 獲利配對平倉時的總獲利（這與鎖倉無關，是獨立的平倉方式）

**注意**：當 `RM_UseLocking = YES` 時，虧損金額已被鎖定，理論上不會有「虧損轉獲利」的情況。

v1.20 之前，這些獲利直接消失，沒有被利用，浪費了市場波動帶來的額外收益。

### 解決方案

**獲利回收到可消費額度**

當平倉結果為獲利時，將獲利金額加回 `ACCUMULATED_PROFIT`，讓這筆錢可以用於後續的虧損平倉。

---

## v1.30 新增功能

### 1. 平倉獲利回收

在 `CloseVirtualOrderPartial()` 中：

```mql4
// 計算平倉獲利（按比例）
double closeProfit = g_virtualOrders[idx].profit * (closeLots / g_virtualOrders[idx].remainLots);

// 獲利回收邏輯
if(RM_EnableProfitRecovery == YES && closeProfit > 0)
  {
   double currentAccProfit = ReadGV("ACCUMULATED_PROFIT", 0);
   WriteGV("ACCUMULATED_PROFIT", currentAccProfit + closeProfit);
   g_recoveredProfit += closeProfit;
   g_recoveredCount++;
   WriteLog("[v1.30] 獲利回收: +" + DoubleToStr(closeProfit, 2) + 
            " 累計回收: " + DoubleToStr(g_recoveredProfit, 2));
  }
```

### 2. 對沖獲利回收

在 `ExecuteHedgeProfitClose()` 中：

```mql4
// 對沖平倉後，將獲利加回可消費額度
if(RM_RecoverHedgeProfit == YES && totalProfit > 0)
  {
   double currentAccProfit = ReadGV("ACCUMULATED_PROFIT", 0);
   WriteGV("ACCUMULATED_PROFIT", currentAccProfit + totalProfit);
   g_recoveredProfit += totalProfit;
   g_recoveredCount++;
   WriteLog("[v1.30] 對沖獲利回收: +" + DoubleToStr(totalProfit, 2) + 
            " 累計回收: " + DoubleToStr(g_recoveredProfit, 2));
  }
```

### 3. 日誌檔案參數列印

在 `OpenLogFile()` 中，日誌檔案開頭會列印所有外部參數：

```
================================================================
           Recovery EA v1.31 參數設定
================================================================
啟動時間: 2025.12.20 xx:xx:xx

【組別設定】
  組別 ID: A
  跨商品模式: 否
  目標商品: XAUUSDm

【訂單識別設定】
  處理順序: 困難優先
  MagicNumber 群組: 全部
  ...

【動態掃描設定 v1.10】
【動態盈虧回饋 v1.20】
【獲利回收設定 v1.30】
【前置處理設定】
【啟動設定】
【部分平倉設定】
【整體止盈設定】
【保護設定】
【GV 通訊設定】

================================================================
                         執行日誌開始
================================================================
```

---

## 全域變數

```mql4
// 獲利回收統計 (v1.30)
double         g_recoveredProfit        = 0.0;   // 累計回收獲利金額
int            g_recoveredCount         = 0;     // 回收次數

// 狀態變化追蹤（預留）
int            g_lossToProfit           = 0;     // 虧損轉獲利次數
int            g_profitToLoss           = 0;     // 獲利轉虧損次數
```

---

## 外部參數

### 獲利回收設定 (v1.30)

```mql4
sinput string  RM_Help1d                 = "----------------";   // 獲利回收設定
input ENUM_BOOL RM_EnableProfitRecovery  = YES;                  // 啟用獲利回收
input ENUM_BOOL RM_RecoverHedgeProfit    = YES;                  // 回收對沖獲利
input ENUM_BOOL RM_TrackStateChanges     = YES;                  // 追蹤盈虧狀態變化
```

---

## UI 面板顯示

```
=== Recovery v1.31 [測試] ===
*** 測試模式 ***
訂單: 2/6 輪數: 15
組別: A
商品: XAUUSDm
模式: 動態掃描
虧損訂單: 4
總虧損: -125.50
手數: B=0.06 S=0.06
失衡: +0.00
處理中: Sell #99004
部分虧損: -8.25
目標獲利: 10.25
累積獲利: 45.00
進度: 100.0%
狀態: 消費中
Grids: 就緒
對沖獲利: 2次 $15.20
獲利回收: 5次 $23.45
TxID: 520
```

---

## 完整參數列表

### 組別設定
- `RM_GroupID` - 組別 ID (A-Z 或 1-99)
- `RM_CrossSymbol` - 跨商品模式
- `RM_TargetSymbol` - 目標商品

### 訂單識別設定
- `RM_OrderSelector` - 處理順序 (簡單優先/困難優先)
- `RM_MagicSelection` - MagicNumber 群組
- `RM_MagicNumbers` - 要恢復的 MagicNumber
- `RM_FirstTicket` - 優先處理的訂單 Ticket

### 動態掃描設定 (v1.10)
- `RM_DynamicScan` - 啟用動態掃描
- `RM_MaxImbalance` - 最大多空失衡手數
- `RM_RescanInterval` - 重新掃描間隔
- `RM_SwitchThreshold` - 切換閾值

### 動態盈虧回饋 (v1.20)
- `RM_EnableHedgeProfit` - 啟用對沖獲利平倉（Buy 獲利 + Sell 獲利配對平倉，與鎖倉無關）
- `RM_SkipProfitOrders` - 跳過已轉盈訂單（v1.31：只在有虧損訂單時生效，與鎖倉無關）
- `RM_DynamicTargetAdjust` - 動態調整目標獲利

### 獲利回收設定 (v1.30)
- `RM_EnableProfitRecovery` - 啟用獲利回收
- `RM_RecoverHedgeProfit` - 回收對沖獲利（與鎖倉無關，是對沖平倉的獲利回收）
- `RM_TrackStateChanges` - 追蹤盈虧狀態變化

### 前置處理設定
- `RM_UseLocking` - 啟用鎖倉
- `RM_DeleteSLTP` - 刪除 SL 和 TP
- `RM_CloseProfitAtLaunch` - 啟動時關閉盈利訂單
- `RM_DeletePendingAtLaunch` - 啟動時刪除掛單

### 啟動設定
- `RM_LaunchType` - 啟動類型
- `RM_LaunchThreshold` - 啟動閾值
- `RM_DisableOtherEAs` - 停用其他EA

### 部分平倉設定
- `RM_PartialLots` - 每次平倉手數
- `RM_TakeProfitMoney` - 部分平倉止盈金額

### 整體止盈設定
- `RM_UseBasketTP` - 啟用整體籃子止盈
- `RM_BasketTPMoney` - 整體籃子止盈金額

### 保護設定
- `RM_MaxSlippage` - 最大滑點
- `RM_LockMagic` - 鎖倉訂單 MagicNumber

### GV 通訊設定
- `RM_GV_Prefix` - GV 前綴
- `RM_UpdateInterval` - 更新間隔
- `RM_AckTimeout` - 確認超時
- `RM_CheckConflict` - 檢查組別衝突

### UI 顯示設定
- `RM_ShowPanel` - 顯示資訊面板
- `RM_PanelX` - 面板 X 座標
- `RM_PanelY` - 面板 Y 座標

### 除錯設定
- `RM_ShowDebugLogs` - 顯示除錯日誌
- `RM_EnableSharedLog` - 啟用共用日誌檔

### 測試模式設定
- `RM_TestMode` - 啟用測試模式
- `RM_TestSkipGrids` - 跳過 Grids 通訊
- `RM_TestAutoProfit` - 自動模擬獲利
- `RM_TestMaxRounds` - 最大測試輪數
- `RM_TestBuyCount` - Buy 訂單數量
- `RM_TestSellCount` - Sell 訂單數量
- `RM_TestGridGap` - 網格間距
- `RM_TestLotsPerOrder` - 每筆訂單手數

---

## 版本歷史

- **v1.33** - 統一訂單介面
  - 新增 `UnifiedOrder` 結構，抽象化訂單存取
  - `ScanAllOrders()` 同時建立統一訂單陣列
  - `SelectBestOrder()`、`CalculatePartialLoss()`、`ExecuteHedgeProfitClose()` 使用統一陣列
  - 測試模式和正常模式共用核心邏輯

- **v1.32** - 效能優化：統一訂單掃描
  - 新增 `ScanAllOrders()` 函數，一次遍歷完成所有統計
  - 修改 `ScanLossPositions()` 改為呼叫統一掃描
  - 修改 `UpdateOrderStats()` 重用統一掃描結果
  - 修改 `SelectBestOrder()` 重用 `g_scanLossCount`/`g_scanProfitCount`
  - 每個 tick 遍歷次數從 4~5 次減少到 2 次

- **v1.31** - 獲利訂單自動清倉
  - 修正 `RM_SkipProfitOrders` 導致獲利訂單卡住的問題
  - 當沒有虧損訂單時，自動切換成處理獲利訂單
  - 修改 `SelectBestVirtualOrder()`、`SelectBestOrder()`
  - 修改 `GetVirtualOrderStats()`、`ScanLossPositions()`

- **v1.30** - 獲利回收機制
  - 平倉時檢查實際盈虧，將獲利加回可消費額度
  - 對沖獲利平倉的利潤回收到 ACCUMULATED_PROFIT
  - 日誌檔案開頭列印所有外部參數
  - 新增獲利回收統計顯示

- **v1.20** - 動態盈虧回饋 + 對沖獲利平倉
  - 新增 OrderStats 結構
  - 新增對沖獲利平倉功能
  - 新增跳過已轉盈訂單功能
  - 新增動態調整目標獲利

- **v1.11** - 測試模式 + 視覺化虛擬訂單

- **v1.10** - 動態掃描 + 平衡保護機制

- **v1.00** - 基礎版本

---

## 重要注意事項

1. **鎖倉 vs 對沖平倉** - 這是兩個不同的概念：
   - 鎖倉（`RM_UseLocking`）：開立對沖單固定虧損
   - 對沖平倉（`RM_EnableHedgeProfit`）：用 OrderCloseBy 配對平倉
2. **鎖倉機制** - `RM_UseLocking = YES` 時，虧損金額固定；`= NO` 時，虧損可能隨價格浮動
3. **獲利訂單自動清倉** - 當虧損訂單都平完後，會自動處理剩餘獲利訂單（v1.31）
4. **獲利回收** - 平倉時如果結果為獲利，會自動加回可消費額度（適用於停用鎖倉或測試模式）
5. **對沖獲利回收** - 對沖平倉的獲利也會回收（可透過參數關閉）
6. **日誌參數列印** - 日誌檔案開頭會列印所有外部參數，方便判讀
7. **測試模式** - 實盤請關閉 `RM_TestMode`
8. **GV 同步** - 需確保與 Grids EA 的 GV 前綴設定一致
