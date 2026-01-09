# 雙 EA 協作架構設計 v3.00

## 概述

將原本 AW Recovery EA 的概念拆分為兩個獨立的 EA，透過全局變數 (Global Variable, GV) 進行溝通協作：

1. **Recovery Manager EA** - 負責虧損管理與部分平倉
2. **Profit Generator EA** - 負責透過網格或其他策略累積獲利

### 版本歷史

| 版本 | 日期 | 說明 |
|------|------|------|
| v3.00 | 2024-12-12 | 新增 GroupID 組別隔離機制，支援多組 EA 和跨商品協作 |
| v2.00 | 2024-12-12 | 實現狀態機 + 雙向確認 + 交易 ID 機制 |
| v1.00 | 2024-12-12 | 初始版本，基本 GV 通訊 |

---

## 架構圖

```
┌─────────────────────────────────────────────────────────────────┐
│                        MetaTrader 終端                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────┐      ┌──────────────────────┐        │
│  │  Recovery Manager EA │      │  Profit Generator EA │        │
│  │                      │      │                      │        │
│  │  • 虧損掃描          │      │  • 網格交易          │        │
│  │  • 鎖倉管理          │      │  • 趨勢跟蹤          │        │
│  │  • 部分平倉          │      │  • 其他獲利策略      │        │
│  │  • 獲利分配          │      │  • 累積小額獲利      │        │
│  └──────────┬───────────┘      └───────────┬──────────┘        │
│             │                              │                    │
│             │    ┌─────────────────┐       │                    │
│             └───►│  Global Variable │◄──────┘                    │
│                  │     (GV 通訊)    │                            │
│                  │                  │                            │
│                  │  • 獲利金額      │                            │
│                  │  • 目標金額      │                            │
│                  │  • 狀態標誌      │                            │
│                  │  • 指令傳遞      │                            │
│                  └─────────────────┘                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 模組一：Recovery Manager EA

### 主要職責

1. **虧損掃描與識別**
2. **鎖倉管理**
3. **部分平倉執行**
4. **獲利需求計算與發布**

### 功能詳述

#### 1.1 虧損掃描 (Loss Scanning)

```
功能：持續掃描帳戶中的虧損倉位
輸入：
  - MagicNumber 過濾條件
  - 商品過濾條件
  - 最小虧損閾值
輸出：
  - 虧損倉位清單
  - 總虧損金額
  - 各方向手數統計
```

**掃描邏輯：**
- 遍歷所有持倉訂單
- 根據 MagicNumber 和商品過濾
- 計算每個訂單的浮動盈虧
- 識別需要恢復的虧損倉位
- 按難易度排序（可選從簡單或困難開始）

#### 1.2 鎖倉管理 (Lock Management)

```
功能：平衡 Buy/Sell 手數，固定虧損
輸入：
  - 當前 Buy 總手數
  - 當前 Sell 總手數
  - 是否啟用鎖倉
輸出：
  - 鎖倉訂單（如需要）
  - 鎖倉狀態
```

**鎖倉邏輯：**
```
IF Buy_Lots > Sell_Lots THEN
    開立 Sell 訂單，手數 = Buy_Lots - Sell_Lots
ELSE IF Sell_Lots > Buy_Lots THEN
    開立 Buy 訂單，手數 = Sell_Lots - Buy_Lots
END IF
```

#### 1.3 部分平倉計算 (Partial Close Calculation)

```
功能：計算每次需要平倉的部分
輸入：
  - 虧損倉位資訊
  - 部分平倉手數設定
  - 可用獲利金額（從 GV 讀取）
輸出：
  - 待平倉訂單清單
  - 每個訂單的平倉手數
  - 所需獲利金額
```

**計算邏輯：**
```
1. 選擇當前處理的虧損訂單（按設定的順序）
2. 計算部分平倉的虧損金額：
   部分虧損 = (訂單總虧損 / 訂單手數) × 部分平倉手數
3. 發布所需獲利金額到 GV
4. 等待 Profit Generator 累積足夠獲利
5. 執行部分平倉
```

#### 1.4 獲利需求發布 (Profit Request Publishing)

```
功能：向 GV 發布獲利需求
輸出到 GV：
  - GV_PROFIT_TARGET：目標獲利金額
  - GV_RECOVERY_STATUS：Recovery EA 狀態
  - GV_PARTIAL_LOSS：當前部分虧損金額
```

---

## 模組二：Profit Generator EA

### 主要職責

1. **執行獲利策略（網格/其他）**
2. **累積小額獲利**
3. **獲利狀態回報**
4. **響應 Recovery Manager 的需求**

### 功能詳述

#### 2.1 網格交易系統 (Grid Trading System)

```
功能：透過網格策略累積獲利
輸入：
  - 網格間距
  - 起始手數
  - 手數倍增係數
  - 最大網格層數
輸出：
  - 網格訂單
  - 累積獲利
```

**網格邏輯：**
```
1. 根據當前價格建立網格
2. 價格觸及網格線時開單
3. 達到止盈時平倉
4. 將獲利累積到 GV_ACCUMULATED_PROFIT
```

#### 2.2 獲利累積與回報 (Profit Accumulation)

```
功能：追蹤並回報累積獲利
輸出到 GV：
  - GV_ACCUMULATED_PROFIT：已累積獲利金額
  - GV_GENERATOR_STATUS：Generator EA 狀態
  - GV_LAST_PROFIT_TIME：最後獲利時間
```

#### 2.3 獲利轉移機制 (Profit Transfer)

```
功能：當累積獲利達到目標時通知 Recovery Manager
邏輯：
  IF GV_ACCUMULATED_PROFIT >= GV_PROFIT_TARGET THEN
      設定 GV_PROFIT_READY = true
      等待 Recovery Manager 確認使用
      重置 GV_ACCUMULATED_PROFIT
  END IF
```

---

---

## 組別隔離機制 (v3.00 新增)

### 問題分析

當多組 EA 同時運行時，可能發生以下衝突：

| 場景 | 問題 | 解決方案 |
|------|------|----------|
| 同商品多組 | GV 互相覆蓋 | 使用不同 GroupID |
| 跨商品協作 | GV 綁定商品無法通訊 | 啟用 CrossSymbol 模式 |
| 重複啟動 | 同組別多個 EA 競爭 | 衝突檢測機制 |

### 組別設定參數

```mql4
// Recovery EA
input string   RM_GroupID                = "A";       // 組別 ID
input bool     RM_CrossSymbol            = false;     // 跨商品模式
input string   RM_TargetSymbol           = "";        // 目標商品
input bool     RM_CheckConflict          = true;      // 檢查組別衝突

// Grids EA
input string   PG_GroupID                = "A";       // 組別 ID (必須與 Recovery 相同)
input bool     PG_CrossSymbol            = false;     // 跨商品模式
input string   PG_TargetSymbol           = "";        // 目標商品
input bool     PG_CheckConflict          = true;      // 檢查組別衝突
```

### 使用情境

#### 情境 1：單商品單組（預設）
```
EURUSD:
  Recovery EA: GroupID = "A"
  Grids EA:    GroupID = "A"
  
GV 範例: RECOVERY_A_EURUSD_PROFIT_TARGET
```

#### 情境 2：單商品多組
```
EURUSD 組別 A (處理 Magic 11111):
  Recovery EA: GroupID = "A", MagicNumbers = "11111"
  Grids EA:    GroupID = "A"
  GV 範例: RECOVERY_A_EURUSD_PROFIT_TARGET

EURUSD 組別 B (處理 Magic 22222):
  Recovery EA: GroupID = "B", MagicNumbers = "22222"
  Grids EA:    GroupID = "B"
  GV 範例: RECOVERY_B_EURUSD_PROFIT_TARGET
```

#### 情境 3：多商品各自獨立
```
EURUSD:
  Recovery EA: GroupID = "A"
  Grids EA:    GroupID = "A"
  GV 範例: RECOVERY_A_EURUSD_PROFIT_TARGET

GBPUSD:
  Recovery EA: GroupID = "A"  // 可以用相同 GroupID，因為商品不同
  Grids EA:    GroupID = "A"
  GV 範例: RECOVERY_A_GBPUSD_PROFIT_TARGET
```

#### 情境 4：跨商品協作
```
EURUSD Recovery 使用 GBPUSD Grids 的獲利:
  Recovery EA (EURUSD): GroupID = "X", CrossSymbol = true
  Grids EA (GBPUSD):    GroupID = "X", CrossSymbol = true
  GV 範例: RECOVERY_X_CROSS_PROFIT_TARGET
```

### 衝突檢測機制

```mql4
// 檢查是否已有同組別的 EA 運行
bool CheckGroupConflict()
{
    string lockGV = GetGVFullName("RECOVERY_LOCK");
    
    if(GlobalVariableCheck(lockGV))
    {
        double existingId = GlobalVariableGet(lockGV);
        datetime lastUpdate = (datetime)ReadGV("LAST_UPDATE", 0);
        
        // 如果上次更新超過 60 秒，視為已停止
        if(TimeCurrent() - lastUpdate > 60)
        {
            Print("偵測到舊的實例已停止，接管組別");
        }
        else if(existingId != g_instanceId && existingId != 0)
        {
            Print("錯誤：組別已有其他 EA 運行！");
            return true;
        }
    }
    
    // 註冊自己
    GlobalVariableSet(lockGV, g_instanceId);
    return false;
}
```

---

## 全局變數 (GV) 通訊協議

### GV 命名規範

```
前綴：RECOVERY_
格式：RECOVERY_{GroupID}_{商品}_{變數名}
範例：RECOVERY_A_EURUSD_PROFIT_TARGET

跨商品模式：
格式：RECOVERY_{GroupID}_CROSS_{變數名}
範例：RECOVERY_A_CROSS_PROFIT_TARGET
```

### 核心 GV 變數

| 變數名 | 類型 | 寫入者 | 讀取者 | 說明 |
|--------|------|--------|--------|------|
| `TRANSACTION_ID` | double | Recovery | Grids | 交易週期序列號 |
| `PROFIT_TARGET` | double | Recovery | Grids | 目標獲利金額 |
| `ACCUMULATED_PROFIT` | double | Grids | Recovery | 已累積獲利 |
| `RECOVERY_STATE` | int | Recovery | Grids | Recovery 狀態碼 |
| `GRIDS_STATE` | int | Grids | Recovery | Grids 狀態碼 |
| `RECOVERY_ACK_ID` | double | Recovery | Grids | Recovery 確認的交易 ID |
| `GRIDS_ACK_ID` | double | Grids | Recovery | Grids 確認的交易 ID |
| `PARTIAL_LOSS` | double | Recovery | Grids | 當前部分虧損 |
| `LOCK_VOLUME` | double | Recovery | Both | 鎖倉手數 |
| `LAST_UPDATE` | datetime | Both | Both | 最後更新時間 |
| `RECOVERY_LOCK` | double | Recovery | Recovery | Recovery 實例鎖定 ID (v3.00) |
| `GRIDS_LOCK` | double | Grids | Grids | Grids 實例鎖定 ID (v3.00) |

### 狀態碼定義

**Recovery Status:**
```
0 = 閒置 (Idle)
1 = 掃描中 (Scanning)
2 = 鎖倉中 (Locking)
3 = 等待獲利 (Waiting for Profit)
4 = 執行平倉 (Executing Close)
5 = 暫停 (Paused)
9 = 錯誤 (Error)
```

**Generator Status:**
```
0 = 閒置 (Idle)
1 = 交易中 (Trading)
2 = 累積獲利中 (Accumulating)
3 = 獲利就緒 (Profit Ready)
5 = 暫停 (Paused)
9 = 錯誤 (Error)
```

**Command 指令:**
```
0 = 無指令
1 = 開始交易
2 = 停止交易
3 = 確認獲利使用
4 = 重置累積
5 = 緊急停止
```

---

## 工作流程

### 完整恢復週期

```
┌─────────────────────────────────────────────────────────────────┐
│                        工作流程                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Recovery Manager                    Profit Generator            │
│  ───────────────                    ─────────────────            │
│        │                                   │                     │
│   1. 掃描虧損                              │                     │
│        │                                   │                     │
│   2. 執行鎖倉                              │                     │
│        │                                   │                     │
│   3. 計算部分虧損                          │                     │
│        │                                   │                     │
│   4. 發布獲利目標 ──────────────────────►  │                     │
│        │              GV_PROFIT_TARGET     │                     │
│        │                                   │                     │
│   5. 等待獲利                         6. 執行網格交易            │
│        │                                   │                     │
│        │                              7. 累積獲利                │
│        │                                   │                     │
│        │  ◄────────────────────────── 8. 回報獲利就緒           │
│        │         GV_PROFIT_READY           │                     │
│        │                                   │                     │
│   9. 確認使用獲利 ─────────────────────►   │                     │
│        │           GV_COMMAND=3            │                     │
│        │                                   │                     │
│  10. 執行部分平倉                    11. 重置累積                │
│        │                                   │                     │
│  12. 檢查是否完成                          │                     │
│        │                                   │                     │
│   └──► 若未完成，回到步驟 3                │                     │
│                                            │                     │
└─────────────────────────────────────────────────────────────────┘
```

### 時序圖

```
Recovery Manager          Global Variable          Profit Generator
      │                         │                         │
      │──── 寫入目標獲利 ──────►│                         │
      │                         │◄──── 讀取目標 ──────────│
      │                         │                         │
      │                         │                    執行交易
      │                         │                         │
      │                         │◄──── 更新累積獲利 ──────│
      │◄─── 讀取累積獲利 ───────│                         │
      │                         │                         │
      │     [獲利未達標]        │                         │
      │         等待            │                    繼續交易
      │                         │                         │
      │                         │◄──── 獲利達標通知 ──────│
      │◄─── 讀取就緒標誌 ───────│                         │
      │                         │                         │
      │──── 確認使用指令 ──────►│                         │
      │                         │◄──── 讀取指令 ──────────│
      │                         │                         │
   執行平倉                      │                    重置累積
      │                         │                         │
```

---

## 參數設計

### Recovery Manager EA 參數

```mql5
// ===== 訂單識別設定 =====
input string   RM_Help1                = "----------------";   // 訂單識別設定
input int      RM_MagicFilter          = 0;                    // 過濾 MagicNumber (0=全部)
input string   RM_SymbolFilter         = "";                   // 過濾商品 (空=當前商品)
input bool     RM_IncludeManual        = true;                 // 包含手動訂單

// ===== 鎖倉設定 =====
input string   RM_Help2                = "----------------";   // 鎖倉設定
input bool     RM_UseLocking           = true;                 // 啟用鎖倉
input int      RM_LockMagic            = 88888;                // 鎖倉訂單 MagicNumber

// ===== 部分平倉設定 =====
input string   RM_Help3                = "----------------";   // 部分平倉設定
input double   RM_PartialLots          = 0.01;                 // 每次平倉手數
input int      RM_CloseOrder           = 0;                    // 平倉順序 (0=簡單優先, 1=困難優先)
input double   RM_MinProfit            = 1.0;                  // 最小獲利緩衝

// ===== 啟動設定 =====
input string   RM_Help4                = "----------------";   // 啟動設定
input int      RM_LaunchType           = 0;                    // 啟動類型 (0=立即, 1=回撤%, 2=回撤金額)
input double   RM_LaunchThreshold      = 5.0;                  // 啟動閾值

// ===== GV 通訊設定 =====
input string   RM_Help5                = "----------------";   // GV 通訊設定
input string   RM_GV_Prefix            = "RECOVERY_SYSTEM_";   // GV 前綴
input int      RM_UpdateInterval       = 1;                    // 更新間隔 (秒)
```

### Profit Generator EA 參數

```mql5
// ===== 網格設定 =====
input string   PG_Help1                = "----------------";   // 網格設定
input double   PG_GridStep             = 50.0;                 // 網格間距 (點)
input double   PG_InitialLots          = 0.01;                 // 起始手數
input double   PG_LotMultiplier        = 1.5;                  // 手數倍增
input int      PG_MaxGridLevels        = 10;                   // 最大網格層數
input double   PG_TakeProfit           = 30.0;                 // 止盈 (點)

// ===== 交易方向 =====
input string   PG_Help2                = "----------------";   // 交易方向
input int      PG_TradeDirection       = 0;                    // 方向 (0=雙向, 1=只買, 2=只賣)

// ===== 風險控制 =====
input string   PG_Help3                = "----------------";   // 風險控制
input double   PG_MaxDrawdown          = 20.0;                 // 最大回撤 (%)
input double   PG_MaxLots              = 1.0;                  // 最大總手數
input int      PG_MagicNumber          = 99999;                // MagicNumber

// ===== GV 通訊設定 =====
input string   PG_Help4                = "----------------";   // GV 通訊設定
input string   PG_GV_Prefix            = "RECOVERY_SYSTEM_";   // GV 前綴
input int      PG_UpdateInterval       = 1;                    // 更新間隔 (秒)
input bool     PG_WaitForTarget        = true;                 // 等待目標才交易
```

---

## GV 操作函數範例 (v3.00)

### 取得完整 GV 名稱

```mql4
string GetGVFullName(string name)
{
    // 格式: RECOVERY_{GroupID}_{Symbol}_{name}
    // 跨商品模式: RECOVERY_{GroupID}_CROSS_{name}
    if(CrossSymbol)
        return GV_Prefix + GroupID + "_CROSS_" + name;
    else
        return GV_Prefix + GroupID + "_" + g_gvSymbol + "_" + name;
}
```

### 寫入 GV

```mql4
void WriteGV(string name, double value)
{
    string fullName = GetGVFullName(name);
    GlobalVariableSet(fullName, value);
}
```

### 讀取 GV

```mql4
double ReadGV(string name, double defaultValue = 0)
{
    string fullName = GetGVFullName(name);
    if(GlobalVariableCheck(fullName))
        return GlobalVariableGet(fullName);
    return defaultValue;
}
```

### 檢查 GV 存在

```mql4
bool CheckGV(string name)
{
    string fullName = GetGVFullName(name);
    return GlobalVariableCheck(fullName);
}
```

### 刪除 GV

```mql4
void DeleteGV(string name)
{
    string fullName = GetGVFullName(name);
    if(GlobalVariableCheck(fullName))
        GlobalVariableDel(fullName);
}
```

---

## 優勢與考量

### 優勢

1. **模組化設計** - 兩個 EA 可獨立開發、測試、優化
2. **靈活性** - Profit Generator 可替換為任何獲利策略
3. **可擴展性** - 可增加更多 Generator EA 協同工作
4. **風險隔離** - 虧損管理與獲利策略分離
5. **易於維護** - 單一職責，程式碼更清晰

### 考量事項

1. **同步問題** - 需確保 GV 讀寫的時序正確
2. **延遲** - GV 通訊可能有微小延遲
3. **錯誤處理** - 需處理 EA 異常停止的情況
4. **資源佔用** - 兩個 EA 同時運行的資源消耗
5. **測試複雜度** - 需要同時測試兩個 EA 的協作

---

## 後續開發建議

1. **Phase 1** - 先開發 Recovery Manager EA 的核心功能
2. **Phase 2** - 開發簡單的網格 Profit Generator EA
3. **Phase 3** - 整合測試 GV 通訊機制
4. **Phase 4** - 優化與擴展功能
5. **Phase 5** - 開發其他類型的 Profit Generator EA
