//+------------------------------------------------------------------+
//|                                    Keltner_Martingale_Grid_EA.mq4 |
//|                                                             Andy |
//|                     基於 Keltner 通道的馬丁網格與順勢反馬丁適應性策略 |
//+------------------------------------------------------------------+
#property copyright "Andy"
#property link      ""
#property version   "1.13"
#property strict

//--- 枚舉定義
enum ENUM_MARKET_MODE
  {
   MARKET_RANGING,   // 震盪模式 (逆勢馬丁)
   MARKET_TRENDING   // 趨勢模式 (順勢反馬丁)
  };

//--- 輸入參數
input string  Section1        = "========== Keltner 通道參數 ==========";
input int     Keltner_Period  = 13;                                        // Keltner EMA 週期
input int     Keltner_ATR     = 13;                                        // Keltner ATR 週期
input double  Keltner_Multi   = 2.0;                                       // Keltner 倍數

input string  Section2        = "========== ADX/ATR 過濾參數 ==========";
input int     ADX_Period      = 14;                                        // ADX 週期
input double  ADX_Max         = 25.0;                                      // ADX 最大值（低於此值為震盪）
input int     ATR_Period      = 14;                                        // ATR 週期
input double  ATR_Min         = 0.0005;                                    // ATR 最小值（高於此值才交易）

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
input string  Section3        = "========== 震盪網格參數 (Martingale) ==========";
input double  Grid_Step_Pips  = 250;                                       // 網格間距（點數）
input int     Max_Grid_Levels = 15;                                        // 最大網格層數
input double  Initial_Lot     = 0.01;                                      // 初始手數
input double  Martingale_Multi= 1.5;                                       // 馬丁倍數 (逆勢)

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
input string  Section4        = "========== 趨勢加碼參數 (Anti-Martingale) ==========";
input double  Trend_Lot_Multi = 1.2;                                       // 順勢加碼倍數
input double  Trend_TS_Pips   = 200;                                       // 趨勢模式移動止盈點數

input string  Section5        = "========== 風險管理參數 ==========";
input double  TP_Pips         = 100;                                       // 基礎止盈點數
input double  Profit_Exit     = 1.0;                                       // 趨勢轉變時的獲利平倉門檻
input double  Max_Spread      = 30;                                        // 最大點差
input int     Magic_Number    = 16888888;                                  // 魔術碼

//--- 全域變數
double        grid_step_price;                                             // 網格間距（價格）
double        upper_band, lower_band, middle_line;                         // Keltner 指標
double        adx_value, atr_value;                                        // 過濾指標
int           buy_grid_count = 0, sell_grid_count = 0;                     // 網格計數
ENUM_MARKET_MODE current_mode = MARKET_RANGING;                            // 當前市場模式
ENUM_MARKET_MODE last_mode    = MARKET_RANGING;                            // 上一次市場模式

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   grid_step_price = Grid_Step_Pips * Point * 10;
   Print("=== Keltner 適應性網格 EA v1.13 啟動 ===");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   UpdateIndicators();
   CountGridOrders();

// 模式判斷
   last_mode = current_mode;
   current_mode = (adx_value >= ADX_Max) ? MARKET_TRENDING : MARKET_RANGING;

// 檢查模式轉變：從震盪轉向趨勢
   if(last_mode == MARKET_RANGING && current_mode == MARKET_TRENDING)
     {
      HandleTrendTransition();
     }

// 點差檢查
   double spread = (Ask - Bid) / Point;
   if(spread > Max_Spread * 10)
      return;

// 執行對應模式邏輯
   if(current_mode == MARKET_RANGING)
     {
      ManageRangingGrid();  // 逆勢馬丁
     }
   else
     {
      ManageTrendingGrid(); // 順勢反馬丁
     }

   DisplayInfo();
  }

//+------------------------------------------------------------------+
//| 指標更新                                                         |
//+------------------------------------------------------------------+
void UpdateIndicators()
  {
   double ema = iMA(Symbol(), 0, Keltner_Period, 0, MODE_EMA, PRICE_CLOSE, 1);
   double atr = iATR(Symbol(), 0, Keltner_ATR, 1);

   middle_line = ema;
   upper_band  = ema + (Keltner_Multi * atr);
   lower_band  = ema - (Keltner_Multi * atr);
   adx_value   = iADX(Symbol(), 0, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
   atr_value   = iATR(Symbol(), 0, ATR_Period, 1);
  }

//+------------------------------------------------------------------+
//| 處理模式轉換保護 (獲利平倉/虧損鎖倉)                               |
//+------------------------------------------------------------------+
void HandleTrendTransition()
  {
   double total_profit = 0;
   double buy_lots = 0, sell_lots = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
           {
            total_profit += OrderProfit() + OrderSwap() + OrderCommission();
            if(OrderType() == OP_BUY)
               buy_lots += OrderLots();
            if(OrderType() == OP_SELL)
               sell_lots += OrderLots();
           }
        }
     }

   if(buy_lots == 0 && sell_lots == 0)
      return;

   if(total_profit >= Profit_Exit)
     {
      Print("模式轉變：獲利 ", total_profit, "，執行全平倉保護");
      CloseAllOrders();
     }
   else
     {
      Print("模式轉變：虧損中，執行鎖倉保護");
      ExecuteHedge(buy_lots, sell_lots);
     }
  }

//+------------------------------------------------------------------+
//| 震盪模式邏輯 (逆勢馬丁)                                            |
//+------------------------------------------------------------------+
void ManageRangingGrid()
  {
   double current_price = (Ask + Bid) / 2;

// 開啟首單 (逆勢)
   if(current_price <= lower_band && buy_grid_count == 0)
      OpenOrder(OP_BUY, Initial_Lot, "Range_Buy_0");
   if(current_price >= upper_band && sell_grid_count == 0)
      OpenOrder(OP_SELL, Initial_Lot, "Range_Sell_0");

// 加倉邏輯 (逆勢馬丁)
   if(buy_grid_count > 0 && buy_grid_count < Max_Grid_Levels)
     {
      double last_price = GetLastOrderPrice(OP_BUY);
      if(Bid < (last_price - grid_step_price))
        {
         double lots = NormalizeDouble(Initial_Lot * MathPow(Martingale_Multi, buy_grid_count), 2);
         OpenOrder(OP_BUY, lots, "Range_Buy_M_" + IntegerToString(buy_grid_count));
        }
     }

   if(sell_grid_count > 0 && sell_grid_count < Max_Grid_Levels)
     {
      double last_price = GetLastOrderPrice(OP_SELL);
      if(Ask > (last_price + grid_step_price))
        {
         double lots = NormalizeDouble(Initial_Lot * MathPow(Martingale_Multi, sell_grid_count), 2);
         OpenOrder(OP_SELL, lots, "Range_Sell_M_" + IntegerToString(sell_grid_count));
        }
     }
  }

//+------------------------------------------------------------------+
//| 趨勢模式邏輯 (順勢反馬丁)                                          |
//+------------------------------------------------------------------+
void ManageTrendingGrid()
  {
// 開啟首單 (順勢突破)
   if(Bid > upper_band && buy_grid_count == 0)
      OpenOrder(OP_BUY, Initial_Lot, "Trend_Buy_0");
   if(Ask < lower_band && sell_grid_count == 0)
      OpenOrder(OP_SELL, Initial_Lot, "Trend_Sell_0");

// 加倉邏輯 (順勢反馬丁)
   if(buy_grid_count > 0)
     {
      double last_price = GetLastOrderPrice(OP_BUY);
      if(Bid > (last_price + grid_step_price)) // 價格繼續漲，順勢加碼
        {
         double lots = NormalizeDouble(Initial_Lot * MathPow(Trend_Lot_Multi, buy_grid_count), 2);
         OpenOrder(OP_BUY, lots, "Trend_Buy_A_" + IntegerToString(buy_grid_count));
        }
     }

   if(sell_grid_count > 0)
     {
      double last_price = GetLastOrderPrice(OP_SELL);
      if(Ask < (last_price - grid_step_price)) // 價格繼續跌，順勢加碼
        {
         double lots = NormalizeDouble(Initial_Lot * MathPow(Trend_Lot_Multi, sell_grid_count), 2);
         OpenOrder(OP_SELL, lots, "Trend_Sell_A_" + IntegerToString(sell_grid_count));
        }
     }

// 趨勢模式啟用移動止損
   ApplyTrendingTrailingStop();
  }

//+------------------------------------------------------------------+
//| 輔助函數                                                         |
//+------------------------------------------------------------------+
void OpenOrder(int type, double lots, string comment)
  {
   double price = (type == OP_BUY) ? Ask : Bid;
   double tp = (type == OP_BUY) ? (price + TP_Pips * Point * 10) : (price - TP_Pips * Point * 10);
   int ticket = OrderSend(Symbol(), type, lots, price, 3, 0, tp, comment, Magic_Number, 0, (type == OP_BUY ? clrBlue : clrRed));
   if(ticket < 0)
      Print("開倉失敗, 錯誤代碼: ", GetLastError());
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CloseAllOrders()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
           {
            if(OrderType() == OP_BUY)
               OrderClose(OrderTicket(), OrderLots(), Bid, 3, clrWhite);
            if(OrderType() == OP_SELL)
               OrderClose(OrderTicket(), OrderLots(), Ask, 3, clrWhite);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ExecuteHedge(double buy_lots, double sell_lots)
  {
   double net_lots = NormalizeDouble(buy_lots - sell_lots, 2);
   if(MathAbs(net_lots) < 0.01)
      return;

   if(net_lots > 0)
      OrderSend(Symbol(), OP_SELL, net_lots, Bid, 3, 0, 0, "Hedge_Lock", Magic_Number, 0, clrYellow);
   else
      OrderSend(Symbol(), OP_BUY, MathAbs(net_lots), Ask, 3, 0, 0, "Hedge_Lock", Magic_Number, 0, clrYellow);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetLastOrderPrice(int type)
  {
   double last_price = 0;
   datetime last_time = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number && OrderType() == type)
           {
            if(OrderOpenTime() > last_time)
              {
               last_time = OrderOpenTime();
               last_price = OrderOpenPrice();
              }
           }
        }
     }
   return last_price;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CountGridOrders()
  {
   buy_grid_count = 0;
   sell_grid_count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
           {
            if(OrderType() == OP_BUY)
               buy_grid_count++;
            if(OrderType() == OP_SELL)
               sell_grid_count++;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ApplyTrendingTrailingStop()
  {
   double ts_step = Trend_TS_Pips * Point * 10;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
           {
            if(OrderType() == OP_BUY && Bid > OrderOpenPrice() + ts_step)
              {
               double new_sl = Bid - ts_step;
               if(OrderStopLoss() < new_sl)
                  OrderModify(OrderTicket(), OrderOpenPrice(), new_sl, OrderTakeProfit(), 0, clrGreen);
              }
            if(OrderType() == OP_SELL && Ask < OrderOpenPrice() - ts_step)
              {
               double new_sl = Ask + ts_step;
               if(OrderStopLoss() == 0 || OrderStopLoss() > new_sl)
                  OrderModify(OrderTicket(), OrderOpenPrice(), new_sl, OrderTakeProfit(), 0, clrGreen);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DisplayInfo()
  {
   string mode_str = (current_mode == MARKET_TRENDING) ? "趨勢模式 (順向加碼)" : "震盪模式 (馬丁網格)";
   string msg = "=== Keltner 適應性網格 EA ===\n" +
                "當前模式: " + mode_str + "\n" +
                "ADX 數值: " + DoubleToStr(adx_value, 2) + "\n" +
                "買單層數: " + IntegerToString(buy_grid_count) + "\n" +
                "賣單層數: " + IntegerToString(sell_grid_count);
   Comment(msg);
  }
//+------------------------------------------------------------------+
