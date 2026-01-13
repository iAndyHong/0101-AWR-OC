//+------------------------------------------------------------------+
//|                                              HA_Adaptive_EA.mq4 |
//|                                                             Andy |
//|                     基於 Heiken Ashi 的趨勢追蹤與全局獲利回跌系統 |
//+------------------------------------------------------------------+
#property copyright "Andy"
#property link      ""
#property version   "1.30"

//+------------------------------------------------------------------+
//| 枚舉定義                                                          |
//+------------------------------------------------------------------+
enum ENUM_MARTINGALE_TYPE
  {
   MODE_MARTINGALE    = 0, // 馬丁 (虧損加倍)
   MODE_ANTI_MARTY    = 1  // 反馬丁 (獲利加倍)
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

//+------------------------------------------------------------------+
//| 全域變數                                                          |
//+------------------------------------------------------------------+
datetime          g_lastBarTime             = 0;
double            g_peakTotalProfit         = 0;
string            g_uiPrefix                = "HA_UI_";
string            g_sessionPrefix           = "HA_Profit_";
string            g_fullLogPath             = "";     // 完整日誌路徑

// --- 趨勢反轉偵測與網格重置變數 ---
int               g_prevHaTrend             = 0;      // 上一次的 HA 趨勢 (0:無, 1:多, -1:空)
double            g_buyBasePrice            = 0;      // 買單網格參考點
double            g_sellBasePrice           = 0;      // 賣單網格參考點
int               g_buyGridLevel            = 0;      // 買單目前網格層數
int               g_sellGridLevel           = 0;      // 賣單目前網格層數

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("=== HA Adaptive EA v1.30 啟動 (穩定性增強版) ===");
   CreateUI();

   // --- 系統日誌初始化 ---
   if(Log_File_Name != "")
     {
      string baseName = Log_File_Name;
      string ext = "";
      int dotPos = StringFind(Log_File_Name, ".", 0);
      if(dotPos >= 0)
        {
         baseName = StringSubstr(Log_File_Name, 0, dotPos);
         ext = StringSubstr(Log_File_Name, dotPos);
        }

      if(IsTesting())
        {
         g_fullLogPath = baseName + "_BackTest" + ext;
         int h = FileOpen(g_fullLogPath, FILE_WRITE|FILE_TXT|FILE_SHARE_READ);
         if(h != INVALID_HANDLE)
           {
            FileWrite(h, "=== HA Adaptive EA BackTest Log ===");
            FileClose(h);
           }
        }
      else
        {
         MqlDateTime dt;
         TimeToStruct(TimeLocal(), dt);
         string ts = StringFormat("%02d%02d%02d_%02d%02d%02d", dt.year % 100, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
         g_fullLogPath = baseName + "_" + ts + ext;
        }
      
      string header = "=== 系統啟動參數設定 ===\n";
      header += StringFormat("Trade_Mode: %d (%s)\n", Trade_Mode, (Trade_Mode==0?"順勢":"逆勢"));
      header += StringFormat("Martin_Type: %d (%s)\n", Martin_Type, (Martin_Type==0?"馬丁":"反馬丁"));
      header += StringFormat("Initial_Lot: %.2f\n", Initial_Lot);
      header += StringFormat("Lot_Multiplier: %.2f\n", Lot_Multiplier);
      header += StringFormat("Grid_Distance_Pips: %d\n", Grid_Distance_Pips);
      header += StringFormat("Distance_Multiplier: %.2f\n", Distance_Multiplier);
      header += StringFormat("Total_Profit_Target: %.2f\n", Total_Profit_Target);
      header += StringFormat("Profit_Retracement_Pct: %.2f\n", Profit_Retracement_Pct);
      header += StringFormat("Magic_Number: %d\n", Magic_Number);
      header += StringFormat("Max_Spread: %d\n", Max_Spread);
      header += "=========================";
      WriteToLog(header);
     }

   // --- 網格狀態自動同步 (防止重啟失效) ---
   g_buyGridLevel = 0; g_sellGridLevel = 0;
   g_buyBasePrice = 0; g_sellBasePrice = 0;
   datetime lastBuyTime = 0, lastSellTime = 0;
   
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
           {
            if(OrderType() == OP_BUY)
              {
               g_buyGridLevel++;
               if(OrderOpenTime() > lastBuyTime)
                 {
                  g_buyBasePrice = OrderOpenPrice();
                  lastBuyTime = OrderOpenTime();
                 }
              }
            if(OrderType() == OP_SELL)
              {
               g_sellGridLevel++;
               if(OrderOpenTime() > lastSellTime)
                 {
                  g_sellBasePrice = OrderOpenPrice();
                  lastSellTime = OrderOpenTime();
                 }
              }
           }
        }
     }
   if(g_buyGridLevel > 0) Print("同步買單狀態：層級 ", g_buyGridLevel, " 基準價 ", g_buyBasePrice);
   if(g_sellGridLevel > 0) Print("同步賣單狀態：層級 ", g_sellGridLevel, " 基準價 ", g_sellBasePrice);

   // 初始化趨勢狀態
   double ho=0, hc=0;
   GetHeikenAshiNoRepaint(1, ho, hc);
   bool isBull = (hc > ho);
   bool isBear = (hc < ho);
   
   if(Trade_Mode == DIR_TREND)
     {
      if(isBull) g_prevHaTrend = 1;
      if(isBear) g_prevHaTrend = -1;
     }
   else
     {
      if(isBull) g_prevHaTrend = -1;
      if(isBear) g_prevHaTrend = 1;
     }
     
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   Print("EA 已停止。");
  }

void OnTick()
  {
   ManageGlobalExit();
   
   // 網格加碼檢測 (Tick-based: 確保格距精準度)
   ExecuteGridCheck();

   if(Time[0] != g_lastBarTime)
     {
      // 趨勢進場檢測 (Bar-based: 遵循 HA 趨勢)
      ExecuteBarEntry();
      g_lastBarTime = Time[0];
     }
   UpdateUI();
  }

void GetHeikenAshiNoRepaint(int shift, double &haOpen, double &haClose)
  {
   int lookback = 50;
   int startIdx = shift + lookback;
   if(startIdx >= Bars) startIdx = Bars - 1;
   double curHAOpen  = iOpen(NULL, 0, startIdx);
   double curHAClose = iClose(NULL, 0, startIdx);
   for(int i = startIdx - 1; i >= shift; i--)
     {
      double prevHAOpen  = curHAOpen;
      double prevHAClose = curHAClose;
      curHAOpen = (prevHAOpen + prevHAClose) / 2.0;
      curHAClose = (iOpen(NULL, 0, i) + iHigh(NULL, 0, i) + iLow(NULL, 0, i) + iClose(NULL, 0, i)) / 4.0;
     }
   haOpen  = curHAOpen;
   haClose = curHAClose;
  }

//+------------------------------------------------------------------+
//| 網格加碼檢測 (Tick-based)                                         |
//+------------------------------------------------------------------+
void ExecuteGridCheck()
  {
   int bCount = 0, sCount = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
           {
            if(OrderType() == OP_BUY) bCount++;
            if(OrderType() == OP_SELL) sCount++;
           }
        }
     }

   if(bCount > 0) CheckAndSendGridOrder(OP_BUY);
   if(sCount > 0) CheckAndSendGridOrder(OP_SELL);
  }

void ExecuteBarEntry()
  {
   if(((Ask - Bid) / Point) > Max_Spread * 10) return;
   double ho = 0, hc = 0;
   GetHeikenAshiNoRepaint(1, ho, hc);
   bool isBull = (hc > ho);
   bool isBear = (hc < ho);
   int haTrend = 0;
   if(Trade_Mode == DIR_TREND) { if(isBull) haTrend = 1; if(isBear) haTrend = -1; }
   else { if(isBull) haTrend = -1; if(isBear) haTrend = 1; }
   if(haTrend == 0) return;

   int buyCount = 0, sellCount = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
           {
            if(OrderType() == OP_BUY) buyCount++;
            if(OrderType() == OP_SELL) sellCount++;
           }
        }
     }

   if(haTrend != g_prevHaTrend)
     {
      if(haTrend == 1 && buyCount == 0) { g_buyBasePrice = Ask; g_buyGridLevel = 0; }
      if(haTrend == -1 && sellCount == 0) { g_sellBasePrice = Bid; g_sellGridLevel = 0; }
      g_prevHaTrend = haTrend;
     }

   if(haTrend == 1)
     {
      if(buyCount == 0)
        {
         g_buyBasePrice = Ask; g_buyGridLevel = 0;
         SendOrder(OP_BUY, Initial_Lot, "HA趨勢首單", Grid_Distance_Pips, 1.0, 1.0);
         g_buyGridLevel++;
        }
     }
   if(haTrend == -1)
     {
      if(sellCount == 0)
        {
         g_sellBasePrice = Bid; g_sellGridLevel = 0;
         SendOrder(OP_SELL, Initial_Lot, "HA趨勢首單", Grid_Distance_Pips, 1.0, 1.0);
         g_sellGridLevel++;
        }
     }
  }

void CheckAndSendGridOrder(int type)
  {
   int currentLevel = (type == OP_BUY) ? g_buyGridLevel : g_sellGridLevel;
   double basePrice = (type == OP_BUY) ? g_buyBasePrice : g_sellBasePrice;
   
   // 計算目前層級應用的手數倍率 (首單為 1.0, 之後為 Lot_Multiplier 的次方)
   double currentLotMult = MathPow(Lot_Multiplier, currentLevel);
   double nextLot = Initial_Lot * currentLotMult;
   nextLot = NormalizeDouble(nextLot, 2);
   
   // 計算格距
   double currentDistMult = MathPow(Distance_Multiplier, currentLevel - 1);
   double currentDist = Grid_Distance_Pips * currentDistMult;
   double step = currentDist * 10 * Point;

   if(type == OP_BUY)
     {
      if(Martin_Type == MODE_MARTINGALE)
        {
         if(Bid <= NormalizeDouble(basePrice - step, Digits))
           {
            SendOrder(OP_BUY, nextLot, StringFormat("網格加碼(層級:%d)", g_buyGridLevel), currentDist, currentDistMult, currentLotMult);
            g_buyGridLevel++; g_buyBasePrice = Bid;
           }
        }
      else
        {
         if(Bid >= NormalizeDouble(basePrice + step, Digits))
           {
            SendOrder(OP_BUY, nextLot, StringFormat("網格加碼(層級:%d)", g_buyGridLevel), currentDist, currentDistMult, currentLotMult);
            g_buyGridLevel++; g_buyBasePrice = Bid;
           }
        }
     }
   else if(type == OP_SELL)
     {
      if(Martin_Type == MODE_MARTINGALE)
        {
         if(Ask >= NormalizeDouble(basePrice + step, Digits))
           {
            SendOrder(OP_SELL, nextLot, StringFormat("網格加碼(層級:%d)", g_sellGridLevel), currentDist, currentDistMult, currentLotMult);
            g_sellGridLevel++; g_sellBasePrice = Ask;
           }
        }
      else
        {
         if(Ask <= NormalizeDouble(basePrice - step, Digits))
           {
            SendOrder(OP_SELL, nextLot, StringFormat("網格加碼(層級:%d)", g_sellGridLevel), currentDist, currentDistMult, currentLotMult);
            g_sellGridLevel++; g_sellBasePrice = Ask;
           }
        }
     }
  }

void SendOrder(int type, double lot, string reason, double currentDist = 0, double currentDistMult = 0, double currentLotMult = 0)
  {
   double price = (type == OP_BUY) ? Ask : Bid;
   color col = (type == OP_BUY) ? clrBlue : clrRed;
   string typeStr = (type == OP_BUY) ? "BUY" : "SELL";
   int ticket = OrderSend(Symbol(), type, lot, price, 3, 0, 0, "HA_Grid_v1.3", Magic_Number, 0, col);
   if(ticket > 0) 
     {
      // 依據要求加註：格距 / 格距放大倍率 / 手數 / 放大倍率
      string detail = StringFormat(", 格距: %.1f, 格距放大倍率: %.2f, 手數: %.2f, 手數放大倍率: %.2f", 
                                   currentDist, currentDistMult, lot, currentLotMult);
      WriteToLog(StringFormat("進場 [%s]: %s, 價格: %.5f, 原因: %s%s", 
                 typeStr, Symbol(), price, reason, detail));
     }
   else Print("網格開倉失敗: ", GetLastError());
  }

void ManageGlobalExit()
  {
   double currentProfit = 0; int totalOrders = 0;
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
   if(totalOrders == 0) { g_peakTotalProfit = 0; return; }
   if(currentProfit >= Total_Profit_Target) { if(currentProfit > g_peakTotalProfit) g_peakTotalProfit = currentProfit; }
   if(g_peakTotalProfit >= Total_Profit_Target)
     {
      double limit = g_peakTotalProfit * (1.0 - (Profit_Retracement_Pct / 100.0));
      // 修正：必須同時滿足「低於回跌點」且「目前盈虧仍大於起始獲利目標」
      // 避免在行情瞬間跳空導致總盈虧大幅縮水時，錯誤觸發結算而導致虧損或獲利過低
      if(currentProfit <= limit && currentProfit >= Total_Profit_Target)
        {
         Print("=== 觸發智慧結算平倉 (獲利回跌鎖定) ===");
         SmartHedgeClose();
         g_peakTotalProfit = 0;
        }
     }
  }

void SmartHedgeClose()
  {
   double totalSettlement = 0;
   datetime closeTime = TimeCurrent(); 
   double closePrice = Bid;
   
   Print("=== 執行快速結算平倉 ===");
   
   // 使用快速直接平倉循環，減少滑價與對沖成本
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
           {
            int tkt = OrderTicket();
            double lots = OrderLots();
            double p = OrderProfit() + OrderSwap() + OrderCommission();
            
            RefreshRates();
            bool res = false;
            if(OrderType() == OP_BUY) res = OrderClose(tkt, lots, Bid, 10, clrWhite);
            if(OrderType() == OP_SELL) res = OrderClose(tkt, lots, Ask, 10, clrWhite);
            
            if(res)
              {
               totalSettlement += p;
               WriteToLog(StringFormat("出場 [結算]: Ticket #%d, 盈虧: %.2f", tkt, p));
              }
            else
              {
               Print("結算平倉失敗 Ticket: ", tkt, " 錯誤: ", GetLastError());
              }
           }
        }
     }
   
   CreateProfitTextAtPrice(totalSettlement, closeTime, closePrice);
   WriteToLog(StringFormat("出場 [全局結算完成]: 總結算盈虧: %.2f, 峰值盈虧: %.2f, 回跌點: %.2f", 
              totalSettlement, g_peakTotalProfit, (g_peakTotalProfit * (1.0 - (Profit_Retracement_Pct / 100.0)))));
  }

void RecursiveCloseBy() { } // 棄用

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

void UpdateUI()
  {
   double curProfit = 0; int bCount = 0, sCount = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
           {
            curProfit += OrderProfit() + OrderSwap() + OrderCommission();
            if(OrderType() == OP_BUY) bCount++;
            if(OrderType() == OP_SELL) sCount++;
           }
        }
     }
   SetLabel(0, "=== HA 適應性系統 v1.30 ===");
   SetLabel(1, "模式: " + (Trade_Mode == DIR_TREND ? "順勢" : "逆勢"));
   SetLabel(2, "持倉: 買單[" + IntegerToString(bCount) + "] / 賣單[" + IntegerToString(sCount) + "]");
   SetLabel(3, "--------------------------------");
   SetLabel(4, "當前總盈虧: " + DoubleToStr(curProfit, 2));
   SetLabel(5, "獲利最高點: " + DoubleToStr(g_peakTotalProfit, 2));
   string targetStr = (g_peakTotalProfit >= Total_Profit_Target) ? DoubleToStr(g_peakTotalProfit * (1.0 - Profit_Retracement_Pct/100.0), 2) : "未達標";
   SetLabel(6, "全平觸發點: " + targetStr);
   string logStatus = (g_fullLogPath != "") ? "運作中" : "未開啟";
   SetLabel(7, "日誌狀態: " + logStatus);
  }

void SetLabel(int index, string text)
  {
   string name = g_uiPrefix + IntegerToString(index);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
  }

void WriteToLog(string text)
  {
   if(g_fullLogPath == "") return;
   int h = FileOpen(g_fullLogPath, FILE_READ|FILE_WRITE|FILE_TXT|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h != INVALID_HANDLE)
     {
      FileSeek(h, 0, SEEK_END);
      FileWrite(h, "[" + TimeToStr(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "] " + text);
      FileClose(h);
     }
  }
