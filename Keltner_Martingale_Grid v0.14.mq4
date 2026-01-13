//+------------------------------------------------------------------+
//|                                    Keltner_Martingale_Grid_EA.mq4 |
//|                                                             Andy |
//|                     基於 Keltner 通道的馬丁網格與順勢反馬丁適應性策略 |
//+------------------------------------------------------------------+
#property copyright "Andy"
#property link      ""
#property version   "1.17"
#property strict

//+------------------------------------------------------------------+
//| 枚舉定義                                                          |
//+------------------------------------------------------------------+
enum ENUM_MARKET_MODE 
{ 
   MARKET_RANGING,      // 震盪模式 (逆勢馬丁)
   MARKET_TRENDING      // 趨勢模式 (順勢反馬丁)
};

//+------------------------------------------------------------------+
//| 輸入參數                                                          |
//+------------------------------------------------------------------+
sinput string  Section_1                  = "----------------";   // Keltner 通道參數
input  int     Keltner_Period             = 13;                   // Keltner EMA 週期
input  int     Keltner_ATR                = 13;                   // Keltner ATR 週期
input  double  Keltner_Multi              = 2.0;                  // Keltner 倍數

sinput string  Section_2                  = "----------------";   // ADX/ATR 過濾參數
input  int     ADX_Period                 = 14;                   // ADX 週期
input  double  ADX_Max                    = 25.0;                 // ADX 最大值 (低於此值為震盪)
input  int     ATR_Period                 = 14;                   // ATR 週期
input  double  ATR_Min                    = 0.0005;               // ATR 最小值 (高於此值才交易)

sinput string  Section_3                  = "----------------";   // 震盪網格參數 (Martingale)
input  double  Grid_Step_Pips             = 250;                  // 網格間距 (點數)
input  int     Max_Grid_Levels            = 15;                   // 最大網格層數
input  double  Initial_Lot                = 0.01;                 // 初始手數
input  double  Martingale_Multi           = 1.5;                  // 馬丁倍數 (逆勢)

sinput string  Section_4                  = "----------------";   // 趨勢加碼參數 (Anti-Martingale)
input  double  Trend_Lot_Multi            = 1.2;                  // 順勢加碼倍數
input  double  Trend_TS_Pips              = 200;                  // 趨勢模式移動止盈點數

sinput string  Section_5                  = "----------------";   // 全局動態出場參數
input  double  Total_Profit_Target        = 10.0;                 // 總獲利門檻 (金額)
input  double  Profit_Retracement_Pct     = 25.0;                 // 獲利回跌百分比 (%)

sinput string  Section_6                  = "----------------";   // 風險管理參數
input  double  Profit_Exit                = 1.0;                  // 趨勢轉變時的平倉門檻
input  double  Max_Spread                 = 30;                   // 最大點差 (10點=1Pips)
input  int     Magic_Number               = 16888888;             // 魔術碼

//+------------------------------------------------------------------+
//| 全域變數                                                          |
//+------------------------------------------------------------------+
double            g_gridStepPrice;                                // 網格間距 (價格)
double            g_upperBand, g_lowerBand, g_middleLine;         // Keltner 指標
double            g_adxValue, g_atrValue;                         // 過濾指標
int               g_buyGridCount            = 0;                  // 買單網格計數
int               g_sellGridCount           = 0;                  // 賣單網格計數
ENUM_MARKET_MODE  g_currentMode             = MARKET_RANGING;     // 當前市場模式
ENUM_MARKET_MODE  g_lastMode                = MARKET_RANGING;     // 上一次市場模式
double            g_peakTotalProfit         = 0;                  // 帳戶紀錄最高總獲利

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_gridStepPrice = Grid_Step_Pips * Point * 10;
   Print("=== Keltner 適應性網格 EA v1.17 啟動 ===");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdateIndicators();
   CountGridOrders();
   
   ManageGlobalExit();

   g_lastMode = g_currentMode;
   g_currentMode = (g_adxValue >= ADX_Max) ? MARKET_TRENDING : MARKET_RANGING;

   if(g_lastMode == MARKET_RANGING && g_currentMode == MARKET_TRENDING)
   {
      HandleTrendTransition();
   }

   if(((Ask - Bid) / Point) > Max_Spread * 10) return;

   if(g_currentMode == MARKET_RANGING)
      ManageRangingGrid();
   else
      ManageTrendingGrid();

   DisplayInfo();
}

//+------------------------------------------------------------------+
//| 全局盈虧監控                                                      |
//+------------------------------------------------------------------+
void ManageGlobalExit()
{
   double currentProfit = 0;
   int    totalOrders   = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
         {
            currentProfit += OrderProfit() + OrderSwap() + OrderCommission();
            totalOrders++;
         }
      }
   }

   if(totalOrders == 0)
   {
      g_peakTotalProfit = 0;
      return;
   }

   if(currentProfit >= Total_Profit_Target)
   {
      if(currentProfit > g_peakTotalProfit) g_peakTotalProfit = currentProfit;
   }

   if(g_peakTotalProfit >= Total_Profit_Target)
   {
      double limit = g_peakTotalProfit * (1.0 - (Profit_Retracement_Pct / 100.0));
      if(currentProfit <= limit)
      {
         Print("=== 全局獲利回跌平倉 ===");
         CloseAllOrders();
         g_peakTotalProfit = 0;
      }
   }
   
   if(currentProfit <= 0) g_peakTotalProfit = 0;
}

//+------------------------------------------------------------------+
//| 指標更新                                                         |
//+------------------------------------------------------------------+
void UpdateIndicators()
{
   double ema = iMA(Symbol(), 0, Keltner_Period, 0, MODE_EMA, PRICE_CLOSE, 1);
   double atr = iATR(Symbol(), 0, Keltner_ATR, 1);

   g_middleLine = ema;
   g_upperBand  = ema + (Keltner_Multi * atr);
   g_lowerBand  = ema - (Keltner_Multi * atr);
   g_adxValue   = iADX(Symbol(), 0, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
   g_atrValue   = iATR(Symbol(), 0, ATR_Period, 1);
}

//+------------------------------------------------------------------+
//| 處理模式轉換保護                                                  |
//+------------------------------------------------------------------+
void HandleTrendTransition()
{
   double profit = 0;
   double bLots = 0, sLots = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
         {
            profit += OrderProfit() + OrderSwap() + OrderCommission();
            if(OrderType() == OP_BUY)  bLots += OrderLots();
            if(OrderType() == OP_SELL) sLots += OrderLots();
         }
      }
   }

   if(bLots == 0 && sLots == 0) return;

   if(profit >= Profit_Exit)
   {
      Print("模式轉變：全平保護");
      CloseAllOrders();
   }
   else
   {
      Print("模式轉變：鎖倉保護");
      ExecuteHedge(bLots, sLots);
   }
}

//+------------------------------------------------------------------+
//| 震盪模式邏輯 (逆勢馬丁)                                            |
//+------------------------------------------------------------------+
void ManageRangingGrid()
{
   double price = (Ask + Bid) / 2;

   if(price <= g_lowerBand && g_buyGridCount == 0) OpenOrder(OP_BUY, Initial_Lot, "Range_Buy_0");
   if(price >= g_upperBand && g_sellGridCount == 0) OpenOrder(OP_SELL, Initial_Lot, "Range_Sell_0");

   if(g_buyGridCount > 0 && g_buyGridCount < Max_Grid_Levels)
   {
      double lastPrice = GetLastOrderPrice(OP_BUY);
      if(Bid < (lastPrice - g_gridStepPrice))
      {
         double lots = NormalizeDouble(Initial_Lot * MathPow(Martingale_Multi, g_buyGridCount), 2);
         OpenOrder(OP_BUY, lots, "Range_Buy_M_" + IntegerToString(g_buyGridCount));
      }
   }
   
   if(g_sellGridCount > 0 && g_sellGridCount < Max_Grid_Levels)
   {
      double lastPrice = GetLastOrderPrice(OP_SELL);
      if(Ask > (lastPrice + g_gridStepPrice))
      {
         double lots = NormalizeDouble(Initial_Lot * MathPow(Martingale_Multi, g_sellGridCount), 2);
         OpenOrder(OP_SELL, lots, "Range_Sell_M_" + IntegerToString(g_sellGridCount));
      }
   }
}

//+------------------------------------------------------------------+
//| 趨勢模式邏輯 (順勢反馬丁)                                          |
//+------------------------------------------------------------------+
void ManageTrendingGrid()
{
   if(Bid > g_upperBand && g_buyGridCount == 0) OpenOrder(OP_BUY, Initial_Lot, "Trend_Buy_0");
   if(Ask < g_lowerBand && g_sellGridCount == 0) OpenOrder(OP_SELL, Initial_Lot, "Trend_Sell_0");

   if(g_buyGridCount > 0)
   {
      double lastPrice = GetLastOrderPrice(OP_BUY);
      if(Bid > (lastPrice + g_gridStepPrice)) 
      {
         double lots = NormalizeDouble(Initial_Lot * MathPow(Trend_Lot_Multi, g_buyGridCount), 2);
         OpenOrder(OP_BUY, lots, "Trend_Buy_A_" + IntegerToString(g_buyGridCount));
      }
   }

   if(g_sellGridCount > 0)
   {
      double lastPrice = GetLastOrderPrice(OP_SELL);
      if(Ask < (lastPrice - g_gridStepPrice)) 
      {
         double lots = NormalizeDouble(Initial_Lot * MathPow(Trend_Lot_Multi, g_sellGridCount), 2);
         OpenOrder(OP_SELL, lots, "Trend_Sell_A_" + IntegerToString(g_sellGridCount));
      }
   }
}

//+------------------------------------------------------------------+
//| 輔助函數：開倉 (徹底移除 TP 邏輯)                                    |
//+------------------------------------------------------------------+
void OpenOrder(int type, double lots, string comment)
{
   double price = (type == OP_BUY) ? Ask : Bid;
   // 徹底移除單筆 TP：將 tp 設為 0，確保訂單不帶有任何硬性止盈
   int ticket = OrderSend(Symbol(), type, lots, price, 3, 0, 0, comment, Magic_Number, 0, (type == OP_BUY ? clrBlue : clrRed));
   if(ticket < 0) 
   {
      Print("開倉失敗, Ticket: ", ticket, " 錯誤代碼: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| 輔助函數：全平倉                                                  |
//+------------------------------------------------------------------+
void CloseAllOrders()
{
   bool allClosed = false;
   int  retries = 3;

   while(!allClosed && retries > 0)
   {
      allClosed = true;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         {
            if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
            {
               bool res = false;
               RefreshRates();
               if(OrderType() == OP_BUY)  res = OrderClose(OrderTicket(), OrderLots(), Bid, 10, clrWhite);
               if(OrderType() == OP_SELL) res = OrderClose(OrderTicket(), OrderLots(), Ask, 10, clrWhite);
               
               if(!res) 
               {
                  allClosed = false;
                  Print("平倉失敗 Ticket: ", OrderTicket(), " 錯誤: ", GetLastError());
               }
            }
         }
      }
      if(!allClosed) { retries--; Sleep(200); }
   }
}

//+------------------------------------------------------------------+
//| 輔助函數：鎖倉對沖                                                |
//+------------------------------------------------------------------+
void ExecuteHedge(double bLots, double sLots)
{
   double netLots = NormalizeDouble(bLots - sLots, 2);
   if(MathAbs(netLots) < 0.01) return;
   
   int ticket = -1;
   if(netLots > 0) ticket = OrderSend(Symbol(), OP_SELL, netLots, Bid, 3, 0, 0, "Hedge_Lock", Magic_Number, 0, clrYellow);
   else            ticket = OrderSend(Symbol(), OP_BUY, MathAbs(netLots), Ask, 3, 0, 0, "Hedge_Lock", Magic_Number, 0, clrYellow);
   
   if(ticket < 0)
   {
      Print("鎖倉失敗, 錯誤: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| 輔助函數：獲取最後一筆價格                                          |
//+------------------------------------------------------------------+
double GetLastOrderPrice(int type)
{
   double lastP = 0; datetime lastT = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number && OrderType() == type)
         {
            if(OrderOpenTime() > lastT) { lastT = OrderOpenTime(); lastP = OrderOpenPrice(); }
         }
      }
   }
   return lastP;
}

//+------------------------------------------------------------------+
//| 輔助函數：統計網格層數                                              |
//+------------------------------------------------------------------+
void CountGridOrders()
{
   g_buyGridCount = 0; g_sellGridCount = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
         {
            if(OrderType() == OP_BUY) g_buyGridCount++;
            if(OrderType() == OP_SELL) g_sellGridCount++;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 顯示面板資訊                                                      |
//+------------------------------------------------------------------+
void DisplayInfo()
{
   double currentProfit = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
         {
            currentProfit += OrderProfit() + OrderSwap() + OrderCommission();
         }
      }
   }

   string modeS = (g_currentMode == MARKET_TRENDING) ? "趨勢模式 (順向加碼)" : "震盪模式 (馬丁網格)";
   string msg   = "=== Keltner 適應性網格 EA v1.17 ===\n" +
                  "當前模式: " + modeS + "\n" +
                  "ADX 數值: " + DoubleToStr(g_adxValue, 2) + "\n" +
                  "買單層數: " + IntegerToString(g_buyGridCount) + " | 賣單層數: " + IntegerToString(g_sellGridCount) + "\n" +
                  "----------------------------------\n" +
                  "當前總盈虧: " + DoubleToStr(currentProfit, 2) + "\n" +
                  "獲利最高點: " + DoubleToStr(g_peakTotalProfit, 2) + "\n" +
                  "平倉目標點: " + (g_peakTotalProfit >= Total_Profit_Target ? DoubleToStr(g_peakTotalProfit * (1.0 - Profit_Retracement_Pct/100.0), 2) : "尚未達標");
   Comment(msg);
}
