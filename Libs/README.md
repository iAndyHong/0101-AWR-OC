# Andy 個人 MQL4 代碼庫

這是 Andy 的共用 MQL4 模組庫，供各專案重複使用。

---

## 如何請 Kiro 套用模組

### 方式一：直接指定模組名稱

```
請在 [EA名稱] 中加入 CHedgeClose 模組，用於 [平倉情境]
```

範例：
- 「請在 Grids 1.12 中加入 CHedgeClose 模組，用於整體止盈平倉」
- 「幫我把 CHedgeClose 整合到 Recovery EA，當籃子獲利達標時使用」

### 方式二：描述需求，讓 Kiro 自動選擇

```
我需要 [功能描述]
```

範例：
- 「我需要對沖平倉功能」→ Kiro 會自動使用 CHedgeClose
- 「我需要快速平掉所有持倉」→ Kiro 會自動使用 CHedgeClose

### 方式三：詢問可用模組

```
Libs 裡有什麼模組可以用？
```

Kiro 會列出所有可用模組及其用途。

---

## 可用模組

### GridsCore/ - 網格交易核心模組 (NEW)

**位置**：`Libs/GridsCore/`

**檔案**：
- `CGridsCore.mqh` - 主要代碼
- `Logic.md` - 邏輯說明文件

**功能**：網格交易的核心邏輯，包含訂單管理、風險控制、平倉邏輯。不包含多空信號判斷，由外部提供信號。

**設計理念**：
- 將「網格交易邏輯」與「多空信號邏輯」分離
- 外部 EA 只需實作信號函數（GetSignal 等）
- 核心模組負責所有交易執行、風控、平倉

**標準用法**：
```mql4
#include "../Libs/GridsCore/CGridsCore.mqh"

CGridsCore g_core;

// 實作信號函數
int MyGetSignal() { return SIGNAL_BUY; }
bool MyAllowFirstOrder() { return true; }
bool MyAllowAveraging(int dir) { return true; }
int MyGetTradeDirection() { return 1; }
string MyGetSignalName() { return "My Signal"; }
string MyGetDirectionName() { return "看漲"; }

int OnInit()
{
   GridsCoreConfig config;
   config.groupID = "A";
   config.gridStep = 500.0;
   // ... 其他配置
   
   g_core.Init(config);
   g_core.SetSignalCallback(MyGetSignal);
   g_core.SetAllowFirstOrderCallback(MyAllowFirstOrder);
   g_core.SetAllowAveragingCallback(MyAllowAveraging);
   g_core.SetTradeDirectionCallback(MyGetTradeDirection);
   g_core.SetSignalNameCallback(MyGetSignalName);
   g_core.SetDirectionNameCallback(MyGetDirectionName);
   return INIT_SUCCEEDED;
}

void OnTick() { g_core.OnTick(); }
void OnDeinit(const int reason) { g_core.Deinit(); }
```

**詳細說明**：參見 `Libs/GridsCore/Logic.md`

---

### HedgeClose/ - 對沖平倉模組

**位置**：`Libs/HedgeClose/`

**檔案**：
- `CHedgeClose.mqh` - 主要代碼
- `Logic.md` - 邏輯說明文件

**功能**：先下對沖單鎖住持倉，再用 OrderCloseBy 互相平倉

**優點**：
- 減少點差損失
- 雙重保險（失敗時自動改用一般平倉）

**快速用法**：
```mql4
#include "../Libs/HedgeClose/CHedgeClose.mqh"

// 一行完成平倉
CHedgeClose::CloseAll(MagicNumber);
```

**標準用法**：
```mql4
#include "../Libs/HedgeClose/CHedgeClose.mqh"

CHedgeClose g_hedgeClose;

// OnInit
g_hedgeClose.Init(MagicNumber, 30, Symbol());

// 需要平倉時
g_hedgeClose.Execute();

// OnDeinit
g_hedgeClose.Deinit();
```

**詳細說明**：參見 `Libs/HedgeClose/Logic.md`

---

### ProfitTrailingStop/ - 獲利回跌停利模組

**位置**：`Libs/ProfitTrailingStop/`

**檔案**：
- `CProfitTrailingStop.mqh` - 主要代碼
- `Logic.md` - 邏輯說明文件

**功能**：當浮動獲利達到閾值後啟動追蹤，獲利回跌到指定百分比時觸發平倉

**定位**：這是「平倉條件」，決定「何時平倉」。可搭配 CHedgeClose 作為「平倉方法」

**標準用法**：
```mql4
#include "../Libs/ProfitTrailingStop/CProfitTrailingStop.mqh"

CProfitTrailingStop g_profitTrailing;

// OnInit - 參數：閾值, 保留%, Magic, 商品
g_profitTrailing.Init(100.0, 75.0, MagicNumber, Symbol());

// OnTick - 自動平倉模式
if(g_profitTrailing.Check())
   Print("已觸發平倉");

// OnTick - 搭配對沖平倉模式
if(g_profitTrailing.ShouldClose())
  {
   g_hedgeClose.Execute();
   g_profitTrailing.Reset();
  }

// OnDeinit
g_profitTrailing.Deinit();
```

**詳細說明**：參見 `Libs/ProfitTrailingStop/Logic.md`

---

### TradeArrowManager/ - 交易箭頭管理模組

**位置**：`Libs/TradeArrowManager/`

**檔案**：
- `CTradeArrowManager.mqh` - 主要代碼
- `Logic.md` - 邏輯說明文件

**功能**：在圖表上繪製開倉與歷史交易的箭頭標記，將 MT4 原生箭頭替換為圓圈樣式

**標準用法**：
```mql4
#include "../Libs/TradeArrowManager/CTradeArrowManager.mqh"

CTradeArrowManager arrowManager;

// OnInit
arrowManager.InitFull(Symbol(), "MyEA_", true, 5, MagicNumber, 10,
                      clrOrangeRed, clrLawnGreen, clrDarkRed, clrDarkGreen);

// OnTick
arrowManager.ArrowOnTick();

// OnDeinit
arrowManager.ArrowOnDeinit();
```

**詳細說明**：參見 `Libs/TradeArrowManager/Logic.md`

---

### RecoveryProfit/ - Recovery 獲利通訊模組

**位置**：`Libs/RecoveryProfit/`

**檔案**：
- `CRecoveryProfit.mqh` - 主要代碼
- `Logic.md` - 邏輯說明文件

**功能**：與 Recovery EA 進行 GV 通訊，累積獲利並提供給 Recovery 消費

**定位**：這是「通訊協調」模組，負責 Grids EA 與 Recovery EA 之間的狀態同步

**狀態機**：
```
IDLE → ACCUMULATING → READY → ACKNOWLEDGED → IDLE
```

**標準用法**：
```mql4
#include "../Libs/RecoveryProfit/CRecoveryProfit.mqh"

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

**詳細說明**：參見 `Libs/RecoveryProfit/Logic.md`

---

## 整合範例

假設你有一個 EA 需要在獲利達標時平倉：

**對 Kiro 說**：
```
請在我的 EA 中整合 CHedgeClose，當 totalProfit >= 50 時執行對沖平倉
```

**Kiro 會自動**：
1. 加入 `#include "../Libs/HedgeClose/CHedgeClose.mqh"`
2. 宣告 `CHedgeClose g_hedgeClose;`
3. 在 OnInit 中初始化
4. 在適當位置加入平倉判斷邏輯
5. 在 OnDeinit 中清理

---

## 新增模組

當你有新的共用模組要加入：

1. 在 `Libs/` 下建立模組資料夾（如 `Libs/ModuleName/`）
2. 放入 .mqh 檔案和相關文件（Logic.md、範例等）
3. 告訴 Kiro：「請更新 Libs 的 README 和 steering，加入 [模組名稱] 的說明」

---

### UI/ - 圖表面板管理模組 (NEW)

**位置**：`Libs/UI/`

**檔案**：
- `CChartPanel.mqh` - 主要代碼
- `Logic.md` - 邏輯說明文件

**功能**：管理圖表上的資訊面板顯示，包含標籤建立、更新、刪除以及盈虧標記顯示功能

**特性**：
- 動態行管理（新增、修改、刪除）
- 更新頻率控制（避免過度重繪）
- 每行獨立顏色設定
- 可見性控制
- 盈虧標記顯示

**標準用法**：
```mql4
#include "../Libs/UI/CChartPanel.mqh"

CChartPanel g_panel;

// OnInit
g_panel.Init("MyEA_", 10, 30, 5);  // 前綴, X, Y, 更新間隔
g_panel.AddLine("Title", "=== 我的 EA ===", clrWhite);
g_panel.AddLine("Status", "狀態: 運行中", clrLime);

// OnTick
g_panel.SetLine("Profit", "盈虧: " + DoubleToString(profit, 2), profitColor);
g_panel.Update();

// 平倉時顯示盈虧標記
g_panel.PrintPL(profit, TimeCurrent(), Bid);

// OnDeinit
g_panel.Deinit();      // 保留面板
// g_panel.Cleanup();  // 清理面板
```

**詳細說明**：參見 `Libs/UI/Logic.md`

---

## 資料夾結構

```
Libs/
├── README.md               ← 本文件（使用說明）
├── GridsCore/              ← 網格交易核心模組
│   ├── CGridsCore.mqh      ← 主要代碼
│   └── Logic.md            ← 邏輯說明
├── HedgeClose/             ← 對沖平倉模組
│   ├── CHedgeClose.mqh     ← 主要代碼
│   └── Logic.md            ← 邏輯說明
├── ProfitTrailingStop/     ← 獲利回跌停利模組
│   ├── CProfitTrailingStop.mqh
│   └── Logic.md
├── TradeArrowManager/      ← 交易箭頭管理模組
│   ├── CTradeArrowManager.mqh
│   └── Logic.md
├── RecoveryProfit/         ← Recovery 獲利通訊模組
│   ├── CRecoveryProfit.mqh
│   └── Logic.md
├── UI/                     ← 圖表面板管理模組 (NEW)
│   ├── CChartPanel.mqh
│   └── Logic.md
└── [未來新增模組]/
    ├── CModuleName.mqh
    └── Logic.md
```

對應的 steering 文件：`.kiro/steering/05-mylibs-guide.md`
