//+------------------------------------------------------------------+
//|                                              HA_Adaptive_EA.mq4 |
//|                                                             Andy |
//|                     基於 Heiken Ashi 的趨勢追蹤與全局獲利回跌系統 |
//+------------------------------------------------------------------+
#property copyright "Andy"
#property link      ""
#property version   "1.51"

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
input  ENUM_TRADE_DIRECTION Trade_Mode    = DIR_TREND;            // 趨勢過濾模式 (順勢/逆勢)

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
   Print("=== HA Adaptive EA v1.51 啟動 (Canvas UI 遷移版) ===");

// --- 初始化日誌 ---
   InitTradeLog();

// --- 初始化專業面板 ---
   if(UI_Panel_Enabled)
     {
      g_panel.Init("HA_UI_", 20, 20, 1);
      g_panel.SetEAVersion("1.51");
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
// 1. 執行單次帳戶掃描 (效能核心：每個價格跳動點僅執行一次訂單遍歷)
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
//| 核心演算法：Heiken Ashi 運算                                      |
//+------------------------------------------------------------------+
void GetHeikenAshiNoRepaint(int shift, double &haOpen, double &haClose)
  {
   int lookback = 50;
   int startIdx = shift + lookback;
   if(startIdx >= iBars(NULL, HA_TimeFrame))
      startIdx = iBars(NULL, HA_TimeFrame) - 1;
   double curHAOpen  = iOpen(NULL, HA_TimeFrame, startIdx);
   double curHAClose = iClose(NULL, HA_TimeFrame, startIdx);
   for(int i = startIdx - 1; i >= shift; i--)
     {
      double prevHAOpen  = curHAOpen;
      double prevHAClose = curHAClose;
      curHAOpen = (prevHAOpen + prevHAClose) / 2.0;
      curHAClose = (iOpen(NULL, HA_TimeFrame, i) + iHigh(NULL, HA_TimeFrame, i) + iLow(NULL, HA_TimeFrame, i) + iClose(NULL, HA_TimeFrame, i)) / 4.0;
     }
   haOpen = curHAOpen;
   haClose = curHAClose;
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
   double ho = 0, hc = 0;
   GetHeikenAshiNoRepaint(1, ho, hc);
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
   int t = OrderSend(Symbol(), type, lot, p, 3, 0, 0, "HA_v1.51", Magic_Number, 0, (type == OP_BUY ? clrBlue : clrRed));
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
      FileWrite(h, "=== HA Adaptive EA v1.51 Log ===");
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
   double ho=0, hc=0;
   GetHeikenAshiNoRepaint(1, ho, hc);
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
