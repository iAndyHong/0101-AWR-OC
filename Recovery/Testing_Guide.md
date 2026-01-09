# Recovery EA 測試指南

## 問題分析

Recovery EA 測試困難的原因：
1. 需要「先有虧損持倉」才能測試恢復邏輯
2. 需要與 Grids EA 配合（GV 通訊）
3. 狀態機有多個階段，難以逐一測試
4. 等待獲利累積耗時

---

## 解決方案：模擬測試環境

### 方案 A：手動建立測試持倉

在 MT4 中手動開單，模擬虧損狀態：

1. **開啟兩個相反方向的訂單**
   - BUY 0.1 手（會虧損）
   - SELL 0.05 手（會虧損）
   - 確保總體是虧損狀態

2. **設定 MagicNumber = 0**
   - Recovery EA 設定 `RM_MagicSelection = 0`（處理所有訂單）
   - 這樣手動單也會被處理

3. **優點**：快速建立測試環境
4. **缺點**：無法測試 GV 通訊

---

### 方案 B：獨立測試模式（推薦）

在 Recovery EA 中加入「測試模式」參數：

```mql4
input bool     RM_TestMode              = false;                // 測試模式
input double   RM_TestSimulatedLoss     = -50.0;               // 模擬虧損金額
input double   RM_TestSimulatedProfit   = 100.0;               // 模擬可用獲利
```

測試模式下：
- 不需要真實虧損持倉
- 不需要 Grids EA 配合
- 直接模擬 GV 數值
- 可快速測試所有狀態轉換

---

### 方案 C：GV 模擬腳本

建立一個獨立的 Script，模擬 Grids EA 的 GV 行為：

```mql4
// GV_Simulator.mq4
// 模擬 Grids EA 的 GV 通訊

input string   GroupID = "A";
input int      SimulateState = 2;        // 0=IDLE, 1=累積中, 2=就緒, 3=已確認
input double   SimulateProfit = 50.0;    // 模擬累積獲利

void OnStart()
{
   string prefix = "REC_" + GroupID + "_";
   
   GlobalVariableSet(prefix + "GRIDS_STATE", SimulateState);
   GlobalVariableSet(prefix + "ACCUMULATED_PROFIT", SimulateProfit);
   GlobalVariableSet(prefix + "GRIDS_ACK_ID", GlobalVariableGet(prefix + "TRANSACTION_ID"));
   
   Print("GV 模擬完成: State=", SimulateState, " Profit=", SimulateProfit);
}
```

---

## 測試步驟設計

### 階段 1：基礎功能測試

#### 1.1 初始化測試
- [ ] EA 載入成功
- [ ] GV 變數正確建立
- [ ] 組別衝突檢測正常
- [ ] UI 面板顯示正確

#### 1.2 前置處理測試
- [ ] 刪除 SL/TP 功能
- [ ] 刪除掛單功能
- [ ] 關閉盈利訂單功能
- [ ] 鎖倉功能

---

### 階段 2：狀態機測試

使用 GV 模擬腳本，逐一測試每個狀態：

#### 2.1 STATE_R_IDLE → STATE_R_REQUESTING
觸發條件：有虧損持倉
- [ ] 正確計算部分虧損
- [ ] 正確發布獲利目標
- [ ] 正確遞增交易 ID

#### 2.2 STATE_R_REQUESTING → STATE_R_WAITING
觸發條件：Grids 確認請求
- [ ] 正確讀取 Grids 狀態
- [ ] 正確驗證 ACK ID
- [ ] 超時重發機制

#### 2.3 STATE_R_WAITING → STATE_R_CONSUMING
觸發條件：獲利達標
- [ ] 正確判斷獲利是否達標
- [ ] 正確進入消費狀態

#### 2.4 STATE_R_CONSUMING → STATE_R_CONFIRMING
觸發條件：平倉成功
- [ ] 部分平倉執行正確
- [ ] 正確發送確認 ID

#### 2.5 STATE_R_CONFIRMING → STATE_R_IDLE
觸發條件：Grids 重置
- [ ] 正確回到閒置狀態
- [ ] GV 正確清理

---

### 階段 3：異常狀況測試

#### 3.1 通訊異常
- [ ] Grids EA 未運行時的行為
- [ ] GV 被意外刪除時的行為
- [ ] 超時處理

#### 3.2 訂單異常
- [ ] 平倉失敗時的重試
- [ ] 手數不足時的處理
- [ ] 滑價過大時的處理

#### 3.3 參數異常
- [ ] RM_PartialLots = 0
- [ ] RM_TakeProfitMoney = 0
- [ ] RM_GroupID 為空

---

### 階段 4：整合測試

#### 4.1 與 Grids EA 配合測試
- [ ] 完整的獲利請求 → 累積 → 消費週期
- [ ] 多次連續恢復週期
- [ ] 中途重啟 EA

#### 4.2 壓力測試
- [ ] 大量訂單（50+ 單）
- [ ] 快速市場波動
- [ ] 長時間運行穩定性

---

## 快速測試流程

### 最小測試環境

1. **開啟 Demo 帳戶**

2. **手動建立虧損持倉**
   ```
   BUY  0.05 手 @ 市價
   SELL 0.03 手 @ 市價
   等待價格波動產生虧損
   ```

3. **載入 Recovery EA**
   ```
   RM_MagicSelection = 0（處理所有訂單）
   RM_TestMode = true（如果有實作）
   RM_ShowDebugLogs = true
   ```

4. **執行 GV 模擬腳本**
   ```
   模擬 Grids 狀態 = READY
   模擬累積獲利 = 100
   ```

5. **觀察 Recovery EA 行為**
   - 檢查日誌輸出
   - 檢查狀態轉換
   - 檢查平倉執行

---

## 測試參數檔

### normal_test.set
```
RM_GroupID=TEST
RM_MagicSelection=0
RM_PartialLots=0.01
RM_TakeProfitMoney=2.0
RM_ShowDebugLogs=true
```

### boundary_test.set
```
RM_GroupID=TEST
RM_MagicSelection=0
RM_PartialLots=0.01
RM_TakeProfitMoney=0.0
RM_ShowDebugLogs=true
```

### stress_test.set
```
RM_GroupID=TEST
RM_MagicSelection=0
RM_PartialLots=0.01
RM_TakeProfitMoney=0.5
RM_UpdateInterval=0
RM_ShowDebugLogs=false
```

---

## 建議的改進

### 1. 加入測試模式參數
讓 EA 可以在沒有真實持倉的情況下測試邏輯

### 2. 建立 GV 模擬腳本
獨立控制 Grids EA 的 GV 狀態

### 3. 加入狀態強制切換
除錯時可手動切換狀態機狀態

### 4. 詳細的狀態日誌
每次狀態轉換都輸出完整資訊

---

## 更新記錄

- 2025-12-19：建立測試指南
