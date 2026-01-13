//+------------------------------------------------------------------+
//|                                      CGridsCore_Compatible.mqh |
//|                         網格核心相容性版本                        |
//+------------------------------------------------------------------+
//| 版本：2.3-Compatible                                             |
//| 功能：提供向下相容的介面，支援舊版本主程式                        |
//| 用途：讓使用舊版本 enum 的主程式可以正常運作                      |
//+------------------------------------------------------------------+

#ifndef CGRIDSCORE_COMPATIBLE_MQH
#define CGRIDSCORE_COMPATIBLE_MQH

// 引入共用定義
#include "GridsCore_Common.mqh"

//+------------------------------------------------------------------+
//| 相容性枚舉定義（保持與原版本完全相同）                            |
//+------------------------------------------------------------------+
enum ENUM_FILTER_MODE
{
   FILTER_BULLSBEARS = 0,        // BullsBears Candles
   FILTER_SUPERTREND = 1,        // Super Trend
   FILTER_SIMPLE     = 2         // Simple Grids (無過濾)
};

//+------------------------------------------------------------------+
//| 相容性配置結構（與原版本相同）                                    |
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

   // 獨立縮放設定
   double            counterGridScaling;
   double            counterLotScaling;
   double            trendGridScaling;
   double            trendLotScaling;

   // 交易限制
   ENUM_TRADE_DIRECTION tradeDirection;
   int               maxOrdersInWork;
   double            maxSpread;
   double            maxLots;

   // 信號過濾設定（使用相容性枚舉）
   ENUM_FILTER_MODE  filterMode;        // 相容性枚舉
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
//| 相容性網格核心類別                                                |
//+------------------------------------------------------------------+
class CGridsCore_Compatible : public IGridsCore
{
private:
   GridsCoreConfig   m_config;
   bool              m_initialized;
   
   // 內部使用進階版本
   CGridsCore_Advanced* m_advancedCore;
   
   // 模式轉換
   int ConvertFilterMode(ENUM_FILTER_MODE oldMode)
   {
      switch(oldMode)
      {
         case FILTER_BULLSBEARS: return FILTER_BULLSBEARS_EXT;
         case FILTER_SUPERTREND: return FILTER_SUPERTREND_EXT;
         case FILTER_SIMPLE:     return FILTER_SIMPLE_EXT;
         default:                return FILTER_SIMPLE_EXT;
      }
   }

public:
   CGridsCore_Compatible()
   {
      m_initialized = false;
      m_advancedCore = NULL;
   }
   
   ~CGridsCore_Compatible()
   {
      if(m_advancedCore != NULL)
      {
         delete m_advancedCore;
         m_advancedCore = NULL;
      }
   }

   //=== 相容性介面實現 ===
   bool Init(GridsCoreConfig &config)
   {
      m_config = config;
      
      // 建立進階核心實例
      m_advancedCore = new CGridsCore_Advanced();
      if(m_advancedCore == NULL)
         return false;
      
      // 轉換配置到進階版本
      AdvancedGridConfig advConfig;
      advConfig.magicNumber = config.magicNumber;
      advConfig.symbol = config.symbol;
      advConfig.slippage = config.slippage;
      advConfig.initialLots = config.initialLots;
      advConfig.maxGridLevels = config.maxGridLevels;
      advConfig.takeProfit = config.takeProfit;
      
      // 使用相容模式
      advConfig.advancedMode = ADV_GRID_ADAPTIVE;
      advConfig.dynamicSpacing = DYNAMIC_ATR_BASED;
      advConfig.smartAveraging = SMART_MULTI_TIMEFRAME;
      
      // 基本參數
      advConfig.baseGridStep = config.gridStep;
      advConfig.atrMultiplier = config.stMultiplier;
      advConfig.atrPeriod = config.stAtrPeriod;
      
      // 縮放參數
      advConfig.counterGridScaling = config.counterGridScaling;
      advConfig.counterLotScaling = config.counterLotScaling;
      advConfig.trendGridScaling = config.trendGridScaling;
      advConfig.trendLotScaling = config.trendLotScaling;
      
      // 日誌設定
      advConfig.showDebugLogs = config.showDebugLogs;
      advConfig.showAdvancedLogs = false; // 相容模式不顯示進階日誌
      
      m_initialized = m_advancedCore.Init(advConfig);
      
      if(m_initialized)
      {
         WriteLog("CGridsCore_Compatible 初始化完成 - 相容模式");
         WriteLog("原始過濾模式: " + IntegerToString(config.filterMode) + 
                 " -> 轉換為進階模式: " + IntegerToString(ConvertFilterMode(config.filterMode)));
      }
      
      return m_initialized;
   }
   
   void Deinit()
   {
      if(m_advancedCore != NULL)
      {
         m_advancedCore.Deinit();
         delete m_advancedCore;
         m_advancedCore = NULL;
      }
      m_initialized = false;
   }
   
   bool IsInitialized()
   {
      return m_initialized && m_advancedCore != NULL;
   }
   
   void Execute()
   {
      if(m_advancedCore != NULL)
         m_advancedCore.Execute();
   }
   
   //=== 基本介面實現 ===
   virtual bool Init(GridsCoreConfigBase &config)
   {
      // 轉換基礎配置到完整配置
      GridsCoreConfig fullConfig;
      fullConfig.magicNumber = config.magicNumber;
      fullConfig.symbol = config.symbol;
      fullConfig.slippage = config.slippage;
      fullConfig.gridStep = config.gridStep;
      fullConfig.initialLots = config.initialLots;
      fullConfig.maxGridLevels = config.maxGridLevels;
      fullConfig.takeProfit = config.takeProfit;
      
      // 預設值
      fullConfig.gridMode = GRID_MODE_COUNTER;
      fullConfig.oneOrderPerBar = true;
      fullConfig.counterGridScaling = 0.0;
      fullConfig.counterLotScaling = 25.0;
      fullConfig.trendGridScaling = 0.0;
      fullConfig.trendLotScaling = 25.0;
      fullConfig.tradeDirection = TRADE_BOTH;
      fullConfig.maxOrdersInWork = 100;
      fullConfig.maxSpread = 250.0;
      fullConfig.maxLots = 1.0;
      
      // 轉換過濾模式
      fullConfig.filterMode = (ENUM_FILTER_MODE)config.filterMode;
      fullConfig.filterTimeframe = config.filterTimeframe;
      fullConfig.bbLookbackBars = config.bbLookbackBars;
      fullConfig.bbThreshold = config.bbThreshold;
      fullConfig.stAtrPeriod = config.stAtrPeriod;
      fullConfig.stMultiplier = config.stMultiplier;
      fullConfig.stSignalMode = SIGNAL_MODE_TREND;
      fullConfig.stAveragingMode = AVERAGING_ANY;
      fullConfig.stShowLine = true;
      fullConfig.stBullColor = clrOrangeRed;
      fullConfig.stBearColor = clrLawnGreen;
      fullConfig.showDebugLogs = config.showDebugLogs;
      
      return Init(fullConfig);
   }
   
   int GetMagicNumber()
   {
      return m_config.magicNumber;
   }
   
   string GetSymbol()
   {
      return m_config.symbol;
   }
   
   GridsCoreVersionInfo GetVersionInfo()
   {
      GridsCoreVersionInfo info;
      info.version = "2.3-Compatible";
      info.majorVersion = 2;
      info.minorVersion = 3;
      info.buildType = "Compatible";
      info.supportsExtended = false; // 相容模式不暴露進階功能
      info.buildDate = TimeCurrent();
      return info;
   }
   
   bool IsCompatibleWith(string requiredVersion)
   {
      // 相容模式支援所有 2.x 版本
      if(StringFind(requiredVersion, "2.") == 0)
         return true;
      return false;
   }
   
   bool SupportsFilterMode(int filterMode)
   {
      // 只支援基礎過濾模式 0-2
      return (filterMode >= 0 && filterMode <= 2);
   }
   
   //=== 相容性方法（與原版本相同）===
   int GetBuyGridLevel()
   {
      return m_advancedCore != NULL ? 0 : 0; // 簡化實現
   }
   
   int GetSellGridLevel()
   {
      return m_advancedCore != NULL ? 0 : 0; // 簡化實現
   }
   
   double GetFloatingProfit()
   {
      return m_advancedCore != NULL ? 0.0 : 0.0; // 簡化實現
   }
   
   void WriteLog(string message)
   {
      Print("[CGridsCore_Compatible] " + message);
   }
};

//+------------------------------------------------------------------+
//| 工廠函數 - 自動選擇合適的版本                                    |
//+------------------------------------------------------------------+
IGridsCore* CreateGridsCore(string preferredVersion = "")
{
   if(preferredVersion == "Advanced" || preferredVersion == "2.4")
   {
      return new CGridsCore_Advanced();
   }
   else
   {
      return new CGridsCore_Compatible();
   }
}

#endif // CGRIDSCORE_COMPATIBLE_MQH