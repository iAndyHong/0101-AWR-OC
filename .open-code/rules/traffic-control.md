# 流量監督與控制規範 (Traffic Control Rules)

本文件定義了 OC Agent 如何執行流量監督，確保資源消耗在可控範圍內。

## 1. 流量審計流程 (Auditing Process)
1. **任務開始**：Agent 紀錄起始時間。
2. **執行中**：優先選用低成本模型（如 Claude 3.5 Haiku/Sonnet）進行研究，僅在複雜邏輯時呼叫 Oracle。
3. **任務結束**：
   - Agent 讀取系統傳回的 `Usage Metadata`。
   - 計算本次任務消耗的 Input/Output Tokens。
   - 更新 `.open-code/TRAFFIC.md` 中的明細。

## 2. 模型使用原則
- **研究與搜索**：使用 `librarian` 或 `explore` 背景任務。
- **簡單代碼修改**：直接使用主模型。
- **高難度 Debug / 架構設計**：必須在 `TRAFFIC.md` 中標註為何使用 Oracle。

## 3. 熔斷機制 (Circuit Breaker)
- 如果單次 Session 的預估費用超過 $5.00，Agent **必須主動停下** 並詢問 Andy 是否繼續。
- 如果本月累積費用接近預算上限，Agent 應提醒 Andy 檢視 `TRAFFIC.md`。

## 4. 檔案維護要求
- 每次更新 `TRAFFIC.md` 時，必須保留最近 20 筆明細，過舊的資料應進行摘要壓縮。
