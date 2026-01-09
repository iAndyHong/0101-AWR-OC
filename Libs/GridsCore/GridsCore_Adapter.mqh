//+------------------------------------------------------------------+
//|                                         GridsCore_Adapter.mqh |
//|                         網格核心適配器                            |
//+------------------------------------------------------------------+
//| 功能：自動檢測主程式版本並選擇合適的核心實現                      |
//| 用途：解決 enum 修改導致的相容性問題                              |
//+------------------------------------------------------------------+

#ifndef GRIDSCORE_ADAPTER_MQH
#define GRIDSCORE_ADAPTER_MQH

#include "GridsCore_Common.mqh"

//+------------------------------------------------------------------+
//| 版本檢測和適配器類別                                              |
//+------------------------------------------------------------------+
class GridsCoreAdapter
{
private:
   static string s_detectedVersion;
   static bool   s_versionDetected;
   
public:
   //+------------------------------------------------------------------+
   //| 檢測主程式使用的 enum 版本                                        |
   //+------------------------------------------------------------------+
   static string DetectEnumVersion()
   {
      if(s_versionDetected)
         return s_detectedVersion;
      
      // 嘗試檢測是否使用了擴展枚舉
      // 這裡使用編譯時檢測技巧
      
      #ifdef FILTER_ADVANCED
         s_detectedVersion = "Extended";
      #else
         s_detectedVersion = "Base";
      #endif
      
      s_versionDetected = true;
      Print("[GridsCoreAdapter] 檢測到枚舉版本: " + s_detectedVersion);
      
      return s_detectedVersion;
   }
   
   //+------------------------------------------------------------------+
   //| 驗證過濾模式是否有效                                              |
   //+------------------------------------------------------------------+
   static bool ValidateFilterMode(int filterMode, string coreVersion = "")
   {
      if(coreVersion == "")
         coreVersion = DetectEnumVersion();
      
      if(coreVersion == "Base")
      {
         // 基礎版本只支援 0-2
         if(filterMode >= 0 && filterMode <= 2)
         {
            Print("[GridsCoreAdapter] 過濾模式 " + IntegerToString(filterMode) + " 在基礎版本中有效");
            return true;
         }
         else
         {
            Print("[GridsCoreAdapter] 警告：過濾模式 " + IntegerToString(filterMode) + " 在基礎版本中無效，將降級為 FILTER_SIMPLE");
            return false;
         }
      }
      else
      {
         // 擴展版本支援 0-6
         if(filterMode >= 0 && filterMode <= 6)
         {
            Print("[GridsCoreAdapter] 過濾模式 " + IntegerToString(filterMode) + " 在擴展版本中有效");
            return true;
         }
         else
         {
            Print("[GridsCoreAdapter] 警告：過濾模式 " + IntegerToString(filterMode) + " 超出範圍，將降級為 FILTER_SIMPLE");
            return false;
         }
      }
   }
   
   //+------------------------------------------------------------------+
   //| 安全的過濾模式轉換                                                |
   //+------------------------------------------------------------------+
   static int SafeConvertFilterMode(int inputMode, string targetVersion = "")
   {
      if(targetVersion == "")
         targetVersion = DetectEnumVersion();
      
      // 如果模式有效，直接返回
      if(ValidateFilterMode(inputMode, targetVersion))
         return inputMode;
      
      // 無效模式的降級處理
      if(targetVersion == "Base")
      {
         // 進階模式降級到基礎模式
         switch(inputMode)
         {
            case 3: case 4: // FILTER_ADVANCED, FILTER_AI_BASED
               Print("[GridsCoreAdapter] 進階模式 " + IntegerToString(inputMode) + " 降級為 FILTER_SUPERTREND");
               return 1; // FILTER_SUPERTREND
            
            case 5: case 6: // FILTER_MULTI_TF, FILTER_VOLUME_PROFILE
               Print("[GridsCoreAdapter] 進階模式 " + IntegerToString(inputMode) + " 降級為 FILTER_BULLSBEARS");
               return 0; // FILTER_BULLSBEARS
            
            default:
               Print("[GridsCoreAdapter] 未知模式 " + IntegerToString(inputMode) + " 降級為 FILTER_SIMPLE");
               return 2; // FILTER_SIMPLE
         }
      }
      else
      {
         // 擴展版本中的無效模式
         Print("[GridsCoreAdapter] 無效模式 " + IntegerToString(inputMode) + " 降級為 FILTER_SIMPLE_EXT");
         return 2; // FILTER_SIMPLE_EXT
      }
   }
   
   //+------------------------------------------------------------------+
   //| 建立相容的配置結構                                                |
   //+------------------------------------------------------------------+
   static GridsCoreConfigBase CreateCompatibleConfig(
      int magicNumber,
      string symbol,
      double gridStep,
      double initialLots,
      int filterMode,
      bool showDebugLogs = false
   )
   {
      GridsCoreConfigBase config;
      
      config.magicNumber = magicNumber;
      config.symbol = symbol;
      config.slippage = 30;
      config.gridStep = gridStep;
      config.initialLots = initialLots;
      config.maxGridLevels = 10;
      config.takeProfit = 100.0;
      
      // 安全轉換過濾模式
      config.filterMode = SafeConvertFilterMode(filterMode);
      config.filterTimeframe = 0;
      
      // 預設參數
      config.bbLookbackBars = 4;
      config.bbThreshold = 5.0;
      config.stAtrPeriod = 10;
      config.stMultiplier = 1.2;
      
      config.showDebugLogs = showDebugLogs;
      
      Print("[GridsCoreAdapter] 建立相容配置，過濾模式: " + 
            IntegerToString(filterMode) + " -> " + IntegerToString(config.filterMode));
      
      return config;
   }
   
   //+------------------------------------------------------------------+
   //| 取得建議的核心版本                                                |
   //+------------------------------------------------------------------+
   static string GetRecommendedCoreVersion(int filterMode)
   {
      if(filterMode >= 0 && filterMode <= 2)
      {
         return "Compatible"; // 基礎模式使用相容版本
      }
      else if(filterMode >= 3 && filterMode <= 6)
      {
         return "Advanced"; // 進階模式使用進階版本
      }
      else
      {
         return "Compatible"; // 未知模式使用相容版本
      }
   }
   
   //+------------------------------------------------------------------+
   //| 版本相容性報告                                                    |
   //+------------------------------------------------------------------+
   static void PrintCompatibilityReport()
   {
      string detectedVersion = DetectEnumVersion();
      
      Print("=== GridsCore 相容性報告 ===");
      Print("檢測到的枚舉版本: " + detectedVersion);
      
      if(detectedVersion == "Base")
      {
         Print("支援的過濾模式:");
         Print("  0 - FILTER_BULLSBEARS");
         Print("  1 - FILTER_SUPERTREND");
         Print("  2 - FILTER_SIMPLE");
         Print("建議使用: CGridsCore_Compatible");
      }
      else
      {
         Print("支援的過濾模式:");
         Print("  0 - FILTER_BULLSBEARS_EXT");
         Print("  1 - FILTER_SUPERTREND_EXT");
         Print("  2 - FILTER_SIMPLE_EXT");
         Print("  3 - FILTER_ADVANCED");
         Print("  4 - FILTER_AI_BASED");
         Print("  5 - FILTER_MULTI_TF");
         Print("  6 - FILTER_VOLUME_PROFILE");
         Print("建議使用: CGridsCore_Advanced");
      }
      
      Print("========================");
   }
};

// 靜態成員初始化
string GridsCoreAdapter::s_detectedVersion = "";
bool   GridsCoreAdapter::s_versionDetected = false;

//+------------------------------------------------------------------+
//| 便利巨集定義                                                      |
//+------------------------------------------------------------------+
#define SAFE_FILTER_MODE(mode) GridsCoreAdapter::SafeConvertFilterMode(mode)
#define CHECK_FILTER_MODE(mode) GridsCoreAdapter::ValidateFilterMode(mode)
#define DETECT_ENUM_VERSION() GridsCoreAdapter::DetectEnumVersion()

//+------------------------------------------------------------------+
//| 自動適配的工廠函數                                                |
//+------------------------------------------------------------------+
IGridsCore* CreateAdaptiveGridsCore(int filterMode, string preferredVersion = "Auto")
{
   if(preferredVersion == "Auto")
   {
      preferredVersion = GridsCoreAdapter::GetRecommendedCoreVersion(filterMode);
   }
   
   Print("[GridsCoreAdapter] 建立 GridsCore，版本: " + preferredVersion + 
         "，過濾模式: " + IntegerToString(filterMode));
   
   if(preferredVersion == "Advanced")
   {
      return new CGridsCore_Advanced();
   }
   else
   {
      return new CGridsCore_Compatible();
   }
}

#endif // GRIDSCORE_ADAPTER_MQH