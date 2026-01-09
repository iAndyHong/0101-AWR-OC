//+------------------------------------------------------------------+
//|                                        CGridsCore_Advanced.mqh |
//|                         網格交易核心 - 進階功能版本                |
//+------------------------------------------------------------------+
//| 版本：2.4-Advanced                                               |
//| 開發者：Kiro-2                                                   |
//| 基於：CGridsCore.mqh v2.3                                        |
//| 功能：動態間距、智能加倉、多時間框架分析                          |
//| 狀態：開發中                                                     |
//| 更新日期：2025-01-04                                             |
//+------------------------------------------------------------------+

#ifndef CGRIDSCORE_ADVANCED_MQH
#define CGRIDSCORE_ADVANCED_MQH

#property version "2.4-Advanced"

//+------------------------------------------------------------------+
//| 常數定義（與原版本相容）                                          |
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

// 進階功能專用常數
#define ADV_MAX_TIMEFRAMES        5      // 最大時間框架數量
#define ADV_VOLATILITY_PERIOD    20      // 波動率計算週期
#define ADV_TREND_STRENGTH_PERIOD 14     // 趨勢強度計算週期

//+------------------------------------------------------------------+
//| 進階網格模式枚舉                                                  |
//+------------------------------------------------------------------+
enum ENUM_ADVANCED_GRID_MODE
{
   ADV_GRID_ADAPTIVE    = 0,     // 自適應網格
   ADV_GRID_VOLATILITY  = 1,     // 波動率網格
   ADV_GRID_FIBONACCI   = 2,     // 費波納契網格
   ADV_GRID_HARMONIC    = 3      // 諧波網格
};

//+------------------------------------------------------------------+
//| 動態間距模式枚舉                                                  |
//+------------------------------------------------------------------+
enum ENUM_DYNAMIC_SPACING
{
   DYNAMIC_ATR_BASED    = 0,     // 基於 ATR
   DYNAMIC_VOLATILITY   = 1,     // 基於波動率
   DYNAMIC_SUPPORT_RESISTANCE = 2, // 基於支撐阻力
   DYNAMIC_FIBONACCI    = 3      // 基於費波納契
};

//+------------------------------------------------------------------+
//| 智能加倉模式枚舉                                                  |
//+------------------------------------------------------------------+
enum ENUM_SMART_AVERAGING
{
   SMART_VOLUME_PROFILE = 0,     // 基於成交量分佈
   SMART_PRICE_ACTION   = 1,     // 基於價格行為
   SMART_MARKET_STRUCTURE = 2,   // 基於市場結構
   SMART_MULTI_TIMEFRAME = 3     // 基於多時間框架
};

//+------------------------------------------------------------------+
//| 進階網格配置結構                                                  |
//+------------------------------------------------------------------+
struct AdvancedGridConfig
{
   // 基本設定（與原版本相容）
   int               magicNumber;
   string            symbol;
   int               slippage;
   double            initialLots;
   int               maxGridLevels;
   double            takeProfit;

   // 進階網格模式
   ENUM_ADVANCED_GRID_MODE advancedMode;
   ENUM_DYNAMIC_SPACING    dynamicSpacing;
   ENUM_SMART_AVERAGING    smartAveraging;

   // 動態間距參數
   double            baseGridStep;           // 基礎間距
   double            atrMultiplier;          // ATR 乘數
   int               atrPeriod;              // ATR 週期
   double            volatilityThreshold;    // 波動率閾值
   double            fibonacciRatio;         // 費波納契比率

   // 智能加倉參數
   double            volumeThreshold;        // 成交量閾值
   double            priceActionSensitivity; // 價格行為敏感度
   int               structureAnalysisPeriod; // 市場結構分析週期

   // 多時間框架設定
   int               timeframes[ADV_MAX_TIMEFRAMES];
   double            timeframeWeights[ADV_MAX_TIMEFRAMES];
   int               timeframeCount;

   // 風險管理
   double            maxDrawdownPercent;     // 最大回撤百分比
   double            dynamicStopLoss;        // 動態停損
   bool              enableTrailingStop;     // 啟用移動停損

   // 除錯設定
   bool              showDebugLogs;
   bool              showAdvancedLogs;
};

//+------------------------------------------------------------------+
//| 市場分析結構                                                      |
//+------------------------------------------------------------------+
struct MarketAnalysis
{
   double            currentVolatility;      // 當前波動率
   double            trendStrength;          // 趨勢強度
   int               marketPhase;            // 市場階段 (0=震盪, 1=趨勢, 2=反轉)
   double            supportLevel;           // 支撐位
   double            resistanceLevel;        // 阻力位
   double            volumeProfile;          // 成交量分佈
   datetime          lastAnalysisTime;       // 上次分析時間
};

//+------------------------------------------------------------------+
//| 進階網格交易核心類別                                              |
//+------------------------------------------------------------------+
class CGridsCore_Advanced
{
private:
   //=== 配置 ===
   AdvancedGridConfig    m_config;
   bool                  m_initialized;

   //=== 市場分析 ===
   MarketAnalysis        m_marketAnalysis;
   double                m_atrValues[ADV_VOLATILITY_PERIOD];
   double                m_priceHistory[100];
   int                   m_priceHistoryIndex;

   //=== 動態網格狀態 ===
   double                m_dynamicGridStep;
   double                m_adaptiveMultiplier;
   int                   m_currentGridLevel;
   double                m_lastGridPrice;

   //=== 多時間框架分析 ===
   struct TimeframeSignal
   {
      int    timeframe;
      int    signal;
      double strength;
      datetime lastUpdate;
   };
   TimeframeSignal       m_timeframeSignals[ADV_MAX_TIMEFRAMES];

   //=== 智能加倉系統 ===
   struct SmartEntry
   {
      double price;
      double confidence;
      int    reason;  // 1=成交量, 2=價格行為, 3=結構, 4=多時間框架
      datetime validUntil;
   };
   SmartEntry            m_smartEntries[20];
   int                   m_smartEntryCount;

   //=== 內部方法 - 市場分析 ===
   void                  UpdateMarketAnalysis();
   double                CalculateVolatility();
   double                CalculateTrendStrength();
   int                   DetermineMarketPhase();
   void                  FindSupportResistance();
   double                AnalyzeVolumeProfile();

   //=== 內部方法 - 動態間距 ===
   double                CalculateDynamicGridStep();
   double                GetATRBasedSpacing();
   double                GetVolatilityBasedSpacing();
   double                GetSupportResistanceSpacing();
   double                GetFibonacciSpacing();

   //=== 內部方法 - 智能加倉 ===
   void                  UpdateSmartEntries();
   bool                  ShouldSmartAverage(int direction);
   double                GetVolumeBasedConfidence();
   double                GetPriceActionConfidence();
   double                GetStructureConfidence();
   double                GetMultiTimeframeConfidence();

   //=== 內部方法 - 多時間框架 ===
   void                  UpdateTimeframeSignals();
   int                   GetTimeframeSignal(int timeframe);
   double                GetSignalStrength(int timeframe);
   int                   GetConsensusSignal();

   //=== 日誌 ===
   void                  WriteLog(string message);
   void                  WriteDebugLog(string message);
   void                  WriteAdvancedLog(string message);

public:
   //=== 建構/解構 ===
                         CGridsCore_Advanced();
                        ~CGridsCore_Advanced();

   //=== 初始化 ===
   bool                  Init(AdvancedGridConfig &config);
   void                  Deinit();
   bool                  IsInitialized() { return m_initialized; }

   //=== 主要執行方法 ===
   void                  Execute();

   //=== 進階功能方法 ===
   void                  EnableAdvancedMode(ENUM_ADVANCED_GRID_MODE mode);
   void                  SetDynamicSpacing(ENUM_DYNAMIC_SPACING mode);
   void                  SetSmartAveraging(ENUM_SMART_AVERAGING mode);
   void                  AddTimeframe(int timeframe, double weight);
   void                  UpdateParameters();

   //=== 狀態查詢 ===
   double                GetCurrentVolatility()     { return m_marketAnalysis.currentVolatility; }
   double                GetTrendStrength()         { return m_marketAnalysis.trendStrength; }
   int                   GetMarketPhase()           { return m_marketAnalysis.marketPhase; }
   double                GetDynamicGridStep()       { return m_dynamicGridStep; }
   int                   GetSmartEntryCount()       { return m_smartEntryCount; }
   string                GetAdvancedStatus();

   //=== 相容性介面（與原版本相同）===
   int                   GetMagicNumber()           { return m_config.magicNumber; }
   string                GetSymbol()                { return m_config.symbol; }
   string                GetVersion()               { return "2.4-Advanced"; }
};

//+------------------------------------------------------------------+
//| 建構函數                                                          |
//+------------------------------------------------------------------+
CGridsCore_Advanced::CGridsCore_Advanced()
{
   m_initialized = false;
   m_currentGridLevel = 0;
   m_lastGridPrice = 0.0;
   m_dynamicGridStep = 0.0;
   m_adaptiveMultiplier = 1.0;
   m_priceHistoryIndex = 0;
   m_smartEntryCount = 0;

   // 初始化市場分析
   m_marketAnalysis.currentVolatility = 0.0;
   m_marketAnalysis.trendStrength = 0.0;
   m_marketAnalysis.marketPhase = 0;
   m_marketAnalysis.supportLevel = 0.0;
   m_marketAnalysis.resistanceLevel = 0.0;
   m_marketAnalysis.volumeProfile = 0.0;
   m_marketAnalysis.lastAnalysisTime = 0;

   WriteLog("CGridsCore_Advanced v2.4 建構完成");
}

//+------------------------------------------------------------------+
//| 解構函數                                                          |
//+------------------------------------------------------------------+
CGridsCore_Advanced::~CGridsCore_Advanced()
{
   Deinit();
}

//+------------------------------------------------------------------+
//| 初始化                                                            |
//+------------------------------------------------------------------+
bool CGridsCore_Advanced::Init(AdvancedGridConfig &config)
{
   m_config = config;

   if(m_config.symbol == "")
      m_config.symbol = Symbol();

   // 初始化多時間框架
   if(m_config.timeframeCount == 0)
   {
      // 預設時間框架設定
      m_config.timeframes[0] = 5;    // M5
      m_config.timeframes[1] = 15;   // M15
      m_config.timeframes[2] = 60;   // H1
      m_config.timeframeWeights[0] = 0.3;
      m_config.timeframeWeights[1] = 0.4;
      m_config.timeframeWeights[2] = 0.3;
      m_config.timeframeCount = 3;
   }

   // 初始化價格歷史
   for(int i = 0; i < 100; i++)
   {
      m_priceHistory[i] = 0.0;
   }

   // 初始化 ATR 陣列
   for(int i = 0; i < ADV_VOLATILITY_PERIOD; i++)
   {
      m_atrValues[i] = 0.0;
   }

   m_initialized = true;

   WriteLog("=== CGridsCore_Advanced v2.4 初始化完成 ===");
   WriteLog("進階模式: " + IntegerToString(m_config.advancedMode));
   WriteLog("動態間距: " + IntegerToString(m_config.dynamicSpacing));
   WriteLog("智能加倉: " + IntegerToString(m_config.smartAveraging));
   WriteLog("多時間框架數量: " + IntegerToString(m_config.timeframeCount));

   return true;
}

//+------------------------------------------------------------------+
//| 反初始化                                                          |
//+------------------------------------------------------------------+
void CGridsCore_Advanced::Deinit()
{
   if(!m_initialized)
      return;

   WriteLog("=== CGridsCore_Advanced 已停止 ===");
   m_initialized = false;
}

//+------------------------------------------------------------------+
//| 更新市場分析                                                      |
//+------------------------------------------------------------------+
void CGridsCore_Advanced::UpdateMarketAnalysis()
{
   datetime currentTime = TimeCurrent();
   if(currentTime - m_marketAnalysis.lastAnalysisTime < 60) // 每分鐘更新一次
      return;

   // 更新價格歷史
   double currentPrice = MarketInfo(m_config.symbol, MODE_BID);
   m_priceHistory[m_priceHistoryIndex] = currentPrice;
   m_priceHistoryIndex = (m_priceHistoryIndex + 1) % 100;

   // 計算市場指標
   m_marketAnalysis.currentVolatility = CalculateVolatility();
   m_marketAnalysis.trendStrength = CalculateTrendStrength();
   m_marketAnalysis.marketPhase = DetermineMarketPhase();
   
   FindSupportResistance();
   m_marketAnalysis.volumeProfile = AnalyzeVolumeProfile();
   
   m_marketAnalysis.lastAnalysisTime = currentTime;

   WriteAdvancedLog("市場分析更新: 波動率=" + DoubleToString(m_marketAnalysis.currentVolatility, 4) +
                   ", 趨勢強度=" + DoubleToString(m_marketAnalysis.trendStrength, 2) +
                   ", 市場階段=" + IntegerToString(m_marketAnalysis.marketPhase));
}

//+------------------------------------------------------------------+
//| 計算波動率                                                        |
//+------------------------------------------------------------------+
double CGridsCore_Advanced::CalculateVolatility()
{
   double atr = iATR(m_config.symbol, 0, ADV_VOLATILITY_PERIOD, 1);
   if(atr <= 0) atr = MarketInfo(m_config.symbol, MODE_POINT) * 100;
   
   // 更新 ATR 歷史
   for(int i = ADV_VOLATILITY_PERIOD - 1; i > 0; i--)
   {
      m_atrValues[i] = m_atrValues[i-1];
   }
   m_atrValues[0] = atr;
   
   // 計算波動率變化率
   double avgATR = 0.0;
   for(int i = 0; i < ADV_VOLATILITY_PERIOD; i++)
   {
      avgATR += m_atrValues[i];
   }
   avgATR /= ADV_VOLATILITY_PERIOD;
   
   return (atr > 0 && avgATR > 0) ? atr / avgATR : 1.0;
}

//+------------------------------------------------------------------+
//| 計算趨勢強度                                                      |
//+------------------------------------------------------------------+
double CGridsCore_Advanced::CalculateTrendStrength()
{
   double adx = iADX(m_config.symbol, 0, ADV_TREND_STRENGTH_PERIOD, PRICE_CLOSE, MODE_MAIN, 1);
   if(adx <= 0) return 0.0;
   
   // 標準化趨勢強度 (0-1)
   return MathMin(1.0, adx / 50.0);
}

//+------------------------------------------------------------------+
//| 判斷市場階段                                                      |
//+------------------------------------------------------------------+
int CGridsCore_Advanced::DetermineMarketPhase()
{
   double volatility = m_marketAnalysis.currentVolatility;
   double trendStrength = m_marketAnalysis.trendStrength;
   
   if(trendStrength > 0.6 && volatility > 1.2)
      return 1; // 強趨勢
   else if(trendStrength < 0.3 && volatility < 0.8)
      return 0; // 震盪
   else
      return 2; // 反轉或過渡
}

//+------------------------------------------------------------------+
//| 尋找支撐阻力                                                      |
//+------------------------------------------------------------------+
void CGridsCore_Advanced::FindSupportResistance()
{
   // 簡化的支撐阻力計算
   double high = iHigh(m_config.symbol, 0, iHighest(m_config.symbol, 0, MODE_HIGH, 20, 1));
   double low = iLow(m_config.symbol, 0, iLowest(m_config.symbol, 0, MODE_LOW, 20, 1));
   
   m_marketAnalysis.resistanceLevel = high;
   m_marketAnalysis.supportLevel = low;
}

//+------------------------------------------------------------------+
//| 分析成交量分佈                                                    |
//+------------------------------------------------------------------+
double CGridsCore_Advanced::AnalyzeVolumeProfile()
{
   // 簡化的成交量分析
   double avgVolume = 0.0;
   for(int i = 1; i <= 20; i++)
   {
      avgVolume += iVolume(m_config.symbol, 0, i);
   }
   avgVolume /= 20.0;
   
   double currentVolume = iVolume(m_config.symbol, 0, 1);
   return (avgVolume > 0) ? currentVolume / avgVolume : 1.0;
}

//+------------------------------------------------------------------+
//| 計算動態網格間距                                                  |
//+------------------------------------------------------------------+
double CGridsCore_Advanced::CalculateDynamicGridStep()
{
   double baseStep = m_config.baseGridStep * MarketInfo(m_config.symbol, MODE_POINT);
   
   switch(m_config.dynamicSpacing)
   {
      case DYNAMIC_ATR_BASED:
         return GetATRBasedSpacing();
      case DYNAMIC_VOLATILITY:
         return GetVolatilityBasedSpacing();
      case DYNAMIC_SUPPORT_RESISTANCE:
         return GetSupportResistanceSpacing();
      case DYNAMIC_FIBONACCI:
         return GetFibonacciSpacing();
      default:
         return baseStep;
   }
}

//+------------------------------------------------------------------+
//| 基於 ATR 的間距                                                   |
//+------------------------------------------------------------------+
double CGridsCore_Advanced::GetATRBasedSpacing()
{
   double atr = iATR(m_config.symbol, 0, m_config.atrPeriod, 1);
   if(atr <= 0) atr = MarketInfo(m_config.symbol, MODE_POINT) * 100;
   
   return atr * m_config.atrMultiplier;
}

//+------------------------------------------------------------------+
//| 基於波動率的間距                                                  |
//+------------------------------------------------------------------+
double CGridsCore_Advanced::GetVolatilityBasedSpacing()
{
   double baseStep = m_config.baseGridStep * MarketInfo(m_config.symbol, MODE_POINT);
   double volatilityMultiplier = MathMax(0.5, MathMin(2.0, m_marketAnalysis.currentVolatility));
   
   return baseStep * volatilityMultiplier;
}

//+------------------------------------------------------------------+
//| 基於支撐阻力的間距                                                |
//+------------------------------------------------------------------+
double CGridsCore_Advanced::GetSupportResistanceSpacing()
{
   double range = m_marketAnalysis.resistanceLevel - m_marketAnalysis.supportLevel;
   if(range <= 0) return m_config.baseGridStep * MarketInfo(m_config.symbol, MODE_POINT);
   
   return range / 10.0; // 將支撐阻力區間分為10等份
}

//+------------------------------------------------------------------+
//| 基於費波納契的間距                                                |
//+------------------------------------------------------------------+
double CGridsCore_Advanced::GetFibonacciSpacing()
{
   double baseStep = m_config.baseGridStep * MarketInfo(m_config.symbol, MODE_POINT);
   
   // 費波納契比率：0.618, 1.0, 1.618
   double fibRatios[] = {0.618, 1.0, 1.618, 2.618};
   int level = m_currentGridLevel % 4;
   
   return baseStep * fibRatios[level] * m_config.fibonacciRatio;
}

//+------------------------------------------------------------------+
//| 主要執行方法                                                      |
//+------------------------------------------------------------------+
void CGridsCore_Advanced::Execute()
{
   if(!m_initialized) return;
   
   // 更新市場分析
   UpdateMarketAnalysis();
   
   // 更新多時間框架信號
   UpdateTimeframeSignals();
   
   // 更新智能進場點
   UpdateSmartEntries();
   
   // 計算動態網格間距
   m_dynamicGridStep = CalculateDynamicGridStep();
   
   WriteAdvancedLog("動態間距更新: " + DoubleToString(m_dynamicGridStep / MarketInfo(m_config.symbol, MODE_POINT), 1) + " 點");
}

//+------------------------------------------------------------------+
//| 更新多時間框架信號                                                |
//+------------------------------------------------------------------+
void CGridsCore_Advanced::UpdateTimeframeSignals()
{
   for(int i = 0; i < m_config.timeframeCount; i++)
   {
      int tf = m_config.timeframes[i];
      m_timeframeSignals[i].timeframe = tf;
      m_timeframeSignals[i].signal = GetTimeframeSignal(tf);
      m_timeframeSignals[i].strength = GetSignalStrength(tf);
      m_timeframeSignals[i].lastUpdate = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| 取得時間框架信號                                                  |
//+------------------------------------------------------------------+
int CGridsCore_Advanced::GetTimeframeSignal(int timeframe)
{
   // 簡化的信號計算（使用移動平均）
   double ma1 = iMA(m_config.symbol, timeframe, 10, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ma2 = iMA(m_config.symbol, timeframe, 20, 0, MODE_SMA, PRICE_CLOSE, 1);
   
   if(ma1 > ma2) return SIGNAL_BUY;
   else if(ma1 < ma2) return SIGNAL_SELL;
   else return SIGNAL_NEUTRAL;
}

//+------------------------------------------------------------------+
//| 取得信號強度                                                      |
//+------------------------------------------------------------------+
double CGridsCore_Advanced::GetSignalStrength(int timeframe)
{
   double rsi = iRSI(m_config.symbol, timeframe, 14, PRICE_CLOSE, 1);
   
   // 基於 RSI 計算信號強度
   if(rsi > 70) return (rsi - 70) / 30.0; // 超買強度
   else if(rsi < 30) return (30 - rsi) / 30.0; // 超賣強度
   else return 0.0;
}

//+------------------------------------------------------------------+
//| 更新智能進場點                                                    |
//+------------------------------------------------------------------+
void CGridsCore_Advanced::UpdateSmartEntries()
{
   m_smartEntryCount = 0;
   
   // 基於不同策略尋找智能進場點
   switch(m_config.smartAveraging)
   {
      case SMART_VOLUME_PROFILE:
         // 基於成交量分佈的進場點
         break;
      case SMART_PRICE_ACTION:
         // 基於價格行為的進場點
         break;
      case SMART_MARKET_STRUCTURE:
         // 基於市場結構的進場點
         break;
      case SMART_MULTI_TIMEFRAME:
         // 基於多時間框架的進場點
         break;
   }
}

//+------------------------------------------------------------------+
//| 取得進階狀態                                                      |
//+------------------------------------------------------------------+
string CGridsCore_Advanced::GetAdvancedStatus()
{
   string status = "進階網格狀態:\n";
   status += "波動率: " + DoubleToString(m_marketAnalysis.currentVolatility, 2) + "\n";
   status += "趨勢強度: " + DoubleToString(m_marketAnalysis.trendStrength, 2) + "\n";
   status += "市場階段: " + IntegerToString(m_marketAnalysis.marketPhase) + "\n";
   status += "動態間距: " + DoubleToString(m_dynamicGridStep / MarketInfo(m_config.symbol, MODE_POINT), 1) + " 點\n";
   status += "智能進場點: " + IntegerToString(m_smartEntryCount) + " 個";
   
   return status;
}

//+------------------------------------------------------------------+
//| 日誌方法                                                          |
//+------------------------------------------------------------------+
void CGridsCore_Advanced::WriteLog(string message)
{
   Print("[CGridsCore_Advanced] " + message);
}

void CGridsCore_Advanced::WriteDebugLog(string message)
{
   if(m_config.showDebugLogs)
      Print("[DEBUG-Advanced] " + message);
}

void CGridsCore_Advanced::WriteAdvancedLog(string message)
{
   if(m_config.showAdvancedLogs)
      Print("[ADVANCED] " + message);
}

#endif // CGRIDSCORE_ADVANCED_MQH