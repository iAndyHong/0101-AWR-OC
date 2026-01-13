# CGridsCore 網格交易核心模組

## 模組定位

將「網格交易邏輯」與「多空信號邏輯」分離，讓不同的信號算法可以共用同一套網格核心。

## 架構設計

```
EA 檔案 (如 Grids_SuperTrend.mq4)
    │
    ├── 實作信號函數（GetSignal, IsAllowFirstOrder 等）
    │
    └── 呼叫 CGridsCore
            │
            ├── 網格交易執行
            ├── 風險控制
            ├── 訂單管理
            ├── GV 通訊（CRecoveryProfit）
            ├── 對沖平倉（CHedgeClose）
            ├── 獲利回跌停利（CProfitTrailingStop）
            └── 箭頭管理（CTradeArrowManager）
```

## 使用方式

### 1. 引入模組

```mql4
#include "../Libs/GridsCore/CGridsCore.mqh"
```

### 2. 宣告實例與信號函數

```mql4
CGridsCore g_core;

// 實作信號函數
int MyGetSignal()
{
   // 你的多空邏輯
   return SIGNAL_BUY;  // 或 SIGNAL_SELL, SIGNAL_NEUTRAL
}

bool MyAllowFirstOrder()
{
   return true;  // 是否允許首單
}

bool MyAllowAveraging(int basketDirection)
{
   return true;  // 是否允許加倉
}

int MyGetTradeDirection()
{
   // 根據信號返回交易方向
   // 1 = 買, -1 = 賣, 0 = 無
   return 1;
}

string MyGetSignalName()
{
   return "My Signal";  // 顯示在面板上
}

string MyGetDirectionName()
{
   int signal = MyGetSignal();
   if(signal == SIGNAL_BUY) return "看漲";
   if(signal == SIGNAL_SELL) return "看跌";
   return "中性";
}
```

### 3. OnInit 初始化

```mql4
int OnInit()
{
   // 設定配置
   GridsCoreConfig config;
   config.groupID = "A";
   config.crossSymbol = false;
   config.gridStep = 500.0;
   config.initialLots = 0.01;
   config.lotMultiplier = 1.1;
   config.maxGridLevels = 99;
   config.takeProfit = 10.0;
   config.oneOrderPerBar = true;
   config.slippage = 30;
   config.maxOrdersInWork = 100;
   config.tradeDirection = TRADE_BOTH;
   config.maxDrawdown = 20.0;
   config.maxLots = 1.0;
   config.maxSpread = 250.0;
   config.magicNumber = 16888;
   config.gvPrefix = "REC_";
   config.updateInterval = 1;
   config.standaloneMode = true;
   config.standaloneTP = 10.0;
   config.showDebugLogs = false;
   config.enableArrows = true;
   config.arrowDays = 5;
   config.arrowInterval = 10;
   config.arrowBuyOpen = clrOrangeRed;
   config.arrowSellOpen = clrLawnGreen;
   config.arrowBuyHistory = clrDarkRed;
   config.arrowSellHistory = clrDarkGreen;
   config.enableTrailing = true;
   config.profitThreshold = 10.0;
   config.drawdownPercent = 75.0;
   
   // 初始化核心
   if(!g_core.Init(config))
      return INIT_FAILED;
   
   // 設定信號回調
   g_core.SetSignalCallback(MyGetSignal);
   g_core.SetAllowFirstOrderCallback(MyAllowFirstOrder);
   g_core.SetAllowAveragingCallback(MyAllowAveraging);
   g_core.SetTradeDirectionCallback(MyGetTradeDirection);
   g_core.SetSignalNameCallback(MyGetSignalName);
   g_core.SetDirectionNameCallback(MyGetDirectionName);
   
   return INIT_SUCCEEDED;
}
```

### 4. OnTick / OnDeinit

```mql4
void OnTick()
{
   g_core.OnTick();
}

void OnDeinit(const int reason)
{
   g_core.Deinit();
}

void OnTimer()
{
   g_core.OnTimer();
}
```

## 信號回調函數說明

| 回調函數 | 用途 | 返回值 |
|---------|------|--------|
| `GetSignal` | 取得當前趨勢信號 | SIGNAL_BUY / SIGNAL_SELL / SIGNAL_NEUTRAL |
| `AllowFirstOrder` | 是否允許開首單 | true / false |
| `AllowAveraging` | 是否允許加倉 | true / false |
| `GetTradeDirection` | 取得交易方向 | 1=買, -1=賣, 0=無 |
| `GetSignalName` | 取得信號模式名稱 | 字串（顯示用） |
| `GetDirectionName` | 取得方向名稱 | "看漲" / "看跌" / "中性" |

## 版本資訊

- 建立日期：2025-12-22
- 版本：1.0
