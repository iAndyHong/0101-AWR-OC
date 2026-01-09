//+------------------------------------------------------------------+
//| Utils.mqh                                                        |
//| 工具函數模組                                                      |
//+------------------------------------------------------------------+

#ifndef UTILS_MQH
#define UTILS_MQH

//+------------------------------------------------------------------+
//| 常數定義（加入防護避免重複定義）                                  |
//+------------------------------------------------------------------+
#ifndef EA_STATUS_INIT
#define EA_STATUS_INIT      0    // 初始化中
#endif
#ifndef EA_STATUS_RUNNING
#define EA_STATUS_RUNNING   1    // 正常運行
#endif
#ifndef EA_STATUS_PAUSED
#define EA_STATUS_PAUSED    2    // 暫停交易
#endif
#ifndef EA_STATUS_ERROR
#define EA_STATUS_ERROR     3    // 錯誤狀態
#endif
#ifndef EA_STATUS_CLOSING
#define EA_STATUS_CLOSING   4    // 關閉中
#endif

#define TRADE_BUY           0    // 買入
#define TRADE_SELL          1    // 賣出

// 錯誤類型常數
#define ERROR_TYPE_TRADE    1    // 交易錯誤
#define ERROR_TYPE_SYSTEM   2    // 系統錯誤
#define ERROR_TYPE_LOGIC    3    // 邏輯錯誤

// 日誌級別常數
#define LOG_LEVEL_DEBUG     0    // 調試級別
#define LOG_LEVEL_INFO      1    // 資訊級別
#define LOG_LEVEL_WARNING   2    // 警告級別
#define LOG_LEVEL_ERROR     3    // 錯誤級別

//+------------------------------------------------------------------+
//| 全域變數                                                          |
//+------------------------------------------------------------------+
static datetime g_utils_lastBarTime = 0;    // 上一個K線時間
static int g_logLevel = LOG_LEVEL_INFO;     // 預設日誌級別

//+------------------------------------------------------------------+
//| 錯誤描述函數                                                      |
//+------------------------------------------------------------------+
string ErrorDescription(int error_code)
{
   switch(error_code)
   {
      case 0:   return "無錯誤";
      case 1:   return "無錯誤但結果未知";
      case 2:   return "一般錯誤";
      case 3:   return "無效的交易參數";
      case 4:   return "交易伺服器忙碌";
      case 5:   return "舊版客戶端";
      case 6:   return "無連線";
      case 7:   return "權限不足";
      case 8:   return "請求過於頻繁";
      case 9:   return "操作異常";
      case 64:  return "帳戶被禁用";
      case 65:  return "無效帳戶";
      case 128: return "交易超時";
      case 129: return "無效價格";
      case 130: return "無效停損";
      case 131: return "無效手數";
      case 132: return "市場關閉";
      case 133: return "交易被禁用";
      case 134: return "資金不足";
      case 135: return "價格已改變";
      case 136: return "無報價";
      case 137: return "經紀商忙碌";
      case 138: return "重新報價";
      case 139: return "訂單被鎖定";
      case 140: return "只允許買入";
      case 141: return "請求過多";
      case 145: return "修改被禁止";
      case 146: return "交易上下文忙碌";
      case 147: return "到期日被禁用";
      case 148: return "訂單過多";
      case 149: return "對沖被禁止";
      case 150: return "FIFO 規則違反";
      default:  return "錯誤 " + IntegerToString(error_code);
   }
}

//+------------------------------------------------------------------+
//| 檢查是否為新K線（支援指定時間框架）                               |
//+------------------------------------------------------------------+
bool IsNewBar(int timeframe = 0)
{
   if(timeframe == 0)
      timeframe = Period();
      
   datetime currentBarTime = iTime(Symbol(), timeframe, 0);
   if(currentBarTime != g_utils_lastBarTime)
   {
      g_utils_lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| 取得有效時間框架                                                  |
//+------------------------------------------------------------------+
int GetValidTimeframe(int requestedTF, int minBarsRequired = 20)
{
   int tf = requestedTF;
   if(tf == 0)
      return Period();
      
   // 有效的時間框架列表
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
      
   // 檢查是否有足夠的K線數據
   if(iBars(Symbol(), tf) < minBarsRequired)
      return Period();
      
   return tf;
}


//+------------------------------------------------------------------+
//| 錯誤處理類別                                                      |
//+------------------------------------------------------------------+
class ErrorHandler
{
public:
   //+------------------------------------------------------------------+
   //| 處理交易錯誤                                                      |
   //+------------------------------------------------------------------+
   static bool HandleTradeError(int error_code)
   {
      switch(error_code)
      {
         case ERR_NO_ERROR:
            return true;
            
         case ERR_SERVER_BUSY:
         case ERR_NO_CONNECTION:
         case ERR_TOO_FREQUENT_REQUESTS:
            Utils::ErrorPrint("HandleTradeError", "網路連線問題，錯誤代碼: " + IntegerToString(error_code));
            Sleep(1000);
            return false;
            
         case ERR_NOT_ENOUGH_MONEY:
            Utils::ErrorPrint("HandleTradeError", "資金不足，錯誤代碼: " + IntegerToString(error_code));
            return false;
            
         case ERR_INVALID_PRICE:
         case ERR_INVALID_STOPS:
            Utils::ErrorPrint("HandleTradeError", "價格異常，錯誤代碼: " + IntegerToString(error_code));
            return false;
            
         default:
            Utils::ErrorPrint("HandleTradeError", "未知交易錯誤，錯誤代碼: " + IntegerToString(error_code));
            return false;
      }
   }
   
   //+------------------------------------------------------------------+
   //| 記錄錯誤日誌                                                      |
   //+------------------------------------------------------------------+
   static void LogError(string function, int error_code, string description)
   {
      string error_msg = "[錯誤] " + function + "(): " + description + 
                        " (錯誤代碼: " + IntegerToString(error_code) + ")";
      Print(error_msg);
   }
   
   //+------------------------------------------------------------------+
   //| 從錯誤中恢復                                                      |
   //+------------------------------------------------------------------+
   static bool RecoverFromError(int error_type)
   {
      switch(error_type)
      {
         case ERROR_TYPE_TRADE:
            Utils::InfoPrint("嘗試從交易錯誤中恢復");
            Sleep(2000);
            return true;
            
         case ERROR_TYPE_SYSTEM:
            Utils::InfoPrint("嘗試從系統錯誤中恢復");
            return true;
            
         case ERROR_TYPE_LOGIC:
            Utils::InfoPrint("嘗試從邏輯錯誤中恢復");
            return true;
            
         default:
            Utils::ErrorPrint("RecoverFromError", "未知錯誤類型: " + IntegerToString(error_type));
            return false;
      }
   }
   
   //+------------------------------------------------------------------+
   //| 安全關閉                                                          |
   //+------------------------------------------------------------------+
   static void SafeShutdown()
   {
      Utils::InfoPrint("執行安全關閉程序");
      Utils::InfoPrint("安全關閉完成");
   }
};

//+------------------------------------------------------------------+
//| 工具函數類別                                                      |
//+------------------------------------------------------------------+
class Utils
{
public:
   //+------------------------------------------------------------------+
   //| 調試日誌輸出                                                      |
   //+------------------------------------------------------------------+
   static void DebugPrint(string message, bool show_debug = true)
   {
      if(show_debug && g_logLevel <= LOG_LEVEL_DEBUG)
         Print("[調試] " + TimeToString(TimeCurrent()) + " - " + message);
   }
   
   //+------------------------------------------------------------------+
   //| 錯誤日誌輸出                                                      |
   //+------------------------------------------------------------------+
   static void ErrorPrint(string function, string message)
   {
      if(g_logLevel <= LOG_LEVEL_ERROR)
         Print("[錯誤] " + function + "(): " + message + " (時間: " + TimeToString(TimeCurrent()) + ")");
   }
   
   //+------------------------------------------------------------------+
   //| 資訊日誌輸出                                                      |
   //+------------------------------------------------------------------+
   static void InfoPrint(string message)
   {
      if(g_logLevel <= LOG_LEVEL_INFO)
         Print("[資訊] " + TimeToString(TimeCurrent()) + " - " + message);
   }
   
   //+------------------------------------------------------------------+
   //| 警告日誌輸出                                                      |
   //+------------------------------------------------------------------+
   static void WarningPrint(string message)
   {
      if(g_logLevel <= LOG_LEVEL_WARNING)
         Print("[警告] " + TimeToString(TimeCurrent()) + " - " + message);
   }
   
   //+------------------------------------------------------------------+
   //| 設定日誌級別                                                      |
   //+------------------------------------------------------------------+
   static void SetLogLevel(int level)
   {
      g_logLevel = level;
      InfoPrint("日誌級別設定為: " + IntegerToString(level));
   }
   
   //+------------------------------------------------------------------+
   //| 標準化價格                                                        |
   //+------------------------------------------------------------------+
   static double NormalizePrice(double price)
   {
      return NormalizeDouble(price, Digits);
   }
   
   //+------------------------------------------------------------------+
   //| 標準化手數                                                        |
   //+------------------------------------------------------------------+
   static double NormalizeLots(double lots)
   {
      double min_lot = MarketInfo(Symbol(), MODE_MINLOT);
      double max_lot = MarketInfo(Symbol(), MODE_MAXLOT);
      double lot_step = MarketInfo(Symbol(), MODE_LOTSTEP);
      
      if(lots < min_lot) lots = min_lot;
      if(lots > max_lot) lots = max_lot;
      
      lots = NormalizeDouble(lots / lot_step, 0) * lot_step;
      
      return NormalizeDouble(lots, 2);
   }
   
   //+------------------------------------------------------------------+
   //| 驗證價格有效性                                                    |
   //+------------------------------------------------------------------+
   static bool IsValidPrice(double price)
   {
      if(price <= 0) return false;
      if(price != price) return false;
      
      double min_price = MarketInfo(Symbol(), MODE_MINLOT) * MarketInfo(Symbol(), MODE_TICKVALUE);
      if(price < min_price) return false;
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| 驗證手數有效性                                                    |
   //+------------------------------------------------------------------+
   static bool IsValidLots(double lots)
   {
      if(lots <= 0) return false;
      if(lots != lots) return false;
      
      double min_lot = MarketInfo(Symbol(), MODE_MINLOT);
      double max_lot = MarketInfo(Symbol(), MODE_MAXLOT);
      
      if(lots < min_lot || lots > max_lot) return false;
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| 計算點值                                                          |
   //+------------------------------------------------------------------+
   static double PointValue()
   {
      if(Digits == 5 || Digits == 3)
         return Point * 10;
      else
         return Point;
   }
   
   //+------------------------------------------------------------------+
   //| 點數轉價格差                                                      |
   //+------------------------------------------------------------------+
   static double PointsToPrice(double points)
   {
      return points * PointValue();
   }
   
   //+------------------------------------------------------------------+
   //| 價格差轉點數                                                      |
   //+------------------------------------------------------------------+
   static double PriceToPoints(double price_diff)
   {
      return price_diff / PointValue();
   }
   
   //+------------------------------------------------------------------+
   //| 格式化貨幣顯示                                                    |
   //+------------------------------------------------------------------+
   static string FormatCurrency(double amount)
   {
      return DoubleToStr(amount, 2);
   }
   
   //+------------------------------------------------------------------+
   //| 格式化百分比顯示                                                  |
   //+------------------------------------------------------------------+
   static string FormatPercent(double percent)
   {
      return DoubleToStr(percent, 2) + "%";
   }
};

//+------------------------------------------------------------------+
//| 日誌管理類別（支援檔案輸出）                                      |
//+------------------------------------------------------------------+
class LogManager
{
private:
   static string    s_eaName;
   static string    s_logFile;
   static bool      s_showDebug;
   static long      s_chartId;
   
public:
   //+------------------------------------------------------------------+
   //| 初始化日誌管理器                                                  |
   //+------------------------------------------------------------------+
   static void Init(string eaName, string logFile = "", bool showDebug = false)
   {
      s_eaName = eaName;
      s_logFile = logFile;
      s_showDebug = showDebug;
      s_chartId = ChartID();
   }
   
   //+------------------------------------------------------------------+
   //| 寫入日誌                                                          |
   //+------------------------------------------------------------------+
   static void WriteLog(string message)
   {
      string fullMsg = "[" + s_eaName + "] " + message;
      Print(fullMsg);
      
      if(s_logFile != "")
         WriteToFile(fullMsg);
   }
   
   //+------------------------------------------------------------------+
   //| 寫入除錯日誌                                                      |
   //+------------------------------------------------------------------+
   static void WriteDebugLog(string message)
   {
      if(s_showDebug)
         WriteLog("[DEBUG] " + message);
   }
   
   //+------------------------------------------------------------------+
   //| 設定除錯模式                                                      |
   //+------------------------------------------------------------------+
   static void SetDebugMode(bool enable)
   {
      s_showDebug = enable;
   }
   
   //+------------------------------------------------------------------+
   //| 設定日誌檔案                                                      |
   //+------------------------------------------------------------------+
   static void SetLogFile(string logFile)
   {
      s_logFile = logFile;
   }
   
private:
   //+------------------------------------------------------------------+
   //| 寫入檔案                                                          |
   //+------------------------------------------------------------------+
   static void WriteToFile(string message)
   {
      if(s_logFile == "")
         return;
         
      // 建立帶圖表 ID 後綴的檔名
      string chartIdStr = IntegerToString(s_chartId);
      int len = StringLen(chartIdStr);
      string suffix = (len >= 4) ? StringSubstr(chartIdStr, len - 4, 4) : chartIdStr;
      
      int dotPos = StringFind(s_logFile, ".", 0);
      string actualLogFile;
      
      if(dotPos < 0)
         actualLogFile = s_logFile + "_" + suffix;
      else
      {
         string baseName = StringSubstr(s_logFile, 0, dotPos);
         string extension = StringSubstr(s_logFile, dotPos);
         actualLogFile = baseName + "_" + suffix + extension;
      }
      
      int handle = FileOpen(actualLogFile, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(handle != INVALID_HANDLE)
      {
         FileSeek(handle, 0, SEEK_END);
         FileWriteString(handle, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + " " + message + "\n");
         FileFlush(handle);
         FileClose(handle);
      }
   }
};

// 靜態成員初始化
string LogManager::s_eaName = "EA";
string LogManager::s_logFile = "";
bool   LogManager::s_showDebug = false;
long   LogManager::s_chartId = 0;

#endif // UTILS_MQH
