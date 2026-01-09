# Grids 2.0 設計文件

## 文件資訊

- 版本：1.21
- 建立日期：2026-01-01
- 最後更新：2026-01-01

---

## 1. 系統架構

### 1.1 架構概覽

```
Grids 1.20.mq4 (EA 主檔案)
    │
    ├── CEACore (EA 中樞框架)
    │   ├── CTradeCore        - 交易核心
    │   ├── CHedgeClose       - 對沖平倉
    │   ├── CProfitTrailingStop - 獲利追蹤停利
    │   ├── CTradeArrowManager  - 交易箭頭
    │   ├── CRecoveryProfit   - 獲利通訊
    │   ├── CChartPanelCanvas - UI 面板
    │   └── CTimerManager     - 計時器管理
    │
    └── CGridsCore (網格交易核心)
        ├── 網格交易邏輯
        ├── 信號計算（SuperTrend/BullsBears）
        └── 訂單管理
```

### 1.2 模組職責分離

| 模組 | 職責 |
|------|------|
| Grids 1.20.mq4 | EA 入口、參數定義、回調連接 |
| CEACore | 統一管理輔助模組、風控、UI、計時器 |
| CGridsCore | 網格交易核心邏輯、信號計算 |

### 1.3 回調機制

```
CGridsCore 止盈觸發
    │
    ├── OnRequestHedgeClose() ← 請求 CEACore 執行對沖平倉
    │       │
    │       └── g_eaCore.HedgeCloseAll()
    │
    └── OnGridClose(profit, time, price) ← 通知平倉完成
            │
            ├── g_eaCore.AddProfit(profit)
            └── g_gridsCore.SetTradedThisSignal(true)
```

---

## 2. 資料模型

### 2.1 外部參數結構

#### 組別設定
```mql4
input string   PG_GroupID       = "A";      // 組別 ID
input int      PG_MagicNumber   = 16888;    // MagicNumber
```

#### 趨勢過濾設定
```mql4
input ENUM_FILTER_MODE TF_FilterMode = FILTER_SUPERTREND;
input int      TF_Timeframe     = 0;        // 分析時間框架
```

#### BullsBears 設定
```mql4
input int      BB_LookbackBars  = 4;        // 回看 K 線數量
input double   BB_Threshold     = 5.0;      // 力量差異閾值
```

#### SuperTrend 設定
```mql4
input int      ST_ATR_Period    = 10;       // ATR 週期
input double   ST_Multiplier    = 1.2;      // ATR 乘數
input ENUM_SIGNAL_MODE ST_SignalMode = SIGNAL_MODE_TREND;
input ENUM_AVERAGING_MODE ST_AveragingMode = AVERAGING_ANY;
input ENUM_BOOL ST_ShowLine     = YES;      // 顯示趨勢線
```

#### 網格設定
```mql4
input ENUM_GRID_MODE PG_GridMode = GRID_MODE_COUNTER;
input double   PG_GridStep      = 200.0;    // 網格間距 (點)
input double   PG_InitialLots   = 0.01;     // 起始手數
input int      PG_MaxGridLevels = 99;       // 最大網格層數
input double   PG_TakeProfit    = 10.0;     // 止盈金額
```

#### 獨立縮放設定
```mql4
input double   PG_CounterGridScaling = 0.0; // 逆向間距縮放% (0=不縮放)
input double   PG_CounterLotScaling  = 0.0; // 逆向手數縮放% (0=不縮放)
input double   PG_TrendGridScaling   = 0.0; // 順向間距縮放% (0=不縮放)
input double   PG_TrendLotScaling    = 0.0; // 順向手數縮放% (0=不縮放)
```

#### 訂單保護設定
```mql4
input ENUM_BOOL OP_OneOrderPerBar = YES;    // 每根K線只開一單
input int      OP_Slippage      = 30;       // 滑點容許值
input int      OP_MaxOrdersInWork = 100;    // 最大訂單數量
```

#### 風險控制
```mql4
input double   PG_MaxDrawdown   = 20.0;     // 最大回撤 (%)
input double   PG_MaxLots       = 1.0;      // 最大總手數
input double   PG_MaxSpread     = 250.0;    // 最大點差
```

#### 獲利回跌停利設定
```mql4
input ENUM_BOOL PT_EnableTrailing = YES;    // 啟用獲利回跌停利
input double   PT_ProfitThreshold = 10.0;   // 獲利閾值
input double   PT_DrawdownPercent = 75.0;   // 保留利潤百分比
```

### 2.2 配置結構體

#### GridsCoreConfig
```mql4
struct GridsCoreConfig
{
   // 基本設定
   int               magicNumber;
   string            symbol;
   int               slippage;
   
   // 網格參數
   ENUM_GRID_MODE    gridMode;
   double            gridStep;
   double            initialLots;
   int               maxGridLevels;
   double            takeProfit;
   bool              oneOrderPerBar;
   
   // 獨立縮放參數
   double            counterGridScaling;  // 逆向間距縮放%
   double            counterLotScaling;   // 逆向手數縮放%
   double            trendGridScaling;    // 順向間距縮放%
   double            trendLotScaling;     // 順向手數縮放%
   
   // 交易限制
   ENUM_TRADE_DIRECTION tradeDirection;
   int               maxOrdersInWork;
   double            maxSpread;
   double            maxLots;
   
   // 信號過濾設定
   ENUM_FILTER_MODE  filterMode;
   int               filterTimeframe;
   
   // BullsBears 參數
   int               bbLookbackBars;
   double            bbThreshold;
   
   // SuperTrend 參數
   int               stAtrPeriod;
   double            stMultiplier;
   ENUM_SIGNAL_MODE  stSignalMode;
   ENUM_AVERAGING_MODE stAveragingMode;
   bool              stShowLine;
   color             stBullColor;
   color             stBearColor;
   
   // 日誌設定
   bool              showDebugLogs;
};
```

### 2.3 枚舉定義

```mql4
enum ENUM_GRID_MODE
{
   GRID_MODE_TREND   = 0,    // 順向網格
   GRID_MODE_COUNTER = 1     // 逆向網格
};

enum ENUM_TRADE_DIRECTION
{
   TRADE_BOTH      = 0,      // 雙向交易
   TRADE_BUY_ONLY  = 1,      // 只買
   TRADE_SELL_ONLY = 2       // 只賣
};

enum ENUM_FILTER_MODE
{
   FILTER_BULLSBEARS = 0,    // BullsBears Candles
   FILTER_SUPERTREND = 1,    // Super Trend
   FILTER_SIMPLE     = 2     // Simple Grids
};

enum ENUM_SIGNAL_MODE
{
   SIGNAL_MODE_TREND    = 0, // 趨勢方向內持續開單
   SIGNAL_MODE_REVERSAL = 1, // 只在趨勢反轉時開單
   SIGNAL_MODE_DISABLED = 2  // 不使用趨勢過濾
};

enum ENUM_AVERAGING_MODE
{
   AVERAGING_ANY      = 0,   // 任意方向加倉
   AVERAGING_TREND    = 1,   // 僅順勢時加倉
   AVERAGING_DISABLED = 2    // 不使用趨勢過濾
};
```

---

## 3. 核心演算法

### 3.1 網格交易邏輯

#### 首單開倉條件
```
1. 籃子層級 == 0
2. 信號方向符合（BUY/SELL）
3. AllowFirstOrder() == true
4. 交易方向允許
5. 一根 K 線一單限制通過
```

#### 加倉條件
```
1. 籃子層級 > 0 且 < 最大層級
2. AllowAveraging() == true
3. 價格達到觸發點

逆向網格（COUNTER）：
  - 買入加倉：currentPrice <= basePrice - cumulativeDistance
  - 賣出加倉：currentPrice >= basePrice + cumulativeDistance

順向網格（TREND）：
  - 買入加倉：currentPrice >= basePrice + cumulativeDistance
  - 賣出加倉：currentPrice <= basePrice - cumulativeDistance
```

#### 累積間距計算（獨立縮放）
```mql4
double CalculateCumulativeDistance(int level)
{
   if(level <= 0) return 0.0;
   
   double baseStep = gridStep * Point;
   
   // 根據網格模式選擇對應的縮放參數
   double scalingPercent = 0.0;
   if(gridMode == GRID_MODE_COUNTER)
      scalingPercent = counterGridScaling;
   else
      scalingPercent = trendGridScaling;
   
   // 縮放值為 0 則不縮放（固定間距模式）
   if(scalingPercent == 0.0)
      return baseStep * level;
   
   // 遞增間距模式
   double total = 0.0;
   for(int i = 0; i < level; i++)
   {
      double scalingFactor = 1.0 + (i * scalingPercent / 100.0);
      total += baseStep * scalingFactor;
   }
   
   return total;
}
```

#### 手數計算（獨立縮放）
```mql4
double CalculateScaledLots(int level)
{
   if(level <= 1) return initialLots;
   
   // 根據網格模式選擇對應的縮放參數
   double scalingPercent = 0.0;
   if(gridMode == GRID_MODE_COUNTER)
      scalingPercent = counterLotScaling;
   else
      scalingPercent = trendLotScaling;
   
   // 縮放值為 0 則不縮放
   if(scalingPercent == 0.0)
      return initialLots;
   
   // 計算縮放後的手數
   double scalingFactor = 1.0 + ((level - 1) * scalingPercent / 100.0);
   double lots = initialLots * scalingFactor;
   
   // 最大手數限制
   if(maxLots > 0 && lots > maxLots)
      lots = maxLots;
   
   // 市場限制驗證
   lots = ValidateLotSize(lots);
   
   return lots;
}
```

### 3.2 SuperTrend 信號計算

```mql4
int CalculateSuperTrend()
{
   double atr = iATR(symbol, timeframe, atrPeriod, 1);
   double hl2 = (High[1] + Low[1]) / 2.0;
   double upperLevel = hl2 + multiplier * atr;
   double lowerLevel = hl2 - multiplier * atr;
   
   // 趨勢判斷
   if(Close[1] > prevSuperTrendValue && Close[2] <= prevSuperTrendValue)
   {
      superTrendValue = lowerLevel;
      direction = 1;  // 看漲
   }
   else if(Close[1] < prevSuperTrendValue && Close[2] >= prevSuperTrendValue)
   {
      superTrendValue = upperLevel;
      direction = -1; // 看跌
   }
   
   // 趨勢反轉檢測
   trendReversed = (direction != prevDirection && prevDirection != 0);
   
   return direction;
}
```

### 3.3 BullsBears 信號計算

```mql4
int CalculateBullsBears()
{
   double bullsPower = 0.0;
   double bearsPower = 0.0;
   
   for(int i = 1; i <= lookbackBars; i++)
   {
      if(Close[i] > Open[i])  // 陽線
      {
         bullsPower += (High[i] - Open[i]);
         bearsPower += (Open[i] - Low[i]);
      }
      else  // 陰線
      {
         bullsPower += (Close[i] - Low[i]);
         bearsPower += (High[i] - Close[i]);
      }
   }
   
   double thresholdMultiplier = 1.0 + threshold / 100.0;
   
   if(bullsPower > bearsPower * thresholdMultiplier)
      return SIGNAL_BUY;
   else if(bearsPower > bullsPower * thresholdMultiplier)
      return SIGNAL_SELL;
   
   return SIGNAL_NEUTRAL;
}
```

### 3.4 獲利回跌停利邏輯

```
1. 浮動獲利 >= 獲利閾值 → 啟動追蹤
2. 記錄獲利峰值
3. 當前獲利 <= 峰值 * 保留百分比 → 觸發平倉
```

---

## 4. 流程設計

### 4.1 初始化流程

```
OnInit()
    │
    ├── 設定 CEACore 參數
    │   ├── SetMagic, SetSymbol, SetGroupId
    │   ├── SetMaxDrawdown, SetMaxLots, SetMaxSpread
    │   ├── EnableHedgeClose, EnableProfitTrailing
    │   ├── EnableArrows, EnableRecoveryProfit
    │   └── EnableChartPanel, EnableTimer
    │
    ├── g_eaCore.OnInitCore()
    │   ├── 初始化市場資訊緩存
    │   ├── 初始化 CTradeCore
    │   ├── 初始化 CHedgeClose
    │   ├── 初始化 CProfitTrailingStop
    │   ├── 初始化 CTradeArrowManager
    │   ├── 初始化 CRecoveryProfit
    │   ├── 初始化 CChartPanelCanvas
    │   └── 初始化 CTimerManager
    │
    ├── 建立 GridsCoreConfig
    │   ├── 設定基本參數
    │   └── 設定獨立縮放參數
    │
    ├── g_gridsCore.Init(config)
    │
    └── 設定回調函數
        ├── SetOnRequestCloseCallback
        └── SetOnCloseCallback
```

### 4.2 主循環流程

```
OnTick()
    │
    ├── g_eaCore.OnTickCore()
    │   ├── 更新點差緩存
    │   ├── 更新訂單緩存
    │   ├── 風險控制檢查
    │   ├── 獲利追蹤檢查
    │   └── RecoveryProfit.OnTick()
    │
    ├── 檢查 IsRunning()
    │
    └── g_gridsCore.Execute()
        ├── 更新手數統計
        ├── 取得趨勢信號
        ├── 買入籃子邏輯
        │   ├── 首單檢查
        │   └── 加倉檢查（使用獨立縮放）
        ├── 賣出籃子邏輯
        │   ├── 首單檢查
        │   └── 加倉檢查（使用獨立縮放）
        └── 止盈檢查
            └── 觸發平倉回調
```

### 4.3 平倉流程

```
CheckTakeProfitClose()
    │
    ├── 計算網格浮動盈虧
    │
    ├── profit >= takeProfit?
    │   │
    │   └── YES
    │       │
    │       ├── 呼叫 OnRequestHedgeClose()
    │       │   └── g_eaCore.HedgeCloseAll()
    │       │
    │       ├── ResetBaskets()
    │       │
    │       └── 呼叫 OnGridClose(profit, time, price)
    │           ├── g_eaCore.AddProfit(profit)
    │           └── SetTradedThisSignal(true)
```

---

## 5. 模組介面

### 5.1 CGridsCore 公開方法

| 方法 | 說明 |
|------|------|
| `Init(config)` | 初始化網格核心 |
| `Deinit()` | 反初始化 |
| `Execute()` | 主要執行方法 |
| `SetOnCloseCallback(func)` | 設定平倉完成回調 |
| `SetOnRequestCloseCallback(func)` | 設定請求平倉回調 |
| `CloseAllPositions()` | 平倉所有持倉 |
| `ResetBaskets()` | 重置籃子狀態 |
| `SetTradedThisSignal(traded)` | 設定本信號已交易 |
| `GetBuyGridLevel()` | 取得買入層級 |
| `GetSellGridLevel()` | 取得賣出層級 |
| `GetFloatingProfit()` | 取得浮動盈虧 |
| `GetSignalName()` | 取得信號模式名稱 |
| `GetDirectionName()` | 取得方向名稱 |

### 5.2 CEACore 公開方法

| 方法 | 說明 |
|------|------|
| `OnInitCore()` | 初始化 |
| `OnTickCore()` | 主循環 |
| `OnDeinitCore(reason)` | 反初始化 |
| `OnTimerCore()` | 計時器事件 |
| `HedgeCloseAll()` | 對沖平倉所有訂單 |
| `AddProfit(profit)` | 新增獲利 |
| `IsRunning()` | 是否運行中 |
| `CheckRiskControl()` | 風險控制檢查 |

---

## 6. 變更紀錄

| 日期 | 版本 | 變更說明 |
|------|------|----------|
| 2026-01-01 | 1.20 | 根據 Grids 1.20.mq4 重建設計文件 |
| 2026-01-01 | 1.21 | 移除 stepMultiplier、lotMultiplier，新增獨立縮放參數設計 |
