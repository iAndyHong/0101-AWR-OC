//+------------------------------------------------------------------+
//|                                                   CGridsCore.mqh |
//|                              網格交易核心模組 v2.3                |
//+------------------------------------------------------------------+
//| 【模組說明 - 供 Kiro AI 讀取】                                    |
//|                                                                   |
//| 功能：網格交易核心模組，包含網格邏輯和信號計算                    |
//|       不包含 UI、箭頭、獲利追蹤等功能（由 CEACore 統一管理）      |
//|                                                                   |
//| 設計原則：                                                        |
//|   - 處理網格交易核心邏輯                                          |
//|   - 內建信號計算（SuperTrend、BullsBears）                        |
//|   - 透過事件通知外部模組（平倉獲利等）                            |
//|   - 不直接操作 UI 或其他輔助功能                                  |
//|   - 平倉透過回調請求外部執行（支援對沖平倉）                      |
//|   - 支援獨立縮放設定（間距/手數，順向/逆向分開，0=不縮放）        |
//|                                                                   |
//| 引用方式：#include "../Libs/GridsCore/CGridsCore.mqh"             |
//+------------------------------------------------------------------+

#ifndef CGRIDSCORE_MQH
#define CGRIDSCORE_MQH

#property copyright "Recovery System"
#property version   "2.30"
#property strict

//+------------------------------------------------------------------+
//| 常數定義（加入防護避免重複定義）                                  |
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
   FILTER_BULLSBEARS = 0,        // BullsBears Candles
   FILTER_SUPERTREND = 1,        // Super Trend
   FILTER_SIMPLE     = 2         // Simple Grids (無過濾)
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
   // 基本設定
   int               magicNumber;
   string            symbol;
   int               slippage;

   // 網格參數
   ENUM_GRID_MODE    gridMode;
   double            gridStep;
   double            initialLots;
   int               maxGridLevels;
   double            takeProfit;
   bool              oneOrderPerBar;

   // 獨立縮放設定（0=不縮放）
   double            counterGridScaling;    // 逆向間距縮放%
   double            counterLotScaling;     // 逆向手數縮放%
   double            trendGridScaling;      // 順向間距縮放%
   double            trendLotScaling;       // 順向手數縮放%

   // 交易限制
   ENUM_TRADE_DIRECTION tradeDirection;
   int               maxOrdersInWork;
   double            maxSpread;
   double            maxLots;

   // 信號過濾設定
   ENUM_FILTER_MODE  filterMode;
   int               filterTimeframe;

   // BullsBears 參數
   int               bbLookbackBars;
   double            bbThreshold;

   // SuperTrend 參數
   int               stAtrPeriod;
   double            stMultiplier;
   ENUM_SIGNAL_MODE  stSignalMode;
   ENUM_AVERAGING_MODE stAveragingMode;
   bool              stShowLine;
   color             stBullColor;
   color             stBearColor;

   // 日誌設定
   bool              showDebugLogs;
  };

//+------------------------------------------------------------------+
//| 平倉完成回調（通知外部模組獲利金額）                              |
//+------------------------------------------------------------------+
typedef void (*OnCloseCallback)(double profit, datetime time, double price);

//+------------------------------------------------------------------+
//| 請求平倉回調（請求外部執行平倉，返回獲利金額）                    |
//+------------------------------------------------------------------+
typedef double (*OnRequestCloseCallback)(void);


//+------------------------------------------------------------------+
//| 網格交易核心類別                                                  |
//+------------------------------------------------------------------+
class CGridsCore
  {
private:
   //=== 配置 ===
   GridsCoreConfig   m_config;
   bool              m_initialized;

   //=== 市場資訊緩存 ===
   double            m_pointValue;
   int               m_digits;

   //=== 網格狀態 ===
   int               m_buyGridLevel;
   int               m_sellGridLevel;
   double            m_buyBasePrice;
   double            m_sellBasePrice;
   double            m_totalBuyLots;
   double            m_totalSellLots;
   datetime          m_lastOrderBarTime;

   //=== 信號狀態 ===
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

   //=== 回調函數 ===
   OnCloseCallback        m_onClose;
   OnRequestCloseCallback m_onRequestClose;

   //=== 內部方法 - 網格 ===
   double            CalculateLots(int level);
   double            CalculateScaledLots(int level);
   double            CalculateCumulativeDistance(int level);
   double            CalculateScaledGridDistance(int level);
   bool              OpenGridOrder(int orderType, double lots);
   void              CheckTakeProfitClose();
   int               CountGridOrders();
   void              UpdateTotalLots();
   double            CalculateGridProfit();

   //=== 內部方法 - 信號 ===
   int               GetTrendSignal();
   int               CalculateBullsBears();
   int               CalculateSuperTrend();
   void              DrawSuperTrendLine();
   bool              AllowFirstOrder();
   bool              AllowAveraging(int basketDirection);
   bool              IsNewBar(int timeframe);
   int               GetValidTimeframe(int requestedTF, int minBarsRequired);

   //=== 日誌 ===
   void              WriteLog(string message);
   void              WriteDebugLog(string message);

public:
   //=== 建構/解構 ===
                     CGridsCore();
                    ~CGridsCore();

   //=== 初始化 ===
   bool              Init(GridsCoreConfig &config);
   void              Deinit();
   bool              IsInitialized() { return m_initialized; }

   //=== 設定回調函數 ===
   void              SetOnCloseCallback(OnCloseCallback func) { m_onClose = func; }
   void              SetOnRequestCloseCallback(OnRequestCloseCallback func) { m_onRequestClose = func; }

   //=== 主要執行方法 ===
   void              Execute();

   //=== 外部觸發平倉 ===
   double            CloseAllPositions();
   void              ResetBaskets();
   void              SetTradedThisSignal(bool traded) { m_tradedThisSignal = traded; }

   //=== 狀態查詢 ===
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

//+------------------------------------------------------------------+
//| 建構函數                                                          |
//+------------------------------------------------------------------+
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
   m_lastOrderBarTime = 0;

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
  }

//+------------------------------------------------------------------+
//| 解構函數                                                          |
//+------------------------------------------------------------------+
CGridsCore::~CGridsCore()
  {
   Deinit();
  }

//+------------------------------------------------------------------+
//| 初始化                                                            |
//+------------------------------------------------------------------+
bool CGridsCore::Init(GridsCoreConfig &config)
  {
   m_config = config;

   if(m_config.symbol == "")
      m_config.symbol = Symbol();

   m_pointValue = MarketInfo(m_config.symbol, MODE_POINT);
   m_digits = (int)MarketInfo(m_config.symbol, MODE_DIGITS);

   if(m_digits == 5 || m_digits == 3)
      m_pointValue = m_pointValue * 10;

   m_buyGridLevel = 0;
   m_sellGridLevel = 0;
   m_initialized = true;

   WriteLog("=== CGridsCore v2.3 初始化完成 ===");
   WriteLog("網格模式: " + (m_config.gridMode == GRID_MODE_TREND ? "順向網格" : "逆向網格"));
   WriteLog("網格間距: " + DoubleToString(m_config.gridStep, 1) + " 點");
   WriteLog("信號模式: " + GetSignalName());

   if(m_config.gridMode == GRID_MODE_COUNTER)
     {
      WriteLog("逆向間距縮放: " + (m_config.counterGridScaling == 0 ? "不縮放" : DoubleToString(m_config.counterGridScaling, 1) + "%"));
      WriteLog("逆向手數縮放: " + (m_config.counterLotScaling == 0 ? "不縮放" : DoubleToString(m_config.counterLotScaling, 1) + "%"));
     }
   else
     {
      WriteLog("順向間距縮放: " + (m_config.trendGridScaling == 0 ? "不縮放" : DoubleToString(m_config.trendGridScaling, 1) + "%"));
      WriteLog("順向手數縮放: " + (m_config.trendLotScaling == 0 ? "不縮放" : DoubleToString(m_config.trendLotScaling, 1) + "%"));
     }

   return true;
  }

//+------------------------------------------------------------------+
//| 反初始化                                                          |
//+------------------------------------------------------------------+
void CGridsCore::Deinit()
  {
   if(!m_initialized)
      return;

   string objName = "SuperTrend_Line_" + IntegerToString(m_config.magicNumber);
   ObjectDelete(objName);

   WriteLog("=== CGridsCore 已停止 ===");
   m_initialized = false;
  }

//+------------------------------------------------------------------+
//| 日誌輸出                                                          |
//+------------------------------------------------------------------+
void CGridsCore::WriteLog(string message)
  {
   Print("[CGridsCore] " + message);
  }

//+------------------------------------------------------------------+
//| 除錯日誌輸出                                                      |
//+------------------------------------------------------------------+
void CGridsCore::WriteDebugLog(string message)
  {
   if(!m_config.showDebugLogs)
      return;
   WriteLog("[DEBUG] " + message);
  }

//+------------------------------------------------------------------+
//| 取得信號名稱                                                      |
//+------------------------------------------------------------------+
string CGridsCore::GetSignalName()
  {
   switch(m_config.filterMode)
     {
      case FILTER_BULLSBEARS:
         return "BullsBears";
      case FILTER_SUPERTREND:
         return "SuperTrend";
      default:
         return "Simple";
     }
  }

//+------------------------------------------------------------------+
//| 取得方向名稱                                                      |
//+------------------------------------------------------------------+
string CGridsCore::GetDirectionName()
  {
   int signal = GetTrendSignal();
   switch(signal)
     {
      case SIGNAL_BUY:
         return "看漲";
      case SIGNAL_SELL:
         return "看跌";
      default:
         return "中性";
     }
  }

//+------------------------------------------------------------------+
//| 檢查是否為新 K 線                                                 |
//+------------------------------------------------------------------+
bool CGridsCore::IsNewBar(int timeframe)
  {
   if(timeframe == 0)
      timeframe = Period();

   datetime currentBarTime = iTime(m_config.symbol, timeframe, 0);
   if(currentBarTime != m_lastBarTime)
     {
      m_lastBarTime = currentBarTime;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| 取得有效時間框架                                                  |
//+------------------------------------------------------------------+
int CGridsCore::GetValidTimeframe(int requestedTF, int minBarsRequired)
  {
   int tf = requestedTF;
   if(tf == 0)
      return Period();

   int validTFs[] = {1, 5, 15, 30, 60, 240, 1440, 10080, 43200};
   bool isValid = false;

   for(int i = 0; i < ArraySize(validTFs); i++)
     {
      if(tf == validTFs[i])
        {
         isValid = true;
         break;
        }
     }

   if(!isValid)
      return Period();

   if(iBars(m_config.symbol, tf) < minBarsRequired)
      return Period();

   return tf;
  }

//+------------------------------------------------------------------+
//| 取得趨勢信號                                                      |
//+------------------------------------------------------------------+
int CGridsCore::GetTrendSignal()
  {
   int tf = GetValidTimeframe(m_config.filterTimeframe,
                              MathMax(m_config.bbLookbackBars, m_config.stAtrPeriod) + 10);

   if(!IsNewBar(tf) && m_lastTrendCalcTime > 0)
      return m_cachedTrendSignal;

   switch(m_config.filterMode)
     {
      case FILTER_BULLSBEARS:
         m_cachedTrendSignal = CalculateBullsBears();
         break;
      case FILTER_SUPERTREND:
         m_cachedTrendSignal = CalculateSuperTrend();
         break;
      default:
         m_cachedTrendSignal = SIGNAL_NEUTRAL;
         break;
     }
   m_lastTrendCalcTime = TimeCurrent();
   return m_cachedTrendSignal;
  }

//+------------------------------------------------------------------+
//| 計算 BullsBears 信號                                              |
//+------------------------------------------------------------------+
int CGridsCore::CalculateBullsBears()
  {
   int tf = GetValidTimeframe(m_config.filterTimeframe,
                              MathMax(m_config.bbLookbackBars, m_config.stAtrPeriod) + 10);
   m_bullsPower = 0.0;
   m_bearsPower = 0.0;

   for(int i = 1; i <= m_config.bbLookbackBars; i++)
     {
      double open = iOpen(m_config.symbol, tf, i);
      double high = iHigh(m_config.symbol, tf, i);
      double low = iLow(m_config.symbol, tf, i);
      double close = iClose(m_config.symbol, tf, i);

      if(close > open)
        {
         m_bullsPower += (high - open);
         m_bearsPower += (open - low);
        }
      else
        {
         m_bullsPower += (close - low);
         m_bearsPower += (high - close);
        }
     }

   double thresholdMultiplier = 1.0 + m_config.bbThreshold / 100.0;
   if(m_bullsPower > m_bearsPower * thresholdMultiplier)
      return SIGNAL_BUY;
   else
      if(m_bearsPower > m_bullsPower * thresholdMultiplier)
         return SIGNAL_SELL;

   return SIGNAL_NEUTRAL;
  }

//+------------------------------------------------------------------+
//| 計算 SuperTrend 信號                                              |
//+------------------------------------------------------------------+
int CGridsCore::CalculateSuperTrend()
  {
   int tf = GetValidTimeframe(m_config.filterTimeframe,
                              MathMax(m_config.bbLookbackBars, m_config.stAtrPeriod) + 10);

   double dAtr = iATR(m_config.symbol, tf, m_config.stAtrPeriod, 1);
   if(dAtr <= 0 || dAtr == EMPTY_VALUE)
      dAtr = m_pointValue * 100;

   double hl2 = (iHigh(m_config.symbol, tf, 1) + iLow(m_config.symbol, tf, 1)) / 2.0;
   double dUpperLevel = hl2 + m_config.stMultiplier * dAtr;
   double dLowerLevel = hl2 - m_config.stMultiplier * dAtr;
   double close1 = iClose(m_config.symbol, tf, 1);
   double close2 = iClose(m_config.symbol, tf, 2);

   m_superTrendPrevValue = m_superTrendValue;
   m_superTrendPrevDirection = m_superTrendDirection;

   if(m_superTrendValue == 0.0)
     {
      m_superTrendValue = (close1 > hl2) ? dLowerLevel : dUpperLevel;
      m_superTrendDirection = (close1 > hl2) ? 1 : -1;
     }
   else
     {
      if(close1 > m_superTrendPrevValue && close2 <= m_superTrendPrevValue)
        {
         m_superTrendValue = dLowerLevel;
         m_superTrendDirection = 1;
        }
      else
         if(close1 < m_superTrendPrevValue && close2 >= m_superTrendPrevValue)
           {
            m_superTrendValue = dUpperLevel;
            m_superTrendDirection = -1;
           }
         else
            if(m_superTrendPrevValue < dLowerLevel)
              {
               m_superTrendValue = dLowerLevel;
               m_superTrendDirection = 1;
              }
            else
               if(m_superTrendPrevValue > dUpperLevel)
                 {
                  m_superTrendValue = dUpperLevel;
                  m_superTrendDirection = -1;
                 }
               else
                 {
                  m_superTrendValue = m_superTrendPrevValue;
                 }
     }

   m_trendReversed = (m_superTrendDirection != m_superTrendPrevDirection &&
                      m_superTrendPrevDirection != 0);
   if(m_trendReversed)
      m_tradedThisSignal = false;

   if(m_config.stShowLine)
      DrawSuperTrendLine();

   if(m_superTrendDirection == 1)
      return SIGNAL_BUY;
   else
      if(m_superTrendDirection == -1)
         return SIGNAL_SELL;

   return SIGNAL_NEUTRAL;
  }

//+------------------------------------------------------------------+
//| 繪製 SuperTrend 線                                                |
//+------------------------------------------------------------------+
void CGridsCore::DrawSuperTrendLine()
  {
   int tf = GetValidTimeframe(m_config.filterTimeframe,
                              MathMax(m_config.bbLookbackBars, m_config.stAtrPeriod) + 10);

   string objName = "SuperTrend_Line_" + IntegerToString(m_config.magicNumber);
   ObjectDelete(objName);

   datetime time1 = iTime(m_config.symbol, tf, 1);
   datetime time2 = iTime(m_config.symbol, tf, 0);

   ObjectCreate(objName, OBJ_TREND, 0, time1, m_superTrendValue, time2, m_superTrendValue);
   ObjectSet(objName, OBJPROP_COLOR, m_superTrendDirection == 1 ? m_config.stBullColor : m_config.stBearColor);
   ObjectSet(objName, OBJPROP_WIDTH, 2);
   ObjectSet(objName, OBJPROP_RAY, false);
  }

//+------------------------------------------------------------------+
//| 檢查是否允許首單                                                  |
//+------------------------------------------------------------------+
bool CGridsCore::AllowFirstOrder()
  {
   if(m_config.filterMode == FILTER_SIMPLE || m_config.filterMode == FILTER_BULLSBEARS)
      return true;

   if(m_config.filterMode == FILTER_SUPERTREND)
     {
      if(m_config.stSignalMode == SIGNAL_MODE_TREND ||
         m_config.stSignalMode == SIGNAL_MODE_DISABLED)
         return true;

      if(m_config.stSignalMode == SIGNAL_MODE_REVERSAL)
         return (m_trendReversed && !m_tradedThisSignal);
     }

   return true;
  }

//+------------------------------------------------------------------+
//| 檢查是否允許加倉                                                  |
//+------------------------------------------------------------------+
bool CGridsCore::AllowAveraging(int basketDirection)
  {
   if(m_config.filterMode == FILTER_SIMPLE || m_config.filterMode == FILTER_BULLSBEARS)
      return true;

   if(m_config.filterMode == FILTER_SUPERTREND)
     {
      if(m_config.stAveragingMode == AVERAGING_ANY ||
         m_config.stAveragingMode == AVERAGING_DISABLED)
         return true;

      if(m_config.stAveragingMode == AVERAGING_TREND)
        {
         int currentSignal = GetTrendSignal();
         if(basketDirection == OP_BUY)
            return (currentSignal == SIGNAL_BUY || currentSignal == SIGNAL_NEUTRAL);
         if(basketDirection == OP_SELL)
            return (currentSignal == SIGNAL_SELL || currentSignal == SIGNAL_NEUTRAL);
        }
     }

   return true;
  }

//+------------------------------------------------------------------+
//| 計算縮放後的間距（根據網格模式選擇縮放參數，0=不縮放）            |
//+------------------------------------------------------------------+
double CGridsCore::CalculateScaledGridDistance(int level)
  {
   double baseStep = m_config.gridStep * MarketInfo(m_config.symbol, MODE_POINT);

   if(level <= 1)
      return baseStep;

   double scalingPercent = 0.0;
   if(m_config.gridMode == GRID_MODE_COUNTER)
      scalingPercent = m_config.counterGridScaling;
   else
      scalingPercent = m_config.trendGridScaling;

   if(scalingPercent == 0.0)
      return baseStep;

   double scalingFactor = 1.0 + ((level - 1) * scalingPercent / 100.0);
   double scaledDistance = baseStep * scalingFactor;

   WriteDebugLog("層級 " + IntegerToString(level) + " 間距縮放: " +
                 DoubleToString(baseStep / MarketInfo(m_config.symbol, MODE_POINT), 1) + " → " +
                 DoubleToString(scaledDistance / MarketInfo(m_config.symbol, MODE_POINT), 1) + " 點");

   return scaledDistance;
  }

//+------------------------------------------------------------------+
//| 計算累積間距                                                      |
//+------------------------------------------------------------------+
double CGridsCore::CalculateCumulativeDistance(int level)
  {
   if(level <= 0)
      return 0.0;

   double baseStep = m_config.gridStep * MarketInfo(m_config.symbol, MODE_POINT);

   double scalingPercent = 0.0;
   if(m_config.gridMode == GRID_MODE_COUNTER)
      scalingPercent = m_config.counterGridScaling;
   else
      scalingPercent = m_config.trendGridScaling;

// 縮放值為 0 則固定間距
   if(scalingPercent == 0.0)
      return baseStep * level;

// 遞增間距模式
   double total = 0.0;
   for(int i = 0; i < level; i++)
     {
      double stepDistance = baseStep;

      if(i > 0)
        {
         double scalingFactor = 1.0 + (i * scalingPercent / 100.0);
         stepDistance *= scalingFactor;
        }

      total += stepDistance;
     }

   return total;
  }

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| 計算縮放後的手數（根據網格模式選擇縮放參數，0=不縮放）            |
//+------------------------------------------------------------------+
double CGridsCore::CalculateScaledLots(int level)
  {
   double baseLots = m_config.initialLots;
   
   if(level <= 1)
      return baseLots;
   
   double scalingPercent = 0.0;
   if(m_config.gridMode == GRID_MODE_COUNTER)
      scalingPercent = m_config.counterLotScaling;
   else
      scalingPercent = m_config.trendLotScaling;
   
   if(scalingPercent == 0.0)
      return baseLots;
   
   double scalingFactor = 1.0 + ((level - 1) * scalingPercent / 100.0);
   double scaledLots = baseLots * scalingFactor;
   
   WriteDebugLog("層級 " + IntegerToString(level) + " 手數縮放: " + 
                DoubleToString(baseLots, 2) + " → " + 
                DoubleToString(scaledLots, 2));
   
   return scaledLots;
  }

//+------------------------------------------------------------------+
//| 計算手數（整合縮放和市場限制）                                    |
//+------------------------------------------------------------------+
double CGridsCore::CalculateLots(int level)
  {
   if(level <= 0) return m_config.initialLots;
   
   double lots = CalculateScaledLots(level);
   
   if(m_config.maxLots > 0 && lots > m_config.maxLots)
      lots = m_config.maxLots;
   
   double minLot = MarketInfo(m_config.symbol, MODE_MINLOT);
   double lotStep = MarketInfo(m_config.symbol, MODE_LOTSTEP);
   lots = MathFloor(lots / lotStep) * lotStep;
   if(lots < minLot) lots = minLot;
   
   return lots;
  }

//+------------------------------------------------------------------+
//| 開單                                                              |
//+------------------------------------------------------------------+
bool CGridsCore::OpenGridOrder(int orderType, double lots)
  {
   double spread = MarketInfo(m_config.symbol, MODE_SPREAD);
   if(m_config.maxSpread > 0 && spread > m_config.maxSpread)
     {
      WriteDebugLog("點差過大: " + DoubleToString(spread, 1));
      return false;
     }
   
   if(m_config.maxOrdersInWork > 0 && CountGridOrders() >= m_config.maxOrdersInWork)
     {
      WriteDebugLog("訂單數量已達上限");
      return false;
     }
   
   double price = (orderType == OP_BUY) ? MarketInfo(m_config.symbol, MODE_ASK) 
                                        : MarketInfo(m_config.symbol, MODE_BID);
   
   int ticket = OrderSend(m_config.symbol, orderType, lots, price, m_config.slippage, 
                          0, 0, "GC", m_config.magicNumber, 0, 
                          (orderType == OP_BUY) ? clrBlue : clrRed);
   
   if(ticket < 0)
     {
      WriteLog("開單失敗: " + IntegerToString(GetLastError()));
      return false;
     }
   
   WriteDebugLog("開單成功 #" + IntegerToString(ticket) + " " + 
                (orderType == OP_BUY ? "BUY" : "SELL") + " " + 
                DoubleToString(lots, 2) + " @ " + DoubleToString(price, m_digits));
   
   return true;
  }

//+------------------------------------------------------------------+
//| 計算訂單數量                                                      |
//+------------------------------------------------------------------+
int CGridsCore::CountGridOrders()
  {
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderMagicNumber() == m_config.magicNumber && OrderSymbol() == m_config.symbol)
            count++;
        }
     }
   return count;
  }

//+------------------------------------------------------------------+
//| 更新總手數                                                        |
//+------------------------------------------------------------------+
void CGridsCore::UpdateTotalLots()
  {
   m_totalBuyLots = 0.0;
   m_totalSellLots = 0.0;
   
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderMagicNumber() == m_config.magicNumber && OrderSymbol() == m_config.symbol)
           {
            if(OrderType() == OP_BUY)
               m_totalBuyLots += OrderLots();
            else if(OrderType() == OP_SELL)
               m_totalSellLots += OrderLots();
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| 計算網格浮動盈虧                                                  |
//+------------------------------------------------------------------+
double CGridsCore::CalculateGridProfit()
  {
   double profit = 0.0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderMagicNumber() == m_config.magicNumber && OrderSymbol() == m_config.symbol)
            profit += OrderProfit() + OrderSwap() + OrderCommission();
        }
     }
   return profit;
  }

//+------------------------------------------------------------------+
//| 主要執行方法（由外部 OnTick 呼叫）                                |
//+------------------------------------------------------------------+
void CGridsCore::Execute()
  {
   if(!m_initialized) return;
   
   UpdateTotalLots();
   
   int signal = GetTrendSignal();
   
   double currentPrice = MarketInfo(m_config.symbol, MODE_BID);
   
   bool allowFirst = AllowFirstOrder();
   
   if(m_config.oneOrderPerBar && m_lastOrderBarTime == iTime(m_config.symbol, 0, 0))
      return;
   
   //=== 買入籃子邏輯 ===
   if(m_config.tradeDirection != TRADE_SELL_ONLY)
     {
      if(m_buyGridLevel == 0 && signal == SIGNAL_BUY && allowFirst)
        {
         double lots = CalculateLots(1);
         if(OpenGridOrder(OP_BUY, lots))
           {
            m_buyGridLevel = 1;
            m_buyBasePrice = currentPrice;
            m_lastOrderBarTime = iTime(m_config.symbol, 0, 0);
            WriteLog("買入首單 L1，價格=" + DoubleToString(currentPrice, m_digits));
           }
        }
      else if(m_buyGridLevel > 0 && m_buyGridLevel < m_config.maxGridLevels)
        {
         bool allowAvg = AllowAveraging(OP_BUY);
         
         if(allowAvg)
           {
            double dist = CalculateCumulativeDistance(m_buyGridLevel);
            double triggerPrice;
            bool shouldAdd;
            
            if(m_config.gridMode == GRID_MODE_COUNTER)
              {
               triggerPrice = m_buyBasePrice - dist;
               shouldAdd = (currentPrice <= triggerPrice);
              }
            else
              {
               triggerPrice = m_buyBasePrice + dist;
               shouldAdd = (currentPrice >= triggerPrice);
              }
            
            if(shouldAdd)
              {
               double lots = CalculateLots(m_buyGridLevel + 1);
               if(OpenGridOrder(OP_BUY, lots))
                 {
                  m_buyGridLevel++;
                  m_lastOrderBarTime = iTime(m_config.symbol, 0, 0);
                  WriteLog("買入加倉 L" + IntegerToString(m_buyGridLevel));
                 }
              }
           }
        }
     }
   
   //=== 賣出籃子邏輯 ===
   if(m_config.tradeDirection != TRADE_BUY_ONLY)
     {
      if(m_sellGridLevel == 0 && signal == SIGNAL_SELL && allowFirst)
        {
         double lots = CalculateLots(1);
         if(OpenGridOrder(OP_SELL, lots))
           {
            m_sellGridLevel = 1;
            m_sellBasePrice = currentPrice;
            m_lastOrderBarTime = iTime(m_config.symbol, 0, 0);
            WriteLog("賣出首單 L1，價格=" + DoubleToString(currentPrice, m_digits));
           }
        }
      else if(m_sellGridLevel > 0 && m_sellGridLevel < m_config.maxGridLevels)
        {
         bool allowAvg = AllowAveraging(OP_SELL);
         
         if(allowAvg)
           {
            double dist = CalculateCumulativeDistance(m_sellGridLevel);
            double triggerPrice;
            bool shouldAdd;
            
            if(m_config.gridMode == GRID_MODE_COUNTER)
              {
               triggerPrice = m_sellBasePrice + dist;
               shouldAdd = (currentPrice >= triggerPrice);
              }
            else
              {
               triggerPrice = m_sellBasePrice - dist;
               shouldAdd = (currentPrice <= triggerPrice);
              }
            
            if(shouldAdd)
              {
               double lots = CalculateLots(m_sellGridLevel + 1);
               if(OpenGridOrder(OP_SELL, lots))
                 {
                  m_sellGridLevel++;
                  m_lastOrderBarTime = iTime(m_config.symbol, 0, 0);
                  WriteLog("賣出加倉 L" + IntegerToString(m_sellGridLevel));
                 }
              }
           }
        }
     }
   
   CheckTakeProfitClose();
  }

//+------------------------------------------------------------------+
//| 檢查止盈平倉（透過回調請求外部執行對沖平倉）                      |
//+------------------------------------------------------------------+
void CGridsCore::CheckTakeProfitClose()
  {
   if(m_config.takeProfit <= 0) return;
   
   double profit = CalculateGridProfit();
   if(profit >= m_config.takeProfit)
     {
      WriteLog("網格止盈觸發: " + DoubleToString(profit, 2));
      
      double closedProfit = 0.0;
      
      if(m_onRequestClose != NULL)
        {
         WriteLog("請求外部執行對沖平倉...");
         closedProfit = m_onRequestClose();
        }
      else
        {
         WriteLog("使用內部直接平倉...");
         closedProfit = CloseAllPositions();
        }
      
      ResetBaskets();
      
      if(m_onClose != NULL)
         m_onClose(closedProfit, TimeCurrent(), MarketInfo(m_config.symbol, MODE_BID));
     }
  }

//+------------------------------------------------------------------+
//| 平倉所有持倉（內部備用方法，無對沖）                              |
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
            double price = (OrderType() == OP_BUY) ? MarketInfo(m_config.symbol, MODE_BID) 
                                                   : MarketInfo(m_config.symbol, MODE_ASK);
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
   m_tradedThisSignal = true;
   WriteLog("籃子已重置");
  }

#endif // CGRIDSCORE_MQH
