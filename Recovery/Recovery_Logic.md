# Recovery EA 交易邏輯 v3.00

## 概述

Recovery EA 是一個專門負責虧損管理與部分平倉的專家顧問。它透過全局變數 (GV) 與 Grids EA 協作，接收獲利並用於恢復虧損倉位。

**v3.00 更新**：新增 GroupID 組別隔離機制，支援多組 EA 同時運行和跨商品協作。

**v2.00 更新**：採用狀態機 + 雙向確認 + 交易 ID 機制，確保 GV 通訊的安全性和一致性。

---

## 對應程式碼

**檔案名稱**: `Recovery.mq4`

---

## 核心職責

1. **前置處理** - 啟動時執行鎖倉、關閉盈利訂單、刪除 SL/TP
2. **虧損掃描與識別** - 持續監控帳戶中的虧損倉位
3. **虛擬分割** - 將大訂單虛擬分割成多個小部分
4. **部分平倉執行** - 使用外部獲利逐一關閉分割後的小部分
5. **獲利需求發布** - 向 GV 發布所需獲利金額

---

## 狀態機通訊機制

### 為什麼需要狀態機？

MQL4 的 GlobalVariable 雖然在單一終端內是原子操作，但存在以下風險：

1. **讀取-修改-寫入** 不是原子操作
2. 兩個 EA 可能同時讀取舊值
3. 可能導致獲利被「吞掉」或重複使用

### 解決方案：狀態機 + 雙向確認 + 交易 ID

```
┌─────────────────────────────────────────────────────────────────┐
│                    狀態機通訊協議                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Recovery EA                              Grids EA               │
│  ───────────                              ────────               │
│                                                                  │
│  STATE_R_IDLE ────────────────────────── STATE_G_IDLE           │
│       │                                       │                  │
│       │ 發布目標 + 遞增 TxID                  │                  │
│       ▼                                       │                  │
│  STATE_R_REQUESTING ──────────────────► 讀取目標                │
│       │                                       │                  │
│       │                                       ▼                  │
│       │                               STATE_G_ACCUMULATING       │
│       │                               (確認 TxID)                │
│       │                                       │                  │
│       │ 等待確認                              │ 累積獲利         │
│       ▼                                       │                  │
│  STATE_R_WAITING ◄────────────────────────────┘                 │
│       │                                       │                  │
│       │                                       ▼                  │
│       │  ◄──────────────────────────── STATE_G_READY            │
│       │         (獲利達標)                    │                  │
│       ▼                                       │                  │
│  STATE_R_CONSUMING ─────────────────────► 等待確認              │
│       │         (執行平倉)                    │                  │
│       │                                       │                  │
│       │ 發送 ACK_ID                           │                  │
│       ▼                                       ▼                  │
│  STATE_R_CONFIRMING ──────────────────► STATE_G_ACKNOWLEDGED    │
│       │                                       │                  │
│       ▼                                       ▼                  │
│  STATE_R_IDLE ◄─────────────────────────  STATE_G_IDLE          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Recovery EA 狀態定義

```mql4
#define STATE_R_IDLE          0    // 閒置 - 無獲利請求
#define STATE_R_REQUESTING    1    // 請求中 - 已發布獲利目標，等待 Grids 確認
#define STATE_R_WAITING       2    // 等待中 - Grids 已確認，等待獲利累積
#define STATE_R_CONSUMING     3    // 消費中 - 正在使用獲利執行平倉
#define STATE_R_CONFIRMING    4    // 確認中 - 平倉完成，等待 Grids 重置
```

### 關鍵設計原則

1. **單一寫入者原則**：每個 GV 變數只有一個 EA 負責寫入
2. **狀態轉換確認**：狀態變更需要對方確認才能進入下一步
3. **交易 ID 機制**：每次交易週期有唯一的序列號，防止舊資料干擾
4. **超時處理**：請求超時會自動重試

---

## 組別隔離機制 (v3.00 新增)

### 為什麼需要組別隔離？

當多組 EA 同時運行時，可能發生以下衝突：

1. **同商品多組**：兩組 Recovery+Grids 在同一商品上運行，GV 會互相覆蓋
2. **跨商品協作**：Recovery 在 EURUSD，但需要使用 GBPUSD 的 Grids 獲利
3. **資源競爭**：多個 EA 同時寫入相同的 GV 變數

### 解決方案：GroupID + 衝突檢測

```mql4
// 組別設定參數
input string   RM_GroupID                = "A";       // 組別 ID
input bool     RM_CrossSymbol            = false;     // 跨商品模式
input string   RM_TargetSymbol           = "";        // 目標商品
input bool     RM_CheckConflict          = true;      // 檢查組別衝突
```

### 使用情境

#### 情境 1：單商品單組（預設）
```
EURUSD:
  Recovery EA: GroupID = "A"
  Grids EA:    GroupID = "A"
```

#### 情境 2：單商品多組
```
EURUSD 組別 A (處理 Magic 11111):
  Recovery EA: GroupID = "A", MagicNumbers = "11111"
  Grids EA:    GroupID = "A"

EURUSD 組別 B (處理 Magic 22222):
  Recovery EA: GroupID = "B", MagicNumbers = "22222"
  Grids EA:    GroupID = "B"
```

#### 情境 3：多商品各自獨立
```
EURUSD:
  Recovery EA: GroupID = "A"
  Grids EA:    GroupID = "A"

GBPUSD:
  Recovery EA: GroupID = "A"  // 可以用相同 GroupID，因為商品不同
  Grids EA:    GroupID = "A"
```

#### 情境 4：跨商品協作
```
EURUSD Recovery 使用 GBPUSD Grids 的獲利:
  Recovery EA (EURUSD): GroupID = "X", CrossSymbol = true
  Grids EA (GBPUSD):    GroupID = "X", CrossSymbol = true
```

---

## GV 通訊協議

### GV 命名規範

```
前綴：REC_（簡短易讀）
格式：REC_{GroupID}_{商品}_{變數名}
範例：REC_A_EURUSD_PT

跨商品模式：
格式：REC_{GroupID}_X_{變數名}
範例：REC_A_X_PT
```

### GV 名稱長度限制

MQL4 GlobalVariable 名稱最大長度為 **63 個字元**。EA 會自動檢查並截斷過長的名稱：

```mql4
// GV 名稱長度檢查（MQL4 限制 63 字元）
if(StringLen(fullName) > GV_MAX_LENGTH)
{
    Print("[警告] GV 名稱過長，已截斷");
    fullName = StringSubstr(fullName, 0, GV_MAX_LENGTH);
}
```

**建議**：GroupID 不要超過 10 個字元。

### Recovery EA 寫入的 GV 變數

| 變數名 | 類型 | 說明 |
|--------|------|------|
| `TRANSACTION_ID` | double | 交易週期序列號（每次請求遞增） |
| `PROFIT_TARGET` | double | 目標獲利金額 |
| `PARTIAL_LOSS` | double | 當前部分虧損金額 |
| `RECOVERY_STATE` | int | Recovery EA 狀態碼 |
| `RECOVERY_ACK_ID` | double | Recovery 確認的交易 ID |
| `LOCK_VOLUME` | double | 鎖倉手數 |
| `LAST_UPDATE` | datetime | 最後更新時間 |
| `RECOVERY_LOCK` | double | Recovery EA 實例鎖定 ID (v3.00) |

### Recovery EA 讀取的 GV 變數

| 變數名 | 類型 | 說明 |
|--------|------|------|
| `ACCUMULATED_PROFIT` | double | Grids EA 已累積獲利 |
| `GRIDS_STATE` | int | Grids EA 狀態碼 |
| `GRIDS_ACK_ID` | double | Grids 確認的交易 ID |

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

// ===== 除錯設定 =====
sinput string  RM_Help8                  = "----------------";   // 除錯設定
input bool     RM_ShowDebugLogs          = false;                // 顯示除錯日誌
```

---

## 工作流程

```
┌─────────────────────────────────────────────────────────────────┐
│                    Recovery EA 工作流程                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   1. OnInit() - 初始化                                           │
│      │                                                           │
│      ▼                                                           │
│   2. CheckLaunchCondition() - 檢查啟動條件                       │
│      │                                                           │
│      ▼                                                           │
│   3. ExecuteLaunchProcessing() - 執行前置處理（僅一次）          │
│      │                                                           │
│      ▼                                                           │
│   4. ScanLossPositions() - 掃描虧損倉位                          │
│      │                                                           │
│      ▼                                                           │
│   5. ExecuteStateMachine() - 執行狀態機邏輯                      │
│      │                                                           │
│      ├─► STATE_R_IDLE: 發起獲利請求                              │
│      │                                                           │
│      ├─► STATE_R_REQUESTING: 等待 Grids 確認                     │
│      │                                                           │
│      ├─► STATE_R_WAITING: 等待獲利累積                           │
│      │                                                           │
│      ├─► STATE_R_CONSUMING: 執行部分平倉                         │
│      │                                                           │
│      └─► STATE_R_CONFIRMING: 等待 Grids 重置                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 函數清單

| 函數名稱 | 說明 |
|----------|------|
| `OnInit()` | 初始化 EA |
| `OnDeinit()` | 反初始化 EA |
| `OnTick()` | 主要交易邏輯 |
| `ExecuteStateMachine()` | 狀態機核心邏輯 |
| `HandleStateIdle()` | 處理閒置狀態 |
| `HandleStateRequesting()` | 處理請求狀態 |
| `HandleStateWaiting()` | 處理等待狀態 |
| `HandleStateConsuming()` | 處理消費狀態 |
| `HandleStateConfirming()` | 處理確認狀態 |
| `ResetToIdle()` | 重置到閒置狀態 |
| `WriteGV()` | 寫入全局變數 |
| `ReadGV()` | 讀取全局變數 |
| `CheckLaunchCondition()` | 檢查啟動條件 |
| `ExecuteLaunchProcessing()` | 執行前置處理 |
| `ScanLossPositions()` | 掃描虧損倉位 |
| `SelectCurrentOrders()` | 選擇當前要處理的訂單 |
| `CalculatePartialLoss()` | 計算部分虧損 |
| `ExecutePartialClose()` | 執行部分平倉 |
| `CheckBasketTakeProfit()` | 檢查整體籃子止盈 |

---

## 重要注意事項

1. **單一運行** - EA 只能在一個終端運行，避免重複開立鎖倉訂單
2. **GV 同步** - 需確保與 Grids EA 的 GV 前綴設定一致
3. **狀態機安全** - 狀態機機制確保不會發生 GV 寫入衝突
4. **超時處理** - 請求超時會自動重試，避免死鎖
5. **測試建議** - 在實盤啟動前，務必在策略測試器中測試設定
