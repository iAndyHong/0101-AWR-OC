//+------------------------------------------------------------------+
//|                                              HA_Adaptive_EA.mq4 |
//|                                                             Andy |
//|                     基於 Heiken Ashi 的趨勢追蹤與全局獲利回跌系統 |
//+------------------------------------------------------------------+
#property copyright "Andy"
#property link      ""
#property version   "1.55"
#property strict

//+------------------------------------------------------------------+
//| 包含檔案與外部依賴                                                 |
//+------------------------------------------------------------------+
#include "Libs/UI/CChartPanelCanvas_v2.4.mqh"

//+------------------------------------------------------------------+
//| 枚舉定義                                                          |
//+------------------------------------------------------------------+
enum enMaTypes
  {
   ma_sma,    // SMA
   ma_ema,    // EMA
   ma_smma,   // SMMA
   ma_lwma,   // LWMA
   ma_tema,   // TEMA
   ma_hma     // HMA
  };

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

enum ENUM_SYSTEM_MODE
  {
   SYS_NORMAL   = 0,     // 正常交易模式
   SYS_EXIT_ONLY = 1,    // 僅平倉模式
   SYS_PAUSED   = 2      // 暫停交易模式
  };

//+------------------------------------------------------------------+
//| 輸入參數                                                          |
//+------------------------------------------------------------------+
sinput string  Section_0                  = "----------------";   // [系統主控]
input  ENUM_SYSTEM_MODE System_Mode       = SYS_NORMAL;           // 系統運行模式
sinput string  Section_1                  = "----------------";   // [趨勢過濾]
input  ENUM_TIMEFRAMES HA_TimeFrame       = PERIOD_CURRENT;       // Heiken Ashi 運算週期
input  enMaTypes       HA_MaMethod1       = ma_ema;               // HA 平滑方法 1
input  int             HA_MaPeriod1       = 6;                    // HA 平滑週期 1
input  enMaTypes       HA_MaMethod2       = ma_lwma;              // HA 平滑方法 2 (對齊 v1.52)
input  int             HA_MaPeriod2       = 2;                    // HA 平滑週期 2
input  ENUM_TRADE_DIRECTION Trade_Mode    = DIR_TREND;            // 預設趨勢過濾模式

sinput string  Section_ADX                = "----------------";   // [ADX 自適應設定]
input  int             ADX_Mode           = 1;                    // ADX 模式 (0:禁用, 1:過濾, 2:自適應)
input  int             ADX_Period         = 14;                   // ADX 週期
input  int             ADX_Level_Low      = 20;                   // 震盪閾值
input  int             ADX_Level_High     = 25;                   // 趨勢閾值
input  bool            UseDI              = true;                 // 使用 DI 判定
input  bool            UseDIForDirection  = true;                 // DI 覆蓋方向
input  int             ADX_Switch_Delay   = 2;                    // 切換緩衝期(Bars)

sinput string  Section_2                  = "----------------";   // [網格馬丁]
input  ENUM_MARTINGALE_TYPE Martin_Type   = MODE_MARTINGALE;      // 預設加碼模式
input  double          Initial_Lot        = 0.01;                 // 起始下單手數
input  double          Lot_Multiplier     = 1.5;                  // 手數縮放倍率
input  int             Grid_Distance_Pips = 20;                   // 基礎網格間距 (Pips)
input  double          Distance_Multiplier= 1.0;                  // 格距縮放倍率

sinput string  Section_4                  = "----------------";   // [全局監控]
input  double          Total_Profit_Target    = 10.0;             // 獲利結算門檻
input  double          Profit_Retracement_Pct = 25.0;             // 獲利回跌百分比 (%)

sinput string  Section_5                  = "----------------";   // [風險管理]
input  int             Magic_Number       = 168888;               // EA 魔術碼
input  int             Max_Spread         = 30;                   // 最大允許點差 (Points)
input  string          Log_File_Name      = "Debug.Log";          // 交易日誌名稱

sinput string  Section_6                  = "----------------";   // [視覺效果]
input  bool            UI_Panel_Enabled   = true;                 // 啟動儀表板
input  bool            Arrow_Mgr_Enabled  = true;                 // 啟用箭頭管理
input  int             Arrow_Hist_Days    = 3;                    // 歷史回溯天數
input  color           Arrow_Buy_Live     = clrOrangeRed;         // 持倉買單
input  color           Arrow_Sell_Live    = clrLawnGreen;         // 持倉賣單
input  color           Arrow_Buy_Hist     = clrDarkRed;           // 歷史買單
input  color           Arrow_Sell_Hist    = clrDarkGreen;         // 歷史賣單

//+------------------------------------------------------------------+
//| 全域變數定義                                                       |
//+------------------------------------------------------------------+
// --- 核心實例 ---
CChartPanelCanvas  g_panel;
CTradeArrowManager g_arrowMgr;

// --- 執行狀態變數 ---
int    g_execTradeMode   = -1;
int    g_execMartinType  = -1;
datetime g_lastBarTime   = 0;
double g_peakTotalProfit = 0;
string g_fullLogPath     = "";

// --- ADX 狀態機變數 ---
int    g_adxCurrentTrade  = -1;
int    g_adxCurrentMartin = -1;
int    g_adxTargetTrade   = -1;
int    g_adxTargetMartin  = -1;
int    g_adxSwitchCounter = 0;
double g_adxValue         = 0;
double g_diPlusValue      = 0;
double g_diMinusValue     = 0;

// --- 網格控制變數 ---
int    g_prevHaTrend      = 0;
double g_buyBasePrice     = 0;
double g_sellBasePrice    = 0;
int    g_buyGridLevel     = 0;
int    g_sellGridLevel    = 0;

// --- Heiken Ashi 平滑緩衝區 ---
double g_haOpen[], g_haClose[], g_haHigh[], g_haLow[];
double g_haL5[], g_haL6[], g_haL7[], g_haL8[];
double g_haL9[], g_haL10[], g_haL11[], g_haL12[];

// --- MA 計算工作緩衝區 ---
double workSmaEa[][8], workEmaEa[][8], workSmmaEa[][8], workLwmaEa[][8];
double workTemaEa[][24], workHmaEa[][16], workLwmaHmaEa[][24];

// --- 帳戶快照結構 ---
struct AccountSnapshot
  {
   int    buyCount, sellCount, totalOrders;
   double buyLots, sellLots, buyProfit, sellProfit, totalProfit;
   double buyAvgPrice, sellAvgPrice, equity, balance, marginLevel;
  };
AccountSnapshot g_snapshot;

//+------------------------------------------------------------------+
//| MQL4 標準事件函數                                                 |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("=== HA Adaptive EA v1.55 啟動 (自適應邏輯執行版) ===");
   InitTradeLog();
   
   // 修正：在初始化 UI 前先掃描一次帳戶，確保 g_snapshot 有初始數據
   UpdateAccountSnapshot();

   g_execTradeMode = Trade_Mode;
   g_execMartinType = Martin_Type;

   if(UI_Panel_Enabled)
     {
      g_panel.Init("HA_UI_", 20, 20, 1);
      g_panel.SetEAVersion("1.55");
      g_panel.SetSystemInfo((Trade_Mode == DIR_TREND ? "順勢" : "逆勢"), Symbol());
      g_panel.SetTradeInfo(Magic_Number);
     }

   g_arrowMgr.InitFull(Symbol(), "HA_Arrow_", Arrow_Mgr_Enabled, Arrow_Hist_Days, Magic_Number, 10,
                       Arrow_Buy_Live, Arrow_Sell_Live, Arrow_Buy_Hist, Arrow_Sell_Hist);

   SyncGridState();
   
   // 修正：重新載入時，將當前的盈虧與歷史紀錄同步到 UI 實例中
   if(UI_Panel_Enabled)
     {
      g_panel.RecordClosedProfit(g_snapshot.totalProfit);
      g_panel.SetCurrentProfit(g_snapshot.totalProfit);
      g_panel.RecordMarginLevel(g_snapshot.marginLevel);
     }

   InitHATrend();

   // 修正：在初始化結束前強制繪製一次 UI，確保即便沒有 Tick 也能立即看到面板
   if(UI_Panel_Enabled)
      g_panel.Update(true);

   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   g_arrowMgr.ArrowOnDeinit();
   Print("EA 已停止。");
  }

void OnTick()
  {
   UpdateAccountSnapshot();
   
   // 如果系統處於暫停模式，停止所有邏輯
   if(System_Mode == SYS_PAUSED) return;

   CalcADXIndicators();
   UpdateADXState();
   
   GetADXState(g_execTradeMode, g_execMartinType);
   if(ADX_Mode == 0) { g_execTradeMode = Trade_Mode; g_execMartinType = Martin_Type; }

   UpdateUI();
   ManageGlobalExit();
   ExecuteGridCheck();

   if(Time[0] != g_lastBarTime)
     {
      ExecuteBarEntry();
      g_lastBarTime = Time[0];
     }

   RefreshVisuals();
  }

//+------------------------------------------------------------------+
//| ADX 自適應邏輯函數層                                               |
//+------------------------------------------------------------------+
void CalcADXIndicators()
  {
   g_adxValue = iADX(NULL, HA_TimeFrame, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
   g_diPlusValue = iADX(NULL, HA_TimeFrame, ADX_Period, PRICE_CLOSE, MODE_PLUSDI, 1);
   g_diMinusValue = iADX(NULL, HA_TimeFrame, ADX_Period, PRICE_CLOSE, MODE_MINUSDI, 1);

   if(g_adxValue > ADX_Level_High)
     {
      g_adxTargetTrade = DIR_TREND;
      g_adxTargetMartin = MODE_ANTI_MARTY;
     }
   else if(g_adxValue < ADX_Level_Low)
     {
      g_adxTargetTrade = DIR_REVERSAL;
      g_adxTargetMartin = MODE_MARTINGALE;
     }
   else return;

   if(UseDI && UseDIForDirection)
     {
      if(g_diPlusValue > g_diMinusValue) g_adxTargetTrade = DIR_TREND;
      else g_adxTargetTrade = DIR_REVERSAL;
     }
  }

void UpdateADXState()
  {
   if(g_adxCurrentTrade == -1 || g_adxCurrentMartin == -1)
     {
      g_adxCurrentTrade = g_adxTargetTrade;
      g_adxCurrentMartin = g_adxTargetMartin;
      g_adxSwitchCounter = 0;
      return;
     }

   if(g_adxTargetTrade == g_adxCurrentTrade && g_adxTargetMartin == g_adxCurrentMartin)
     {
      g_adxSwitchCounter = 0;
      return;
     }

   if(g_adxSwitchCounter < ADX_Switch_Delay)
     {
      g_adxSwitchCounter++;
      return;
     }

   g_adxCurrentTrade = g_adxTargetTrade;
   g_adxCurrentMartin = g_adxTargetMartin;
   g_adxSwitchCounter = 0;
  }

void GetADXState(int &tMode, int &mType)
  {
   tMode = g_adxCurrentTrade;
   mType = g_adxCurrentMartin;
  }

//+------------------------------------------------------------------+
//| 交易核心函數層                                                    |
//+------------------------------------------------------------------+
void ExecuteBarEntry()
  {
   // 僅平倉模式下不允許開立首單
   if(System_Mode == SYS_EXIT_ONLY) return;

   if(((Ask - Bid) / Point) > Max_Spread * 10) return;
   UpdateHASignals();

   double ho = g_haOpen[1], hc = g_haClose[1];
   int haTrend = 0;
   
   if(g_execTradeMode == DIR_TREND) haTrend = (hc > ho ? 1 : -1);
   else haTrend = (hc > ho ? -1 : 1);

   if(haTrend == 0) return;

   if(haTrend != g_prevHaTrend)
     {
      if(haTrend == 1)  { g_buyBasePrice = Ask; g_buyGridLevel = 0; WriteToLog("趨勢反轉(多)：重置網格"); }
      if(haTrend == -1) { g_sellBasePrice = Bid; g_sellGridLevel = 0; WriteToLog("趨勢反轉(空)：重置網格"); }
      g_prevHaTrend = haTrend;
     }

   if(haTrend == 1 && g_snapshot.buyCount == 0)
     {
      g_buyBasePrice = Ask; g_buyGridLevel = 0;
      SendOrder(OP_BUY, Initial_Lot, "HA趨勢首單", Grid_Distance_Pips, 1.0, 1.0);
      g_buyGridLevel++;
     }
   if(haTrend == -1 && g_snapshot.sellCount == 0)
     {
      g_sellBasePrice = Bid; g_sellGridLevel = 0;
      SendOrder(OP_SELL, Initial_Lot, "HA趨勢首單", Grid_Distance_Pips, 1.0, 1.0);
      g_sellGridLevel++;
     }
  }

void ExecuteGridCheck()
  {
   // 僅平倉模式下不允許網格加碼
   if(System_Mode == SYS_EXIT_ONLY) return;

   if(g_snapshot.buyCount > 0) CheckAndSendGridOrder(OP_BUY);
   if(g_snapshot.sellCount > 0) CheckAndSendGridOrder(OP_SELL);
  }

void CheckAndSendGridOrder(int type)
  {
   int level = (type == OP_BUY) ? g_buyGridLevel : g_sellGridLevel;
   double base = (type == OP_BUY) ? g_buyBasePrice : g_sellBasePrice;
   double lotMult = MathPow(Lot_Multiplier, level);
   double nextLot = NormalizeDouble(Initial_Lot * lotMult, 2);
   double distMult = MathPow(Distance_Multiplier, fmax(level - 1, 0));
   double step = Grid_Distance_Pips * distMult * 10 * Point;

   if(type == OP_BUY)
     {
      bool canBuy = (g_execMartinType == MODE_MARTINGALE) ? (Bid <= NormalizeDouble(base - step, Digits)) : (Bid >= NormalizeDouble(base + step, Digits));
      if(canBuy) { SendOrder(OP_BUY, nextLot, "網格加碼", Grid_Distance_Pips * distMult, Distance_Multiplier, lotMult); g_buyGridLevel++; g_buyBasePrice = Bid; }
     }
   else
     {
      bool canSell = (g_execMartinType == MODE_MARTINGALE) ? (Ask >= NormalizeDouble(base + step, Digits)) : (Ask <= NormalizeDouble(base - step, Digits));
      if(canSell) { SendOrder(OP_SELL, nextLot, "網格加碼", Grid_Distance_Pips * distMult, Distance_Multiplier, lotMult); g_sellGridLevel++; g_sellBasePrice = Ask; }
     }
  }

void SendOrder(int type, double lot, string reason, double d, double dm, double lm)
  {
   double p = (type == OP_BUY) ? Ask : Bid;
   int t = OrderSend(Symbol(), type, lot, p, 3, 0, 0, "HA_v1.54", Magic_Number, 0, (type == OP_BUY ? clrBlue : clrRed));
   if(t > 0) WriteToLog(StringFormat("進場 [%s]: 價格 %.5f, 原因: %s, 格距: %.1f, 格距倍率: %.2f, 手數倍率: %.2f", (type == OP_BUY ? "BUY" : "SELL"), p, reason, d, dm, lm));
  }

//+------------------------------------------------------------------+
//| 結算與風險管理函數層                                               |
//+------------------------------------------------------------------+
void ManageGlobalExit()
  {
   if(g_snapshot.totalOrders == 0) { g_peakTotalProfit = 0; return; }
   double cp = g_snapshot.totalProfit;
   if(cp >= Total_Profit_Target && cp > g_peakTotalProfit) g_peakTotalProfit = cp;
   if(g_peakTotalProfit >= Total_Profit_Target)
     {
      double limit = g_peakTotalProfit * (1.0 - (Profit_Retracement_Pct / 100.0));
      if(cp <= limit && cp >= Total_Profit_Target) { Print("=== 觸發智慧結算 ==="); SmartHedgeClose(); g_peakTotalProfit = 0; }
     }
  }

void SmartHedgeClose()
  {
   double bL = 0, sL = 0, ts = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
        {
         ts += OrderProfit() + OrderSwap() + OrderCommission();
         if(OrderType() == OP_BUY) bL += OrderLots(); else sL += OrderLots();
        }
   double nl = NormalizeDouble(bL - sL, 2);
   if(MathAbs(nl) >= 0.01)
     {
      RefreshRates();
      if(nl > 0) OrderSend(Symbol(), OP_SELL, nl, Bid, 3, 0, 0, "Hedge_Lock", Magic_Number, 0, clrYellow);
      else OrderSend(Symbol(), OP_BUY, MathAbs(nl), Ask, 3, 0, 0, "Hedge_Lock", Magic_Number, 0, clrYellow);
     }
   if(UI_Panel_Enabled) g_panel.PrintPL(ts, TimeCurrent(), Bid);
   RecursiveCloseBy();
   WriteToLog(StringFormat("出場 [全局結算]: 盈虧 %.2f", ts));
  }

void RecursiveCloseBy()
  {
   int bt = -1, st = -1;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
        { if(OrderType() == OP_BUY && bt == -1) bt = OrderTicket(); if(OrderType() == OP_SELL && st == -1) st = OrderTicket(); }
   if(bt != -1 && st != -1) { if(OrderCloseBy(bt, st, clrWhite)) RecursiveCloseBy(); else RecursiveCloseBy(); }
   else
      for(int k = OrdersTotal() - 1; k >= 0; k--)
         if(OrderSelect(k, SELECT_BY_POS, MODE_TRADES) && OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
           {
            double op = OrderProfit() + OrderSwap() + OrderCommission();
            if(OrderClose(OrderTicket(), OrderLots(), (OrderType() == OP_BUY ? Bid : Ask), 3, clrWhite))
               if(UI_Panel_Enabled) g_panel.PrintPL(op, TimeCurrent(), (OrderType() == OP_BUY ? Bid : Ask));
           }
  }

//+------------------------------------------------------------------+
//| Heiken Ashi 訊號計算函數層                                         |
//+------------------------------------------------------------------+
void UpdateHASignals()
  {
   int bars = iBars(NULL, HA_TimeFrame);
   if(bars < 100) return;
   if(ArrayRange(g_haOpen, 0) != bars)
     {
      ArrayResize(g_haOpen, bars); ArrayResize(g_haClose, bars); ArrayResize(g_haHigh, bars); ArrayResize(g_haLow, bars);
      ArrayResize(g_haL5, bars); ArrayResize(g_haL6, bars); ArrayResize(g_haL7, bars); ArrayResize(g_haL8, bars);
      ArrayResize(g_haL9, bars); ArrayResize(g_haL10, bars); ArrayResize(g_haL11, bars); ArrayResize(g_haL12, bars);
     }
   int limit = fmin(bars - 1, 1000);
   for(int pos = limit; pos >= 0; pos--)
     {
      double maO = iCustomMaEa(HA_MaMethod1, iOpen(NULL, HA_TimeFrame, pos), HA_MaPeriod1, pos, 0);
      double maC = iCustomMaEa(HA_MaMethod1, iClose(NULL, HA_TimeFrame, pos), HA_MaPeriod1, pos, 1);
      double maL = iCustomMaEa(HA_MaMethod1, iLow(NULL, HA_TimeFrame, pos), HA_MaPeriod1, pos, 2);
      double maH = iCustomMaEa(HA_MaMethod1, iHigh(NULL, HA_TimeFrame, pos), HA_MaPeriod1, pos, 3);
      double haO = (pos < bars-1) ? (g_haL9[pos+1] + g_haL10[pos+1]) / 2.0 : maO;
      double haC = (maO + maH + maL + maC) / 4.0;
      if(haO < haC) { g_haL11[pos] = fmin(maL, fmin(haO, haC)); g_haL12[pos] = fmax(maH, fmax(haO, haC)); }
      else { g_haL11[pos] = fmax(maH, fmax(haO, haC)); g_haL12[pos] = fmin(maL, fmin(haO, haC)); }
      g_haL9[pos] = haO; g_haL10[pos] = haC;
      g_haLow[pos] = iCustomMaEa(HA_MaMethod2, g_haL11[pos], HA_MaPeriod2, pos, 4);
      g_haHigh[pos] = iCustomMaEa(HA_MaMethod2, g_haL12[pos], HA_MaPeriod2, pos, 5);
      g_haOpen[pos] = iCustomMaEa(HA_MaMethod2, g_haL9[pos], HA_MaPeriod2, pos, 6);
      g_haClose[pos] = iCustomMaEa(HA_MaMethod2, g_haL10[pos], HA_MaPeriod2, pos, 7);
     }
  }

double iCustomMaEa(int mode, double price, double length, int r, int instanceNo = 0)
  {
   switch(mode)
     {
      case ma_sma: return iSmaEa(price, (int)length, r, instanceNo);
      case ma_ema: return iEmaEa(price, length, r, instanceNo);
      case ma_smma: return iSmmaEa(price, (int)length, r, instanceNo);
      case ma_lwma: return iLwmaEa(price, length, r, instanceNo);
      case ma_tema: return iTemaEa(price, (int)length, r, instanceNo);
      case ma_hma: return iHmaEa(price, (int)length, r, instanceNo);
      default: return price;
     }
  }

double iSmaEa(double p, int per, int r, int inst) { int bars = iBars(NULL, HA_TimeFrame); if(ArrayRange(workSmaEa, 0) != bars) ArrayResize(workSmaEa, bars); workSmaEa[r][inst] = p; double sum = 0; int k; for(k = 0; k < per && (r - k) >= 0; k++) sum += workSmaEa[r - k][inst]; return sum / fmax(k, 1); }
double iEmaEa(double p, double per, int r, int inst) { int bars = iBars(NULL, HA_TimeFrame); if(ArrayRange(workEmaEa, 0) != bars) ArrayResize(workEmaEa, bars); workEmaEa[r][inst] = p; if(r > 0 && per > 1) workEmaEa[r][inst] = workEmaEa[r - 1][inst] + (2.0 / (1.0 + per)) * (p - workEmaEa[r - 1][inst]); return workEmaEa[r][inst]; }
double iSmmaEa(double p, double per, int r, int inst) { int bars = iBars(NULL, HA_TimeFrame); if(ArrayRange(workSmmaEa, 0) != bars) ArrayResize(workSmmaEa, bars); workSmmaEa[r][inst] = p; if(r > 0 && per > 1) workSmmaEa[r][inst] = workSmmaEa[r - 1][inst] + (p - workSmmaEa[r - 1][inst]) / per; return workSmmaEa[r][inst]; }
double iLwmaEa(double p, double per, int r, int inst) { int bars = iBars(NULL, HA_TimeFrame); if(ArrayRange(workLwmaEa, 0) != bars) ArrayResize(workLwmaEa, bars); workLwmaEa[r][inst] = p; if(per <= 1) return p; double sw = 0, s = 0; for(int k = 0; k < (int)per && (r - k) >= 0; k++) { double w = per - k; sw += w; s += w * workLwmaEa[r - k][inst]; } return s / fmax(sw, 1); }
double iTemaEa(double p, int per, int r, int inst) { int bars = iBars(NULL, HA_TimeFrame); if(ArrayRange(workTemaEa, 0) != bars) ArrayResize(workTemaEa, bars); int n = inst * 3; double a = 2.0 / (1.0 + per); workTemaEa[r][n] = p; workTemaEa[r][n+1] = p; workTemaEa[r][n+2] = p; if(r > 0) { workTemaEa[r][n] = workTemaEa[r-1][n] + a * (p - workTemaEa[r-1][n]); workTemaEa[r][n+1] = workTemaEa[r-1][n+1] + a * (workTemaEa[r][n] - workTemaEa[r-1][n+1]); workTemaEa[r][n+2] = workTemaEa[r-1][n+2] + a * (workTemaEa[r][n+1] - workTemaEa[r-1][n+2]); } return workTemaEa[r][n+2] + 3.0 * (workTemaEa[r][n] - workTemaEa[r][n+1]); }
double iHmaEa(double p, int per, int r, int inst) { int bars = iBars(NULL, HA_TimeFrame); if(ArrayRange(workHmaEa, 0) != bars) ArrayResize(workHmaEa, bars); if(per <= 1) return p; int n = inst * 2; double h = iLwmaHmaEa(p, per / 2, r, n), f = iLwmaHmaEa(p, per, r, n + 1); return iLwmaHmaEa(2.0 * h - f, (int)MathSqrt(per), r, n + 8); }
double iLwmaHmaEa(double p, double per, int r, int inst) { int bars = iBars(NULL, HA_TimeFrame); if(ArrayRange(workLwmaHmaEa, 0) != bars) ArrayResize(workLwmaHmaEa, bars); workLwmaHmaEa[r][inst] = p; if(per <= 1) return p; double sw = 0, s = 0; for(int k = 0; k < (int)per && (r - k) >= 0; k++) { double w = per - k; sw += w; s += w * workLwmaHmaEa[r - k][inst]; } return s / fmax(sw, 1); }

//+------------------------------------------------------------------+
//| 系統輔助函數層                                                    |
//+------------------------------------------------------------------+
void UpdateAccountSnapshot()
  {
   ZeroMemory(g_snapshot); double bV = 0, sV = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
        {
         double p = OrderProfit() + OrderSwap() + OrderCommission(); g_snapshot.totalProfit += p; g_snapshot.totalOrders++;
         if(OrderType() == OP_BUY) { g_snapshot.buyCount++; g_snapshot.buyLots += OrderLots(); g_snapshot.buyProfit += p; bV += OrderOpenPrice() * OrderLots(); }
         if(OrderType() == OP_SELL) { g_snapshot.sellCount++; g_snapshot.sellLots += OrderLots(); g_snapshot.sellProfit += p; sV += OrderOpenPrice() * OrderLots(); }
        }
   if(g_snapshot.buyLots > 0) g_snapshot.buyAvgPrice = bV / g_snapshot.buyLots;
   if(g_snapshot.sellLots > 0) g_snapshot.sellAvgPrice = sV / g_snapshot.sellLots;
   g_snapshot.equity = AccountEquity(); g_snapshot.balance = AccountBalance();
   g_snapshot.marginLevel = (AccountMargin() > 0) ? (AccountEquity() / AccountMargin() * 100.0) : 0;
  }

void UpdateUI()
  {
   if(!UI_Panel_Enabled || !g_panel.IsInitialized()) return;
   string dirStr = (g_execTradeMode == DIR_TREND) ? "順勢" : "逆勢";
   string martStr = (g_execMartinType == MODE_ANTI_MARTY) ? "反馬丁" : "馬丁";
   string adxInfo = StringFormat(" / ADX:%.1f DI+:%.1f DI-:%.1f", g_adxValue, g_diPlusValue, g_diMinusValue);
   g_panel.SetSystemInfo(dirStr, martStr + " " + adxInfo);
  }

void RefreshVisuals()
  {
   static int lastCnt = -1; static uint lastRend = 0;
   if(g_snapshot.totalOrders != lastCnt || GetTickCount() - lastRend > 1000)
     {
      if(UI_Panel_Enabled)
        {
         OrderStats s; s.buyCount = g_snapshot.buyCount; s.sellCount = g_snapshot.sellCount;
         s.buyLots = g_snapshot.buyLots; s.sellLots = g_snapshot.sellLots;
         s.buyProfit = g_snapshot.buyProfit; s.sellProfit = g_snapshot.sellProfit;
         s.profit = g_snapshot.totalProfit; s.count = g_snapshot.totalOrders;
         g_panel.UpdateWithStats(s, true); g_panel.DrawAvgLines();
        }
      g_arrowMgr.ArrowOnTick(); lastCnt = g_snapshot.totalOrders; lastRend = GetTickCount();
     }
  }

void InitTradeLog()
  {
   if(Log_File_Name == "") return;
   if(IsTesting()) g_fullLogPath = Log_File_Name + "_BackTest.log";
   else { MqlDateTime dt; TimeLocal(dt); g_fullLogPath = StringFormat("%s_%02d%02d%02d.log", Log_File_Name, dt.year%100, dt.mon, dt.day); }
   int h = FileOpen(g_fullLogPath, FILE_WRITE|FILE_TXT); if(h != INVALID_HANDLE) { FileWrite(h, "=== EA Log ==="); FileClose(h); }
  }

void WriteToLog(string t)
  {
   if(g_fullLogPath == "") return;
   int h = FileOpen(g_fullLogPath, FILE_READ|FILE_WRITE|FILE_TXT|FILE_SHARE_WRITE);
   if(h != INVALID_HANDLE) { FileSeek(h, 0, SEEK_END); FileWrite(h, "[" + TimeToStr(TimeCurrent()) + "] " + t); FileClose(h); }
  }

void SyncGridState()
  {
   datetime lb = 0, ls = 0;
   for(int i = 0; i < OrdersTotal(); i++)
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
        {
         if(OrderType() == OP_BUY) { g_buyGridLevel++; if(OrderOpenTime() > lb) { g_buyBasePrice = OrderOpenPrice(); lb = OrderOpenTime(); } }
         if(OrderType() == OP_SELL) { g_sellGridLevel++; if(OrderOpenTime() > ls) { g_sellBasePrice = OrderOpenPrice(); ls = OrderOpenTime(); } }
        }
  }

void InitHATrend() { UpdateHASignals(); double ho = g_haOpen[1], hc = g_haClose[1]; g_prevHaTrend = (g_execTradeMode == DIR_TREND) ? (hc > ho ? 1 : -1) : (hc > ho ? -1 : 1); }
