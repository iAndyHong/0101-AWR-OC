//+------------------------------------------------------------------+
//| CGridsCore.mqh
//| 網格交易核心模組 v2.4
//+------------------------------------------------------------------+
//| 【模組說明 - 供 Kiro AI 讀取】
//|
//| 功能：網格交易核心模組，包含網格邏輯和信號計算
//|       不包含 UI、箭頭、獲利追蹤等功能（由 CEACore 統一管理）
//|
//| 設計原則：
//|   - 處理網格交易核心邏輯
//|   - 內建信號計算（BullsBears、SuperTrend、Heiken Ashi、Simple）
//|   - 透過事件通知外部模組（平倉獲利等）
//|   - 不直接操作 UI 或其他輔助功能
//|   - 平倉透過回調請求外部執行（支援對沖平倉）
//|   - 支援獨立縮放設定（間距/手數，順向/逆向分開，0=不縮放）
//|
//| 引用方式：#include "../Libs/GridsCore/CGridsCore_v2.3.mqh"
//+------------------------------------------------------------------+

#ifndef CGRIDSCORE_V22_MQH
#define CGRIDSCORE_V22_MQH

#property copyright "Recovery System"
#property version   "2.40"
#property strict

//+------------------------------------------------------------------+
//| 常數定義
//+------------------------------------------------------------------+
#ifndef SIGNAL_BUY
#define SIGNAL_BUY                1
#endif
#ifndef SIGNAL_SELL
#define SIGNAL_SELL              -1
#endif
#ifndef SIGNAL_NEUTRAL
#define SIGNAL_NEUTRAL            0
#endif

// 引用 CEACore 的 OrderStats 結構定義（假設在同一專案環境下）
#include "../EACore/CEACore_v2.3.mqh"

// 引用子模組
#include "../HedgeClose/CHedgeClose.mqh"

//+------------------------------------------------------------------+
//| 網格模式枚舉
//+------------------------------------------------------------------+
enum ENUM_GRID_MODE
  {
   GRID_MODE_TREND   = 0,        // 順向網格（順勢加倉）
   GRID_MODE_COUNTER = 1         // 逆向網格（逆勢加倉）
  };

enum ENUM_TRADE_DIRECTION
  {
   TRADE_BOTH      = 0,          // 雙向交易
   TRADE_BUY_ONLY  = 1,          // 只買
   TRADE_SELL_ONLY = 2           // 只賣
  };

enum ENUM_FILTER_MODE
  {
   FILTER_BULLSBEARS = 0,        // BullsBears Candles
   FILTER_SUPERTREND = 1,        // Super Trend
   FILTER_HeikenAshi = 2,        // Heiken Ashi
   FILTER_SIMPLE     = 3         // Simple Grids (無過濾)
  };

enum ENUM_SIGNAL_MODE
  {
   SIGNAL_MODE_TREND    = 0,     // 趨勢方向內持續開單
   SIGNAL_MODE_REVERSAL = 1,     // 只在趨勢反轉時開單
   SIGNAL_MODE_DISABLED = 2      // 不使用趨勢過濾開單
  };

enum ENUM_AVERAGING_MODE
  {
   AVERAGING_ANY      = 0,       // 任意方向加倉
   AVERAGING_TREND    = 1,       // 僅順勢時加倉
   AVERAGING_DISABLED = 2        // 不使用趨勢過濾加倉
  };

struct GridsCoreConfig
  {
   int               magicNumber;
   string            symbol;
   int               slippage;
   string            logFile;
   ENUM_GRID_MODE    gridMode;
   double            gridStep;
   double            initialLots;
   int               maxGridLevels;
   double            takeProfit;
   bool              oneOrderPerBar;
   double            counterGridScaling;
   double            counterLotScaling;
   double            trendGridScaling;
   double            trendLotScaling;
   ENUM_TRADE_DIRECTION tradeDirection;
   int               maxOrdersInWork;
   double            maxSpread;
   double            maxLots;
   ENUM_FILTER_MODE  filterMode;
   int               filterTimeframe;
   int               bbLookbackBars;
   double            bbThreshold;
   int               stAtrPeriod;
   double            stMultiplier;
   ENUM_SIGNAL_MODE  stSignalMode;
   ENUM_AVERAGING_MODE stAveragingMode;
   bool              stShowLine;
   color             stBullColor;
   color             stBearColor;
   // Heiken Ashi 參數
   int               heikenMaPeriod;     // Heiken Ashi 平滑週期
   ENUM_MA_METHOD    heikenMaMethod;     // Heiken Ashi 平滑方法
   double            heikenThreshold;    // Heiken Ashi 趨勢確認閾值（已不使用）
   ENUM_SIGNAL_MODE  heikenSignalMode;   // Heiken Ashi 信號模式（趨勢/反轉/無）
   ENUM_AVERAGING_MODE heikenAveragingMode; // Heiken Ashi 加倉模式
   bool              showDebugLogs;
  };

typedef void (*OnCloseCallback)(double profit, datetime time, double price);
typedef double (*OnRequestCloseCallback)(void);

class CGridsCore
  {
private:
   GridsCoreConfig   m_config;
   CHedgeClose       m_hedgeClose;     // 新增：對沖平倉組件
   bool              m_initialized;
   double            m_pointValue;
   int               m_digits;
   double            m_lotStep;
   double            m_minLot;
   int               m_buyGridLevel;
   int               m_sellGridLevel;
   double            m_buyBasePrice;
   double            m_sellBasePrice;
   double            m_totalBuyLots;
   double            m_totalSellLots;
   datetime          m_lastBuyBarTime;
   datetime          m_lastSellBarTime;
   datetime          m_lastOrderTime;
   double            m_cachedBuyCumulativeDist;
   double            m_cachedSellCumulativeDist;
   int               m_lastBuyDistLevel;
   int               m_lastSellDistLevel;
   int               m_cachedTrendSignal;
   datetime          m_lastTrendCalcTime;
   double            m_superTrendValue;
   double            m_superTrendPrevValue;
   int               m_superTrendDirection;
   int               m_superTrendPrevDirection;
   bool              m_trendReversed;
   bool              m_tradedThisSignal;
   double            m_bullsPower;
   double            m_bearsPower;
   datetime          m_lastBarTime;
   // Heiken Ashi 狀態變數
   double            m_heikenOpen;
   double            m_heikenClose;
   double            m_heikenHigh;
   double            m_heikenLow;
   int               m_heikenDirection;
   int               m_heikenPrevDirection;
   int               m_heikenConsecutive;
   bool              m_heikenReversed;
   OnCloseCallback        m_onClose;
   OnRequestCloseCallback m_onRequestClose;

   double            CalculateLots(int level);
   double            CalculateScaledLots(int level);
   double            CalculateCumulativeDistance(int level);
   double            CalculateScaledGridDistance(int level);
   bool              OpenGridOrder(int orderType, double lots);
   void              CheckTakeProfitClose(double currentProfit);
   int               CountGridOrders();
   void              UpdateTotalLots();
   double            CalculateGridProfit(int direction = -1);
   double            CloseGridPositions(int direction);
   double            GetCumulativeDistance(int direction, int level);
   int               GetTrendSignal();
   int               CalculateBullsBears();
   int               CalculateSuperTrend();
   int               CalculateHeiken();
   void              GetSmoothedOHLC(int tf, int period, ENUM_MA_METHOD method, int shift, double &o, double &c, double &h, double &l);
   void              DrawSuperTrendLine();
   void              DrawReversalLine(color line_color);
   void              DrawBasePriceLine(int direction, double price);
   bool              AllowFirstOrder();
   bool              AllowAveraging(int basketDirection);
   bool              IsNewBar(int timeframe);
   int               GetValidTimeframe(int requestedTF, int minBarsRequired);
   void              WriteLog(string message);
   void              WriteDebugLog(string message);

public:
                     CGridsCore();
                    ~CGridsCore();
   bool              Init(GridsCoreConfig &config);
   void              Deinit();
   bool              IsInitialized() { return m_initialized; }
   void              SetOnCloseCallback(OnCloseCallback func) { m_onClose = func; }
   void              SetOnRequestCloseCallback(OnRequestCloseCallback func) { m_onRequestClose = func; }
   void              Execute(const OrderStats &stats);
   void              Execute();
   double            CloseAllPositions();
   void              ResetBaskets();
   void              SetTradedThisSignal(bool traded) { m_tradedThisSignal = traded; }
   int               GetBuyGridLevel()    { return m_buyGridLevel; }
   int               GetSellGridLevel()   { return m_sellGridLevel; }
   double            GetTotalBuyLots()    { return m_totalBuyLots; }
   double            GetTotalSellLots()   { return m_totalSellLots; }
   double            GetFloatingProfit()  { return CalculateGridProfit(); }
   string            GetSignalName();
   string            GetDirectionName();
   ENUM_GRID_MODE    GetGridMode()        { return m_config.gridMode; }
   int               GetMagicNumber()     { return m_config.magicNumber; }
   string            GetSymbol()          { return m_config.symbol; }
  };

CGridsCore::CGridsCore()
  {
   m_initialized = false;
   m_onClose = NULL;
   m_onRequestClose = NULL;
   m_buyGridLevel = 0;
   m_sellGridLevel = 0;
   m_totalBuyLots = 0.0;
   m_totalSellLots = 0.0;
   m_buyBasePrice = 0.0;
   m_sellBasePrice = 0.0;
   m_lastBuyBarTime = 0;
   m_lastSellBarTime = 0;
   m_lastOrderTime = 0;
   m_cachedTrendSignal = SIGNAL_NEUTRAL;
   m_lastTrendCalcTime = 0;
   m_superTrendValue = 0.0;
   m_superTrendPrevValue = 0.0;
   m_superTrendDirection = 0;
   m_superTrendPrevDirection = 0;
   m_trendReversed = false;
   m_tradedThisSignal = false;
   m_bullsPower = 0.0;
   m_bearsPower = 0.0;
   m_lastBarTime = 0;
   m_cachedBuyCumulativeDist = 0.0;
   m_cachedSellCumulativeDist = 0.0;
   m_lastBuyDistLevel = -1;
   m_lastSellDistLevel = -1;
   m_heikenOpen = 0.0;
   m_heikenClose = 0.0;
   m_heikenHigh = 0.0;
   m_heikenLow = 0.0;
   m_heikenDirection = 0;
   m_heikenPrevDirection = 0;
   m_heikenConsecutive = 0;
   m_heikenReversed = false;
  }

CGridsCore::~CGridsCore() { Deinit(); }

bool CGridsCore::Init(GridsCoreConfig &config)
  {
   m_config = config;
   if(m_config.symbol == "") m_config.symbol = Symbol();
   
   // 初始化對沖平倉組件
   m_hedgeClose.Init(m_config.magicNumber, m_config.slippage, m_config.symbol);

   m_pointValue = MarketInfo(m_config.symbol, MODE_POINT);
   m_digits = (int)MarketInfo(m_config.symbol, MODE_DIGITS);
   m_lotStep = MarketInfo(m_config.symbol, MODE_LOTSTEP);
   m_minLot = MarketInfo(m_config.symbol, MODE_MINLOT);
   m_buyGridLevel = 0;
   m_sellGridLevel = 0;
   m_lastBuyDistLevel = -1;
   m_lastSellDistLevel = -1;
   m_initialized = true;
   return true;
  }

void CGridsCore::Deinit()
  {
   if(!m_initialized) return;
   ObjectDelete("SuperTrend_Line_" + IntegerToString(m_config.magicNumber));
   ObjectDelete("GC_Base_BUY_" + IntegerToString(m_config.magicNumber));
   ObjectDelete("GC_Base_SELL_" + IntegerToString(m_config.magicNumber));
   m_initialized = false;
  }

void CGridsCore::WriteLog(string message)
  {
   if(m_config.logFile == "") return;
   Print(message);
   int handle = FileOpen(m_config.logFile, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(handle != INVALID_HANDLE)
     {
      FileSeek(handle, 0, SEEK_END);
      FileWriteString(handle, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + " | " + message + "\n");
      FileClose(handle);
     }
  }

void CGridsCore::WriteDebugLog(string message)
  {
   if(m_config.showDebugLogs) WriteLog("[DEBUG] " + message);
  }

string CGridsCore::GetSignalName()
  {
   if(m_config.filterMode == FILTER_BULLSBEARS) return "BullsBears";
   if(m_config.filterMode == FILTER_SUPERTREND) return "SuperTrend";
   if(m_config.filterMode == FILTER_HeikenAshi) return "HeikenAshi";
   return "Simple";
  }

string CGridsCore::GetDirectionName()
  {
   int s = GetTrendSignal();
   return (s == SIGNAL_BUY) ? "看漲" : (s == SIGNAL_SELL ? "看跌" : "中性");
  }

bool CGridsCore::IsNewBar(int timeframe)
  {
   if(timeframe == 0) timeframe = Period();
   datetime t = iTime(m_config.symbol, timeframe, 0);
   if(t != m_lastBarTime) { m_lastBarTime = t; return true; }
   return false;
  }

int CGridsCore::GetValidTimeframe(int requestedTF, int minBarsRequired)
  {
   if(requestedTF == 0) return Period();
   return requestedTF;
  }

int CGridsCore::GetTrendSignal()
  {
   int tf = GetValidTimeframe(m_config.filterTimeframe, 20);
   if(!IsNewBar(tf) && m_lastTrendCalcTime > 0) return m_cachedTrendSignal;
   if(m_config.filterMode == FILTER_BULLSBEARS) m_cachedTrendSignal = CalculateBullsBears();
   else if(m_config.filterMode == FILTER_SUPERTREND) m_cachedTrendSignal = CalculateSuperTrend();
   else if(m_config.filterMode == FILTER_HeikenAshi) m_cachedTrendSignal = CalculateHeiken();
   else m_cachedTrendSignal = SIGNAL_NEUTRAL;
   m_lastTrendCalcTime = TimeCurrent();
   return m_cachedTrendSignal;
  }

int CGridsCore::CalculateBullsBears()
  {
   int tf = GetValidTimeframe(m_config.filterTimeframe, 20);
   m_bullsPower = 0; m_bearsPower = 0;
   for(int i = 1; i <= m_config.bbLookbackBars; i++)
     {
      double o = iOpen(m_config.symbol, tf, i), h = iHigh(m_config.symbol, tf, i), l = iLow(m_config.symbol, tf, i), c = iClose(m_config.symbol, tf, i);
      if(c > o) { m_bullsPower += (h - o); m_bearsPower += (o - l); }
      else { m_bullsPower += (c - l); m_bearsPower += (h - c); }
     }
   double m = 1.0 + m_config.bbThreshold / 100.0;
   if(m_bullsPower > m_bearsPower * m) return SIGNAL_BUY;
   if(m_bearsPower > m_bullsPower * m) return SIGNAL_SELL;
   return SIGNAL_NEUTRAL;
  }

int CGridsCore::CalculateSuperTrend()
  {
   int tf = GetValidTimeframe(m_config.filterTimeframe, 20);
   double atr = iATR(m_config.symbol, tf, m_config.stAtrPeriod, 1);
   if(atr <= 0) atr = m_pointValue * 100;
   double hl2 = (iHigh(m_config.symbol, tf, 1) + iLow(m_config.symbol, tf, 1)) / 2.0;
   double up = hl2 + m_config.stMultiplier * atr, dn = hl2 - m_config.stMultiplier * atr;
   double c1 = iClose(m_config.symbol, tf, 1), c2 = iClose(m_config.symbol, tf, 2);
   m_superTrendPrevValue = m_superTrendValue; m_superTrendPrevDirection = m_superTrendDirection;
   if(m_superTrendValue == 0) { m_superTrendValue = (c1 > hl2) ? dn : up; m_superTrendDirection = (c1 > hl2) ? 1 : -1; }
   else
     {
      if(c1 > m_superTrendPrevValue && c2 <= m_superTrendPrevValue) { m_superTrendValue = dn; m_superTrendDirection = 1; }
      else if(c1 < m_superTrendPrevValue && c2 >= m_superTrendPrevValue) { m_superTrendValue = up; m_superTrendDirection = -1; }
      else if(m_superTrendPrevDirection == 1) { m_superTrendValue = MathMax(dn, m_superTrendPrevValue); }
      else if(m_superTrendPrevDirection == -1) { m_superTrendValue = MathMin(up, m_superTrendPrevValue); }
     }
   m_trendReversed = (m_superTrendDirection != m_superTrendPrevDirection && m_superTrendPrevDirection != 0);
   if(m_trendReversed) m_tradedThisSignal = false;
   if(m_config.stShowLine) DrawSuperTrendLine();
   return (m_superTrendDirection == 1) ? SIGNAL_BUY : (m_superTrendDirection == -1 ? SIGNAL_SELL : SIGNAL_NEUTRAL);
  }

int CGridsCore::CalculateHeiken()
  {
   int tf = GetValidTimeframe(m_config.filterTimeframe, 20);
   double maOpen, maClose, maHigh, maLow;
   GetSmoothedOHLC(tf, m_config.heikenMaPeriod, m_config.heikenMaMethod, 0, maOpen, maClose, maHigh, maLow);

   double haOpen = (m_heikenOpen != 0.0) ? (m_heikenClose + m_heikenOpen) / 2.0 : maOpen;
   double haClose = (maOpen + maHigh + maLow + maClose) / 4.0;
   double haHigh = MathMax(maHigh, MathMax(haOpen, haClose));
   double haLow = MathMin(maLow, MathMin(haOpen, haClose));

   m_heikenOpen = haOpen;
   m_heikenClose = haClose;
   m_heikenHigh = haHigh;
   m_heikenLow = haLow;

   m_heikenPrevDirection = m_heikenDirection;
   int newDirection = 0;
   if(m_heikenClose > m_heikenOpen) newDirection = 1;
   else if(m_heikenClose < m_heikenOpen) newDirection = -1;
   else newDirection = 0;

   if(newDirection != 0 && newDirection == m_heikenDirection) m_heikenConsecutive++;
   else m_heikenConsecutive = (newDirection != 0) ? 1 : 0;
   
   m_heikenDirection = newDirection;
   m_heikenReversed = (m_heikenDirection != m_heikenPrevDirection && m_heikenPrevDirection != 0);
   
   if(m_heikenReversed) 
     {
      m_tradedThisSignal = false;
      color line_color = (m_heikenDirection == 1) ? clrDarkRed : clrDarkGreen;
      DrawReversalLine(line_color);
     }

   if(m_heikenConsecutive >= 2) m_heikenReversed = false;

   if(m_config.heikenSignalMode == SIGNAL_MODE_REVERSAL)
     {
      if(m_heikenReversed && !m_tradedThisSignal) return (m_heikenDirection == 1) ? SIGNAL_BUY : (m_heikenDirection == -1 ? SIGNAL_SELL : SIGNAL_NEUTRAL);
      return SIGNAL_NEUTRAL;
     }
   else if(m_config.heikenSignalMode == SIGNAL_MODE_TREND)
     {
      if(m_heikenDirection == 1 && m_heikenConsecutive >= 1) return SIGNAL_BUY;
      if(m_heikenDirection == -1 && m_heikenConsecutive >= 1) return SIGNAL_SELL;
      return SIGNAL_NEUTRAL;
     }
   return SIGNAL_NEUTRAL;
  }

void CGridsCore::GetSmoothedOHLC(int tf, int period, ENUM_MA_METHOD method, int shift, double &o, double &c, double &h, double &l)
  {
   o = iMA(m_config.symbol, tf, period, 0, method, PRICE_OPEN, shift);
   c = iMA(m_config.symbol, tf, period, 0, method, PRICE_CLOSE, shift);
   h = iMA(m_config.symbol, tf, period, 0, method, PRICE_HIGH, shift);
   l = iMA(m_config.symbol, tf, period, 0, method, PRICE_LOW, shift);
  }

void CGridsCore::DrawSuperTrendLine()
  {
   string n = "SuperTrend_Line_" + IntegerToString(m_config.magicNumber);
   ObjectDelete(n);
   ObjectCreate(n, OBJ_TREND, 0, iTime(m_config.symbol, 0, 1), m_superTrendValue, iTime(m_config.symbol, 0, 0), m_superTrendValue);
   ObjectSet(n, OBJPROP_COLOR, m_superTrendDirection == 1 ? m_config.stBullColor : m_config.stBearColor);
   ObjectSet(n, OBJPROP_WIDTH, 2); ObjectSet(n, OBJPROP_RAY, false);
  }

void CGridsCore::DrawReversalLine(color line_color)
  {
   static int lineCount = 0;
   static string lineNames[50]; // 限制最多保留 50 條反轉線
   
   string name = "HK_Rev_" + IntegerToString(m_config.magicNumber) + "_" + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS);
   
   // 如果已經存在同名的線（同一秒內多次觸發），則不建立
   if(ObjectFind(0, name) >= 0) return;

   if(ObjectCreate(0, name, OBJ_VLINE, 0, TimeCurrent(), 0))
     {
      ObjectSetInteger(0, name, OBJPROP_COLOR, line_color);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      
      // 管理快取
      if(lineNames[lineCount % 50] != "") ObjectDelete(0, lineNames[lineCount % 50]);
      lineNames[lineCount % 50] = name;
      lineCount++;
     }
  }

void CGridsCore::DrawBasePriceLine(int dir, double price)
  {
   string name = (dir == OP_BUY ? "GC_Base_BUY_" : "GC_Base_SELL_") + IntegerToString(m_config.magicNumber);
   color clr = (dir == OP_BUY) ? clrDarkRed : clrDarkGreen;
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   else ObjectMove(0, name, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
  }

bool CGridsCore::AllowFirstOrder()
  {
   if(m_config.filterMode == FILTER_SIMPLE) return true;
   if(m_config.filterMode == FILTER_SUPERTREND && m_config.stSignalMode == SIGNAL_MODE_REVERSAL) return (m_trendReversed && !m_tradedThisSignal);
   if(m_config.filterMode == FILTER_HeikenAshi && m_config.heikenSignalMode == SIGNAL_MODE_REVERSAL) return (m_heikenReversed && !m_tradedThisSignal);
   return true;
  }

bool CGridsCore::AllowAveraging(int dir)
  {
   if(m_config.filterMode == FILTER_SIMPLE) return true;
   int s = GetTrendSignal();
   if(m_config.filterMode == FILTER_SUPERTREND && m_config.stAveragingMode == AVERAGING_TREND)
     {
      if(dir == OP_BUY) return (s == SIGNAL_BUY || s == SIGNAL_NEUTRAL);
      if(dir == OP_SELL) return (s == SIGNAL_SELL || s == SIGNAL_NEUTRAL);
     }
   if(m_config.filterMode == FILTER_HeikenAshi)
     {
      if(m_config.gridMode == GRID_MODE_TREND)
        {
         if(dir == OP_BUY) return (s == SIGNAL_BUY);
         if(dir == OP_SELL) return (s == SIGNAL_SELL);
        }
      else if(m_config.gridMode == GRID_MODE_COUNTER)
        {
         if(dir == OP_BUY) return (s == SIGNAL_BUY || s == SIGNAL_NEUTRAL);
         if(dir == OP_SELL) return (s == SIGNAL_SELL || s == SIGNAL_NEUTRAL);
        }
     }
   return true;
  }

double CGridsCore::GetCumulativeDistance(int dir, int lv)
  {
   if(lv <= 0) return 0;
   if(dir == OP_BUY) { if(lv == m_lastBuyDistLevel) return m_cachedBuyCumulativeDist; m_cachedBuyCumulativeDist = CalculateCumulativeDistance(lv); m_lastBuyDistLevel = lv; return m_cachedBuyCumulativeDist; }
   if(lv == m_lastSellDistLevel) return m_cachedSellCumulativeDist; m_cachedSellCumulativeDist = CalculateCumulativeDistance(lv); m_lastSellDistLevel = lv; return m_cachedSellCumulativeDist;
  }

double CGridsCore::CalculateCumulativeDistance(int lv)
  {
   double base = m_config.gridStep * m_pointValue;
   double sc = (m_config.gridMode == GRID_MODE_COUNTER) ? m_config.counterGridScaling : m_config.trendGridScaling;
   if(sc == 0) return base * lv;
   double total = 0;
   for(int i = 0; i < lv; i++) { double s = base; if(i > 0) s *= (1.0 + (i * sc / 100.0)); total += s; }
   return total;
  }

double CGridsCore::CalculateScaledGridDistance(int lv)
  {
   double base = m_config.gridStep * m_pointValue;
   double sc = (m_config.gridMode == GRID_MODE_COUNTER) ? m_config.counterGridScaling : m_config.trendGridScaling;
   if(lv <= 1 || sc == 0) return base;
   return base * (1.0 + ((lv - 1) * sc / 100.0));
  }

double CGridsCore::CalculateLots(int lv)
  {
   double base = m_config.initialLots;
   double sc = (m_config.gridMode == GRID_MODE_COUNTER) ? m_config.counterLotScaling : m_config.trendLotScaling;
   double lots = (lv <= 1 || sc == 0) ? base : base * (1.0 + ((lv - 1) * sc / 100.0));
   if(m_config.maxLots > 0 && lots > m_config.maxLots) lots = m_config.maxLots;
   lots = MathFloor(lots / m_lotStep) * m_lotStep;
   return NormalizeDouble(MathMax(lots, m_minLot), 2);
  }

bool CGridsCore::OpenGridOrder(int type, double lots)
  {
   double spread = MarketInfo(m_config.symbol, MODE_SPREAD);
   if(m_config.maxSpread > 0 && spread > m_config.maxSpread) return false;
   double p = (type == OP_BUY) ? MarketInfo(m_config.symbol, MODE_ASK) : MarketInfo(m_config.symbol, MODE_BID);
   int t = OrderSend(m_config.symbol, type, lots, p, m_config.slippage, 0, 0, "GC", m_config.magicNumber, 0, (type == OP_BUY) ? clrBlue : clrRed);
   if(t < 0) return false;
   return true;
  }

int CGridsCore::CountGridOrders()
  {
   int count = 0;
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(OrderSelect(i, SELECT_BY_POS) && OrderMagicNumber() == m_config.magicNumber && OrderSymbol() == m_config.symbol)
         count++;
     }
   return count;
  }

void CGridsCore::UpdateTotalLots()
  {
   m_totalBuyLots = 0;
   m_totalSellLots = 0;
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(OrderSelect(i, SELECT_BY_POS) && OrderMagicNumber() == m_config.magicNumber && OrderSymbol() == m_config.symbol)
        {
         if(OrderType() == OP_BUY) m_totalBuyLots += OrderLots();
         else if(OrderType() == OP_SELL) m_totalSellLots += OrderLots();
        }
     }
  }

double CGridsCore::CalculateGridProfit(int dir)
  {
   double p = 0;
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(OrderSelect(i, SELECT_BY_POS) && OrderMagicNumber() == m_config.magicNumber && OrderSymbol() == m_config.symbol)
        {
         if(dir == -1 || OrderType() == dir) p += OrderProfit() + OrderSwap() + OrderCommission();
        }
     }
   return p;
  }

double CGridsCore::CloseGridPositions(int dir)
  {
   double p = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS) && OrderMagicNumber() == m_config.magicNumber && OrderSymbol() == m_config.symbol)
        {
          if(OrderType() == dir)
            {
             p += OrderProfit() + OrderSwap() + OrderCommission();
             if(!OrderClose(OrderTicket(), OrderLots(), (OrderType() == OP_BUY ? Bid : Ask), m_config.slippage))
               {
                WriteLog("[GC] CloseGridPositions failed: " + IntegerToString(OrderTicket()) + " Error: " + IntegerToString(GetLastError()));
               }
            }
        }
     }
   return p;
  }

void CGridsCore::Execute(const OrderStats &stats)
  {
   if(!m_initialized) return;
   
   // 每一 tick 都同步一次本地統計，確保 UI 資訊與實際倉位同步
   UpdateTotalLots();
   int currentBuyCount = 0;
   int currentSellCount = 0;
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(OrderSelect(i, SELECT_BY_POS) && OrderMagicNumber() == m_config.magicNumber && OrderSymbol() == m_config.symbol)
        {
         if(OrderType() == OP_BUY) currentBuyCount++;
         else if(OrderType() == OP_SELL) currentSellCount++;
        }
     }
   
   // 自動修復：若場上無單則重置層級
   if(currentBuyCount == 0 && m_buyGridLevel > 0) { m_buyGridLevel = 0; m_buyBasePrice = 0; m_lastBuyDistLevel = -1; ObjectDelete("GC_Base_BUY_" + IntegerToString(m_config.magicNumber)); }
   if(currentSellCount == 0 && m_sellGridLevel > 0) { m_sellGridLevel = 0; m_sellBasePrice = 0; m_lastSellDistLevel = -1; ObjectDelete("GC_Base_SELL_" + IntegerToString(m_config.magicNumber)); }
   
   int sig = GetTrendSignal(); 
   double cp = MarketInfo(m_config.symbol, MODE_BID);
   bool allow1 = AllowFirstOrder();
   bool isSimp = (m_config.filterMode == FILTER_SIMPLE);
   datetime curBT = iTime(m_config.symbol, 0, 0);
   datetime curTime = TimeCurrent();

   //--- Heiken Ashi 趨勢反轉處理：鎖利平倉與重置 ---
   if(m_config.filterMode == FILTER_HeikenAshi && m_heikenReversed)
     {
      double currentTotalProfit = CalculateGridProfit(-1);
      
      if(sig == SIGNAL_BUY)
        {
         if(currentTotalProfit > 1.0 && (m_buyGridLevel > 0 || m_sellGridLevel > 0)) 
           { 
            WriteLog("[GC] Heiken Reversed to BUY | Total Profit: " + DoubleToString(currentTotalProfit, 2) + " | Total Close-out");
            CloseAllPositions(); 
            ResetBaskets(); 
           }
         
         m_buyBasePrice = cp;
         m_buyGridLevel = 0; 
         m_lastBuyDistLevel = -1;
         DrawBasePriceLine(OP_BUY, m_buyBasePrice);
         WriteLog("[GC] Heiken Reversed to BUY | Re-calibrated BUY Base Price: " + DoubleToString(cp, m_digits));
        }
      else if(sig == SIGNAL_SELL)
        {
         if(currentTotalProfit > 1.0 && (m_buyGridLevel > 0 || m_sellGridLevel > 0)) 
           { 
            WriteLog("[GC] Heiken Reversed to SELL | Total Profit: " + DoubleToString(currentTotalProfit, 2) + " | Total Close-out");
            CloseAllPositions(); 
            ResetBaskets(); 
           }

         m_sellBasePrice = cp;
         m_sellGridLevel = 0;
         m_lastSellDistLevel = -1;
         DrawBasePriceLine(OP_SELL, m_sellBasePrice);
         WriteLog("[GC] Heiken Reversed to SELL | Re-calibrated SELL Base Price: " + DoubleToString(cp, m_digits));
        }
      
      m_heikenReversed = false; 
     }

   //--- 買入進場與加碼 ---
   if(m_config.tradeDirection != TRADE_SELL_ONLY)
     {
      bool ok = (!m_config.oneOrderPerBar || m_lastBuyBarTime != curBT);
      if(m_config.oneOrderPerBar == NO && curTime == m_lastOrderTime) ok = false;
      
       if(m_buyGridLevel == 0 && (sig == SIGNAL_BUY || isSimp) && allow1 && ok)
         {
          double l = CalculateLots(1);
          if(m_config.maxLots > 0 && (m_totalBuyLots + m_totalSellLots + l) > m_config.maxLots)
            {
             WriteLog("[GC] Skip Open BUY L1: Total lots limit reached");
            }
          else if(OpenGridOrder(OP_BUY, l)) 
            { 
             m_buyGridLevel = 1; m_buyBasePrice = cp; m_lastBuyBarTime = curBT; m_lastOrderTime = curTime; 
             DrawBasePriceLine(OP_BUY, m_buyBasePrice);
             WriteLog("[GC] ENTRY BUY | Lots: " + DoubleToString(l, 2) + " | Price: " + DoubleToString(cp, m_digits) + " | Level 1 (New Cycle)");
            }
         }
       else if(m_buyGridLevel > 0 && m_buyGridLevel < m_config.maxGridLevels && ok)
         {
          if(AllowAveraging(OP_BUY))
            {
             double step = CalculateScaledGridDistance(m_buyGridLevel + 1);
             double tp = (m_config.gridMode == GRID_MODE_COUNTER) ? (m_buyBasePrice - step) : (m_buyBasePrice + step);
             if((m_config.gridMode == GRID_MODE_COUNTER && cp <= tp) || (m_config.gridMode == GRID_MODE_TREND && cp >= tp))
               {
                double l = CalculateLots(m_buyGridLevel + 1);
                if(m_config.maxLots > 0 && (m_totalBuyLots + m_totalSellLots + l) > m_config.maxLots)
                  {
                   WriteLog("[GC] Skip Open BUY L" + IntegerToString(m_buyGridLevel+1) + ": Total lots limit reached");
                  }
                else if(OpenGridOrder(OP_BUY, l)) 
                  { 
                   m_buyGridLevel++; m_buyBasePrice = cp; m_lastBuyBarTime = curBT; m_lastOrderTime = curTime; 
                   DrawBasePriceLine(OP_BUY, m_buyBasePrice);
                   WriteLog("[GC] ENTRY BUY | Lots: " + DoubleToString(l, 2) + " | Price: " + DoubleToString(cp, m_digits) + " | Level " + IntegerToString(m_buyGridLevel));
                  }
               }
            }
         }
      }

   //--- 賣出進場與加碼 ---
   if(m_config.tradeDirection != TRADE_BUY_ONLY)
     {
      bool ok = (!m_config.oneOrderPerBar || m_lastSellBarTime != curBT);
      if(m_config.oneOrderPerBar == NO && curTime == m_lastOrderTime) ok = false;
      
      if(m_sellGridLevel == 0 && (sig == SIGNAL_SELL || isSimp) && allow1 && ok)
        {
         double l = CalculateLots(1);
         if(m_config.maxLots > 0 && (m_totalBuyLots + m_totalSellLots + l) > m_config.maxLots)
           {
            WriteLog("[GC] Skip Open SELL L1: Total lots limit reached");
           }
         else if(OpenGridOrder(OP_SELL, l)) 
           { 
            m_sellGridLevel = 1; m_sellBasePrice = cp; m_lastSellBarTime = curBT; m_lastOrderTime = curTime; 
            DrawBasePriceLine(OP_SELL, m_sellBasePrice);
            WriteLog("[GC] ENTRY SELL | Lots: " + DoubleToString(l, 2) + " | Price: " + DoubleToString(cp, m_digits) + " | Level 1 (New Cycle)");
           }
        }
      else if(m_sellGridLevel > 0 && m_sellGridLevel < m_config.maxGridLevels && ok)
        {
         if(AllowAveraging(OP_SELL))
           {
            double step = CalculateScaledGridDistance(m_sellGridLevel + 1);
            double tp = (m_config.gridMode == GRID_MODE_COUNTER) ? (m_sellBasePrice + step) : (m_sellBasePrice - step);
            if((m_config.gridMode == GRID_MODE_COUNTER && cp >= tp) || (m_config.gridMode == GRID_MODE_TREND && cp <= tp))
              {
               double l = CalculateLots(m_sellGridLevel + 1);
               if(m_config.maxLots > 0 && (m_totalBuyLots + m_totalSellLots + l) > m_config.maxLots)
                 {
                  WriteLog("[GC] Skip Open SELL L" + IntegerToString(m_sellGridLevel+1) + ": Total lots limit reached");
                 }
               else if(OpenGridOrder(OP_SELL, l)) 
                 { 
                  m_sellGridLevel++; m_sellBasePrice = cp; m_lastSellBarTime = curBT; m_lastOrderTime = curTime; 
                  DrawBasePriceLine(OP_SELL, m_sellBasePrice);
                  WriteLog("[GC] ENTRY SELL | Lots: " + DoubleToString(l, 2) + " | Price: " + DoubleToString(cp, m_digits) + " | Level " + IntegerToString(m_sellGridLevel));
                 }
              }
           }
        }
     }
   CheckTakeProfitClose(stats.profit);
  }

void CGridsCore::Execute()
  {
   OrderStats s; s.count = CountGridOrders(); s.profit = CalculateGridProfit(); UpdateTotalLots(); s.buyLots = m_totalBuyLots; s.sellLots = m_totalSellLots; s.buyCount = 0; s.sellCount = 0;
   for(int i = 0; i < OrdersTotal(); i++) if(OrderSelect(i, SELECT_BY_POS) && OrderMagicNumber() == m_config.magicNumber && OrderSymbol() == m_config.symbol) { if(OrderType() == OP_BUY) s.buyCount++; else if(OrderType() == OP_SELL) s.sellCount++; }
   Execute(s);
  }

void CGridsCore::CheckTakeProfitClose(double p)
  {
   if(m_config.takeProfit > 0 && p >= m_config.takeProfit)
     {
      double cp = (m_onRequestClose != NULL) ? m_onRequestClose() : CloseAllPositions(); ResetBaskets();
      if(m_onClose != NULL) m_onClose(cp, TimeCurrent(), MarketInfo(m_config.symbol, MODE_BID));
     }
  }

double CGridsCore::CloseAllPositions()
  {
   // 1. 優先使用 CHedgeClose 執行快速對沖平倉
   double p = m_hedgeClose.Execute();
   
   // 2. 結清對沖後剩餘的所有殘單 (確保徹底清場)
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS) && OrderMagicNumber() == m_config.magicNumber && OrderSymbol() == m_config.symbol)
        {
         double cp = (OrderType() == OP_BUY ? Bid : Ask);
         if(!OrderClose(OrderTicket(), OrderLots(), cp, m_config.slippage))
           {
            WriteLog("[GC] Failed to close residual order " + IntegerToString(OrderTicket()));
           }
        }
     }
   return p;
  }

void CGridsCore::ResetBaskets()
  {
   m_buyGridLevel = 0; m_sellGridLevel = 0; m_buyBasePrice = 0; m_sellBasePrice = 0; m_lastBuyDistLevel = -1; m_lastSellDistLevel = -1; m_lastBuyBarTime = 0; m_lastSellBarTime = 0; m_tradedThisSignal = false;
   ObjectDelete("GC_Base_BUY_" + IntegerToString(m_config.magicNumber));
   ObjectDelete("GC_Base_SELL_" + IntegerToString(m_config.magicNumber));
  }

#endif
