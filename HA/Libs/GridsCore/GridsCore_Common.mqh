//+------------------------------------------------------------------+
//|                                           GridsCore_Common.mqh |
//|                         網格核心共用定義檔                        |
//+------------------------------------------------------------------+
//| 功能：定義所有版本共用的枚舉、常數和介面                          |
//| 用途：確保不同版本間的相容性                                      |
//+------------------------------------------------------------------+

#ifndef GRIDSCORE_COMMON_MQH
#define GRIDSCORE_COMMON_MQH

//+------------------------------------------------------------------+
//| 版本相容性管理                                                    |
//+------------------------------------------------------------------+
#define GRIDSCORE_API_VERSION_MAJOR    2
#define GRIDSCORE_API_VERSION_MINOR    0
#define GRIDSCORE_API_VERSION_PATCH    0

//+------------------------------------------------------------------+
//| 基礎枚舉定義（所有版本必須支援）                                  |
//+------------------------------------------------------------------+
enum ENUM_FILTER_MODE_BASE
{
   FILTER_BULLSBEARS = 0,        // BullsBears Candles
   FILTER_SUPERTREND = 1,        // Super Trend
   FILTER_SIMPLE     = 2         // Simple Grids (無過濾)
};

//+------------------------------------------------------------------+
//| 擴展枚舉定義（進階版本專用）                                      |
//+------------------------------------------------------------------+
enum ENUM_FILTER_MODE_EXTENDED
{
   // 基礎模式（與 BASE 相同）
   FILTER_BULLSBEARS_EXT = 0,
   FILTER_SUPERTREND_EXT = 1,
   FILTER_SIMPLE_EXT     = 2,
   
   // 進階模式（新增）
   FILTER_ADVANCED       = 3,    // 進階過濾
   FILTER_AI_BASED       = 4,    // AI 基礎過濾
   FILTER_MULTI_TF       = 5,    // 多時間框架過濾
   FILTER_VOLUME_PROFILE = 6     // 成交量分佈過濾
};

//+------------------------------------------------------------------+
//| 網格模式枚舉（所有版本通用）                                      |
//+------------------------------------------------------------------+
enum ENUM_GRID_MODE
{
   GRID_MODE_TREND   = 0,        // 順向網格
   GRID_MODE_COUNTER = 1         // 逆向網格
};

//+------------------------------------------------------------------+
//| 交易方向枚舉（所有版本通用）                                      |
//+------------------------------------------------------------------+
enum ENUM_TRADE_DIRECTION
{
   TRADE_BOTH      = 0,          // 雙向交易
   TRADE_BUY_ONLY  = 1,          // 只買
   TRADE_SELL_ONLY = 2           // 只賣
};

//+------------------------------------------------------------------+
//| 版本相容性檢查函數                                                |
//+------------------------------------------------------------------+
bool IsFilterModeCompatible(int filterMode, string coreVersion)
{
   // 基礎模式（0-2）所有版本都支援
   if(filterMode >= 0 && filterMode <= 2)
      return true;
   
   // 進階模式（3+）只有進階版本支援
   if(filterMode >= 3)
   {
      if(StringFind(coreVersion, "Advanced") >= 0 || 
         StringFind(coreVersion, "2.4") >= 0)
         return true;
      else
         return false;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 模式轉換函數                                                      |
//+------------------------------------------------------------------+
int ConvertToBaseMode(int extendedMode)
{
   switch(extendedMode)
   {
      case 0: case 1: case 2:
         return extendedMode; // 基礎模式直接返回
      
      case 3: case 4: case 5: case 6:
         return FILTER_SUPERTREND; // 進階模式降級為 SuperTrend
      
      default:
         return FILTER_SIMPLE; // 未知模式降級為 Simple
   }
}

int ConvertToExtendedMode(int baseMode)
{
   switch(baseMode)
   {
      case FILTER_BULLSBEARS:
         return FILTER_BULLSBEARS_EXT;
      case FILTER_SUPERTREND:
         return FILTER_SUPERTREND_EXT;
      case FILTER_SIMPLE:
         return FILTER_SIMPLE_EXT;
      default:
         return FILTER_SIMPLE_EXT;
   }
}

//+------------------------------------------------------------------+
//| 基礎配置結構（所有版本通用）                                      |
//+------------------------------------------------------------------+
struct GridsCoreConfigBase
{
   // 基本設定
   int               magicNumber;
   string            symbol;
   int               slippage;
   double            gridStep;
   double            initialLots;
   int               maxGridLevels;
   double            takeProfit;
   
   // 基礎過濾設定
   int               filterMode;        // 使用 int 而非 enum 提高相容性
   int               filterTimeframe;
   
   // 基礎參數
   int               bbLookbackBars;
   double            bbThreshold;
   int               stAtrPeriod;
   double            stMultiplier;
   
   // 除錯設定
   bool              showDebugLogs;
};

//+------------------------------------------------------------------+
//| 版本資訊結構                                                      |
//+------------------------------------------------------------------+
struct GridsCoreVersionInfo
{
   string            version;           // 版本字串
   int               majorVersion;      // 主版本號
   int               minorVersion;      // 次版本號
   string            buildType;         // 建置類型 (Stable/Advanced/Performance)
   bool              supportsExtended;  // 是否支援擴展功能
   datetime          buildDate;         // 建置日期
};

//+------------------------------------------------------------------+
//| 基礎介面定義（所有版本必須實現）                                  |
//+------------------------------------------------------------------+
class IGridsCore
{
public:
   // 基本生命週期
   virtual bool              Init(GridsCoreConfigBase &config) = 0;
   virtual void              Deinit() = 0;
   virtual bool              IsInitialized() = 0;
   
   // 基本執行
   virtual void              Execute() = 0;
   
   // 基本狀態查詢
   virtual int               GetMagicNumber() = 0;
   virtual string            GetSymbol() = 0;
   virtual GridsCoreVersionInfo GetVersionInfo() = 0;
   
   // 相容性檢查
   virtual bool              IsCompatibleWith(string requiredVersion) = 0;
   virtual bool              SupportsFilterMode(int filterMode) = 0;
};

#endif // GRIDSCORE_COMMON_MQH