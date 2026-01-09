# CChartPanel 圖表面板管理模組

## 模組概述

CChartPanel 是一個通用的圖表面板管理類別，用於在 MT4 圖表上顯示資訊面板。支援動態新增、更新、刪除行，以及盈虧標記顯示功能。

## 主要特性

- **動態行管理**：可隨時新增、修改、刪除面板行
- **更新頻率控制**：內建更新間隔機制，避免過度重繪
- **顏色管理**：每行可獨立設定顏色，內建統一顏色定義
- **可見性控制**：可隱藏/顯示特定行
- **盈虧標記**：在圖表上顯示平倉盈虧標記
- **交易資訊顯示**：自動收集並顯示多空持倉統計
- **盈虧紀錄追蹤**：追蹤最高獲利、最大虧損、目前盈虧

## 顏色定義（v1.23）

```mql4
#define CLR_PROFIT      clrOrangeRed     // 🟠 橘紅色 - 獲利狀態
#define CLR_LOSS        clrLawnGreen     // 🟢 草綠色 - 虧損狀態
#define CLR_NEUTRAL     clrGray          // ⚪ 灰色 - 中性狀態
#define CLR_ACTIVE      clrGold          // 🟡 金色 - 活躍狀態
#define CLR_DANGER      clrRed           // 🔴 紅色 - 危險狀態
#define CLR_CHART_PL    clrYellow        // 🟡 黃色 - 圖表盈虧標記
```

## 盈虧紀錄說明（v1.23 修正）

- **Max_Profit（最高獲利）**：有史以來單次平倉最高獲利金額，**不隨平倉重置**
- **Max_Loss（最大虧損）**：有史以來交易中最大浮動虧損金額，**不隨平倉重置**
- **Current_Profit（目前盈虧）**：目前本次交易的浮動盈虧狀況，平倉後重置為 0

### 重置方法

```mql4
// 只重置目前盈虧（平倉後呼叫，保留歷史紀錄）
g_panel.ResetProfitRecord();

// 重置所有紀錄（包含歷史最高/最低，慎用）
g_panel.ResetAllProfitRecord();
```

## 使用方法

```mql4
#include "../Libs/UI/CChartPanel.mqh"

CChartPanel g_panel;

int OnInit()
{
   g_panel.Init("MyEA_", 10, 30, 1);
   g_panel.SetSystemInfo("COUNTER", Symbol());
   return INIT_SUCCEEDED;
}

void OnTick()
{
   g_panel.SetTradeInfo(MagicNumber);
   g_panel.Update();
}

void OnDeinit(const int reason)
{
   g_panel.Deinit();
}
```

## 版本資訊

- 版本：1.23
- 更新日期：2025-12-29

### 更新紀錄

**v1.23 (2025-12-29)**
- 修正 `ResetProfitRecord()` 只重置 `m_currentProfit`，保留歷史最高獲利和最大虧損
- 新增 `ResetAllProfitRecord()` 用於完全重置所有紀錄（慎用）
- 新增 `CLR_CHART_PL` 顏色定義用於 `PrintPL()` 圖表標記

**v1.22 (2025-12-29)**
- 新增 `CLR_CHART_PL` 顏色定義
- `PrintPL()` 改用 `CLR_CHART_PL` 顏色

**v1.21 (2025-12-29)**
- 新增 `#define` 顏色常數定義
- 新增 `GetProfitColor()` 輔助方法

**v1.20 (2025-12-29)**
- 新增盈虧紀錄追蹤功能
