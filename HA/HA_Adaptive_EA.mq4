//+------------------------------------------------------------------+
//|                                              HA_Adaptive_EA.mq4 |
//|                                                             Andy |
//|                     基於 Heiken Ashi 的趨勢追蹤與全局獲利回跌系統 |
//+------------------------------------------------------------------+
#property copyright "Andy"
#property link      ""
#property version   "1.08"

//+------------------------------------------------------------------+
//| 枚舉定義                                                          |
//+------------------------------------------------------------------+
enum ENUM_TRADE_DIRECTION

  {
   DIR_TREND    = 0,     // 順勢模式 (陽買陰賣)
   DIR_REVERSAL = 1      // 逆勢模式 (陽賣陰買)
  };

enum ENUM_BAR_EXIT_MODE
  {
   EXIT_MIN_LOSS    = 0, // 平掉盈虧 < 0 且虧損最小者
   EXIT_MAX_LOSS    = 1, // 平掉盈虧 < 0 且虧損最大者
   EXIT_MIN_PROFIT  = 2, // 平掉盈虧 > 1 且獲利最小者
   EXIT_MAX_PROFIT  = 3, // 平掉盈虧 > 1 且獲利最大者
   EXIT_OLDEST      = 4  // 平掉最早進場單 (不限盈虧)
  };

//+------------------------------------------------------------------+
//| 輸入參數                                                          |
//+------------------------------------------------------------------+
sinput string  Section_1                  = "----------------";   // Heiken Ashi 設定
input  ENUM_TRADE_DIRECTION Trade_Mode    = DIR_TREND;            // 交易方向模式
input  double  Initial_Lot                = 0.01;                 // 單位進場手數


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
sinput string  Section_3                  = "----------------";   // 出場設定 (K棒限制)
input  int     Max_Bars_Limit             = 99;                   // 最大持有 K 棒數
input  ENUM_BAR_EXIT_MODE Bar_Exit_Type   = EXIT_MIN_PROFIT;      // 超時平倉優先級

sinput string  Section_4                  = "----------------";   // 全局動態出場
input  double  Total_Profit_Target        = 10.0;                 // 獲利監控門檻
input  double  Profit_Retracement_Pct     = 25.0;                 // 獲利回跌百分比

sinput string  Section_5                  = "----------------";   // 風險管理
input  int     Magic_Number               = 168888;               // 魔術碼
input  int     Max_Spread                 = 30;                   // 最大點差限制

//+------------------------------------------------------------------+
//| 全域變數                                                          |
//+------------------------------------------------------------------+
datetime          g_lastBarTime             = 0;
double            g_peakTotalProfit         = 0;
string            g_uiPrefix                = "HA_UI_";
string            g_sessionPrefix           = "HA_Profit_";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("=== HA Adaptive EA v1.08 啟動 (大掃除：純粹不回繪 HA) ===");
   CreateUI();
   return(INIT_SUCCEEDED);
  }


//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("EA 已停止，圖表物件已保留。");
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   ManageGlobalExit();
   if(Time[0] != g_lastBarTime)
     {
      ManageMaxBarExit();
      ExecuteBarEntry();
      g_lastBarTime = Time[0];
     }
   UpdateUI();
  }

//+------------------------------------------------------------------+
//| 計算不回繪的 Heiken Ashi 數值 (採用的演算法來自 HeikenAshi 0.1)     |
//+------------------------------------------------------------------+
void GetHeikenAshiNoRepaint(int shift, double &haOpen, double &haClose)
  {
   // 為了確保數值穩定（不回繪），我們從歷史 K 棒開始遞迴計算
   // 追溯 50 根 K 棒已足夠讓 HA 數值收斂
   int lookback = 50;
   int startIdx = shift + lookback;
   if(startIdx >= Bars) startIdx = Bars - 1;

   // 初始值
   double curHAOpen  = iOpen(NULL, 0, startIdx);
   double curHAClose = iClose(NULL, 0, startIdx);

   // 向前遞迴計算到目標 shift
   for(int i = startIdx - 1; i >= shift; i--)
     {
      double prevHAOpen  = curHAOpen;
      double prevHAClose = curHAClose;

      // HA_Open = (上一個 HA_Open + 上一個 HA_Close) / 2
      curHAOpen = (prevHAOpen + prevHAClose) / 2.0;
      // HA_Close = (O + H + L + C) / 4
      curHAClose = (iOpen(NULL, 0, i) + iHigh(NULL, 0, i) + iLow(NULL, 0, i) + iClose(NULL, 0, i)) / 4.0;
     }

   haOpen  = curHAOpen;
   haClose = curHAClose;
  }

//+------------------------------------------------------------------+
//| 進場邏輯                                                          |
//+------------------------------------------------------------------+
void ExecuteBarEntry()
  {
   if(((Ask - Bid) / Point) > Max_Spread * 10)
      return;

   double haOpen = 0, haClose = 0;
   GetHeikenAshiNoRepaint(1, haOpen, haClose);

   bool isHA_Bullish = (haClose > haOpen);
   bool isHA_Bearish = (haClose < haOpen);


   int orderType = -1;
   if(Trade_Mode == DIR_TREND)
     {
      if(isHA_Bullish)
         orderType = OP_BUY;
      if(isHA_Bearish)
         orderType = OP_SELL;
     }
   else
     {
      if(isHA_Bullish)
         orderType = OP_SELL;
      if(isHA_Bearish)
         orderType = OP_BUY;
     }

   if(orderType != -1)
     {
      double price = (orderType == OP_BUY) ? Ask : Bid;
      int ticket = OrderSend(Symbol(), orderType, Initial_Lot, price, 3, 0, 0, "HA_v106", Magic_Number, 0, (orderType == OP_BUY ? clrBlue : clrRed));
      if(ticket < 0)
         Print("開倉失敗: ", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| 出場邏輯 1：最大 K 棒限制                                         |
//+------------------------------------------------------------------+
void ManageMaxBarExit()
  {
   int ticketToClose = -1;
   double targetValue = 0;
   datetime oldestTime = TimeCurrent();

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
           {
            int barCount = iBarShift(NULL, 0, OrderOpenTime());
            if(barCount >= Max_Bars_Limit)
              {
               double p = OrderProfit() + OrderSwap() + OrderCommission();
               switch(Bar_Exit_Type)
                 {
                  case EXIT_MIN_LOSS:
                     if(p < 0)
                       {
                        if(ticketToClose == -1 || p > targetValue)
                          {
                           targetValue = p;
                           ticketToClose = OrderTicket();
                          }
                       }
                     break;
                  case EXIT_MAX_LOSS:
                     if(p < 0)
                       {
                        if(ticketToClose == -1 || p < targetValue)
                          {
                           targetValue = p;
                           ticketToClose = OrderTicket();
                          }
                       }
                     break;
                  case EXIT_MIN_PROFIT:
                     if(p > 1.0)
                       {
                        if(ticketToClose == -1 || p < targetValue)
                          {
                           targetValue = p;
                           ticketToClose = OrderTicket();
                          }
                       }
                     break;
                  case EXIT_MAX_PROFIT:
                     if(p > 1.0)
                       {
                        if(ticketToClose == -1 || p > targetValue)
                          {
                           targetValue = p;
                           ticketToClose = OrderTicket();
                          }
                       }
                     break;
                  case EXIT_OLDEST:
                     if(OrderOpenTime() < oldestTime)
                       {
                        oldestTime = OrderOpenTime();
                        ticketToClose = OrderTicket();
                       }
                     break;
                 }
              }
           }
        }
     }

   if(ticketToClose != -1)
     {
      if(OrderSelect(ticketToClose, SELECT_BY_TICKET))
        {
         bool res = false;
         RefreshRates();
         if(OrderType() == OP_BUY)
            res = OrderClose(OrderTicket(), OrderLots(), Bid, 10, clrGray);
         if(OrderType() == OP_SELL)
            res = OrderClose(OrderTicket(), OrderLots(), Ask, 10, clrGray);
         if(!res)
            Print("K棒限制平倉失敗: ", GetLastError());
        }
     }
  }

//+------------------------------------------------------------------+
//| 出場邏輯 2：全局盈虧監控                                          |
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
      if(currentProfit > g_peakTotalProfit)
         g_peakTotalProfit = currentProfit;
     }

   if(g_peakTotalProfit >= Total_Profit_Target)
     {
      double limit = g_peakTotalProfit * (1.0 - (Profit_Retracement_Pct / 100.0));
      if(currentProfit <= limit)
        {
         Print("=== 觸發智慧結算平倉 ===");
         SmartHedgeClose();
         g_peakTotalProfit = 0;
        }
     }
  }

//+------------------------------------------------------------------+
//| 智慧對沖平倉                                                      |
//+------------------------------------------------------------------+
void SmartHedgeClose()
  {
   double bLots = 0, sLots = 0;
   double totalSettlement = 0;
   datetime closeTime = TimeCurrent();
   double closePrice = Bid;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
           {
            totalSettlement += OrderProfit() + OrderSwap() + OrderCommission();
            if(OrderType() == OP_BUY)
               bLots += OrderLots();
            if(OrderType() == OP_SELL)
               sLots += OrderLots();
           }
        }
     }

   double netLots = NormalizeDouble(bLots - sLots, 2);
   if(MathAbs(netLots) >= 0.01)
     {
      RefreshRates();
      int t = -1;
      if(netLots > 0)
         t = OrderSend(Symbol(), OP_SELL, netLots, Bid, 3, 0, 0, "Hedge_Lock", Magic_Number, 0, clrYellow);
      else
         t = OrderSend(Symbol(), OP_BUY, MathAbs(netLots), Ask, 3, 0, 0, "Hedge_Lock", Magic_Number, 0, clrYellow);

      if(t > 0 && OrderSelect(t, SELECT_BY_TICKET))
         totalSettlement += OrderProfit() + OrderSwap() + OrderCommission();
      else
         if(t < 0)
            Print("對沖鎖單失敗: ", GetLastError());
     }

   RecursiveCloseBy();
   CreateProfitTextAtPrice(totalSettlement, closeTime, closePrice);
  }

//+------------------------------------------------------------------+
//| 遞迴對沖平倉 (嚴格檢查返回值)                                       |
//+------------------------------------------------------------------+
void RecursiveCloseBy()
  {
   int buyT = -1, sellT = -1;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
           {
            if(OrderType() == OP_BUY && buyT == -1)
               buyT = OrderTicket();
            if(OrderType() == OP_SELL && sellT == -1)
               sellT = OrderTicket();
           }
        }
      if(buyT != -1 && sellT != -1)
         break;
     }

   if(buyT != -1 && sellT != -1)
     {
      bool resCB = OrderCloseBy(buyT, sellT, clrWhite);
      if(resCB)
         RecursiveCloseBy();
      else
        {
         bool rb = false, rs = false;
         if(OrderSelect(buyT, SELECT_BY_TICKET))
            rb = OrderClose(buyT, OrderLots(), Bid, 3, clrWhite);
         if(OrderSelect(sellT, SELECT_BY_TICKET))
            rs = OrderClose(sellT, OrderLots(), Ask, 3, clrWhite);
         RecursiveCloseBy();
        }
     }
    else
      {
       for(int k = OrdersTotal() - 1; k >= 0; k--)
         {
          if(OrderSelect(k, SELECT_BY_POS, MODE_TRADES))
            {
             if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
               {
                bool r = false;
                if(OrderType() == OP_BUY)
                   r = OrderClose(OrderTicket(), OrderLots(), Bid, 3, clrWhite);
                if(OrderType() == OP_SELL)
                   r = OrderClose(OrderTicket(), OrderLots(), Ask, 3, clrWhite);
                if(!r)
                   Print("清理殘留訂單失敗 Ticket: ", OrderTicket(), " 錯誤: ", GetLastError());
               }
            }
         }
      }

  }

//+------------------------------------------------------------------+
//| 建立盈虧標籤                                                      |
//+------------------------------------------------------------------+
void CreateProfitTextAtPrice(double profit, datetime time, double price)
  {
   string objName = g_sessionPrefix + IntegerToString((int)time);
   color  col = (profit >= 0) ? clrOrangeRed : clrLime;
   string text = "結算: " + DoubleToStr(profit, 2);

   if(ObjectCreate(0, objName, OBJ_TEXT, 0, time, price))
     {
      ObjectSetString(0, objName, OBJPROP_TEXT, text);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, col);
      ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 12);
      ObjectSetString(0, objName, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
     }
  }

//+------------------------------------------------------------------+
//| UI 相關函數                                                       |
//+------------------------------------------------------------------+
void CreateUI()
  {
   for(int i=0; i<8; i++)
     {
      string name = g_uiPrefix + IntegerToString(i);
      if(ObjectFind(0, name) < 0)
        {
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 20);
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 20 + (i * 20));
         ObjectSetInteger(0, name, OBJPROP_COLOR, clrGold);
         ObjectSetString(0, name, OBJPROP_FONT, "Arial");
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void UpdateUI()
  {
   double curProfit = 0;
   int bCount = 0, sCount = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
           {
            curProfit += OrderProfit() + OrderSwap() + OrderCommission();
            if(OrderType() == OP_BUY)
               bCount++;
            if(OrderType() == OP_SELL)
               sCount++;
           }
        }
     }

   SetLabel(0, "=== HA 適應性系統 v1.08 ===");

   SetLabel(1, "模式: " + (Trade_Mode == DIR_TREND ? "順勢" : "逆勢"));
   SetLabel(2, "持倉: 買單[" + IntegerToString(bCount) + "] / 賣單[" + IntegerToString(sCount) + "]");
   SetLabel(3, "--------------------------------");
   SetLabel(4, "當前總盈虧: " + DoubleToStr(curProfit, 2));
   SetLabel(5, "獲利最高點: " + DoubleToStr(g_peakTotalProfit, 2));
   string targetStr = (g_peakTotalProfit >= Total_Profit_Target) ? DoubleToStr(g_peakTotalProfit * (1.0 - Profit_Retracement_Pct/100.0), 2) : "未達標";
   SetLabel(6, "全平觸發點: " + targetStr);
   SetLabel(7, "--------------------------------");
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SetLabel(int index, string text)
  {
   string name = g_uiPrefix + IntegerToString(index);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
  }
//+------------------------------------------------------------------+
