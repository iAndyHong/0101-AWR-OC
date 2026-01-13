//+------------------------------------------------------------------+
//|                                              HA_Adaptive_EA.mq4 |
//|                                                             Andy |
//|                     基於 Heiken Ashi 的趨勢追蹤與全局獲利回跌系統 |
//+------------------------------------------------------------------+
#property copyright "Andy"
#property link      ""
#property version   "1.50"

//+------------------------------------------------------------------+
//| 結構定義                                                          |
//+------------------------------------------------------------------+
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
   double            lastBuyPrice;
   double            lastSellPrice;
   int               totalOrders;
   double            equity;
   double            balance;
   double            marginLevel;
  };

AccountSnapshot g_snapshot;
uint            g_lastUiUpdate = 0;
double          g_maxDrawdown  = 0; // 全局歷史最大虧損紀錄

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

sinput string  Section_6                  = "----------------";   // [圖表箭頭管理]
input  bool    Arrow_Manager_Enabled      = true;                 // 啟用箭頭管理模組
input  int     Arrow_History_Days         = 3;                    // 歷史箭頭回溯天數
input  int     Arrow_Update_Seconds       = 10;                   // 實盤更新頻率 (秒)
input  color   Arrow_Buy_Live             = clrOrangeRed;         // 持倉買單顏色
input  color   Arrow_Sell_Live            = clrLightGreen;        // 持倉賣單顏色
input  color   Arrow_Buy_Hist             = clrMaroon;            // 歷史買單顏色
input  color   Arrow_Sell_Hist            = clrDarkGreen;         // 歷史賣單顏色

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

// --- 箭頭管理類別定義 (ULTRAWORK 修正版) ---
class CTradeArrowManager
  {
private:
   uint              m_lastUpdateTime;

public:
                     CTradeArrowManager() : m_lastUpdateTime(0) {}

   void              Update()
     {
      if(!Arrow_Manager_Enabled)
         return;

      // 無論實盤或回測，統一每秒檢查一次 (GetTickCount 控制)
      // 確保視覺化回測時能即時渲染
      if(GetTickCount() - m_lastUpdateTime < 1000)
         return;
      m_lastUpdateTime = GetTickCount();

      ProcessArrows();
     }

   void              ProcessArrows()
     {
      datetime limitTime = TimeCurrent() - (Arrow_History_Days * 24 * 3600);

      for(int i = ObjectsTotal() - 1; i >= 0; i--)
        {
         string name = ObjectName(i);
         int type = (int)ObjectGetInteger(0, name, OBJPROP_TYPE);

         // 僅處理箭頭與趨勢線
         if(type != OBJ_ARROW && type != OBJ_TREND)
            continue;

         // 判斷是否為 MT4 交易物件 (通常包含 # 號)
         if(StringFind(name, "#", 0) < 0)
            continue;

         datetime objTime = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME1);
         if(objTime < limitTime)
            continue;

         // A. 所有交易物件強制設為背景
         ObjectSetInteger(0, name, OBJPROP_BACK, true);

         // B. 針對箭頭進行樣式與顏色優化
         if(type == OBJ_ARROW)
           {
            // 將樣式改為圓圈 (108)
            ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 108);
            ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);

            color liveCol = (color)CLR_NONE;
            color histCol = (color)CLR_NONE;
            bool isBuy = false;
            bool isHedge = (StringFind(name, "Hedge_Lock", 0) >= 0);

            // 從物件名稱判斷類型 (買/賣)
            if(StringFind(name, "buy", 0) >= 0)
              {
               isBuy = true;
               liveCol = Arrow_Buy_Live;
               histCol = Arrow_Buy_Hist;
              }
            else
               if(StringFind(name, "sell", 0) >= 0)
                 {
                  isBuy = false;
                  liveCol = Arrow_Sell_Live;
                  histCol = Arrow_Sell_Hist;
                 }

            // 實作對沖顏色反轉邏輯
            if(isHedge)
              {
               if(isBuy)
                 {
                  liveCol = Arrow_Sell_Live;
                  histCol = Arrow_Sell_Hist;
                 }
               else
                 {
                  liveCol = Arrow_Buy_Live;
                  histCol = Arrow_Buy_Hist;
                 }
              }

            if(liveCol != (color)CLR_NONE)
              {
               if(IsOrderLive(name))
                  ObjectSetInteger(0, name, OBJPROP_COLOR, liveCol);
               else
                  ObjectSetInteger(0, name, OBJPROP_COLOR, histCol);
              }
           }

         // C. 針對趨勢線 (開平倉連結線) 優化
         if(type == OBJ_TREND)
           {
            ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
            ObjectSetInteger(0, name, OBJPROP_COLOR, clrDimGray);
           }
        }
     }

private:
   bool              IsOrderLive(string name)
     {
      for(int i = 0; i < OrdersTotal(); i++)
        {
         if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
           {
            if(StringFind(name, IntegerToString(OrderTicket()), 0) >= 0)
               return true;
           }
        }
      return false;
     }
  };

CTradeArrowManager g_arrowMgr;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("=== HA Adaptive EA v1.50 啟動 (UI 撥亂反正版) ===");

// 徹底清理所有相關物件
   ObjectsDeleteAll(0, g_uiPrefix);

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
         int hL1 = FileOpen(g_fullLogPath, FILE_WRITE|FILE_TXT|FILE_SHARE_READ);
         if(hL1 != INVALID_HANDLE)
           {
            FileWrite(hL1, "=== HA Adaptive EA v1.41 BackTest Log ===");
            FileClose(hL1);
           }
        }
      else
        {
         MqlDateTime dt;
         TimeToStruct(TimeLocal(), dt);
         string ts = StringFormat("%02d%02d%02d_%02d%02d%02d", dt.year % 100, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
         g_fullLogPath = baseName + "_" + ts + ext;

         int hL2 = FileOpen(g_fullLogPath, FILE_WRITE|FILE_TXT|FILE_SHARE_READ);
         if(hL2 != INVALID_HANDLE)
           {
            FileWrite(hL2, "=== HA Adaptive EA v1.41 Live Log ===");
            FileClose(hL2);
           }
        }

      // 寫入啟動參數，並包含版本資訊作為首段紀錄
      string header = "=========================================\n";
      header += "=== 系統啟動參數設定 (版本: v1.50) ===\n";
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
   g_buyGridLevel = 0;
   g_sellGridLevel = 0;
   g_buyBasePrice = 0;
   g_sellBasePrice = 0;
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
   if(g_buyGridLevel > 0)
      Print("同步買單狀態：層級 ", g_buyGridLevel, " 基準價 ", g_buyBasePrice);
   if(g_sellGridLevel > 0)
      Print("同步賣單狀態：層級 ", g_sellGridLevel, " 基準價 ", g_sellBasePrice);

// 初始化趨勢狀態
   double ho=0, hc=0;
   GetHeikenAshiNoRepaint(1, ho, hc);
   bool isBull = (hc > ho);
   bool isBear = (hc < ho);

   if(Trade_Mode == DIR_TREND)
     {
      if(isBull)
         g_prevHaTrend = 1;
      if(isBear)
         g_prevHaTrend = -1;
     }
   else
     {
      if(isBull)
         g_prevHaTrend = -1;
      if(isBear)
         g_prevHaTrend = 1;
     }

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("EA 已停止。");
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
  {
// 1. 執行單次帳戶掃描 (效能核心)
   UpdateAccountSnapshot();

// 2. 圖表箭頭管理 (CTradeArrowManager)
   g_arrowMgr.Update();

// 3. 全局出場監控 (基於快照)
   ManageGlobalExit();

// 3. 網格加碼檢測 (Tick-based: 基於快照數據)
   ExecuteGridCheck();

// 4. HA 趨勢首單檢測 (Bar-based)
   if(Time[0] != g_lastBarTime)
     {
      ExecuteBarEntry();
      g_lastBarTime = Time[0];
     }

// 5. UI 更新 (節流控制: 500ms)
   if(GetTickCount() - g_lastUiUpdate > 500)
     {
      UpdateUI();
      g_lastUiUpdate = GetTickCount();
     }
  }

//+------------------------------------------------------------------+
//| 更新帳戶快照 (ULTRAWORK 優化：全系統僅此一處循環訂單)               |
//+------------------------------------------------------------------+
void UpdateAccountSnapshot()
  {
   ZeroMemory(g_snapshot);
   datetime lastBTime = 0, lastSTime = 0;
   double buyTotalValue = 0, sellTotalValue = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
           {
            double p = OrderProfit() + OrderSwap() + OrderCommission();
            g_snapshot.totalProfit += p;
            g_snapshot.totalOrders++;

            if(OrderType() == OP_BUY)
              {
               g_snapshot.buyCount++;
               g_snapshot.buyLots += OrderLots();
               g_snapshot.buyProfit += p;
               buyTotalValue += OrderOpenPrice() * OrderLots();
               if(OrderOpenTime() > lastBTime)
                 {
                  g_snapshot.lastBuyPrice = OrderOpenPrice();
                  lastBTime = OrderOpenTime();
                 }
              }
            if(OrderType() == OP_SELL)
              {
               g_snapshot.sellCount++;
               g_snapshot.sellLots += OrderLots();
               g_snapshot.sellProfit += p;
               sellTotalValue += OrderOpenPrice() * OrderLots();
               if(OrderOpenTime() > lastSTime)
                 {
                  g_snapshot.lastSellPrice = OrderOpenPrice();
                  lastSTime = OrderOpenTime();
                 }
              }
           }
        }
     }

// 計算加權均價
   if(g_snapshot.buyLots > 0)
      g_snapshot.buyAvgPrice = buyTotalValue / g_snapshot.buyLots;
   if(g_snapshot.sellLots > 0)
      g_snapshot.sellAvgPrice = sellTotalValue / g_snapshot.sellLots;

// 更新帳戶核心指標
   g_snapshot.equity = AccountEquity();
   g_snapshot.balance = AccountBalance();
   g_snapshot.marginLevel = (AccountMargin() > 0) ? (AccountEquity() / AccountMargin() * 100.0) : 0;

// 紀錄最大虧損
   if(g_snapshot.totalProfit < g_maxDrawdown)
      g_maxDrawdown = g_snapshot.totalProfit;
  }

//+------------------------------------------------------------------+
//|                                                                  |
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
   haOpen  = curHAOpen;
   haClose = curHAClose;
  }

//+------------------------------------------------------------------+

//| 網格加碼檢測 (Tick-based)                                         |
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
   bool isBull = (hc > ho);
   bool isBear = (hc < ho);
   int haTrend = 0;
   if(Trade_Mode == DIR_TREND)
     {
      if(isBull)
         haTrend = 1;
      if(isBear)
         haTrend = -1;
     }
   else
     {
      if(isBull)
         haTrend = -1;
      if(isBear)
         haTrend = 1;
     }
   if(haTrend == 0)
      return;

   int buyCount = g_snapshot.buyCount;
   int sellCount = g_snapshot.sellCount;

// --- 趨勢反轉偵測與重置 (修正：反轉即執行全面重置，無論是否有持倉) ---
   if(haTrend != g_prevHaTrend)
     {
      if(haTrend == 1)
        {
         g_buyBasePrice = Ask;
         g_buyGridLevel = 0;
         WriteToLog(StringFormat("趨勢反轉(多)：強制重置基準價為 %.5f，層級歸零", g_buyBasePrice));
        }
      if(haTrend == -1)
        {
         g_sellBasePrice = Bid;
         g_sellGridLevel = 0;
         WriteToLog(StringFormat("趨勢反轉(空)：強制重置基準價為 %.5f，層級歸零", g_sellBasePrice));
        }
      g_prevHaTrend = haTrend;
     }

   if(haTrend == 1)
     {
      if(buyCount == 0)
        {
         g_buyBasePrice = Ask;
         g_buyGridLevel = 0;
         SendOrder(OP_BUY, Initial_Lot, "HA趨勢首單", Grid_Distance_Pips, 1.0, 1.0);
         g_buyGridLevel++;
        }
     }
   if(haTrend == -1)
     {
      if(sellCount == 0)
        {
         g_sellBasePrice = Bid;
         g_sellGridLevel = 0;
         SendOrder(OP_SELL, Initial_Lot, "HA趨勢首單", Grid_Distance_Pips, 1.0, 1.0);
         g_sellGridLevel++;
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
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
            g_buyGridLevel++;
            g_buyBasePrice = Bid;
           }
        }
      else
        {
         if(Bid >= NormalizeDouble(basePrice + step, Digits))
           {
            SendOrder(OP_BUY, nextLot, StringFormat("網格加碼(層級:%d)", g_buyGridLevel), currentDist, currentDistMult, currentLotMult);
            g_buyGridLevel++;
            g_buyBasePrice = Bid;
           }
        }
     }
   else
      if(type == OP_SELL)
        {
         if(Martin_Type == MODE_MARTINGALE)
           {
            if(Ask >= NormalizeDouble(basePrice + step, Digits))
              {
               SendOrder(OP_SELL, nextLot, StringFormat("網格加碼(層級:%d)", g_sellGridLevel), currentDist, currentDistMult, currentLotMult);
               g_sellGridLevel++;
               g_sellBasePrice = Ask;
              }
           }
         else
           {
            if(Ask <= NormalizeDouble(basePrice - step, Digits))
              {
               SendOrder(OP_SELL, nextLot, StringFormat("網格加碼(層級:%d)", g_sellGridLevel), currentDist, currentDistMult, currentLotMult);
               g_sellGridLevel++;
               g_sellBasePrice = Ask;
              }
           }
        }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
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
   else
      Print("網格開倉失敗: ", GetLastError());
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ManageGlobalExit()
  {
   if(g_snapshot.totalOrders == 0)
     {
      g_peakTotalProfit = 0;
      return;
     }

   double currentProfit = g_snapshot.totalProfit;

// 1. 記錄盈虧峰值 (僅在達到目標門檻後開始記錄)
   if(currentProfit >= Total_Profit_Target)
     {
      if(currentProfit > g_peakTotalProfit)
         g_peakTotalProfit = currentProfit;
     }

// 2. 檢查是否觸發回跌平倉
   if(g_peakTotalProfit >= Total_Profit_Target)
     {
      double limit = g_peakTotalProfit * (1.0 - (Profit_Retracement_Pct / 100.0));

      // 修正：必須滿足「低於回跌點」且「目前盈虧仍大於起始獲利目標」，確保盈利鎖定
      if(currentProfit <= limit && currentProfit >= Total_Profit_Target)
        {
         Print("=== 觸發智慧結算平倉 (獲利回跌鎖定) ===");
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
   double bLots = 0, sLots = 0, totalSettlement = 0;
   datetime closeTime = TimeCurrent();
   double closePrice = Bid;

   Print("=== 執行對沖鎖倉結算演算法 ===");

// 1. 從快照或即時統計淨手數
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

// 2. 執行對沖鎖倉 (Lock Profit)
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

// 3. 執行遞迴對沖平倉演算法
   RecursiveCloseBy();

   CreateProfitTextAtPrice(totalSettlement, closeTime, closePrice);
   WriteToLog(StringFormat("出場 [全局結算完成]: 總結算盈虧: %.2f, 峰值盈虧: %.2f, 回跌點: %.2f",
                           totalSettlement, g_peakTotalProfit, (g_peakTotalProfit * (1.0 - (Profit_Retracement_Pct / 100.0)))));
  }

//+------------------------------------------------------------------+
//| 遞迴對沖平倉 (恢復核心演算法：OrderCloseBy)                         |
//+------------------------------------------------------------------+
void RecursiveCloseBy()
  {
   int buyT = -1, sellT = -1;
// 找出一對多單與空單
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
      // 執行兩兩對沖平倉 (節省點差)
      if(OrderCloseBy(buyT, sellT, clrWhite))
         RecursiveCloseBy(); // 成功後繼續遞迴
      else
         RecursiveCloseBy(); // 失敗亦繼續嘗試下一對
     }
   else
     {
      // 處理剩餘單向單
      for(int k = OrdersTotal() - 1; k >= 0; k--)
        {
         if(OrderSelect(k, SELECT_BY_POS, MODE_TRADES))
           {
            if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number)
              {
               double p = OrderProfit() + OrderSwap() + OrderCommission();
               int tkt = OrderTicket();
               bool r = false;
               if(OrderType() == OP_BUY)
                  r = OrderClose(tkt, OrderLots(), Bid, 3, clrWhite);
               if(OrderType() == OP_SELL)
                  r = OrderClose(tkt, OrderLots(), Ask, 3, clrWhite);
               if(r)
                  WriteToLog(StringFormat("出場 [清理訂單]: Ticket #%d, 盈虧: %.2f", tkt, p));
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
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
//|                                                                  |
//+------------------------------------------------------------------+
void CreateUI()
  {
// 定義每一欄的中心位置 (對標截圖中的比例，單位：像素)
   int x_base = 20;  // 持倉類型
   int x_col1 = 80; // 均價
   int x_col2 = 150; // 盈虧
   int x_col3 = 200; // 手數
   int x_col4 = 250; // 筆數

   for(int i=0; i<15; i++)
     {
      // 第 0 欄：左對齊標籤
      CreateCell(i, 0, x_base, CORNER_LEFT_UPPER, ALIGN_LEFT);

      // 第 1~4 欄：右對齊標籤 (數值欄位)
      CreateCell(i, 1, x_col1, CORNER_LEFT_UPPER, ALIGN_RIGHT);
      CreateCell(i, 2, x_col2, CORNER_LEFT_UPPER, ALIGN_RIGHT);
      CreateCell(i, 3, x_col3, CORNER_LEFT_UPPER, ALIGN_RIGHT);
      CreateCell(i, 4, x_col4, CORNER_LEFT_UPPER, ALIGN_RIGHT);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void UpdateUI()
  {
// 取得當前商品小數點精度
   int prcDig = Digits;

// --- 區塊 1：標頭對齊 ---
   SetCell(1, 0, "持倉類型");
   SetCell(1, 1, "均價");
   SetCell(1, 2, "盈虧");
   SetCell(1, 3, "手數");
   SetCell(1, 4, "筆數");

// --- 區塊 2：多頭數據 (紅正綠負) ---
   color bPClr = (g_snapshot.buyProfit >= 0) ? clrRed : clrLime;
   SetCell(2, 0, "多頭", bPClr);
   SetCell(2, 1, DoubleToStr(g_snapshot.buyAvgPrice, prcDig), bPClr);
   SetCell(2, 2, DoubleToStr(g_snapshot.buyProfit, 2), bPClr);
   SetCell(2, 3, DoubleToStr(g_snapshot.buyLots, 2), bPClr);
   SetCell(2, 4, IntegerToString(g_snapshot.buyCount), bPClr);

// --- 區塊 3：空頭數據 (紅正綠負) ---
   color sPClr = (g_snapshot.sellProfit >= 0) ? clrRed : clrLime;
   SetCell(3, 0, "空頭", sPClr);
   SetCell(3, 1, DoubleToStr(g_snapshot.sellAvgPrice, prcDig), sPClr);
   SetCell(3, 2, DoubleToStr(g_snapshot.sellProfit, 2), sPClr);
   SetCell(3, 3, DoubleToStr(g_snapshot.sellLots, 2), sPClr);
   SetCell(3, 4, IntegerToString(g_snapshot.sellCount), sPClr);

// --- 區塊 4：合計數據 (紅正綠負) ---
   color tPClr = (g_snapshot.totalProfit >= 0) ? clrRed : clrLime;
   SetCell(4, 0, "合計", tPClr);
   SetCell(4, 1, "-------", tPClr);
   SetCell(4, 2, DoubleToStr(g_snapshot.totalProfit, 2), tPClr);
   SetCell(4, 3, DoubleToStr(g_snapshot.buyLots + g_snapshot.sellLots, 2), tPClr);
   SetCell(4, 4, IntegerToString(g_snapshot.totalOrders), tPClr);


   SetCell(5, 0, "----------------------------------------------------------------------------------");

// --- 區塊 5：紀錄與風控 (左對齊) ---
   SetCell(6, 0, StringFormat("最高獲利: %.2f / 最大虧損: %.2f", g_peakTotalProfit, g_maxDrawdown));
   string targetStr = (g_peakTotalProfit >= Total_Profit_Target) ? DoubleToStr(g_peakTotalProfit * (1.0 - Profit_Retracement_Pct/100.0), 2) : "未達標";
   SetCell(7, 0, "獲利回跌結算點: " + targetStr);

// --- 區塊 6：保證金與帳務 ---
   SetCell(8, 0, StringFormat("保證金水平: %.1f%%", g_snapshot.marginLevel));
   SetCell(9, 0, StringFormat("餘額: %.2f / 淨值: %.2f", g_snapshot.balance, g_snapshot.equity));

// --- 區塊 7：系統資訊 ---
   SetCell(10, 0, "----------------------------------------------------------------------------------");
   SetCell(11, 0, "目前趨勢模式: " + (Trade_Mode == DIR_TREND ? "順勢" : "逆勢"));
   string logStat = (g_fullLogPath != "") ? "運作中" : "未開啟";
   SetCell(12, 0, "交易日誌紀錄: " + logStat);

// 隱藏剩餘標籤
   for(int r=13; r<15; r++)
      for(int c=0; c<5; c++)
         SetCell(r, c, "");
  }

// --- 輔助函數：建立單元格標籤 (支援對齊設定) ---
void CreateCell(int row, int col, int x, int corner, int align)
  {
   string name = g_uiPrefix + IntegerToString(row) + "_" + IntegerToString(col);
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 20 + (row * 18));
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrGold);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, name, OBJPROP_ALIGN, align);
      ObjectSetString(0, name, OBJPROP_TEXT, "");
     }
  }

// --- 輔助函數：更新單元格文字 ---
void SetCell(int row, int col, string text, color clr = clrGold)
  {
   string name = g_uiPrefix + IntegerToString(row) + "_" + IntegerToString(col);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
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
//|                                                                  |
//+------------------------------------------------------------------+
void WriteToLog(string text)
  {
   if(g_fullLogPath == "")
      return;
   int h = FileOpen(g_fullLogPath, FILE_READ|FILE_WRITE|FILE_TXT|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h != INVALID_HANDLE)
     {
      FileSeek(h, 0, SEEK_END);
      FileWrite(h, "[" + TimeToStr(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "] " + text);
      FileClose(h);
     }
  }
//+------------------------------------------------------------------+
