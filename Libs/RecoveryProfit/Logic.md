# Recovery 獲利通訊模組 (CRecoveryProfit)

## 模組概述

此模組負責 Grids EA 與 Recovery EA 之間的 GV（GlobalVariable）通訊，實現獲利累積和消費的協調機制。

---

## 核心功能

1. **GV 通訊**：透過 GlobalVariable 與 Recovery EA 交換狀態和數據
2. **狀態機管理**：維護 Grids 端的狀態機，與 Recovery 端同步
3. **獲利累積**：追蹤和累積平倉獲利
4. **測試模式支援**：測試環境下使用本地緩存替代真實 GV

---

## 狀態機設計

### Grids EA 狀態

| 狀態 | 值 | 說明 |
|------|---|------|
| IDLE | 0 | 閒置 - 無獲利請求 |
| ACCUMULATING | 1 | 累積中 - 已確認請求，正在累積獲利 |
| READY | 2 | 就緒 - 獲利達標，等待 Recovery 消費 |
| ACKNOWLEDGED | 3 | 已確認 - Recovery 已消費，準備重置 |

### Recovery EA 狀態（用於讀取）

| 狀態 | 值 | 說明 |
|------|---|------|
| IDLE | 0 | 閒置 |
| REQUESTING | 1 | 請求中 |
| WAITING | 2 | 等待中 |
| CONSUMING | 3 | 消費中 |
| CONFIRMING | 4 | 確認中 |

### 狀態轉換流程

```
Grids: IDLE → ACCUMULATING → READY → ACKNOWLEDGED → IDLE
         ↑                                           |
         └───────────────────────────────────────────┘
```

---

## GV 命名規則

### 格式

- 一般模式：`{prefix}{groupId}_{symbol}_{name}`
- 跨商品模式：`{prefix}{groupId}_X_{name}`

### 範例

- `REC_A_EURUSD_ACCUMULATED_PROFIT`
- `REC_A_X_GRIDS_STATE`（跨商品模式）

### GV 清單

| 名稱 | 寫入方 | 說明 |
|------|--------|------|
| ACCUMULATED_PROFIT | Grids | 累積獲利金額 |
| GRIDS_STATE | Grids | Grids 狀態機狀態 |
| GRIDS_ACK_ID | Grids | Grids 確認的交易 ID |
| LAST_UPDATE | Grids | 最後更新時間 |
| TRANSACTION_ID | Recovery | 交易 ID |
| PROFIT_TARGET | Recovery | 目標獲利金額 |
| RECOVERY_STATE | Recovery | Recovery 狀態機狀態 |
| RECOVERY_ACK_ID | Recovery | Recovery 確認的交易 ID |

---

## 使用方式

### 引用

```mql4
#include "../Libs/RecoveryProfit/CRecoveryProfit.mqh"
```

### 標準用法

```mql4
CRecoveryProfit g_recoveryProfit;

// OnInit
g_recoveryProfit.Init("A", "REC_", Symbol());
g_recoveryProfit.SetCrossSymbol(false);
g_recoveryProfit.SetDebugLogs(true);

// OnTick
g_recoveryProfit.OnTick();

// 平倉獲利時
g_recoveryProfit.AddProfit(closedProfit);

// OnDeinit
g_recoveryProfit.Deinit();
```

### 獨立模式（不與 Recovery 通訊）

```mql4
CRecoveryProfit g_recoveryProfit;

// OnInit
g_recoveryProfit.Init("A");

// 平倉獲利時
g_recoveryProfit.AddProfit(closedProfit);

// 查詢累積獲利
double total = g_recoveryProfit.GetAccumulatedProfit();

// 重置獲利
g_recoveryProfit.ResetProfit();
```

---

## API 參考

### 初始化方法

| 方法 | 參數 | 說明 |
|------|------|------|
| `Init()` | groupId, gvPrefix, symbol | 初始化模組 |
| `SetCrossSymbol()` | bool | 設定跨商品模式 |
| `SetDebugLogs()` | bool | 設定除錯日誌開關 |
| `Deinit()` | - | 清理資源 |

### GV 操作方法

| 方法 | 參數 | 說明 |
|------|------|------|
| `WriteGV()` | name, value | 寫入 GV |
| `ReadGV()` | name, defaultValue | 讀取 GV |
| `CheckGV()` | name | 檢查 GV 是否存在 |
| `DeleteGV()` | name | 刪除 GV |

### 狀態機方法

| 方法 | 參數 | 說明 |
|------|------|------|
| `OnTick()` | - | 每個 tick 呼叫，執行狀態機 |
| `ExecuteStateMachine()` | - | 執行狀態機核心邏輯 |

### 獲利操作方法

| 方法 | 參數 | 說明 |
|------|------|------|
| `AddProfit()` | profit | 新增獲利 |
| `ResetProfit()` | - | 重置累積獲利 |
| `GetAccumulatedProfit()` | - | 取得累積獲利 |
| `GetProfitTarget()` | - | 取得目標獲利 |

### 狀態查詢方法

| 方法 | 返回值 | 說明 |
|------|--------|------|
| `GetState()` | int | 取得當前狀態 |
| `GetStateString()` | string | 取得狀態名稱 |
| `IsAccumulating()` | bool | 是否在累積狀態 |
| `IsReady()` | bool | 是否在就緒狀態 |
| `IsIdle()` | bool | 是否在閒置狀態 |
| `HasTarget()` | bool | 是否有目標獲利 |

---

## 測試模式

當 `IsTesting()` 返回 true 時，模組自動切換到本地緩存模式：

- 不寫入真實 GV
- 使用類別內部變數模擬 GV
- 適用於策略測試器環境

---

## 版本資訊

- 版本：1.00
- 建立日期：2025-12-21
- 作者：Andy's Trading System
