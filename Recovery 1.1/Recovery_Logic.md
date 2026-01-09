# Recovery EA 交易邏輯 v1.10

## 概述

Recovery EA 是一個專門負責虧損管理與部分平倉的專家顧問。它透過全局變數 (GV) 與 Grids EA 協作，接收獲利並用於恢復虧損倉位。

**v1.10 更新**：動態掃描 + 平衡保護機制
- 單筆動態掃描取代傳統一多一空配對
- 失衡保護避免單邊過度平倉
- 等待期間動態重新評估目標

**v1.00 更新**：新增 GroupID 組別隔離機制，支援多組 EA 同時運行和跨商品協作。

---

## 對應程式碼

**檔案名稱**: `Recovery.mq4`

---

## v1.10 核心改進：動態掃描 + 平衡保護

### 為什麼需要改進？

**傳統「一多一空」配對的問題：**

1. 原廠設計強調鎖倉平衡，但網格交易本身就會打破鎖倉
2. 必須同時有多空部位才能運作，缺乏彈性
3. 行情變動時，鎖定的訂單對可能變得越來越難處理
4. 只剩單邊部位時無法有效運作

**單筆動態掃描的優勢：**

1. 永遠選擇「當下最容易處理」的訂單
2. 不限多空，哪個容易就處理哪個
3. 等待期間可以動態切換目標
4. 單邊部位也能正常處理

### 平衡保護機制

**問題：單筆掃描可能導致單邊過度平倉**

如果系統一直選擇「最容易」的訂單，可能會：
- 一直平同一邊（例如一直平 Sell）
- 導致多空嚴重失衡
- 剩下的單邊部位風險敞口越來越大

**解決方案：失衡保護**

```mql4
input double RM_MaxImbalance = 0.1;  // 最大多空失衡手數

// 計算當前多空手數差
double imbalance = g_totalBuyLots - g_totalSellLots;

// 如果失衡超過閾值，強制平較多的那一邊
if(MathAbs(imbalance) > RM_MaxImbalance)
{
    forceDirection = true;
    forcedType = (imbalance > 0) ? OP_BUY : OP_SELL;
}
```

---

## 動態掃描參數 (v1.10 新增)

```mql4
// ===== 動態掃描設定 (v1.10 新增) =====
sinput string  RM_Help1b                 = "----------------";   // 動態掃描設定 (v1.10)
input bool     RM_DynamicScan            = true;                 // 啟用動態掃描 (單筆模式)
input double   RM_MaxImbalance           = 0.1;                  // 最大多空失衡手數 (平衡保護)
input int      RM_RescanInterval         = 5;                    // 重新掃描間隔 (秒)
input double   RM_SwitchThreshold        = 20.0;                 // 切換閾值 (%)
```

### 參數說明

- **RM_DynamicScan**
  - `true`：使用單筆動態掃描（推薦）
  - `false`：使用傳統一多一空配對

- **RM_MaxImbalance**
  - 當多空手數差超過此值時，強制平倉較多的那一邊
  - 例如：0.1 表示當 |Buy手數 - Sell手數| > 0.1 時啟動保護

- **RM_RescanInterval**
  - 在等待獲利期間，每隔多少秒重新掃描一次
  - 用於動態切換到更好的目標

- **RM_SwitchThreshold**
  - 新目標必須比舊目標低多少百分比才會切換
  - 例如：20.0 表示新目標需低於舊目標 20% 才切換
  - 避免頻繁切換造成的不穩定

---

## 動態掃描流程

### SelectBestOrder() 函數邏輯

```
1. 檢查是否有優先處理的 Ticket (RM_FirstTicket)
   │
2. 計算當前多空失衡
   │
3. 如果失衡超過閾值 → 啟動平衡保護
   │  └─ 強制只選擇較多那一邊的訂單
   │
4. 掃描所有虧損訂單
   │
5. 計算每筆訂單的「部分虧損」
   │  └─ 部分虧損 = (訂單虧損 / 訂單手數) × RM_PartialLots
   │
6. 根據 RM_OrderSelector 選擇最佳訂單
   │  ├─ 0 = 簡單優先：選擇部分虧損最小的
   │  └─ 1 = 困難優先：選擇部分虧損最大的
   │
7. 設定 g_currentTicket 和 g_currentOrderType
```

### TryRescanForBetterTarget() 函數邏輯

```
在 STATE_R_WAITING 期間，每隔 RM_RescanInterval 秒執行：

1. 保存當前狀態（舊 Ticket、舊目標）
   │
2. 重新執行 SelectBestOrder()
   │
3. 計算新目標獲利
   │
4. 比較新舊目標
   │  ├─ 如果新目標 < 舊目標 × (1 - RM_SwitchThreshold%)
   │  │  └─ 切換到新目標
   │  │     └─ 如果累積獲利已達新目標 → 直接進入消費狀態
   │  │
   │  └─ 否則
   │     └─ 恢復原狀態，不切換
```

---

## 狀態機通訊機制

### Recovery EA 狀態定義

```mql4
#define STATE_R_IDLE          0    // 閒置 - 無獲利請求
#define STATE_R_REQUESTING    1    // 請求中 - 已發布獲利目標，等待 Grids 確認
#define STATE_R_WAITING       2    // 等待中 - Grids 已確認，等待獲利累積
#define STATE_R_CONSUMING     3    // 消費中 - 正在使用獲利執行平倉
#define STATE_R_CONFIRMING    4    // 確認中 - 平倉完成，等待 Grids 重置
```

### 狀態機流程圖

```
Recovery EA                              Grids EA
───────────                              ────────

STATE_R_IDLE ────────────────────────── STATE_G_IDLE
     │                                       │
     │ 發布目標 + 遞增 TxID                  │
     ▼                                       │
STATE_R_REQUESTING ──────────────────► 讀取目標
     │                                       │
     │                                       ▼
     │                               STATE_G_ACCUMULATING
     │                               (確認 TxID)
     │                                       │
     │ 等待確認                              │ 累積獲利
     ▼                                       │
STATE_R_WAITING ◄────────────────────────────┘
     │                                       │
     │ [v1.10] 動態重新評估                  │
     │                                       ▼
     │  ◄──────────────────────────── STATE_G_READY
     │         (獲利達標)                    │
     ▼                                       │
STATE_R_CONSUMING ─────────────────────► 等待確認
     │         (執行平倉)                    │
     │                                       │
     │ 發送 ACK_ID                           │
     ▼                                       ▼
STATE_R_CONFIRMING ──────────────────► STATE_G_ACKNOWLEDGED
     │                                       │
     ▼                                       ▼
STATE_R_IDLE ◄─────────────────────────  STATE_G_IDLE
```

---

## 完整參數列表

```mql4
// ===== 組別設定 (重要！) =====
sinput string  RM_Help0                  = "----------------";   // 組別設定 (重要)
input string   RM_GroupID                = "A";                  // 組別 ID (A-Z 或 1-99)
input bool     RM_CrossSymbol            = false;                // 跨商品模式
input string   RM_TargetSymbol           = "";                   // 目標商品 (跨商品時使用)

// ===== 訂單識別設定 =====
sinput string  RM_Help1                  = "----------------";   // 訂單識別設定
input int      RM_OrderSelector          = 0;                    // 處理順序 (0=簡單優先, 1=困難優先)
input int      RM_MagicSelection         = 0;                    // MagicNumber 群組
input string   RM_MagicNumbers           = "0";                  // 要恢復的 MagicNumber
input int      RM_FirstTicket            = 0;                    // 優先處理的訂單 Ticket

// ===== 動態掃描設定 (v1.10 新增) =====
sinput string  RM_Help1b                 = "----------------";   // 動態掃描設定 (v1.10)
input bool     RM_DynamicScan            = true;                 // 啟用動態掃描 (單筆模式)
input double   RM_MaxImbalance           = 0.1;                  // 最大多空失衡手數 (平衡保護)
input int      RM_RescanInterval         = 5;                    // 重新掃描間隔 (秒)
input double   RM_SwitchThreshold        = 20.0;                 // 切換閾值 (%)

// ===== 前置處理設定 =====
sinput string  RM_Help2                  = "----------------";   // 前置處理設定
input bool     RM_UseLocking             = true;                 // 啟用鎖倉
input bool     RM_DeleteSLTP             = true;                 // 刪除 SL 和 TP
input bool     RM_CloseProfitAtLaunch    = false;                // 啟動時關閉盈利訂單
input bool     RM_DeletePendingAtLaunch  = false;                // 啟動時刪除掛單

// ===== 啟動設定 =====
sinput string  RM_Help3                  = "----------------";   // 啟動設定
input int      RM_LaunchType             = 0;                    // 啟動類型
input double   RM_LaunchThreshold        = 35.0;                 // 啟動閾值
input int      RM_DisableOtherEAs        = 0;                    // 停用其他EA

// ===== 部分平倉設定 (核心) =====
sinput string  RM_Help4                  = "----------------";   // 部分平倉設定
input double   RM_PartialLots            = 0.01;                 // 每次平倉手數
input double   RM_TakeProfitMoney        = 2.0;                  // 部分平倉止盈金額

// ===== 整體止盈設定 =====
sinput string  RM_Help5                  = "----------------";   // 整體止盈設定
input bool     RM_UseBasketTP            = true;                 // 啟用整體籃子止盈
input double   RM_BasketTPMoney          = 5.0;                  // 整體籃子止盈金額

// ===== 保護設定 =====
sinput string  RM_Help6                  = "----------------";   // 保護設定
input int      RM_MaxSlippage            = 30;                   // 最大滑點 (點)
input int      RM_LockMagic              = 88888;                // 鎖倉訂單 MagicNumber

// ===== GV 通訊設定 =====
sinput string  RM_Help7                  = "----------------";   // GV 通訊設定
input string   RM_GV_Prefix              = "REC_";               // GV 前綴 (簡短)
input int      RM_UpdateInterval         = 1;                    // 更新間隔 (秒)
input int      RM_AckTimeout             = 30;                   // 確認超時 (秒)
input bool     RM_CheckConflict          = true;                 // 檢查組別衝突

// ===== UI 顯示設定 =====
sinput string  RM_Help9                  = "----------------";   // UI 顯示設定
input bool     RM_ShowPanel              = true;                 // 顯示資訊面板
input int      RM_PanelX                 = 10;                   // 面板 X 座標
input int      RM_PanelY                 = 30;                   // 面板 Y 座標

// ===== 除錯設定 =====
sinput string  RM_Help8                  = "----------------";   // 除錯設定
input bool     RM_ShowDebugLogs          = false;                // 顯示除錯日誌
input bool     RM_EnableSharedLog        = true;                 // 啟用共用日誌檔
```

---

## 函數清單

### 核心函數

| 函數名稱 | 說明 |
|----------|------|
| `OnInit()` | 初始化 EA |
| `OnDeinit()` | 反初始化 EA |
| `OnTick()` | 主要交易邏輯 |
| `ExecuteStateMachine()` | 狀態機核心邏輯 |

### 狀態處理函數

| 函數名稱 | 說明 |
|----------|------|
| `HandleStateIdle()` | 處理閒置狀態 |
| `HandleStateRequesting()` | 處理請求狀態 |
| `HandleStateWaiting()` | 處理等待狀態（含動態重新評估） |
| `HandleStateConsuming()` | 處理消費狀態 |
| `HandleStateConfirming()` | 處理確認狀態 |
| `ResetToIdle()` | 重置到閒置狀態 |

### 動態掃描函數 (v1.10 新增)

| 函數名稱 | 說明 |
|----------|------|
| `SelectBestOrder()` | 單筆動態掃描，選擇最佳訂單 |
| `TryRescanForBetterTarget()` | 等待期間重新評估目標 |
| `ExecuteSingleClose()` | 執行單筆平倉 |

### 傳統模式函數

| 函數名稱 | 說明 |
|----------|------|
| `SelectCurrentOrders()` | 傳統一多一空配對選擇 |
| `ExecutePartialClose()` | 傳統配對平倉 |

### 輔助函數

| 函數名稱 | 說明 |
|----------|------|
| `WriteGV()` | 寫入全局變數 |
| `ReadGV()` | 讀取全局變數 |
| `CheckLaunchCondition()` | 檢查啟動條件 |
| `ExecuteLaunchProcessing()` | 執行前置處理 |
| `ScanLossPositions()` | 掃描虧損倉位 |
| `CalculatePartialLoss()` | 計算部分虧損 |
| `CheckBasketTakeProfit()` | 檢查整體籃子止盈 |
| `NormalizeLots()` | 標準化手數 |

---

## 版本歷史

- **v1.10** - 動態掃描 + 平衡保護機制
  - 新增單筆動態掃描模式
  - 新增失衡保護機制
  - 新增等待期間動態重新評估
  - 新增切換閾值控制

- **v1.00** - 基礎版本
  - GroupID 組別隔離機制
  - 狀態機 + 雙向確認 + 交易 ID
  - 共用日誌檔機制

---

## 重要注意事項

1. **動態掃描模式** - 預設啟用，可透過 `RM_DynamicScan` 切換回傳統模式
2. **平衡保護** - 當多空失衡超過 `RM_MaxImbalance` 時自動啟動
3. **切換閾值** - 避免頻繁切換目標，建議保持 15-25% 的閾值
4. **GV 同步** - 需確保與 Grids EA 的 GV 前綴設定一致
5. **測試建議** - 在實盤啟動前，務必在策略測試器中測試設定
