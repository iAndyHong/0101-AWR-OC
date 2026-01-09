# AW Recovery EA 交易邏輯分析

## 概述

AW Recovery EA 是一個專門設計用於自動化恢復虧損倉位的專家顧問。它使用獨特的演算法來鎖定虧損倉位，將其分割成多個小部分，並分別關閉每個部分。這種部分關閉的方式可以降低保證金負擔，使虧損恢復過程更加安全。

---

## 系統架構：雙模組協作設計

### 核心概念

本專案將原廠 AW Recovery EA 拆分為兩個獨立但協作的模組：

**Grids EA（獲利累積器）**
- 職責：透過網格策略主動開單，累積小額獲利
- 角色：獲利生產者
- 特點：可獨立運行，也可與 Recovery EA 協作

**Recovery EA（虧損恢復器）**
- 職責：管理虧損倉位，使用外部獲利執行部分平倉
- 角色：獲利消費者
- 特點：被動等待獲利，專注於虧損恢復

### 為什麼要拆分？

原廠 AW Recovery EA 將「均價訂單開立」和「虧損恢復」整合在同一個 EA 中。拆分的優勢：

**靈活性**
- Grids EA 可單獨作為網格交易策略使用
- Recovery EA 可接收任何來源的獲利（不限於網格）
- 可在不同商品上運行兩個模組（跨商品協作）

**可維護性**
- 各模組職責單一，代碼更清晰
- 可獨立測試和優化各模組
- 問題定位更容易

**擴展性**
- 可同時運行多組 Grids + Recovery（組別隔離）
- 可替換不同的獲利策略（不限於網格）
- 可自訂獲利分配邏輯

---

## 雙模組協作流程

### 整體流程

**Grids EA（持續運作）**

- Grids EA 啟動後**永遠在交易**，不會停下來
- 每次止盈平倉後，獲利累加到 `ACCUMULATED_PROFIT`
- 不論 Recovery EA 是否存在，都持續累積

**協作流程（當 Recovery EA 存在時）**

1. **Recovery EA 發起請求**
   - 掃描虧損倉位
   - 計算所需獲利金額
   - 發布獲利請求 → 寫入 `PROFIT_TARGET = X`

2. **Grids EA 持續累積**（本來就在做，不是因為請求才開始）
   - 繼續執行網格交易
   - 獲利持續累加
   - 當 `ACCUMULATED_PROFIT >= PROFIT_TARGET` 時，標記就緒

3. **Recovery EA 消費獲利**
   - 讀取到獲利達標
   - 執行部分平倉
   - 確認消費完成 → 發送重置信號

4. **重置後繼續**
   - Grids EA 收到重置信號，歸零累積獲利
   - Grids EA **繼續交易**（從未停止）
   - Recovery EA 回到步驟 1（處理下一個部分）

### Grids EA 運作原則

**核心原則：Grids EA 永遠在運作，持續累積獲利**

Grids EA 是獨立的獲利引擎，不論 Recovery EA 是否存在或是否有請求，都會：
- 持續執行網格交易策略
- 持續累積獲利到 GV 變數
- 獲利只增不減（除非被 Recovery EA 消費後歸零）

**兩種運作模式**

- **獨立模式**（無 Recovery EA）
  - Grids EA 單獨運作
  - 累積獲利直接反映在帳戶餘額
  - 不需要 GV 通訊

- **協作模式**（有 Recovery EA）
  - Grids EA 持續累積獲利
  - Recovery EA 在需要時「提領」獲利
  - 提領後歸零，繼續累積

### 狀態機通訊協議（協作模式）

為確保兩個 EA 之間的通訊安全，採用狀態機 + 雙向確認 + 交易 ID 機制：

**Recovery EA 狀態**
- `STATE_R_IDLE` (0) - 閒置，無虧損倉位需要處理
- `STATE_R_REQUESTING` (1) - 請求中，已發布獲利目標
- `STATE_R_WAITING` (2) - 等待中，等待獲利達標
- `STATE_R_CONSUMING` (3) - 消費中，正在執行平倉
- `STATE_R_CONFIRMING` (4) - 確認中，等待 Grids 重置

**Grids EA 狀態**
- `STATE_G_TRADING` (0) - 交易中，持續執行網格策略並累積獲利（**永遠在運作**）
- `STATE_G_READY` (1) - 就緒，獲利已達 Recovery 請求的目標
- `STATE_G_ACKNOWLEDGED` (2) - 已確認，等待重置後繼續累積

**重要差異**：Grids EA 沒有「閒置」狀態，`STATE_G_TRADING` 是持續運作狀態

**交易 ID 機制**
- 每次獲利請求都有唯一的 Transaction ID
- 防止舊資料干擾新的交易週期
- 確保獲利不會被重複使用或遺失

---

## 核心交易策略

### 1. 鎖倉機制 (Locking)

**定義**：鎖倉是將 Buy 和 Sell 訂單的交易量對齊。

**運作方式**
- EA 首先尋找盈利的交易，並用它們來減少部分虧損訂單
- 如果這不足以平衡倉位，EA 會開立額外的鎖倉訂單
- 目標是使 BUY 手數 = SELL 手數
- 當倉位被鎖定後，無論市場趨勢如何，虧損金額都不會增加

**注意事項**
- 鎖倉後，虧損的增加僅來自經紀商收取的隔夜利息 (Swap)
- 啟用自動鎖倉時，必須停用計劃恢復的其他 EA

### 2. 均價訂單 / 網格訂單 (Averaging Orders / Grid Orders)

**定義**：EA 開立的訂單，用於利用其利潤來恢復虧損倉位。

**原廠邏輯（整合在單一 EA）**
- 第一個均價訂單的距離等於 `Step for average`
- 第一個均價訂單的手數等於 `Volume of average order`
- 後續均價訂單的手數按 `Multiplier to volume` 係數遞增
- 後續均價訂單的間距按 `Multiplier to step` 係數遞增
- 當前一個均價訂單虧損達到 `Step for average` 點數時，開立新的均價訂單

**本專案邏輯（拆分為 Grids EA）**
- Grids EA 獨立執行網格策略
- 採用雙向獨立籃子設計（Buy 和 Sell 籃子各自運作）
- 趨勢翻轉時開始新方向籃子，舊籃子繼續等待止盈
- 累積的獲利透過 GV 提供給 Recovery EA

**趨勢過濾**
- `BullsBears Candles Filtering` - 使用內建的反轉蠟燭形態指標
- `Super Trend Filtering` - 使用內建的趨勢指標（替代原廠 AW Trend Predictor）
- `Simple Grids` - 不使用趨勢過濾的經典網格

### 3. 部分關閉 (Partial Closing)

**定義**：EA 不會一次關閉整個訂單，而是將大訂單虛擬分割成小部分，逐一關閉。

**運作方式**
- 例如：1.00 手的訂單可以分成 10 個 0.10 手的部分
- 每個部分使用均價訂單的利潤來關閉
- `Part to close from a loss-making position` 決定每次關閉的手數

**優勢**
- 減少保證金佔用
- 保留更多可用資金
- 不需要開立大手數訂單
- 使恢復過程更安全穩定

### 4. 重疊關閉 (Overlap Closing)

**智能關閉系統**
- 均價訂單籃子不會完全關閉
- 只關閉同方向的第一個和最後一個均價訂單
- 這樣可以減少保證金負擔
- 由 `Allow overlap after number of orders` 控制啟用時機

---

## 網格模組與恢復模組的搭配邏輯

### 獲利流向

**Grids EA 端（獲利生產者）**

1. 網格交易 Buy/Sell
2. 止盈平倉 → +$10
3. 累積獲利 → $10
4. 透過 GV 通訊傳遞給 Recovery EA

**Recovery EA 端（獲利消費者）**

1. 虧損倉位 → -$500
2. 讀取獲利 → $10
3. 執行部分平倉
   - 平倉手數：0.01 手
   - 部分虧損：-$5
   - 使用獲利：+$10
   - 淨獲利：+$5

**結果**：虧損從 -$500 減少到 -$495

### 獲利目標計算

Recovery EA 計算所需獲利的公式：

```
所需獲利 = 部分虧損金額 + 止盈金額

其中：
- 部分虧損金額 = 當前要平倉的部分手數 × 虧損點數 × 點值
- 止盈金額 = TakeProfitMoney（用戶設定的每次部分平倉止盈）
```

**範例**
- 虧損訂單：1.00 手，虧損 500 點
- 部分平倉手數：0.01 手
- 部分虧損：0.01 × 500 × $10/點 = $50
- 止盈金額：$2
- 所需獲利：$50 + $2 = $52

### 累積獲利的歸零權限

**重要設計原則**：累積獲利的歸零權限只屬於 Recovery EA

**權限分配**

- 累積獲利 **累加**
  - Grids EA：✅ 可以
  - Recovery EA：❌ 不可以

- 累積獲利 **歸零**
  - Grids EA：❌ 不可以
  - Recovery EA：✅ 可以

- 累積獲利 **讀取**
  - Grids EA：✅ 可以
  - Recovery EA：✅ 可以

**原因**
- 避免寫入競爭導致獲利遺失
- 確保 Recovery EA 完全消費獲利後才歸零
- 使用 `RESET_PENDING` 標記協調歸零時機

### 組別隔離機制

當需要同時運行多組 EA 時，使用 GroupID 進行隔離：

**情境 1：單商品單組（預設）**
```
EURUSD:
  Recovery EA: GroupID = "A"
  Grids EA:    GroupID = "A"
```

**情境 2：單商品多組**
```
EURUSD 組別 A (處理 Magic 11111):
  Recovery EA: GroupID = "A", MagicNumbers = "11111"
  Grids EA:    GroupID = "A"

EURUSD 組別 B (處理 Magic 22222):
  Recovery EA: GroupID = "B", MagicNumbers = "22222"
  Grids EA:    GroupID = "B"
```

**情境 3：跨商品協作**
```
EURUSD Recovery 使用 GBPUSD Grids 的獲利:
  Recovery EA (EURUSD): GroupID = "X", CrossSymbol = true
  Grids EA (GBPUSD):    GroupID = "X", CrossSymbol = true
```

---

## 趨勢過濾系統

### 過濾模式對照

- **BullsBears Candles Filtering**
  - 本專案對應：`TF_FilterMode = 0`
  - 說明：基於蠟燭形態分析多空力量

- **AW Trend Predictor Filtering**
  - 本專案對應：`TF_FilterMode = 1` (Super Trend)
  - 說明：使用開源 Super Trend 替代商用指標

- **Simple Grids**
  - 本專案對應：`TF_FilterMode = 2`
  - 說明：不使用趨勢過濾的經典網格

### Super Trend 與 AW Trend Predictor 的差異

**相同點**
- 都是趨勢追蹤指標
- 都提供買入/賣出信號
- 都可設定分析時間框架

**差異點**
- Super Trend 是開源算法，無需外部指標
- 計算邏輯透明，可自行調整參數
- 效能更好，無需載入外部 DLL
- 參數名稱和數值範圍可能不同

### 首單開立模式

- **ST_SignalMode = 0**（趨勢方向內持續開單）
  - 前一籃子平倉後，立即在當前趨勢方向開立新首單

- **ST_SignalMode = 1**（只在趨勢反轉時開單）
  - 只在收到新的趨勢反轉信號時才開立新首單

### 加倉模式

- **ST_AveragingMode = 0**（順勢或中性時加倉）
  - 趨勢順向或中性時允許加倉，趨勢翻轉時停止加倉

- **ST_AveragingMode = 1**（僅順勢時加倉）
  - 只有趨勢明確順向時才允許加倉

**與原廠的差異**

原廠 AW Recovery EA 的 `Averaging in any direction` 模式會在趨勢翻轉後繼續加倉，因為它的目的是恢復虧損部位。但 Grids EA 的目的是主動開單累積獲利，因此修改了邏輯：趨勢翻轉時停止加倉，避免逆勢風險。

---

## 啟動模式

### 啟動類型 (Type of Launch)

**Instant start** - 立即啟動
- EA 在初始化時立即開始處理訂單

**Start at drawdown in percent** - 達到百分比回撤時啟動
- EA 分析處理的訂單，但只有當回撤達到指定百分比時才開始交易
- 回撤量在 `Drawdown in percentage or in money to Launch` 中設定

**Start at drawdown in money** - 達到金額回撤時啟動
- EA 分析處理的訂單，但只有當回撤達到指定金額時才開始交易
- 回撤量在 `Drawdown in percentage or in money to Launch` 中設定

### 啟動時的操作

**停用其他 EA** (`Disable other EAs at Launch`)
- 不停用
- 停用同一商品的所有 EA
- 停用所有商品的所有 EA

**關閉盈利訂單** (`Close profit at Launch`)
- 關閉所有盈利的處理訂單，用釋放的利潤關閉虧損訂單

**刪除掛單** (`Delete Pending Orders at Launch`)
- 刪除所有與處理倉位相關的掛單

**刪除止損止盈** (`Delete SL and TP`)
- 刪除所有手動或其他演算法設定的 TakeProfit 和 StopLoss

---

## 訂單識別設定

### MagicNumber 群組 (MagicNumbers group for recovery)

**All orders on same symbol**
- 處理同一商品上的所有訂單

**Manual opened orders on the same symbol**
- 只處理 MagicNumber 等於 EA 使用的或等於 "0"（手動開立）的訂單

**Same MagicNumbers on same Symbol**
- 只處理 MagicNumber 與 EA 相同的訂單
- 可用於恢復特定 EA 的訂單

### 訂單處理順序 (What orders to start from)

**Start with easy to close orders**
- 先關閉最容易關閉的訂單
- 適合大倉位加速減少隔夜利息

**Start with hard to close orders**
- 先關閉最難關閉的訂單
- 提高在 TP 關閉整個倉位的機率

---

## 止盈設定

### 部分關閉止盈

- `TakeProfit in money for partial close` - 當前訂單組的止盈金額
- 使用均價訂單的利潤和虧損倉位的部分手數

### 整體籃子止盈

- `Use TP for total basket if possible` - 啟用整體止盈
- `TP for total basket in money` - 整體倉位（鎖倉 + 均價訂單）達到指定利潤時全部關閉
- 適合新聞行情或作為交易面板使用

---

## 保護設定

**One Opened Order per Bar filtering**
- 每根 K 線只開一個訂單，過濾劇烈波動

**Multidirectional trading**
- 允許同時雙向交易

**Maximum slippage in points**
- 最大滑點

**Maximum spread in points**
- 最大點差

**Maximum volume of average order**
- 單個均價訂單最大手數

**Maximum number of average orders**
- 同方向均價訂單最大數量

---

## 設定建議

### 部分關閉手數

```
Part to close from a loss-making position = 最遠虧損訂單手數 / 6 或 8
```

例如：1 手的虧損訂單，關閉部分可設為 0.12 ~ 0.16 手

### 均價訂單手數

```
Volume of average order = Part to close from a loss-making position × 1.5
```

均價訂單手數應不小於關閉部分，建議比例 1:1.5

### 訂單間距

使用 ATR(14) 在 D1 時間框架確定平均日波動：

**高風險**
- Step for average = 日均波動 / 4

**中風險**
- Step for average = 日均波動 / 3

**低風險**
- Step for average = 日均波動 / 2

---

## 重要注意事項

**單一運行**
- EA 只能在一個終端運行，避免重複開立鎖倉和均價訂單

**VPS 轉移**
- 設定只通過輸入設定選單固定，面板上的更改不會轉移到 VPS

**重新啟動**
- 如果希望 EA 在恢復完成後繼續等待新的回撤，需要重新啟動 EA

**其他 EA 衝突**
- 啟用鎖倉時，必須停用可能與 AW Recovery 衝突的其他 EA

**測試建議**
- 在實盤啟動前，務必在策略測試器中使用「視覺化」模式測試設定

**GroupID 一致性**
- Recovery EA 和 Grids EA 的 GroupID 必須相同才能協作

**GV 前綴一致性**
- 兩個 EA 的 GV_Prefix 設定必須相同

---

## 版本記錄

- **2024-12-14 v2.0** → 新增雙模組協作設計說明、獲利流向分析、組別隔離機制
- **2024-11-01 v1.0** → 初始版本，原廠邏輯分析
