//+------------------------------------------------------------------+
//|                                                   CGridsCore.mqh |
//|                              網格交易核心模組 v2.7                |
//+------------------------------------------------------------------+
//| 【模組說明 - 供 Kiro AI 讀取】                                    |
//|                                                                   |
//| 功能：網格交易核心模組，包含網格邏輯和信號計算                    |
//|       不包含 UI、箭頭、獲利追蹤等功能（由 CEACore 統一管理）      |
//|                                                                   |
//| 設計原則：                                                        |
//|   - 處理網格交易核心邏輯                                          |
//|   - 內建信號計算（SuperTrend、BullsBears、動態0線）               |
//|   - 透過事件通知外部模組（平倉獲利等）                            |
//|   - 不直接操作 UI 或其他輔助功能                                  |
//|   - 平倉透過回調請求外部執行（支援對沖平倉）                      |
//|   - 支援獨立縮放設定（間距/手數，順向/逆向分開，0=不縮放）        |
//|   - 支援動態 0 線機制（用近 N 根 K 棒高低點作為反向觸發線）       |
//|                                                                   |
//| v2.7 更新：                                                       |
//|   - 新增日誌回調機制，讓日誌統一寫到 CEACore 的 Log 檔案          |
//|   - SetLogCallback() 設定外部日誌函數                             |
//|                                                                   |
//| v2.6 更新：                                                       |
//|   - 重新設計動態 0 線邏輯                                         |
//|   - 空籃子時同時追蹤兩條 0 線，先觸發哪個就開哪個方向             |
//|   - 有籃子時只追蹤反向 0 線，觸發後重置另一條                     |
//|                                                                   |
//| 引用方式：#include "../Libs/GridsCore/CGridsCore v1.1.mqh"        |
//+------------------------------------------------------------------+

#ifndef CGRIDSCORE_V11_MQH
#define CGRIDSCORE_V11_MQH

#property copyright "Recovery System"
#property version   "2.70"
#property strict

//+------------------------------------------------------------------+
//| 常數定義（避免重複定義）                                          |
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

//+------------------------------------------------------------------+
//| 網格模式枚舉                                                      |
//+------------------------------------------------------------------+
enum ENUM_GRID_MODE
  {
   GRID_MODE_TREND   = 0,        // 順向網格（順勢加倉）
   GRID_MODE_COUNTER = 1         // 逆向網格（逆勢加倉）
  };

//+------------------------------------------------------------------+
//| 交易方向枚舉                                                      |
//+------------------------------------------------------------------+
enum ENUM_TRADE_DIRECTION
  {
   TRADE_BOTH      = 0,          // 雙向交易
   TRADE_BUY_ONLY  = 1,          // 只買
   TRADE_SELL_ONLY = 2           // 只賣
  };

//+------------------------------------------------------------------+
//| 信號過濾模式枚舉                                                  |
//+------------------------------------------------------------------+
enum ENUM_FILTER_MODE
  {
   FILTER_BULLSBEARS   = 0,      // BullsBears Candles
   FILTER_SUPERTREND   = 1,      // Super Trend
   FILTER_SIMPLE       = 2,      // Simple Grids (無過濾)
   FILTER_DYNAMIC_ZERO = 3       // N 根 K 棒反轉（動態 0 線）
  };

//+------------------------------------------------------------------+
//| 首單信號模式枚舉                                                  |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_MODE
  {
   SIGNAL_MODE_TREND    = 0,     // 趨勢方向內持續開單
   SIGNAL_MODE_REVERSAL = 1,     // 只在趨勢反轉時開單
   SIGNAL_MODE_DISABLED = 2      // 不使用趨勢過濾開單
  };

//+------------------------------------------------------------------+
//| 加倉信號模式枚舉                                                  |
//+------------------------------------------------------------------+
enum ENUM_AVERAGING_MODE
  {
   AVERAGING_ANY      = 0,       // 任意方向加倉
   AVERAGING_TREND    = 1,       // 僅順勢時加倉
   AVERAGING_DISABLED = 2        // 不使用趨勢過濾加倉
  };

//+------------------------------------------------------------------+
//| 網格核心配置結構                                                  |
//+------------------------------------------------------------------+
struct GridsCoreConfig
  {
   int               magicNumber;
   string            symbol;
   int               slippage;
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
   bool              enableDynamicZero;
   int               dynamicZeroBars;
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
   bool              showDebugLogs;
  };

typedef void (*OnCloseCallback)(double profit, datetime time, double price);
typedef double (*OnRequestCloseCallback)(void);
typedef void (*OnLogCallback)(string message);

//+------------------------------------------------------------------+
//| 網格交易核心類別                                                  |
//+------------------------------------------------------------------+
class CGridsCore
  {
private:
   GridsCoreConfig   m_config;
   bool              m_initialized;
   double            m_pointValue;
   int               m_digits;
   int               m_buyGridLevel;
   int               m_sellGridLevel;
   double            m_buyBasePrice;
   double            m_sellBasePrice;
   double            m_totalBuyLots;
   double            m_totalSellLots;
   datetime          m_lastOrderBarTime;
   double            m_dynamicBuyZero;
   double            m_dynamicSellZero;
   bool              m_hasOpenedFirstBuy;
   bool              m_hasOpenedFirstSell;
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
   datetime          m_lastDebugTime;
   OnCloseCallback        m_onClose;
   OnRequestCloseCallback m_onRequestClose;
   OnLogCallback          m_onLog;
   OnLogCallback          m_onDebugLog;

   double            CalculateLots(int level);
   double            CalculateScaledLots(int level);
   double            CalculateCumulativeDistance(int level);
   double            CalculateScaledGridDistance(int level);
   bool              OpenGridOrder(int orderType, double lots);
   void              CheckTakeProfitClose();
   int               CountGridOrders();
   void              UpdateTotalLots();
   double            CalculateGridProfit();
   void              UpdateDynamicZeroLines();
   double            GetRecentHigh(int bars);
   double            GetRecentLow(int bars);
   int               GetTrendSignal();
   int               CalculateBullsBears();
   int               CalculateSuperTrend();
   void              DrawSuperTrendLine();
   bool              AllowFirstOrder();
   bool              AllowAveraging(int basketDirection);
   bool              IsNewBar(int timeframe);
   int               GetValidTimeframe(int requestedTF, int minBarsRequired);
   void              ExecuteDynamicZeroMode();
   void              ExecuteTraditionalMode();
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
   void              SetLogCallback(OnLogCallback func) { m_onLog = func; }
   void              SetDebugLogCallback(OnLogCallback func) { m_onDebugLog = func; }
   void              Execute();
   double            CloseAllPositions();
   void              ResetBaskets();
   void              SetTradedThisSignal(bool traded) { m_tradedThisSignal = traded; }
   int               GetBuyGridLevel()    { return m_buyGridLevel; }
   int               GetSellGridLevel()   { return m_sellGridLevel; }
   double            GetTotalBuyLots()    { return m_totalBuyLots; }
   double            GetTotalSellLots()   { return m_totalSellLots; }
   double            GetFloatingProfit()  { return CalculateGridProfit(); }
   double            GetDynamicBuyZero()  { return m_dynamicBuyZero; }
   double            GetDynamicSellZero() { return m_dynamicSellZero; }
   string            GetSignalName();
   string            GetDirectionName();
   ENUM_GRID_MODE    GetGridMode()        { return m_config.gridMode; }
   int               GetMagicNumber()     { return m_config.magicNumber; }
   string            GetSymbol()          { return m_config.symbol; }
  };

//+------------------------------------------------------------------+
//| 建構函數                                                          |
//+------------------------------------------------------------------+
CGridsCore::CGridsCore()
  {
   m_initialized = false;
   m_onClose = NULL;
   m_onRequestClose = NULL;
   m_onLog = NULL;
   m_onDebugLog = NULL;
   m_buyGridLevel = 0;
   m_sellGridLevel = 0;
   m_totalBuyLots = 0.0;
   m_totalSellLots = 0.0;
   m_buyBasePrice = 0.0;
   m_sellBasePrice = 0.0;
   m_lastOrderBarTime = 0;
   m_dynamicBuyZero = 0.0;
   m_dynamicSellZero = 0.0;
   m_hasOpenedFirstBuy = false;
   m_hasOpenedFirstSell = false;
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
   m_lastDebugTime = 0;
  }

CGridsCore::~CGridsCore() { Deinit(); }

//+------------------------------------------------------------------+
//| 日誌輸出（透過回調寫到外部 Log 檔案）                             |
//+------------------------------------------------------------------+
void CGridsCore::WriteLog(string message)
  {
   string fullMsg = "[CGridsCore] " + message;
   if(m_onLog != NULL)
      m_onLog(fullMsg);
   else
      Print(fullMsg);
  }

void CGridsCore::WriteDebugLog(string message)
  {
   if(!m_config.showDebugLogs) return;
   string fullMsg = "[CGridsCore][DEBUG] " + message;
   if(m_onDebugLog != NULL)
      m_onDebugLog(fullMsg);
   else if(m_onLog != NULL)
      m_onLog(fullMsg);
   else
      Print(fullMsg);
  }

//+------------------------------------------------------------------+
//| 初始化                                                            |
//+------------------------------------------------------------------+
bool CGridsCore::Init(GridsCoreConfig &config)
  {
   m_config = config;
   if(m_config.symbol == "") m_config.symbol = Symbol();
   m_pointValue = MarketInfo(m_config.symbol, MODE_POINT);
   m_digits = (int)MarketInfo(m_config.symbol, MODE_DIGITS);
   if(m_digits == 5 || m_digits == 3) m_pointValue = m_pointValue * 10;
   m_buyGridLevel = 0;
   m_sellGridLevel = 0;
   m_dynamicBuyZero = 0.0;
   m_dynamicSellZero = 0.0;
   m_hasOpenedFirstBuy = false;
   m_hasOpenedFirstSell = false;
   m_initialized = true;

   if(m_config.filterMode == FILTER_DYNAMIC_ZERO)
      m_config.enableDynamicZero = true;

   WriteLog("=== CGridsCore v2.7 初始化完成 ===");
   WriteLog("網格模式: " + (m_config.gridMode == GRID_MODE_TREND ? "順向網格" : "逆向網格"));
   WriteLog("網格間距: " + DoubleToString(m_config.gridStep, 1) + " 點");
   WriteLog("信號模式: " + GetSignalName());
   if(m_config.filterMode == FILTER_DYNAMIC_ZERO)
      WriteLog("動態 0 線模式: 回看 " + IntegerToString(m_config.dynamicZeroBars) + " 根 K 棒");
   else if(m_config.enableDynamicZero)
      WriteLog("動態 0 線: 啟用，回看 " + IntegerToString(m_config.dynamicZeroBars) + " 根 K 棒");
   return true;
  }

void CGridsCore::Deinit()
  {
   if(!m_initialized) return;
   ObjectDelete("SuperTrend_Line_" + IntegerToString(m_config.magicNumber));
   WriteLog("=== CGridsCore 已停止 ===");
   m_initialized = false;
  }

string CGridsCore::GetSignalName()
  {
   switch(m_config.filterMode)
     {
      case FILTER_BULLSBEARS:   return "BullsBears";
      case FILTER_SUPERTREND:   return "SuperTrend";
      case FILTER_DYNAMIC_ZERO: return "動態0線";
      default: return "Simple";
     }
  }

string CGridsCore::GetDirectionName()
  {
   if(m_config.filterMode == FILTER_DYNAMIC_ZERO)
     {
      if(m_buyGridLevel > 0 && m_sellGridLevel == 0) return "看漲";
      if(m_sellGridLevel > 0 && m_buyGridLevel == 0) return "看跌";
      return "等待突破";
     }
   int signal = GetTrendSignal();
   switch(signal)
     {
      case SIGNAL_BUY: return "看漲";
      case SIGNAL_SELL: return "看跌";
      default: return "中性";
     }
  }

bool CGridsCore::IsNewBar(int timeframe)
  {
   if(timeframe == 0) timeframe = Period();
   datetime currentBarTime = iTime(m_config.symbol, timeframe, 0);
   if(currentBarTime != m_lastBarTime) { m_lastBarTime = currentBarTime; return true; }
   return false;
  }

int CGridsCore::GetValidTimeframe(int requestedTF, int minBarsRequired)
  {
   int tf = requestedTF;
   if(tf == 0) return Period();
   int validTFs[] = {1, 5, 15, 30, 60, 240, 1440, 10080, 43200};
   bool isValid = false;
   for(int i = 0; i < ArraySize(validTFs); i++) if(tf == validTFs[i]) { isValid = true; break; }
   if(!isValid) return Period();
   if(iBars(m_config.symbol, tf) < minBarsRequired) return Period();
   return tf;
  }

double CGridsCore::GetRecentHigh(int bars)
  {
   if(bars <= 0) bars = 10;
   int highestBar = iHighest(m_config.symbol, 0, MODE_HIGH, bars, 1);
   return iHigh(m_config.symbol, 0, highestBar);
  }

double CGridsCore::GetRecentLow(int bars)
  {
   if(bars <= 0) bars = 10;
   int lowestBar = iLowest(m_config.symbol, 0, MODE_LOW, bars, 1);
   return iLow(m_config.symbol, 0, lowestBar);
  }


//+------------------------------------------------------------------+
//| 更新動態 0 線（重新設計 v2.6）                                    |
//| - 空籃子：同時追蹤兩條 0 線                                       |
//| - 有買入籃子：只追蹤賣出 0 線（前 N 根最低點）                    |
//| - 有賣出籃子：只追蹤買入 0 線（前 N 根最高點）                    |
//+------------------------------------------------------------------+
void CGridsCore::UpdateDynamicZeroLines()
  {
   if(!m_config.enableDynamicZero) return;
   
   // 狀態 1：空籃子 - 同時追蹤兩條 0 線
   if(m_buyGridLevel == 0 && m_sellGridLevel == 0)
     {
      // 追蹤買入 0 線（前 N 根最高點）
      bool canBuy = (m_config.tradeDirection != TRADE_SELL_ONLY);
      if(canBuy)
        {
         double newBuyZero = GetRecentHigh(m_config.dynamicZeroBars);
         if(newBuyZero != m_dynamicBuyZero)
           {
            m_dynamicBuyZero = newBuyZero;
            WriteDebugLog("【空籃子】更新買入 0 線: " + DoubleToString(m_dynamicBuyZero, m_digits));
           }
        }
      
      // 追蹤賣出 0 線（前 N 根最低點）
      bool canSell = (m_config.tradeDirection != TRADE_BUY_ONLY);
      if(canSell)
        {
         double newSellZero = GetRecentLow(m_config.dynamicZeroBars);
         if(newSellZero != m_dynamicSellZero)
           {
            m_dynamicSellZero = newSellZero;
            WriteDebugLog("【空籃子】更新賣出 0 線: " + DoubleToString(m_dynamicSellZero, m_digits));
           }
        }
      return;
     }
   
   // 狀態 2：有買入籃子，無賣出籃子 - 只追蹤賣出 0 線
   if(m_buyGridLevel > 0 && m_sellGridLevel == 0)
     {
      double newSellZero = GetRecentLow(m_config.dynamicZeroBars);
      if(newSellZero != m_dynamicSellZero)
        {
         m_dynamicSellZero = newSellZero;
         WriteDebugLog("【有買入籃子】更新賣出 0 線: " + DoubleToString(m_dynamicSellZero, m_digits));
        }
      return;
     }
   
   // 狀態 3：有賣出籃子，無買入籃子 - 只追蹤買入 0 線
   if(m_sellGridLevel > 0 && m_buyGridLevel == 0)
     {
      double newBuyZero = GetRecentHigh(m_config.dynamicZeroBars);
      if(newBuyZero != m_dynamicBuyZero)
        {
         m_dynamicBuyZero = newBuyZero;
         WriteDebugLog("【有賣出籃子】更新買入 0 線: " + DoubleToString(m_dynamicBuyZero, m_digits));
        }
      return;
     }
   
   // 狀態 4：雙向都有籃子 - 不追蹤任何 0 線（等待平倉）
  }

int CGridsCore::GetTrendSignal()
  {
   if(m_config.filterMode == FILTER_DYNAMIC_ZERO)
      return SIGNAL_NEUTRAL;
   
   int tf = GetValidTimeframe(m_config.filterTimeframe,
                              MathMax(m_config.bbLookbackBars, m_config.stAtrPeriod) + 10);
   if(!IsNewBar(tf) && m_lastTrendCalcTime > 0)
      return m_cachedTrendSignal;

   switch(m_config.filterMode)
     {
      case FILTER_BULLSBEARS: m_cachedTrendSignal = CalculateBullsBears(); break;
      case FILTER_SUPERTREND: m_cachedTrendSignal = CalculateSuperTrend(); break;
      default: m_cachedTrendSignal = SIGNAL_NEUTRAL; break;
     }
   m_lastTrendCalcTime = TimeCurrent();
   return m_cachedTrendSignal;
  }

int CGridsCore::CalculateBullsBears()
  {
   int tf = GetValidTimeframe(m_config.filterTimeframe, MathMax(m_config.bbLookbackBars, m_config.stAtrPeriod) + 10);
   m_bullsPower = 0.0;
   m_bearsPower = 0.0;
   for(int i = 1; i <= m_config.bbLookbackBars; i++)
     {
      double open = iOpen(m_config.symbol, tf, i);
      double high = iHigh(m_config.symbol, tf, i);
      double low = iLow(m_config.symbol, tf, i);
      double close = iClose(m_config.symbol, tf, i);
      if(close > open) { m_bullsPower += (high - open); m_bearsPower += (open - low); }
      else { m_bullsPower += (close - low); m_bearsPower += (high - close); }
     }
   double thresholdMultiplier = 1.0 + m_config.bbThreshold / 100.0;
   if(m_bullsPower > m_bearsPower * thresholdMultiplier) return SIGNAL_BUY;
   else if(m_bearsPower > m_bullsPower * thresholdMultiplier) return SIGNAL_SELL;
   return SIGNAL_NEUTRAL;
  }

int CGridsCore::CalculateSuperTrend()
  {
   int tf = GetValidTimeframe(m_config.filterTimeframe, MathMax(m_config.bbLookbackBars, m_config.stAtrPeriod) + 10);
   double dAtr = iATR(m_config.symbol, tf, m_config.stAtrPeriod, 1);
   if(dAtr <= 0 || dAtr == EMPTY_VALUE) dAtr = m_pointValue * 100;
   double hl2 = (iHigh(m_config.symbol, tf, 1) + iLow(m_config.symbol, tf, 1)) / 2.0;
   double dUpperLevel = hl2 + m_config.stMultiplier * dAtr;
   double dLowerLevel = hl2 - m_config.stMultiplier * dAtr;
   double close1 = iClose(m_config.symbol, tf, 1);
   double close2 = iClose(m_config.symbol, tf, 2);
   m_superTrendPrevValue = m_superTrendValue;
   m_superTrendPrevDirection = m_superTrendDirection;
   if(m_superTrendValue == 0.0)
     { m_superTrendValue = (close1 > hl2) ? dLowerLevel : dUpperLevel; m_superTrendDirection = (close1 > hl2) ? 1 : -1; }
   else
     {
      if(close1 > m_superTrendPrevValue && close2 <= m_superTrendPrevValue) { m_superTrendValue = dLowerLevel; m_superTrendDirection = 1; }
      else if(close1 < m_superTrendPrevValue && close2 >= m_superTrendPrevValue) { m_superTrendValue = dUpperLevel; m_superTrendDirection = -1; }
      else if(m_superTrendPrevValue < dLowerLevel) { m_superTrendValue = dLowerLevel; m_superTrendDirection = 1; }
      else if(m_superTrendPrevValue > dUpperLevel) { m_superTrendValue = dUpperLevel; m_superTrendDirection = -1; }
      else { m_superTrendValue = m_superTrendPrevValue; }
     }
   m_trendReversed = (m_superTrendDirection != m_superTrendPrevDirection && m_superTrendPrevDirection != 0);
   if(m_trendReversed) m_tradedThisSignal = false;
   if(m_config.stShowLine) DrawSuperTrendLine();
   if(m_superTrendDirection == 1) return SIGNAL_BUY;
   else if(m_superTrendDirection == -1) return SIGNAL_SELL;
   return SIGNAL_NEUTRAL;
  }

void CGridsCore::DrawSuperTrendLine()
  {
   int tf = GetValidTimeframe(m_config.filterTimeframe, MathMax(m_config.bbLookbackBars, m_config.stAtrPeriod) + 10);
   string objName = "SuperTrend_Line_" + IntegerToString(m_config.magicNumber);
   ObjectDelete(objName);
   datetime time1 = iTime(m_config.symbol, tf, 1);
   datetime time2 = iTime(m_config.symbol, tf, 0);
   ObjectCreate(objName, OBJ_TREND, 0, time1, m_superTrendValue, time2, m_superTrendValue);
   ObjectSet(objName, OBJPROP_COLOR, m_superTrendDirection == 1 ? m_config.stBullColor : m_config.stBearColor);
   ObjectSet(objName, OBJPROP_WIDTH, 2);
   ObjectSet(objName, OBJPROP_RAY, false);
  }

bool CGridsCore::AllowFirstOrder()
  {
   if(m_config.filterMode == FILTER_SIMPLE || m_config.filterMode == FILTER_BULLSBEARS) return true;
   if(m_config.filterMode == FILTER_DYNAMIC_ZERO) return true;
   if(m_config.filterMode == FILTER_SUPERTREND)
     {
      if(m_config.stSignalMode == SIGNAL_MODE_TREND || m_config.stSignalMode == SIGNAL_MODE_DISABLED) return true;
      if(m_config.stSignalMode == SIGNAL_MODE_REVERSAL) return (m_trendReversed && !m_tradedThisSignal);
     }
   return true;
  }

bool CGridsCore::AllowAveraging(int basketDirection)
  {
   if(m_config.filterMode == FILTER_SIMPLE || m_config.filterMode == FILTER_BULLSBEARS) return true;
   if(m_config.filterMode == FILTER_DYNAMIC_ZERO) return true;
   if(m_config.filterMode == FILTER_SUPERTREND)
     {
      if(m_config.stAveragingMode == AVERAGING_ANY || m_config.stAveragingMode == AVERAGING_DISABLED) return true;
      if(m_config.stAveragingMode == AVERAGING_TREND)
        {
         int currentSignal = GetTrendSignal();
         if(basketDirection == OP_BUY) return (currentSignal == SIGNAL_BUY || currentSignal == SIGNAL_NEUTRAL);
         if(basketDirection == OP_SELL) return (currentSignal == SIGNAL_SELL || currentSignal == SIGNAL_NEUTRAL);
        }
     }
   return true;
  }

double CGridsCore::CalculateScaledGridDistance(int level)
  {
   double baseStep = m_config.gridStep * MarketInfo(m_config.symbol, MODE_POINT);
   if(level <= 1) return baseStep;
   double scalingPercent = (m_config.gridMode == GRID_MODE_COUNTER) ? m_config.counterGridScaling : m_config.trendGridScaling;
   if(scalingPercent == 0.0) return baseStep;
   double scalingFactor = 1.0 + ((level - 1) * scalingPercent / 100.0);
   return baseStep * scalingFactor;
  }

double CGridsCore::CalculateCumulativeDistance(int level)
  {
   if(level <= 0) return 0.0;
   double baseStep = m_config.gridStep * MarketInfo(m_config.symbol, MODE_POINT);
   double scalingPercent = (m_config.gridMode == GRID_MODE_COUNTER) ? m_config.counterGridScaling : m_config.trendGridScaling;
   if(scalingPercent == 0.0) return baseStep * level;
   double total = 0.0;
   for(int i = 0; i < level; i++)
     {
      double stepDistance = baseStep;
      if(i > 0) { double scalingFactor = 1.0 + (i * scalingPercent / 100.0); stepDistance *= scalingFactor; }
      total += stepDistance;
     }
   return total;
  }

double CGridsCore::CalculateScaledLots(int level)
  {
   double baseLots = m_config.initialLots;
   if(level <= 1) return baseLots;
   double scalingPercent = (m_config.gridMode == GRID_MODE_COUNTER) ? m_config.counterLotScaling : m_config.trendLotScaling;
   if(scalingPercent == 0.0) return baseLots;
   double scalingFactor = 1.0 + ((level - 1) * scalingPercent / 100.0);
   return baseLots * scalingFactor;
  }

double CGridsCore::CalculateLots(int level)
  {
   if(level <= 0) return m_config.initialLots;
   double lots = CalculateScaledLots(level);
   if(m_config.maxLots > 0 && lots > m_config.maxLots) lots = m_config.maxLots;
   double minLot = MarketInfo(m_config.symbol, MODE_MINLOT);
   double lotStep = MarketInfo(m_config.symbol, MODE_LOTSTEP);
   lots = MathFloor(lots / lotStep) * lotStep;
   if(lots < minLot) lots = minLot;
   return lots;
  }

bool CGridsCore::OpenGridOrder(int orderType, double lots)
  {
   double spread = MarketInfo(m_config.symbol, MODE_SPREAD);
   if(m_config.maxSpread > 0 && spread > m_config.maxSpread) { WriteDebugLog("點差過大: " + DoubleToString(spread, 1)); return false; }
   if(m_config.maxOrdersInWork > 0 && CountGridOrders() >= m_config.maxOrdersInWork) { WriteDebugLog("訂單數量已達上限"); return false; }
   double price = (orderType == OP_BUY) ? MarketInfo(m_config.symbol, MODE_ASK) : MarketInfo(m_config.symbol, MODE_BID);
   int ticket = OrderSend(m_config.symbol, orderType, lots, price, m_config.slippage, 0, 0, "GC", m_config.magicNumber, 0, (orderType == OP_BUY) ? clrBlue : clrRed);
   if(ticket < 0) { WriteLog("開單失敗: " + IntegerToString(GetLastError())); return false; }
   WriteDebugLog("開單成功 #" + IntegerToString(ticket) + " " + (orderType == OP_BUY ? "BUY" : "SELL") + " " + DoubleToString(lots, 2) + " @ " + DoubleToString(price, m_digits));
   return true;
  }

int CGridsCore::CountGridOrders()
  {
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         if(OrderMagicNumber() == m_config.magicNumber && OrderSymbol() == m_config.symbol) count++;
   return count;
  }

void CGridsCore::UpdateTotalLots()
  {
   m_totalBuyLots = 0.0;
   m_totalSellLots = 0.0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         if(OrderMagicNumber() == m_config.magicNumber && OrderSymbol() == m_config.symbol)
           { if(OrderType() == OP_BUY) m_totalBuyLots += OrderLots(); else if(OrderType() == OP_SELL) m_totalSellLots += OrderLots(); }
  }

double CGridsCore::CalculateGridProfit()
  {
   double profit = 0.0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         if(OrderMagicNumber() == m_config.magicNumber && OrderSymbol() == m_config.symbol)
            profit += OrderProfit() + OrderSwap() + OrderCommission();
   return profit;
  }


//+------------------------------------------------------------------+
//| 主要執行方法                                                      |
//+------------------------------------------------------------------+
void CGridsCore::Execute()
  {
   if(!m_initialized) return;
   UpdateTotalLots();
   if(m_config.oneOrderPerBar && m_lastOrderBarTime == iTime(m_config.symbol, 0, 0)) return;
   if(m_config.filterMode == FILTER_DYNAMIC_ZERO)
      ExecuteDynamicZeroMode();
   else
      ExecuteTraditionalMode();
   CheckTakeProfitClose();
  }

//+------------------------------------------------------------------+
//| 動態 0 線模式執行邏輯（v2.6 重新設計）                            |
//| 邏輯說明：                                                        |
//| - 空籃子：同時追蹤兩條 0 線，先觸發哪個就開哪個方向首單           |
//| - 有買入籃子：追蹤賣出 0 線，跌破後開賣出首單，重置買入 0 線      |
//| - 有賣出籃子：追蹤買入 0 線，突破後開買入首單，重置賣出 0 線      |
//+------------------------------------------------------------------+
void CGridsCore::ExecuteDynamicZeroMode()
  {
   double currentPrice = MarketInfo(m_config.symbol, MODE_BID);
   
   // 更新動態 0 線
   UpdateDynamicZeroLines();
   
   // 每秒輸出一次狀態日誌（避免日誌過多）
   bool shouldLogStatus = (TimeCurrent() - m_lastDebugTime >= 1);
   if(shouldLogStatus && m_config.showDebugLogs)
     {
      m_lastDebugTime = TimeCurrent();
      WriteDebugLog("=== 動態0線狀態 v2.7 ===");
      WriteDebugLog("當前價格: " + DoubleToString(currentPrice, m_digits));
      WriteDebugLog("買入籃子: L" + IntegerToString(m_buyGridLevel) + ", 基準價: " + DoubleToString(m_buyBasePrice, m_digits));
      WriteDebugLog("賣出籃子: L" + IntegerToString(m_sellGridLevel) + ", 基準價: " + DoubleToString(m_sellBasePrice, m_digits));
      WriteDebugLog("動態買入0線: " + DoubleToString(m_dynamicBuyZero, m_digits));
      WriteDebugLog("動態賣出0線: " + DoubleToString(m_dynamicSellZero, m_digits));
     }
   
   //=== 狀態 1：無任何籃子 - 等待 0 線突破開首單 ===
   if(m_buyGridLevel == 0 && m_sellGridLevel == 0)
     {
      bool canBuy = (m_config.tradeDirection != TRADE_SELL_ONLY);
      bool canSell = (m_config.tradeDirection != TRADE_BUY_ONLY);
      
      if(shouldLogStatus && m_config.showDebugLogs)
        {
         WriteDebugLog("狀態: 空籃子，等待 0 線突破");
         WriteDebugLog("canBuy=" + (canBuy ? "true" : "false") + ", canSell=" + (canSell ? "true" : "false"));
         if(canBuy && m_dynamicBuyZero > 0)
            WriteDebugLog("買入觸發條件: 價格 >= " + DoubleToString(m_dynamicBuyZero, m_digits) + " ? " + (currentPrice >= m_dynamicBuyZero ? "是" : "否"));
         if(canSell && m_dynamicSellZero > 0)
            WriteDebugLog("賣出觸發條件: 價格 <= " + DoubleToString(m_dynamicSellZero, m_digits) + " ? " + (currentPrice <= m_dynamicSellZero ? "是" : "否"));
        }
      
      // 檢查買入首單觸發（價格突破買入 0 線）
      if(canBuy && m_dynamicBuyZero > 0 && currentPrice >= m_dynamicBuyZero)
        {
         WriteLog("【動態0線】價格突破買入0線! 價格=" + DoubleToString(currentPrice, m_digits) + 
                 ", 0線=" + DoubleToString(m_dynamicBuyZero, m_digits));
         double lots = CalculateLots(1);
         if(OpenGridOrder(OP_BUY, lots))
           {
            m_buyGridLevel = 1;
            m_buyBasePrice = m_dynamicBuyZero;  // 以 0 線作為基準價
            m_lastOrderBarTime = iTime(m_config.symbol, 0, 0);
            // 重置賣出 0 線（下次會重新計算）
            m_dynamicSellZero = GetRecentLow(m_config.dynamicZeroBars);
            WriteLog("【動態0線】買入首單 L1 開倉成功，基準價=" + DoubleToString(m_buyBasePrice, m_digits));
            WriteLog("【動態0線】重置賣出0線=" + DoubleToString(m_dynamicSellZero, m_digits));
           }
         return;
        }
      
      // 檢查賣出首單觸發（價格跌破賣出 0 線）
      if(canSell && m_dynamicSellZero > 0 && currentPrice <= m_dynamicSellZero)
        {
         WriteLog("【動態0線】價格跌破賣出0線! 價格=" + DoubleToString(currentPrice, m_digits) + 
                 ", 0線=" + DoubleToString(m_dynamicSellZero, m_digits));
         double lots = CalculateLots(1);
         if(OpenGridOrder(OP_SELL, lots))
           {
            m_sellGridLevel = 1;
            m_sellBasePrice = m_dynamicSellZero;  // 以 0 線作為基準價
            m_lastOrderBarTime = iTime(m_config.symbol, 0, 0);
            // 重置買入 0 線（下次會重新計算）
            m_dynamicBuyZero = GetRecentHigh(m_config.dynamicZeroBars);
            WriteLog("【動態0線】賣出首單 L1 開倉成功，基準價=" + DoubleToString(m_sellBasePrice, m_digits));
            WriteLog("【動態0線】重置買入0線=" + DoubleToString(m_dynamicBuyZero, m_digits));
           }
         return;
        }
      
      // 空籃子且未觸發，不做任何事
      return;
     }
   
   //=== 狀態 2：有買入籃子，無賣出籃子 ===
   if(m_buyGridLevel > 0 && m_sellGridLevel == 0)
     {
      // 檢查是否觸發賣出首單（價格跌破賣出 0 線）
      if(m_config.tradeDirection != TRADE_BUY_ONLY)
        {
         if(shouldLogStatus && m_config.showDebugLogs)
           {
            WriteDebugLog("狀態: 有買入籃子 L" + IntegerToString(m_buyGridLevel) + "，檢查賣出觸發");
            if(m_dynamicSellZero > 0)
               WriteDebugLog("賣出觸發條件: 價格 <= " + DoubleToString(m_dynamicSellZero, m_digits) + " ? " + (currentPrice <= m_dynamicSellZero ? "是" : "否"));
           }
         
         if(m_dynamicSellZero > 0 && currentPrice <= m_dynamicSellZero)
           {
            WriteLog("【動態0線】價格跌破賣出0線! 價格=" + DoubleToString(currentPrice, m_digits) + 
                    ", 0線=" + DoubleToString(m_dynamicSellZero, m_digits));
            double lots = CalculateLots(1);
            if(OpenGridOrder(OP_SELL, lots))
              {
               m_sellGridLevel = 1;
               m_sellBasePrice = m_dynamicSellZero;  // 以 0 線作為基準價
               m_lastOrderBarTime = iTime(m_config.symbol, 0, 0);
               // 重置買入 0 線
               m_dynamicBuyZero = GetRecentHigh(m_config.dynamicZeroBars);
               WriteLog("【動態0線】賣出首單 L1 開倉成功，基準價=" + DoubleToString(m_sellBasePrice, m_digits));
               WriteLog("【動態0線】重置買入0線=" + DoubleToString(m_dynamicBuyZero, m_digits));
              }
           }
        }
      
      // 買入籃子加倉邏輯
      if(m_buyGridLevel > 0 && m_buyGridLevel < m_config.maxGridLevels)
        {
         double dist = CalculateCumulativeDistance(m_buyGridLevel);
         double basePrice = m_buyBasePrice;
         double triggerPrice;
         bool shouldAdd;
         
         if(m_config.gridMode == GRID_MODE_COUNTER)
           { triggerPrice = basePrice - dist; shouldAdd = (currentPrice <= triggerPrice); }
         else
           { triggerPrice = basePrice + dist; shouldAdd = (currentPrice >= triggerPrice); }
         
         if(shouldLogStatus && m_config.showDebugLogs)
            WriteDebugLog("買入加倉檢查: 基準=" + DoubleToString(basePrice, m_digits) + 
                         ", 累積距離=" + DoubleToString(dist/m_pointValue, 1) + "點" +
                         ", 觸發價=" + DoubleToString(triggerPrice, m_digits) +
                         ", shouldAdd=" + (shouldAdd ? "是" : "否"));
         
         if(shouldAdd)
           {
            double lots = CalculateLots(m_buyGridLevel + 1);
            if(OpenGridOrder(OP_BUY, lots))
              {
               m_buyGridLevel++;
               m_lastOrderBarTime = iTime(m_config.symbol, 0, 0);
               WriteLog("【動態0線】買入加倉 L" + IntegerToString(m_buyGridLevel) + 
                       "，價格=" + DoubleToString(currentPrice, m_digits));
              }
           }
        }
     }
   
   //=== 狀態 3：有賣出籃子，無買入籃子 ===
   if(m_sellGridLevel > 0 && m_buyGridLevel == 0)
     {
      // 檢查是否觸發買入首單（價格突破買入 0 線）
      if(m_config.tradeDirection != TRADE_SELL_ONLY)
        {
         if(shouldLogStatus && m_config.showDebugLogs)
           {
            WriteDebugLog("狀態: 有賣出籃子 L" + IntegerToString(m_sellGridLevel) + "，檢查買入觸發");
            if(m_dynamicBuyZero > 0)
               WriteDebugLog("買入觸發條件: 價格 >= " + DoubleToString(m_dynamicBuyZero, m_digits) + " ? " + (currentPrice >= m_dynamicBuyZero ? "是" : "否"));
           }
         
         if(m_dynamicBuyZero > 0 && currentPrice >= m_dynamicBuyZero)
           {
            WriteLog("【動態0線】價格突破買入0線! 價格=" + DoubleToString(currentPrice, m_digits) + 
                    ", 0線=" + DoubleToString(m_dynamicBuyZero, m_digits));
            double lots = CalculateLots(1);
            if(OpenGridOrder(OP_BUY, lots))
              {
               m_buyGridLevel = 1;
               m_buyBasePrice = m_dynamicBuyZero;  // 以 0 線作為基準價
               m_lastOrderBarTime = iTime(m_config.symbol, 0, 0);
               // 重置賣出 0 線
               m_dynamicSellZero = GetRecentLow(m_config.dynamicZeroBars);
               WriteLog("【動態0線】買入首單 L1 開倉成功，基準價=" + DoubleToString(m_buyBasePrice, m_digits));
               WriteLog("【動態0線】重置賣出0線=" + DoubleToString(m_dynamicSellZero, m_digits));
              }
           }
        }
      
      // 賣出籃子加倉邏輯
      if(m_sellGridLevel > 0 && m_sellGridLevel < m_config.maxGridLevels)
        {
         double dist = CalculateCumulativeDistance(m_sellGridLevel);
         double basePrice = m_sellBasePrice;
         double triggerPrice;
         bool shouldAdd;
         
         if(m_config.gridMode == GRID_MODE_COUNTER)
           { triggerPrice = basePrice + dist; shouldAdd = (currentPrice >= triggerPrice); }
         else
           { triggerPrice = basePrice - dist; shouldAdd = (currentPrice <= triggerPrice); }
         
         if(shouldLogStatus && m_config.showDebugLogs)
            WriteDebugLog("賣出加倉檢查: 基準=" + DoubleToString(basePrice, m_digits) + 
                         ", 累積距離=" + DoubleToString(dist/m_pointValue, 1) + "點" +
                         ", 觸發價=" + DoubleToString(triggerPrice, m_digits) +
                         ", shouldAdd=" + (shouldAdd ? "是" : "否"));
         
         if(shouldAdd)
           {
            double lots = CalculateLots(m_sellGridLevel + 1);
            if(OpenGridOrder(OP_SELL, lots))
              {
               m_sellGridLevel++;
               m_lastOrderBarTime = iTime(m_config.symbol, 0, 0);
               WriteLog("【動態0線】賣出加倉 L" + IntegerToString(m_sellGridLevel) + 
                       "，價格=" + DoubleToString(currentPrice, m_digits));
              }
           }
        }
     }
   
   //=== 狀態 4：雙向都有籃子 - 只處理加倉，不開新首單 ===
   if(m_buyGridLevel > 0 && m_sellGridLevel > 0)
     {
      if(shouldLogStatus && m_config.showDebugLogs)
         WriteDebugLog("狀態: 雙向籃子，等待平倉");
      
      // 買入籃子加倉
      if(m_buyGridLevel < m_config.maxGridLevels)
        {
         double dist = CalculateCumulativeDistance(m_buyGridLevel);
         double triggerPrice;
         bool shouldAdd;
         if(m_config.gridMode == GRID_MODE_COUNTER)
           { triggerPrice = m_buyBasePrice - dist; shouldAdd = (currentPrice <= triggerPrice); }
         else
           { triggerPrice = m_buyBasePrice + dist; shouldAdd = (currentPrice >= triggerPrice); }
         if(shouldAdd)
           {
            double lots = CalculateLots(m_buyGridLevel + 1);
            if(OpenGridOrder(OP_BUY, lots))
              { m_buyGridLevel++; m_lastOrderBarTime = iTime(m_config.symbol, 0, 0); }
           }
        }
      
      // 賣出籃子加倉
      if(m_sellGridLevel < m_config.maxGridLevels)
        {
         double dist = CalculateCumulativeDistance(m_sellGridLevel);
         double triggerPrice;
         bool shouldAdd;
         if(m_config.gridMode == GRID_MODE_COUNTER)
           { triggerPrice = m_sellBasePrice + dist; shouldAdd = (currentPrice >= triggerPrice); }
         else
           { triggerPrice = m_sellBasePrice - dist; shouldAdd = (currentPrice <= triggerPrice); }
         if(shouldAdd)
           {
            double lots = CalculateLots(m_sellGridLevel + 1);
            if(OpenGridOrder(OP_SELL, lots))
              { m_sellGridLevel++; m_lastOrderBarTime = iTime(m_config.symbol, 0, 0); }
           }
        }
     }
  }


//+------------------------------------------------------------------+
//| 傳統模式執行邏輯                                                  |
//+------------------------------------------------------------------+
void CGridsCore::ExecuteTraditionalMode()
  {
   UpdateDynamicZeroLines();
   int signal = GetTrendSignal();
   double currentPrice = MarketInfo(m_config.symbol, MODE_BID);
   bool allowFirst = AllowFirstOrder();
   
   if(m_config.tradeDirection != TRADE_SELL_ONLY)
     {
      if(m_buyGridLevel == 0)
        {
         bool shouldOpenBuy = false;
         if(m_config.enableDynamicZero && m_sellGridLevel > 0 && m_dynamicBuyZero > 0)
           { if(currentPrice >= m_dynamicBuyZero) { shouldOpenBuy = true; WriteLog("動態 0 線觸發買入首單，0 線=" + DoubleToString(m_dynamicBuyZero, m_digits)); } }
         else if(signal == SIGNAL_BUY && allowFirst)
           { shouldOpenBuy = true; }
         if(shouldOpenBuy)
           {
            double lots = CalculateLots(1);
            if(OpenGridOrder(OP_BUY, lots))
              {
               m_buyGridLevel = 1;
               m_buyBasePrice = currentPrice;
               m_lastOrderBarTime = iTime(m_config.symbol, 0, 0);
               if(m_config.enableDynamicZero) { m_dynamicSellZero = 0.0; }
               WriteLog("買入首單 L1，價格=" + DoubleToString(currentPrice, m_digits));
              }
           }
        }
      else if(m_buyGridLevel > 0 && m_buyGridLevel < m_config.maxGridLevels)
        {
         if(AllowAveraging(OP_BUY))
           {
            double dist = CalculateCumulativeDistance(m_buyGridLevel);
            double basePrice = m_buyBasePrice;
            if(m_config.enableDynamicZero && m_dynamicBuyZero > 0) basePrice = m_dynamicBuyZero;
            double triggerPrice; bool shouldAdd;
            if(m_config.gridMode == GRID_MODE_COUNTER) { triggerPrice = basePrice - dist; shouldAdd = (currentPrice <= triggerPrice); }
            else { triggerPrice = basePrice + dist; shouldAdd = (currentPrice >= triggerPrice); }
            if(shouldAdd)
              {
               double lots = CalculateLots(m_buyGridLevel + 1);
               if(OpenGridOrder(OP_BUY, lots)) { m_buyGridLevel++; m_lastOrderBarTime = iTime(m_config.symbol, 0, 0); WriteLog("買入加倉 L" + IntegerToString(m_buyGridLevel)); }
              }
           }
        }
     }
   
   if(m_config.tradeDirection != TRADE_BUY_ONLY)
     {
      if(m_sellGridLevel == 0)
        {
         bool shouldOpenSell = false;
         if(m_config.enableDynamicZero && m_buyGridLevel > 0 && m_dynamicSellZero > 0)
           { if(currentPrice <= m_dynamicSellZero) { shouldOpenSell = true; WriteLog("動態 0 線觸發賣出首單，0 線=" + DoubleToString(m_dynamicSellZero, m_digits)); } }
         else if(signal == SIGNAL_SELL && allowFirst)
           { shouldOpenSell = true; }
         if(shouldOpenSell)
           {
            double lots = CalculateLots(1);
            if(OpenGridOrder(OP_SELL, lots))
              {
               m_sellGridLevel = 1;
               m_sellBasePrice = currentPrice;
               m_lastOrderBarTime = iTime(m_config.symbol, 0, 0);
               if(m_config.enableDynamicZero) { m_dynamicBuyZero = 0.0; }
               WriteLog("賣出首單 L1，價格=" + DoubleToString(currentPrice, m_digits));
              }
           }
        }
      else if(m_sellGridLevel > 0 && m_sellGridLevel < m_config.maxGridLevels)
        {
         if(AllowAveraging(OP_SELL))
           {
            double dist = CalculateCumulativeDistance(m_sellGridLevel);
            double basePrice = m_sellBasePrice;
            if(m_config.enableDynamicZero && m_dynamicSellZero > 0) basePrice = m_dynamicSellZero;
            double triggerPrice; bool shouldAdd;
            if(m_config.gridMode == GRID_MODE_COUNTER) { triggerPrice = basePrice + dist; shouldAdd = (currentPrice >= triggerPrice); }
            else { triggerPrice = basePrice - dist; shouldAdd = (currentPrice <= triggerPrice); }
            if(shouldAdd)
              {
               double lots = CalculateLots(m_sellGridLevel + 1);
               if(OpenGridOrder(OP_SELL, lots)) { m_sellGridLevel++; m_lastOrderBarTime = iTime(m_config.symbol, 0, 0); WriteLog("賣出加倉 L" + IntegerToString(m_sellGridLevel)); }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| 檢查止盈平倉                                                      |
//+------------------------------------------------------------------+
void CGridsCore::CheckTakeProfitClose()
  {
   if(m_config.takeProfit <= 0) return;
   double profit = CalculateGridProfit();
   if(profit >= m_config.takeProfit)
     {
      WriteLog("網格止盈觸發: " + DoubleToString(profit, 2));
      double closedProfit = 0.0;
      if(m_onRequestClose != NULL) { WriteLog("請求外部執行對沖平倉..."); closedProfit = m_onRequestClose(); }
      else { WriteLog("使用內部直接平倉..."); closedProfit = CloseAllPositions(); }
      ResetBaskets();
      if(m_onClose != NULL) m_onClose(closedProfit, TimeCurrent(), MarketInfo(m_config.symbol, MODE_BID));
     }
  }

//+------------------------------------------------------------------+
//| 平倉所有持倉                                                      |
//+------------------------------------------------------------------+
double CGridsCore::CloseAllPositions()
  {
   double totalProfit = CalculateGridProfit();
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderMagicNumber() == m_config.magicNumber && OrderSymbol() == m_config.symbol)
           {
            double price = (OrderType() == OP_BUY) ? MarketInfo(m_config.symbol, MODE_BID) : MarketInfo(m_config.symbol, MODE_ASK);
            if(!OrderClose(OrderTicket(), OrderLots(), price, m_config.slippage, clrYellow))
               WriteLog("平倉失敗 #" + IntegerToString(OrderTicket()) + ": " + IntegerToString(GetLastError()));
           }
        }
     }
   return totalProfit;
  }

//+------------------------------------------------------------------+
//| 重置籃子狀態                                                      |
//+------------------------------------------------------------------+
void CGridsCore::ResetBaskets()
  {
   m_buyGridLevel = 0;
   m_sellGridLevel = 0;
   m_buyBasePrice = 0.0;
   m_sellBasePrice = 0.0;
   m_totalBuyLots = 0.0;
   m_totalSellLots = 0.0;
   m_dynamicBuyZero = 0.0;
   m_dynamicSellZero = 0.0;
   m_hasOpenedFirstBuy = false;
   m_hasOpenedFirstSell = false;
   m_tradedThisSignal = true;
   WriteLog("籃子已重置");
  }

#endif // CGRIDSCORE_V11_MQH
