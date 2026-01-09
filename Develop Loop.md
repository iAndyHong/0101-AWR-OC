# MQL4 開發閉環系統

## 目標

在 Kiro 環境中完成 MQL4 的完整開發流程：**代碼編寫 → 編譯 → 執行測試 → 除錯**，不需離開 IDE。

---

## 系統架構

```
Kiro (macOS)
    ↓
compile.sh / test.sh / logs.sh
    ↓
PD 虛擬機 (Windows)
    ↓
MetaEditor (編譯) / MT4 終端 (執行測試)
```

---

## 閉環流程

1. **寫代碼** → Kiro 編輯 `.mq4`
2. **編譯** → `./compile.sh` → PD 虛擬機 → MetaEditor
3. **執行測試** → `./test.sh` → PD 虛擬機 → MT4 終端（帶 INI）
4. **查看日誌** → 讀取 MT4 日誌或自訂 LogFile
5. **除錯修正** → 回到步驟 1

---

## 腳本說明

### A. 編譯腳本（已完成）

```bash
./compile.sh "Grids 1.2/Grids 1.12.mq4"
```

功能：
- 自動檢查虛擬機狀態
- 呼叫 MetaEditor 編譯
- 解析編譯日誌，顯示錯誤

### B. 測試腳本（待建立）

```bash
./test.sh "Grids 1.12" "EURUSD" "H1"
```

功能：
- 動態生成 `.ini` 設定檔
- 透過 `prlctl exec` 在 PD 虛擬機中啟動 MT4
- MT4 自動載入指定 EA 和參數

### C. 日誌腳本（待建立）

```bash
./logs.sh "Grids 1.12"
```

功能：
- 從 PD 虛擬機讀取 MT4 日誌
- 或讀取自訂的 `LogFile` 輸出
- 顯示在 Kiro 終端中

### D. 整合腳本（待建立）

```bash
./dev.sh "Grids 1.2/Grids 1.12.mq4"
```

功能：
- 一鍵完成：編譯 + 啟動測試

---

## MT4 命令列啟動

MT4 終端支援命令列參數：

```bash
terminal.exe /config:MyConfig.ini
```

### INI 檔案結構範例

```ini
; MyTest.ini
[Common]
Login=12345678
Server=Demo-Server
Symbol=EURUSD
Period=H1
Template=default

[Expert]
Name=Grids 1.12
Path=Experts\Grids 1.12.ex4
Inputs=Grids 1.12.set

[Tester]
Expert=Grids 1.12
Symbol=EURUSD
Period=H1
Model=1
FromDate=2024.01.01
ToDate=2024.12.31
Optimization=0
```

---

## 建立前需確認的資訊

1. **PD 虛擬機名稱**（用於 `prlctl` 命令）
2. **MT4 終端路徑**（在 Windows 虛擬機中的完整路徑）
3. **MT4 資料夾路徑**（存放 EA、日誌的 `MQL4` 資料夾）
4. **預設測試帳號**（Demo 帳號資訊，可選）

---

## 最終效果

開發時只需要：

```bash
# 改完代碼後
./compile.sh "Grids 1.2/Grids 1.12.mq4"   # 編譯
./test.sh "Grids 1.12"                      # 啟動測試
./logs.sh "Grids 1.12"                      # 查看日誌
```

或整合成一個命令：

```bash
./dev.sh "Grids 1.2/Grids 1.12.mq4"   # 編譯 + 啟動測試
```

---

## 測試策略

測試不應該只是「標準流程跑一遍」，必須涵蓋各種意外狀況和邊界條件。

### 測試類型

#### 1. 正常流程測試（Happy Path）
- 標準參數下的正常運作
- 預期的開單、平倉流程
- 正常市場條件下的表現

#### 2. 邊界條件測試（Boundary Testing）
- 極端參數值（最大/最小/零/負數）
- 手數邊界（0.01、最大手數、超過限制）
- 價格邊界（點差極大、價格跳空）

#### 3. 異常狀況測試（Error Handling）
- 網路斷線後重連
- 訂單執行失敗（滑價、拒絕）
- 餘額不足時的行為
- 伺服器無回應

#### 4. 參數錯誤測試（Invalid Input）
- 不合理的參數組合
- 負數手數、負數間距
- 空字串、特殊字符
- 超出範圍的 MagicNumber

#### 5. 狀態恢復測試（Recovery Testing）
- EA 重啟後的狀態恢復
- MT4 終端重啟後的行為
- 持倉中途載入 EA

#### 6. 併發測試（Concurrency）
- 多個 EA 同時運作
- 同商品多 EA 衝突
- MagicNumber 重複

### 測試案例範本

```
測試名稱：手數為零時的行為
前置條件：Lots = 0.0
預期結果：EA 應拒絕開單並輸出錯誤訊息
實際結果：___
狀態：通過 / 失敗
```

### 測試腳本規劃

```bash
# 執行單一測試案例
./test.sh "Grids 1.12" --case "zero_lots"

# 執行所有邊界測試
./test.sh "Grids 1.12" --suite "boundary"

# 執行完整測試套件
./test.sh "Grids 1.12" --suite "all"
```

### 測試參數檔管理

```
Tests/
├── Grids 1.12/
│   ├── normal.set          # 正常參數
│   ├── boundary_min.set    # 最小邊界
│   ├── boundary_max.set    # 最大邊界
│   ├── invalid_lots.set    # 無效手數
│   └── stress.set          # 壓力測試
```

---

## 其他自動化流程建議

### 優先順序

1. **開發閉環**（進行中）← 最重要
2. **代碼範本生成器** ← 加速新專案啟動
3. **批次回測** ← 提升測試效率
4. **版本管理** ← 避免混亂
5. **監控系統** ← 實盤保護

### 代碼品質自動化

- **存檔時自動編譯檢查**（Kiro Hook）
- **代碼範本生成器**：`./new-ea.sh "MyNewEA"`
- **代碼格式化工具**：自動對齊變數宣告

### 測試自動化

- **批次回測**：`./backtest.sh "Grids 1.12" --symbols "EURUSD,GBPUSD"`
- **參數優化管理**：`./optimize.sh "Grids 1.12" --param "Gap" --range "100-500"`
- **回測結果比較**：`./compare.sh "v1.11" "v1.12"`

### 版本管理自動化

- **版本號自動遞增**：`./release.sh "Grids" "patch"`
- **變更日誌生成**
- **發布打包**：`./package.sh "Grids 1.12"`

### 文件自動化

- **API 文件生成**：從代碼註解自動生成
- **參數說明生成**：從 `input` 變數自動生成
- **回測報告範本**

### 監控自動化

- **實盤日誌監控**：`./monitor.sh "Grids 1.12"`
- **績效追蹤**：定期擷取帳戶狀態
- **異常通知**：關鍵事件發送通知

---

## 狀態

### 開發閉環
- [x] compile.sh - 已完成
- [ ] test.sh - 待建立
- [ ] logs.sh - 待建立
- [ ] dev.sh - 待建立
- [ ] INI 範本 - 待建立

### 測試系統
- [ ] 測試案例範本 - 待建立
- [ ] 測試參數檔結構 - 待建立
- [ ] 批次測試腳本 - 待建立

### 其他自動化
- [ ] 代碼範本生成器 - 待建立
- [ ] 版本管理腳本 - 待建立
- [ ] 監控系統 - 待建立

---

## 更新記錄

- 2025-12-19：建立文件，規劃閉環系統架構
- 2025-12-19：加入測試策略和其他自動化流程建議
