//+------------------------------------------------------------------+
//|                                              HA_Adaptive_EA.mq4 |
//|                                                             Andy |
//|                     基於 Heiken Ashi 的趨勢追蹤與全局獲利回跌系統 |
//+------------------------------------------------------------------+
#property copyright "Andy"
#property link      ""
#property version   "1.52"

// 引入移動平均枚舉以同步指標
enum enMaTypes
  {
   ma_sma,    // SMA
   ma_ema,    // EMA
   ma_smma,   // SMMA
   ma_lwma,   // LWMA
   ma_tema,   // TEMA
   ma_hma     // HMA
  };

#include "Libs/UI/CChartPanelCanvas_v2.4.mqh"

//+------------------------------------------------------------------+
//| 枚舉定義                                                          |
//+------------------------------------------------------------------+
enum ENUM_MARTINGALE_TYPE
  {
   MODE_MARTINGALE    = 0, // 馬丁 (虧損加倉)
   MODE_ANTI_MARTY    = 1  // 反馬丁 (獲利加倉)
  };

enum ENUM_TRADE_DIRECTION
  {
   DIR_TREND    = 0,     // 順勢模式 (陽買陰賣)
   DIR_REVERSAL = 1      // 逆勢模式 (陽賣陰買)
  };

//+------------------------------------------------------------------+
//| 輸入參數                                                          |
//+------------------------------------------------------------------+
sinput string  Section_1                  = "----------------";   // [趨勢過濾]
input  ENUM_TIMEFRAMES HA_TimeFrame       = PERIOD_CURRENT;       // Heiken Ashi 運算週期
input  enMaTypes       HA_MaMethod1       = ma_ema;               // HA 平滑方法 1
input  int             HA_MaPeriod1       = 6;                    // HA 平滑週期 1
input  enMaTypes       HA_MaMethod2       = ma_lwma;              // HA 平滑方法 2
input  int             HA_MaPeriod2       = 2;                    // HA 平滑週期 2
input  ENUM_TRADE_DIRECTION Trade_Mode    = DIR_TREND;            // 趨勢過濾模式 (順勢/逆勢)
input  int ADX_Period = 14;              // ADX 計算週期
input  int ADX_Level_Low = 20;           // ADX 震盪閾值
input  int ADX_Level_High = 25;          // ADX 趨勢閾值
input  int ADX_Mode = 1;                 // ADX 模式 (0: 禁用, 1: 防震盪/過濾, 2: 自適應)
input  bool UseDI = true;                // 使用 +DI/-DI
input  bool UseDIForDirection = true;     // DI 覆蓋方向
input  int ADX_Switch_Delay = 2;          // 緩衝期（bar）

// ADX state machine (skeleton for 1.53 integration)
int g_adxCurrentModeTrade  = -1; // -1: 未設定, 0: 順勢, 1: 逆勢
int g_adxCurrentModeMartin = -1; // -1: 未設定, 0: 馬丁, 1: 反馬丁
int g_adxTargetTrade        = -1;
int g_adxTargetMartin       = -1;
int g_adxSwitchCounter      = 0;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CalcADXIndicators()
  {
// 佔位符：日後接入真實 ADX、+DI、-DI 計算
   double adx = 0.0;
   double diPlus = 0.0;
   double diMinus = 0.0;

// 方向性覆蓋示例（位於未實作的占位，例如日後可根據 DI 方向更新）
   if(adx > ADX_Level_High)
     {
      g_adxCurrentModeTrade = DIR_TREND;
      g_adxCurrentModeMartin = MODE_ANTI_MARTY;
     }
   else
      if(adx < ADX_Level_Low)
        {
         g_adxCurrentModeTrade = DIR_REVERSAL;
         g_adxCurrentModeMartin = MODE_MARTINGALE;
        }
   g_adxSwitchCounter = 0;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. ADX 狀態更新與 UI 顯示
   CalcADXIndicators();
   int _adxTrade=0;
   int _adxMartin=0;
   GetADXState(_adxTrade, _adxMartin);
   string dirStr = (_adxTrade == DIR_TREND) ? "順勢" : "逆勢";
   string martStr = (_adxMartin == MODE_ANTI_MARTY) ? "反馬丁" : "馬丁";
   if(UI_Panel_Enabled && g_panel.IsInitialized())
   {
      g_panel.SetSystemInfo(dirStr, martStr);
   }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void UpdateADXState()
  {
// 目前僅作為占位：不直接改變 Trade_Mode / Martin_Type，僅更新目標狀態
   g_adxTargetTrade = g_adxCurrentModeTrade;
   g_adxTargetMartin = g_adxCurrentModeMartin;
  }


sinput string  Section_2                  = "----------------";   // [網格馬丁]
input  ENUM_MARTINGALE_TYPE Martin_Type   = MODE_MARTINGALE;      // 加碼模式 (馬丁/反馬丁)
input  double  Initial_Lot                = 0.01;                 // 起始下單手數
input  double  Lot_Multiplier             = 1.5;                  // 手數縮放倍率 (Martin)
input  int     Grid_Distance_Pips         = 20;                   // 基礎網格間距 (Pips)
input  double  Distance_Multiplier        = 1.0;                  // 格距縮放倍率 (Grid)

sinput string  Section_4                  = "----------------";   // [全局監控]
input  double  Total_Profit_Target        = 10.0;                 // 全局獲利結算門檻
input  double  Profit_Retracement_Pct     = 25.0;                 // 獲利回跌百分比 (%)

sinput string  Section_5                  = "----------------";   // [風險管理]
input  int     Magic_Number               = 168888;               // EA 魔術碼
input  int     Max_Spread                 = 30;                   // 最大允許點差 (Points)
input  string  Log_File_Name              = "Debug.Log";          // 系統交易日誌名稱 (留空則不紀錄)

sinput string  Section_6                  = "----------------";   // [圖表視覺管理]
input  bool    UI_Panel_Enabled           = true;                 // 啟動專業儀表板
input  bool    Arrow_Manager_Enabled      = true;                 // 啟用箭頭管理模組
input  int     Arrow_History_Days         = 3;                    // 歷史箭頭回溯天數
input  color   Arrow_Buy_Live             = clrOrangeRed;         // 持倉買單顏色
input  color   Arrow_Sell_Live            = clrLawnGreen;         // 持倉賣單顏色
input  color   Arrow_Buy_Hist             = clrDarkRed;           // 歷史買單顏色
input  color   Arrow_Sell_Hist            = clrDarkGreen;         // 歷史賣單顏色

//+------------------------------------------------------------------+
//| 全域變數                                                          |
//+------------------------------------------------------------------+
datetime          g_lastBarTime             = 0;
double            g_peakTotalProfit         = 0;
string            g_sessionPrefix           = "HA_Profit_";
string            g_fullLogPath             = "";     // 完整日誌路徑

// --- 平滑 HA 內部快取緩衝區 (完全對齊指標 14 個緩衝區架構) ---
double            g_haOpen[], g_haClose[], g_haHigh[], g_haLow[]; // 最終平滑結果 (對應指標 Buffer 0-3)
double            g_haL7[], g_haL8[]; // 中間 HA 計算 (對應指標 Buffer 7-8)
double            g_haL5[], g_haL6[]; // HA Open/Close (對應指標 Buffer 5-6)
double            g_haL9[], g_haL10[], g_haL11[], g_haL12[]; // 計算用 (對應指標 Buffer 9-12)

// --- 趨勢反轉偵測與網格重置變數 ---
int               g_prevHaTrend             = 0;      // 上一次的 HA 趨勢
double            g_buyBasePrice            = 0;      // 買單網格參考點
double            g_sellBasePrice           = 0;      // 賣單網格參考點
int               g_buyGridLevel            = 0;      // 買單目前網格層數
int               g_sellGridLevel           = 0;      // 賣單目前網格層數

// --- UI 與 均價線實例 ---
CChartPanelCanvas  g_panel;
CTradeArrowManager g_arrowMgr; // 補回實例宣告，修復未定義識別碼錯誤

// --- 帳戶快照結構 ---
struct AccountSnapshot
  {
   int               buyCount;
   int               sellCount;
   double            buyLots;
   double            sellLots;
   double            buyProfit;
   double            sellProfit;
   double            buyAvgPrice;
   double            sellAvgPrice;
   double            totalProfit;
   int               totalOrders;
   double            equity;
   double            balance;
   double            marginLevel;
  };
AccountSnapshot g_snapshot;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("=== HA Adaptive EA v1.52 啟動 (Canvas UI 遷移版) ===");

// --- 初始化日誌 ---
   InitTradeLog();

// --- 初始化專業面板 ---
   if(UI_Panel_Enabled)
     {
      g_panel.Init("HA_UI_", 20, 20, 1);
      g_panel.SetEAVersion("1.52");
      g_panel.SetSystemInfo((Trade_Mode == DIR_TREND ? "順勢" : "逆勢"), Symbol());
      // 傳遞 Magic Number 以便面板計算持倉與均價線
      g_panel.SetTradeInfo(Magic_Number);
     }

// --- 初始化箭頭管理 (改用 v2.4 外部模組) ---
   g_arrowMgr.InitFull(Symbol(), "HA_Arrow_", Arrow_Manager_Enabled, Arrow_History_Days, Magic_Number, 10,
                       Arrow_Buy_Live, Arrow_Sell_Live, Arrow_Buy_Hist, Arrow_Sell_Hist);

// --- 網格狀態同步 ---
   SyncGridState();

// --- 初始化趨勢 ---
   InitHATrend();

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_panel.Deinit();
   g_arrowMgr.ArrowOnDeinit();
   Print("EA 已停止。");
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
  {
// 1. ADX 狀態更新與 UI 顯示\n   CalcADXIndicators();\n   int _adxTrade=0, _adxMartin=0; GetADXState(_adxTrade, _adxMartin);\n   string dirStr = (_adxTrade == DIR_TREND) ? "順勢" : "逆勢";\n   string martStr = (_adxMartin == MODE_ANTI_MARTY) ? "反馬丁" : "馬丁";\n   if(UI_Panel_Enabled) g_panel.SetSystemInfo(dirStr, martStr);
   CalcADXIndicators();
   int _adxTrade=0, _adxMartin=0;
   GetADXState(_adxTrade, _adxMartin);
   string dirStr = (_adxTrade == DIR_TREND) ? "順勢" : "逆勢";
   string martStr = (_adxMartin == MODE_ANTI_MARTY) ? "反馬丁" : "馬丁";
   if(UI_Panel_Enabled && g_panel.IsInitialized())
     {
      g_panel.SetSystemInfo(dirStr, martStr);
     }
   UpdateAccountSnapshot();


// 2. 全局出場監控 (直接引用快照數據)
   ManageGlobalExit();

// 3. 網格加碼檢測 (直接引用快照數據)
   ExecuteGridCheck();

// 4. 指標趨勢檢測 (僅在每根 K 棒開盤時執行)
   if(Time[0] != g_lastBarTime)
     {
      ExecuteBarEntry();
      g_lastBarTime = Time[0];
     }

// 5. 圖表面板與均價線更新 (效能優化：限制更新頻率為 1 秒一次，或在訂單數變動時立即更新)
   static int lastOrderCount = -1;
   static uint lastRenderTime = 0;
   if(g_snapshot.totalOrders != lastOrderCount || GetTickCount() - lastRenderTime > 1000)
     {
      if(UI_Panel_Enabled)
        {
         OrderStats stats;
         stats.buyCount   = g_snapshot.buyCount;
         stats.sellCount  = g_snapshot.sellCount;
         stats.buyLots    = g_snapshot.buyLots;
         stats.sellLots   = g_snapshot.sellLots;
         stats.buyProfit  = g_snapshot.buyProfit;
         stats.sellProfit = g_snapshot.sellProfit;
         stats.profit     = g_snapshot.totalProfit;
         stats.count      = g_snapshot.totalOrders;

         // 更新面板數據
         g_panel.UpdateWithStats(stats, true);

         // 實作多空持倉均價線顯示 (v2.4 追加功能)
         g_panel.DrawAvgLines();
        }

      // 交易箭頭管理模組同步更新 (已改用 v2.4 外部模組)
      g_arrowMgr.ArrowOnTick();

      lastOrderCount = g_snapshot.totalOrders;
      lastRenderTime = GetTickCount();
     }
  }

//+------------------------------------------------------------------+
//| 核心演算法：更新帳戶快照                                          |
//+------------------------------------------------------------------+
void UpdateAccountSnapshot()
  {
   ZeroMemory(g_snapshot);
   double buyVal = 0, sellVal = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
        {
         double p = OrderProfit() + OrderSwap() + OrderCommission();
         g_snapshot.totalProfit += p;
         g_snapshot.totalOrders++;
         if(OrderType() == OP_BUY)
           {
            g_snapshot.buyCount++;
            g_snapshot.buyLots += OrderLots();
            g_snapshot.buyProfit += p;
            buyVal += OrderOpenPrice() * OrderLots();
           }
         if(OrderType() == OP_SELL)
           {
            g_snapshot.sellCount++;
            g_snapshot.sellLots += OrderLots();
            g_snapshot.sellProfit += p;
            sellVal += OrderOpenPrice() * OrderLots();
           }
        }
     }
   if(g_snapshot.buyLots > 0)
      g_snapshot.buyAvgPrice = buyVal / g_snapshot.buyLots;
   if(g_snapshot.sellLots > 0)
      g_snapshot.sellAvgPrice = sellVal / g_snapshot.sellLots;
   g_snapshot.equity = AccountEquity();
   g_snapshot.balance = AccountBalance();
   g_snapshot.marginLevel = (AccountMargin() > 0) ? (AccountEquity() / AccountMargin() * 100.0) : 0;
  }

//+------------------------------------------------------------------+
//| 核心演算法：更新平滑 HA 訊號 (完全對齊指標 0.2)              |
//+------------------------------------------------------------------+
void UpdateHASignals()
  {
   int bars = iBars(NULL, HA_TimeFrame);
   if(bars < 100)
      return;

// 調整緩衝區大小
   if(ArrayRange(g_haOpen, 0) != bars)
     {
      ArrayResize(g_haOpen, bars);
      ArrayResize(g_haClose, bars);
      ArrayResize(g_haHigh, bars);
      ArrayResize(g_haLow, bars);
      ArrayResize(g_haL5, bars);
      ArrayResize(g_haL6, bars);
      ArrayResize(g_haL7, bars);
      ArrayResize(g_haL8, bars);
      ArrayResize(g_haL9, bars);
      ArrayResize(g_haL10, bars);
      ArrayResize(g_haL11, bars);
      ArrayResize(g_haL12, bars);
     }

   int limit = 1000;
   if(limit > bars - 1)
      limit = bars - 1;

   for(int pos = limit; pos >= 0; pos--)
     {
      // A. 第一階段平滑 (MA1) - 完全對齊指標實例編號 0-3
      double maOpen  = iCustomMaEa(HA_MaMethod1,  iOpen(NULL, HA_TimeFrame, pos),  HA_MaPeriod1, pos, 0);
      double maClose = iCustomMaEa(HA_MaMethod1, iClose(NULL, HA_TimeFrame, pos), HA_MaPeriod1, pos, 1);
      double maLow   = iCustomMaEa(HA_MaMethod1, iLow(NULL, HA_TimeFrame, pos),   HA_MaPeriod1, pos, 2);
      double maHigh  = iCustomMaEa(HA_MaMethod1, iHigh(NULL, HA_TimeFrame, pos),  HA_MaPeriod1, pos, 3);

      // B. 計算 Heiken Ashi 數值 - 完全對齊指標邏輯
      double haOpen = maOpen;
      if(pos < bars - 1)
         haOpen = (g_haL9[pos + 1] + g_haL10[pos + 1]) / 2.0;

      double haClose = (maOpen + maHigh + maLow + maClose) / 4.0;
      double haHigh  = fmax(maHigh, fmax(haOpen, haClose));
      double haLow   = fmin(maLow,  fmin(haOpen, haClose));

      // C. 存入初步計算緩衝區 (中間層)
      if(haOpen < haClose)
        {
         g_haL11[pos] = haLow;
         g_haL12[pos] = haHigh;
        }
      else
        {
         g_haL11[pos] = haHigh;
         g_haL12[pos] = haLow;
        }
      g_haL9[pos]  = haOpen;
      g_haL10[pos] = haClose;

      // D. 執行第二階段平滑 (MA2) 並填充最終數據 - 完全對齊指標實例編號 4-7
      g_haLow[pos]   = iCustomMaEa(HA_MaMethod2, g_haL11[pos], HA_MaPeriod2, pos, 4);
      g_haHigh[pos]  = iCustomMaEa(HA_MaMethod2, g_haL12[pos], HA_MaPeriod2, pos, 5);
      g_haOpen[pos]  = iCustomMaEa(HA_MaMethod2, g_haL9[pos],  HA_MaPeriod2, pos, 6);
      g_haClose[pos] = iCustomMaEa(HA_MaMethod2, g_haL10[pos], HA_MaPeriod2, pos, 7);
     }
  }

// --- MA 計算核心 (完全移植自指標) ---
double iCustomMaEa(int mode, double price, double length, int r, int instanceNo = 0)
  {
   switch(mode)
     {
      case ma_sma:
         return(iSmaEa(price, (int)length, r, instanceNo));
      case ma_ema:
         return(iEmaEa(price, length, r, instanceNo));
      case ma_smma:
         return(iSmmaEa(price, (int)length, r, instanceNo));
      case ma_lwma:
         return(iLwmaEa(price, length, r, instanceNo));
      case ma_tema:
         return(iTemaEa(price, (int)length, r, instanceNo));
      case ma_hma:
         return(iHmaEa(price, (int)length, r, instanceNo));
      default:
         return(price);
     }
  }

double workSmaEa[][8];
double iSmaEa(double price, int period, int r, int instanceNo = 0)
  {
   int bars = iBars(NULL, HA_TimeFrame);
   if(ArrayRange(workSmaEa, 0) != bars)
      ArrayResize(workSmaEa, bars);
   int k;
   workSmaEa[r][instanceNo] = price;
   double sum = 0;
   for(k = 0; k < period && (r - k) >= 0; k++)
      sum += workSmaEa[r - k][instanceNo];
   return(sum / fmax(k, 1));
  }

double workEmaEa[][8];
double iEmaEa(double price, double period, int r, int instanceNo = 0)
  {
   int bars = iBars(NULL, HA_TimeFrame);
   if(ArrayRange(workEmaEa, 0) != bars)
      ArrayResize(workEmaEa, bars);
   workEmaEa[r][instanceNo] = price;
   if(r > 0 && period > 1)
      workEmaEa[r][instanceNo] = workEmaEa[r - 1][instanceNo] + (2.0 / (1.0 + period)) * (price - workEmaEa[r - 1][instanceNo]);
   return(workEmaEa[r][instanceNo]);
  }

double workSmmaEa[][8];
double iSmmaEa(double price, double period, int r, int instanceNo = 0)
  {
   int bars = iBars(NULL, HA_TimeFrame);
   if(ArrayRange(workSmmaEa, 0) != bars)
      ArrayResize(workSmmaEa, bars);
   workSmmaEa[r][instanceNo] = price;
   if(r > 0 && period > 1)
      workSmmaEa[r][instanceNo] = workSmmaEa[r - 1][instanceNo] + (price - workSmmaEa[r - 1][instanceNo]) / period;
   return(workSmmaEa[r][instanceNo]);
  }

double workLwmaEa[][8];
double iLwmaEa(double price, double period, int r, int instanceNo = 0)
  {
   int bars = iBars(NULL, HA_TimeFrame);
   if(ArrayRange(workLwmaEa, 0) != bars)
      ArrayResize(workLwmaEa, bars);
   workLwmaEa[r][instanceNo] = price;
   if(period <= 1)
      return(price);
   double sumw = 0, sum = 0;
   for(int k = 0; k < (int)period && (r - k) >= 0; k++)
     {
      double w = period - k;
      sumw += w;
      sum += w * workLwmaEa[r - k][instanceNo];
     }
   return(sum / fmax(sumw, 1));
  }

double workTemaEa[][24];
double iTemaEa(double price, int period, int r, int instanceNo = 0)
  {
   int bars = iBars(NULL, HA_TimeFrame);
   if(ArrayRange(workTemaEa, 0) != bars)
      ArrayResize(workTemaEa, bars);
   int n = instanceNo * 3;
   double alpha = 2.0 / (1.0 + period);
   workTemaEa[r][n] = price;
   workTemaEa[r][n+1] = price;
   workTemaEa[r][n+2] = price;
   if(r > 0)
     {
      workTemaEa[r][n]   = workTemaEa[r-1][n]   + alpha * (price - workTemaEa[r-1][n]);
      workTemaEa[r][n+1] = workTemaEa[r-1][n+1] + alpha * (workTemaEa[r][n]   - workTemaEa[r-1][n+1]);
      workTemaEa[r][n+2] = workTemaEa[r-1][n+2] + alpha * (workTemaEa[r][n+1] - workTemaEa[r-1][n+2]);
     }
   return(workTemaEa[r][n+2] + 3.0 * (workTemaEa[r][n] - workTemaEa[r][n+1]));
  }

double workHmaEa[][16];
double iHmaEa(double price, int period, int r, int instanceNo = 0)
  {
   int bars = iBars(NULL, HA_TimeFrame);
   if(ArrayRange(workHmaEa, 0) != bars)
      ArrayResize(workHmaEa, bars);
   if(period <= 1)
      return(price);

   int n = instanceNo * 2;
   double lwmaHalf = iLwmaHmaEa(price, period / 2, r, n);
   double lwmaFull = iLwmaHmaEa(price, period,     r, n + 1);

   double diff = 2.0 * lwmaHalf - lwmaFull;
   return(iLwmaHmaEa(diff, (int)MathSqrt(period), r, n + 8));
  }

double workLwmaHmaEa[][24];
double iLwmaHmaEa(double price, double period, int r, int instanceNo = 0)
  {
   int bars = iBars(NULL, HA_TimeFrame);
   if(ArrayRange(workLwmaHmaEa, 0) != bars)
      ArrayResize(workLwmaHmaEa, bars);
   workLwmaHmaEa[r][instanceNo] = price;
   if(period <= 1)
      return(price);
   double sumw = 0, sum = 0;
   for(int k = 0; k < (int)period && (r - k) >= 0; k++)
     {
      double w = period - k;
      sumw += w;
      sum += w * workLwmaHmaEa[r - k][instanceNo];
     }
   return(sum / fmax(sumw, 1));
  }

//+------------------------------------------------------------------+
//| 核心演算法：進場與網格邏輯                                        |
//+------------------------------------------------------------------+
void ExecuteGridCheck()
  {
   if(g_snapshot.buyCount > 0)
      CheckAndSendGridOrder(OP_BUY);
   if(g_snapshot.sellCount > 0)
      CheckAndSendGridOrder(OP_SELL);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ExecuteBarEntry()
  {
   if(((Ask - Bid) / Point) > Max_Spread * 10)
      return;

   UpdateHASignals(); // 每次檢測前更新內部平滑數據

   double ho = g_haOpen[1];
   double hc = g_haClose[1];
   int haTrend = 0;
   if(Trade_Mode == DIR_TREND)
     {
      if(hc > ho)
         haTrend = 1;
      if(hc < ho)
         haTrend = -1;
     }
   else
     {
      if(hc > ho)
         haTrend = -1;
      if(hc < ho)
         haTrend = 1;
     }
   if(haTrend == 0)
      return;

   if(haTrend != g_prevHaTrend)
     {
      if(haTrend == 1)
        {
         g_buyBasePrice = Ask;
         g_buyGridLevel = 0;
         WriteToLog("趨勢反轉(多)：重置網格");
        }
      if(haTrend == -1)
        {
         g_sellBasePrice = Bid;
         g_sellGridLevel = 0;
         WriteToLog("趨勢反轉(空)：重置網格");
        }
      g_prevHaTrend = haTrend;
     }

   if(haTrend == 1 && g_snapshot.buyCount == 0)
     {
      g_buyBasePrice = Ask;
      g_buyGridLevel = 0;
      SendOrder(OP_BUY, Initial_Lot, "HA趨勢首單", Grid_Distance_Pips, 1.0, 1.0);
      g_buyGridLevel++;
     }
   if(haTrend == -1 && g_snapshot.sellCount == 0)
     {
      g_sellBasePrice = Bid;
      g_sellGridLevel = 0;
      SendOrder(OP_SELL, Initial_Lot, "HA趨勢首單", Grid_Distance_Pips, 1.0, 1.0);
      g_sellGridLevel++;
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CheckAndSendGridOrder(int type)
  {
   int level = (type == OP_BUY) ? g_buyGridLevel : g_sellGridLevel;
   double base = (type == OP_BUY) ? g_buyBasePrice : g_sellBasePrice;
   double lotMult = MathPow(Lot_Multiplier, level);
   double nextLot = Initial_Lot * lotMult;
   nextLot = NormalizeDouble(nextLot, 2);
   double distMult = MathPow(Distance_Multiplier, level - 1);
   double step = Grid_Distance_Pips * distMult * 10 * Point;

   if(type == OP_BUY)
     {
      bool canBuy = (Martin_Type == MODE_MARTINGALE) ? (Bid <= NormalizeDouble(base - step, Digits)) : (Bid >= NormalizeDouble(base + step, Digits));
      if(canBuy)
        {
         SendOrder(OP_BUY, nextLot, "網格加碼", Grid_Distance_Pips * distMult, Distance_Multiplier, lotMult);
         g_buyGridLevel++;
         g_buyBasePrice = Bid;
        }
     }
   else
     {
      bool canSell = (Martin_Type == MODE_MARTINGALE) ? (Ask >= NormalizeDouble(base + step, Digits)) : (Ask <= NormalizeDouble(base - step, Digits));
      if(canSell)
        {
         SendOrder(OP_SELL, nextLot, "網格加碼", Grid_Distance_Pips * distMult, Distance_Multiplier, lotMult);
         g_sellGridLevel++;
         g_sellBasePrice = Ask;
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SendOrder(int type, double lot, string reason, double d, double dm, double lm)
  {
   double p = (type == OP_BUY) ? Ask : Bid;
   int t = OrderSend(Symbol(), type, lot, p, 3, 0, 0, "HA_v1.52", Magic_Number, 0, (type == OP_BUY ? clrBlue : clrRed));
   if(t > 0)
      WriteToLog(StringFormat("進場 [%s]: 價格 %.5f, 原因: %s, 格距: %.1f, 格距倍率: %.2f, 手數倍率: %.2f", (type == OP_BUY ? "BUY" : "SELL"), p, reason, d, dm, lm));
  }

//+------------------------------------------------------------------+
//| 核心演算法：對沖鎖倉結算                                          |
//+------------------------------------------------------------------+
void ManageGlobalExit()
  {
   if(g_snapshot.totalOrders == 0)
     {
      g_peakTotalProfit = 0;
      return;
     }
   double cp = g_snapshot.totalProfit;
   if(cp >= Total_Profit_Target && cp > g_peakTotalProfit)
      g_peakTotalProfit = cp;
   if(g_peakTotalProfit >= Total_Profit_Target)
     {
      double limit = g_peakTotalProfit * (1.0 - (Profit_Retracement_Pct / 100.0));
      if(cp <= limit && cp >= Total_Profit_Target)
        {
         Print("=== 觸發智慧結算 ===");
         SmartHedgeClose();
         g_peakTotalProfit = 0;
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SmartHedgeClose()
  {
   double bL = 0, sL = 0, ts = 0;
   datetime cTime = TimeCurrent();
   double cPrice = Bid;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
        {
         ts += OrderProfit() + OrderSwap() + OrderCommission();
         if(OrderType() == OP_BUY)
            bL += OrderLots();
         else
            sL += OrderLots();
        }
   double nl = NormalizeDouble(bL - sL, 2);
   if(MathAbs(nl) >= 0.01)
     {
      RefreshRates();
      int hedgeTicket = -1; // 接收返回值，修復編譯警告
      if(nl > 0)
         hedgeTicket = OrderSend(Symbol(), OP_SELL, nl, Bid, 3, 0, 0, "Hedge_Lock", Magic_Number, 0, clrYellow);
      else
         hedgeTicket = OrderSend(Symbol(), OP_BUY, MathAbs(nl), Ask, 3, 0, 0, "Hedge_Lock", Magic_Number, 0, clrYellow);

      if(hedgeTicket < 0)
         Print("對沖鎖單失敗: ", GetLastError());
     }

// 呼叫面板模組在圖表上繪製結算盈虧標籤
   if(UI_Panel_Enabled)
      g_panel.PrintPL(ts, cTime, cPrice);

   RecursiveCloseBy();
   WriteToLog(StringFormat("出場 [全局結算]: 盈虧 %.2f", ts));
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void RecursiveCloseBy()
  {
   int bt = -1, st = -1;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
        { if(OrderType() == OP_BUY && bt == -1) bt = OrderTicket(); if(OrderType() == OP_SELL && st == -1) st = OrderTicket(); }
   if(bt != -1 && st != -1)
     {
      if(OrderCloseBy(bt, st, clrWhite))
         RecursiveCloseBy();
      else
         RecursiveCloseBy();
     }
   else
      for(int k = OrdersTotal() - 1; k >= 0; k--)
         if(OrderSelect(k, SELECT_BY_POS, MODE_TRADES) && OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
           {
            double op = OrderProfit() + OrderSwap() + OrderCommission();
            int otkt = OrderTicket();
            double olots = OrderLots();
            bool res = false;
            if(OrderType() == OP_BUY)
               res = OrderClose(otkt, olots, Bid, 3, clrWhite);
            if(OrderType() == OP_SELL)
               res = OrderClose(otkt, olots, Ask, 3, clrWhite);

            // 單筆清理時同樣在圖表上標記盈虧
            if(res && UI_Panel_Enabled)
               g_panel.PrintPL(op, TimeCurrent(), (OrderType() == OP_BUY ? Bid : Ask));
           }
  }

//+------------------------------------------------------------------+
//| 輔助功能                                                          |
//+------------------------------------------------------------------+
void InitTradeLog()
  {
   if(Log_File_Name == "")
      return;
   string base = Log_File_Name, ext = "";
   int pos = StringFind(Log_File_Name, ".");
   if(pos >= 0)
     {
      base = StringSubstr(Log_File_Name, 0, pos);
      ext = StringSubstr(Log_File_Name, pos);
     }
   if(IsTesting())
      g_fullLogPath = base + "_BackTest" + ext;
   else
     {
      MqlDateTime dt;
      TimeToStruct(TimeLocal(), dt);
      g_fullLogPath = StringFormat("%s_%02d%02d%02d_%02d%02d%02d%s", base, dt.year%100, dt.mon, dt.day, dt.hour, dt.min, dt.sec, ext);
     }
   int h = FileOpen(g_fullLogPath, FILE_WRITE|FILE_TXT|FILE_SHARE_READ);
   if(h != INVALID_HANDLE)
     {
      FileWrite(h, "=== HA Adaptive EA v1.52 Log ===");
      FileClose(h);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void WriteToLog(string t)
  {
   if(g_fullLogPath == "")
      return;
   int h = FileOpen(g_fullLogPath, FILE_READ|FILE_WRITE|FILE_TXT|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h != INVALID_HANDLE)
     {
      FileSeek(h, 0, SEEK_END);
      FileWrite(h, "[" + TimeToStr(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "] " + t);
      FileClose(h);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SyncGridState()
  {
   datetime lb = 0, ls = 0;
   for(int i = 0; i < OrdersTotal(); i++)
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
        {
         if(OrderType() == OP_BUY)
           {
            g_buyGridLevel++;
            if(OrderOpenTime() > lb)
              {
               g_buyBasePrice = OrderOpenPrice();
               lb = OrderOpenTime();
              }
           }
         if(OrderType() == OP_SELL)
           {
            g_sellGridLevel++;
            if(OrderOpenTime() > ls)
              {
               g_sellBasePrice = OrderOpenPrice();
               ls = OrderOpenTime();
              }
           }
        }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void InitHATrend()
  {
   UpdateHASignals();
   double ho = g_haOpen[1];
   double hc = g_haClose[1];
   if(Trade_Mode == DIR_TREND)
     {
      g_prevHaTrend = (hc > ho ? 1 : -1);
     }
   else
     {
      g_prevHaTrend = (hc > ho ? -1 : 1);
     }
  }
//+------------------------------------------------------------------+
