//+------------------------------------------------------------------+
//|                                    Keltner_Martingale_Grid_EA.mq4 |
//|                                                             Andy |
//|                                      基於 Keltner 通道的馬丁網格策略 |
//+------------------------------------------------------------------+
#property copyright "Andy"
#property link      ""
#property version   "1.00"
#property strict

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
input string  Section3        = "========== 網格交易參數 ==========";
input double  Grid_Step_Pips  = 250;                                       // 網格間距（點數）
input int     Max_Grid_Levels = 99;                                         // 最大網格層數
input string  Section4        = "========== 馬丁參數 ==========";
input double  Initial_Lot     = 0.01;                                      // 初始手數
input double  Martingale_Multi= 1.5;                                       // 馬丁倍數
input string  Section5        = "========== 風險管理參數 ==========";
input double  TP_Pips         = 10;                                        // 止盈點數
input double  Max_Spread      = 300;                                        // 最大點差
input int     Magic_Number    = 16888888;                                  // 魔術碼

//--- 全域變數
double        grid_step_price;                                             // 網格間距（價格）
double        upper_band;                                                  // Keltner 上軌
double        lower_band;                                                  // Keltner 下軌
double        middle_line;                                                 // Keltner 中軌
double        adx_value;                                                   // ADX 數值
double        atr_value;                                                   // ATR 數值
int           buy_grid_count  = 0;                                         // 買單網格計數
int           sell_grid_count = 0;                                         // 賣單網格計數

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
// 計算網格間距
   grid_step_price = Grid_Step_Pips * Point * 10;

   Print("=== Keltner 馬丁網格 EA 已啟動 ===");
   Print("帳戶貨幣: ", AccountCurrency(), " | 初始保證金: ", DoubleToStr(AccountBalance(), 2));
   Print("網格間距: ", Grid_Step_Pips, " 點 | 最大層數: ", Max_Grid_Levels, " | 馬丁倍數: ", DoubleToStr(Martingale_Multi, 2));

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("EA 已停止，原因代碼: ", reason);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
// 更新指標數值
   UpdateIndicators();

// 檢查是否為震盪行情
   if(!IsRangingMarket())
     {
      return; // 不是震盪行情，不進場
     }

// 更新網格計數
   CountGridOrders();

// 檢查點差
   double spread = (Ask - Bid) / Point;
   if(spread > Max_Spread)
     {
      return; // 點差過大，不交易
     }

// 網格交易邏輯
   ManageGridTrades();

// 顯示即時資訊
   DisplayInfo();
  }

//+------------------------------------------------------------------+
//| 更新指標數值                                                       |
//+------------------------------------------------------------------+
void UpdateIndicators()
  {
// 計算 Keltner 通道
   double ema    = iMA(Symbol(), 0, Keltner_Period, 0, MODE_EMA, PRICE_CLOSE, 1);
   double atr    = iATR(Symbol(), 0, Keltner_ATR, 1);

   middle_line   = ema;
   upper_band    = ema + (Keltner_Multi * atr);
   lower_band    = ema - (Keltner_Multi * atr);

// 計算 ADX
   adx_value     = iADX(Symbol(), 0, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);

// 計算 ATR
   atr_value     = iATR(Symbol(), 0, ATR_Period, 1);
  }

//+------------------------------------------------------------------+
//| 判斷是否為震盪行情                                                 |
//+------------------------------------------------------------------+
bool IsRangingMarket()
  {
// ADX 低於閾值 = 弱趨勢/震盪
   bool adx_filter = (adx_value < ADX_Max);

// ATR 高於最小值 = 有足夠波動
   bool atr_filter = (atr_value > ATR_Min);

   return (adx_filter && atr_filter);
  }

//+------------------------------------------------------------------+
//| 統計網格訂單數量                                                   |
//+------------------------------------------------------------------+
void CountGridOrders()
  {
   buy_grid_count  = 0;
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
//| 網格交易管理                                                       |
//+------------------------------------------------------------------+
void ManageGridTrades()
  {
   double current_price = (Ask + Bid) / 2;

// 價格觸碰下軌 → 開啟買單網格
   if(current_price <= lower_band && buy_grid_count == 0)
     {
      OpenGridOrder(OP_BUY);
     }

// 價格觸碰上軌 → 開啟賣單網格
   if(current_price >= upper_band && sell_grid_count == 0)
     {
      OpenGridOrder(OP_SELL);
     }

// 管理現有網格訂單
   ManageExistingGrid();
  }

//+------------------------------------------------------------------+
//| 開啟網格訂單                                                       |
//+------------------------------------------------------------------+
void OpenGridOrder(int order_type)
  {
   double price, sl, tp;
   int    ticket;
   double lots = Initial_Lot;

   if(order_type == OP_BUY)
     {
      price = Ask;
      sl    = 0; // 馬丁策略不設止損
      tp    = price + (TP_Pips * Point * 10);

      ticket = OrderSend(Symbol(), OP_BUY, lots, price, 3, sl, tp,
                         "Keltner_Grid_Buy_0", Magic_Number, 0, clrBlue);

      if(ticket > 0)
        {
         Print("開啟買單網格 #", ticket, " | 價格: ", DoubleToStr(price, Digits), " | 手數: ", DoubleToStr(lots, 2));
        }
     }
   else
      if(order_type == OP_SELL)
        {
         price = Bid;
         sl    = 0; // 馬丁策略不設止損
         tp    = price - (TP_Pips * Point * 10);

         ticket = OrderSend(Symbol(), OP_SELL, lots, price, 3, sl, tp,
                            "Keltner_Grid_Sell_0", Magic_Number, 0, clrRed);

         if(ticket > 0)
           {
            Print("開啟賣單網格 #", ticket, " | 價格: ", DoubleToStr(price, Digits), " | 手數: ", DoubleToStr(lots, 2));
           }
        }
  }

//+------------------------------------------------------------------+
//| 管理現有網格（馬丁加倉）                                           |
//+------------------------------------------------------------------+
void ManageExistingGrid()
  {
// 檢查買單網格
   if(buy_grid_count > 0 && buy_grid_count < Max_Grid_Levels)
     {
      double last_buy_price = GetLastOrderPrice(OP_BUY);

      if(last_buy_price > 0 && Bid < (last_buy_price - grid_step_price))
        {
         // 計算馬丁手數
         double new_lots = Initial_Lot * MathPow(Martingale_Multi, buy_grid_count);
         new_lots = NormalizeDouble(new_lots, 2);

         double tp = Bid + (TP_Pips * Point * 10);

         string comment = "Keltner_Grid_Buy_" + IntegerToString(buy_grid_count);
         int ticket = OrderSend(Symbol(), OP_BUY, new_lots, Ask, 3, 0, tp,
                                comment, Magic_Number, 0, clrBlue);

         if(ticket > 0)
           {
            Print("馬丁加倉買單 #", ticket, " | 層數: ", buy_grid_count, " | 手數: ", DoubleToStr(new_lots, 2));
           }
        }
     }

// 檢查賣單網格
   if(sell_grid_count > 0 && sell_grid_count < Max_Grid_Levels)
     {
      double last_sell_price = GetLastOrderPrice(OP_SELL);

      if(last_sell_price > 0 && Ask > (last_sell_price + grid_step_price))
        {
         // 計算馬丁手數
         double new_lots = Initial_Lot * MathPow(Martingale_Multi, sell_grid_count);
         new_lots = NormalizeDouble(new_lots, 2);

         double tp = Ask - (TP_Pips * Point * 10);

         string comment = "Keltner_Grid_Sell_" + IntegerToString(sell_grid_count);
         int ticket = OrderSend(Symbol(), OP_SELL, new_lots, Bid, 3, 0, tp,
                                comment, Magic_Number, 0, clrRed);

         if(ticket > 0)
           {
            Print("馬丁加倉賣單 #", ticket, " | 層數: ", sell_grid_count, " | 手數: ", DoubleToStr(new_lots, 2));
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| 取得最後訂單價格                                                   |
//+------------------------------------------------------------------+
double GetLastOrderPrice(int order_type)
  {
   double last_price = 0;
   datetime last_time = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() &&
            OrderMagicNumber() == Magic_Number &&
            OrderType() == order_type)
           {
            if(OrderOpenTime() > last_time)
              {
               last_time  = OrderOpenTime();
               last_price = OrderOpenPrice();
              }
           }
        }
     }

   return last_price;
  }

//+------------------------------------------------------------------+
//| 顯示即時資訊                                                       |
//+------------------------------------------------------------------+
void DisplayInfo()
  {
   string info = "";
   double profit_percent = 0;

   if(AccountBalance() > 0)
     {
      profit_percent = (AccountProfit() / AccountBalance() * 100);
     }

   info += "======= Keltner 馬丁網格 EA =======\n";
   info += "帳戶餘額: " + DoubleToStr(AccountBalance(), 2) + " " + AccountCurrency() + "\n";
   info += "帳戶淨值: " + DoubleToStr(AccountEquity(), 2) + " " + AccountCurrency() + "\n";
   info += "浮動盈虧: " + DoubleToStr(AccountProfit(), 2) + " " + AccountCurrency() + " (" + DoubleToStr(profit_percent, 2) + "%)\n";
   info += "-----------------------------------\n";
   info += "Keltner 上軌: " + DoubleToStr(upper_band, Digits) + "\n";
   info += "Keltner 中軌: " + DoubleToStr(middle_line, Digits) + "\n";
   info += "Keltner 下軌: " + DoubleToStr(lower_band, Digits) + "\n";
   info += "-----------------------------------\n";
   info += "ADX 數值: " + DoubleToStr(adx_value, 2);
   if(adx_value < ADX_Max)
      info += " (震盪)\n";
   else
      info += " (趨勢)\n";

   info += "ATR 數值: " + DoubleToStr(atr_value, 5);
   if(atr_value > ATR_Min)
      info += " (可交易)\n";
   else
      info += " (波動不足)\n";

   info += "市場狀態: ";
   if(IsRangingMarket())
      info += "震盪行情 ✓\n";
   else
      info += "趨勢行情 ✗\n";

   info += "-----------------------------------\n";
   info += "買單網格: " + IntegerToString(buy_grid_count) + " 層 | 賣單網格: " + IntegerToString(sell_grid_count) + " 層\n";

   Comment(info);
  }
//+------------------------------------------------------------------+
