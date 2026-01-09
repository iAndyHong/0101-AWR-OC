//+------------------------------------------------------------------+
//|                                                     Recovery.mq4 |
//|                                    Recovery Manager EA v3.20     |
//|                         負責虧損管理與部分平倉的專家顧問           |
//|                         使用狀態機 + 雙向確認機制確保 GV 安全      |
//|                         v3.00: 新增 GroupID 組別隔離機制          |
//|                         v3.20: 新增共用日誌檔機制                 |
//+------------------------------------------------------------------+
#property copyright "Recovery System"
#property link      ""
#property version   "3.20"
#property strict

//+------------------------------------------------------------------+
//| 常數定義
//+------------------------------------------------------------------+
// GV 名稱最大長度常數
#define GV_MAX_LENGTH         63

// UI 顏色常數
#define COLOR_PROFIT          clrLime                             // 獲利顏色
#define COLOR_LOSS            clrRed                              // 虧損顏色
#define COLOR_NEUTRAL         clrWhite                            // 中性顏色
#define COLOR_ACTIVE          clrDodgerBlue                       // 活躍狀態
#define COLOR_INACTIVE        clrGray                             // 閒置狀態
#define COLOR_STAGE1          clrGold                             // 階段1 (請求中)
#define COLOR_STAGE2          clrOrange                           // 階段2 (等待中)
#define COLOR_STAGE3          clrMagenta                          // 階段3 (消費中)
#define COLOR_STAGE4          clrCyan                             // 階段4 (確認中)

// Recovery EA 狀態機狀態定義
#define STATE_R_IDLE          0    // 閒置 - 無獲利請求
#define STATE_R_REQUESTING    1    // 請求中 - 已發布獲利目標，等待 Grids 確認
#define STATE_R_WAITING       2    // 等待中 - Grids 已確認，等待獲利累積
#define STATE_R_CONSUMING     3    // 消費中 - 正在使用獲利執行平倉
#define STATE_R_CONFIRMING    4    // 確認中 - 平倉完成，等待 Grids 重置

// Grids EA 狀態機狀態定義（用於讀取）
#define STATE_G_IDLE          0    // 閒置
#define STATE_G_ACCUMULATING  1    // 累積獲利中
#define STATE_G_READY         2    // 獲利已就緒
#define STATE_G_ACKNOWLEDGED  3    // 已確認 Recovery 的消費

//+------------------------------------------------------------------+
//| 外部參數                                                          |
//+------------------------------------------------------------------+

// ===== 組別設定 (重要！) =====
sinput string  RM_Help0                  = "----------------";   // 組別設定 (重要)
input string   RM_GroupID                = "A";                  // 組別 ID (A-Z 或 1-99)
input bool     RM_CrossSymbol            = false;                // 跨商品模式
input string   RM_TargetSymbol           = "";                   // 目標商品 (跨商品時使用)

// ===== 訂單識別設定 =====
sinput string  RM_Help1                  = "----------------";   // 訂單識別設定
input int      RM_OrderSelector          = 0;                    // 處理順序 (0=簡單優先, 1=困難優先)
input int      RM_MagicSelection         = 0;                    // MagicNumber 群組 (0=全部, 1=手動+本EA, 2=僅本EA)
input string   RM_MagicNumbers           = "0";                  // 要恢復的 MagicNumber (逗號分隔)
input int      RM_FirstTicket            = 0;                    // 優先處理的訂單 Ticket (0=不使用)

// ===== 前置處理設定 =====
sinput string  RM_Help2                  = "----------------";   // 前置處理設定
input bool     RM_UseLocking             = true;                 // 啟用鎖倉
input bool     RM_DeleteSLTP             = true;                 // 刪除 SL 和 TP
input bool     RM_CloseProfitAtLaunch    = false;                // 啟動時關閉盈利訂單
input bool     RM_DeletePendingAtLaunch  = false;                // 啟動時刪除掛單

// ===== 啟動設定 =====
sinput string  RM_Help3                  = "----------------";   // 啟動設定
input int      RM_LaunchType             = 0;                    // 啟動類型 (0=立即, 1=回撤%, 2=回撤金額)
input double   RM_LaunchThreshold        = 35.0;                 // 啟動閾值
input int      RM_DisableOtherEAs        = 0;                    // 停用其他EA (0=不停用, 1=同商品, 2=全部)

// ===== 部分平倉設定 (核心) =====
sinput string  RM_Help4                  = "----------------";   // 部分平倉設定
input double   RM_PartialLots            = 0.01;                 // 每次平倉手數 (Part_For_Close)
input double   RM_TakeProfitMoney        = 2.0;                  // 部分平倉止盈金額

// ===== 整體止盈設定 =====
sinput string  RM_Help5                  = "----------------";   // 整體止盈設定
input bool     RM_UseBasketTP            = true;                 // 啟用整體籃子止盈
input double   RM_BasketTPMoney          = 5.0;                  // 整體籃子止盈金額

// ===== 保護設定 =====
sinput string  RM_Help6                  = "----------------";   // 保護設定
input int      RM_MaxSlippage            = 30;                   // 最大滑點 (點)
input int      RM_LockMagic              = 88888;                // 鎖倉訂單 MagicNumber

// ===== GV 通訊設定 =====
sinput string  RM_Help7                  = "----------------";   // GV 通訊設定
input string   RM_GV_Prefix              = "REC_";               // GV 前綴 (簡短)
input int      RM_UpdateInterval         = 1;                    // 更新間隔 (秒)
input int      RM_AckTimeout             = 30;                   // 確認超時 (秒)
input bool     RM_CheckConflict          = true;                 // 檢查組別衝突

// ===== UI 顯示設定 =====
sinput string  RM_Help9                  = "----------------";   // UI 顯示設定
input bool     RM_ShowPanel              = true;                 // 顯示資訊面板
input int      RM_PanelX                 = 10;                   // 面板 X 座標
input int      RM_PanelY                 = 30;                   // 面板 Y 座標

// ===== 除錯設定 =====
sinput string  RM_Help8                  = "----------------";   // 除錯設定
input bool     RM_ShowDebugLogs          = false;                // 顯示除錯日誌
input bool     RM_EnableSharedLog        = true;                 // 啟用共用日誌檔

// 檔案控制代碼
int            g_logFileHandle           = INVALID_HANDLE;       // 日誌檔案控制代碼
string         g_sharedLogFileName       = "";                   // 共用日誌檔名

//+------------------------------------------------------------------+
//| 全域變數                                                          |
//+------------------------------------------------------------------+

// 狀態變數
bool           g_isInitialized          = false;                 // 初始化狀態
int            g_recoveryState          = 0;                     // Recovery EA 狀態機狀態
datetime       g_lastUpdateTime         = 0;                     // 最後更新時間
bool           g_launchProcessed        = false;                 // 前置處理完成標誌

// 交易 ID（用於狀態機同步）
double         g_transactionId          = 0;                     // 當前交易週期 ID
datetime       g_requestTime            = 0;                     // 請求發送時間

// 虧損倉位變數
double         g_totalLoss              = 0.0;                   // 總虧損金額
double         g_totalBuyLots           = 0.0;                   // Buy 總手數
double         g_totalSellLots          = 0.0;                   // Sell 總手數
int            g_lossOrderCount         = 0;                     // 虧損訂單數量

// 部分平倉變數
double         g_currentPartialLoss     = 0.0;                   // 當前部分虧損
double         g_profitTarget           = 0.0;                   // 目標獲利金額
int            g_currentBuyTicket       = 0;                     // 當前處理的 Buy 訂單
int            g_currentSellTicket      = 0;                     // 當前處理的 Sell 訂單

// 輔助變數
double         g_pointValue             = 0.0;                   // 點值
int            g_digits                 = 0;                     // 小數位數
double         g_instanceId             = 0;                     // EA 實例 ID

//+------------------------------------------------------------------+
//| 日誌檔案操作函數                                                  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 開啟共用日誌檔案
//| 
//| 共用日誌機制說明：
//| 1. Recovery EA 啟動時，取得自己的圖表 ID 後 5 碼
//| 2. 將此 ID 寫入 GV（REC_{GroupID}_LOG），供 Grids EA 讀取
//| 3. 日誌檔名格式：Group[{GroupID}]_{ChartID後5碼}.log
//| 4. 同組別的所有 EA 都寫入同一個日誌檔
//+------------------------------------------------------------------+
void OpenLogFile()
  {
// 檢查是否啟用共用日誌
   if(!RM_EnableSharedLog)
      return;

// 取得圖表 ID 後 5 碼
   long chartId = ChartID();
   string chartIdStr = IntegerToString(chartId);
   int len = StringLen(chartIdStr);
   string chartIdSuffix = (len >= 5) ? StringSubstr(chartIdStr, len - 5, 5) : chartIdStr;

// 將圖表 ID 後 5 碼寫入 GV，供 Grids EA 讀取
   WriteGV("LOG", StringToDouble(chartIdSuffix));

// 產生共用日誌檔名：Group[A]_12345.log
   g_sharedLogFileName = "Group[" + RM_GroupID + "]_" + chartIdSuffix + ".log";

// 開啟日誌檔案（使用 FILE_READ|FILE_WRITE 允許追加）
   g_logFileHandle = FileOpen(g_sharedLogFileName, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(g_logFileHandle == INVALID_HANDLE)
     {
      // 檔案不存在，建立新檔案
      g_logFileHandle = FileOpen(g_sharedLogFileName, FILE_WRITE|FILE_TXT|FILE_ANSI);
     }
   else
     {
      // 檔案存在，移動到檔案末尾（追加模式）
      FileSeek(g_logFileHandle, 0, SEEK_END);
     }

   if(g_logFileHandle == INVALID_HANDLE)
     {
      Print("[Recovery] 無法開啟共用日誌檔案: ", g_sharedLogFileName, " Error=", GetLastError());
     }
   else
     {
      FileWrite(g_logFileHandle, "");
      FileWrite(g_logFileHandle, "=== Recovery EA 啟動 ===");
      FileWrite(g_logFileHandle, "時間: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
      FileWrite(g_logFileHandle, "組別: ", RM_GroupID);
      FileWrite(g_logFileHandle, "商品: ", Symbol());
      FileWrite(g_logFileHandle, "圖表ID: ", chartIdSuffix);
      FileWrite(g_logFileHandle, "");
      Print("[Recovery] 共用日誌檔案: ", g_sharedLogFileName);
     }
  }

// 關閉日誌檔案
void CloseLogFile()
  {
   if(g_logFileHandle != INVALID_HANDLE)
     {
      FileWrite(g_logFileHandle, "");
      FileWrite(g_logFileHandle, "=== Recovery EA 停止 ===");
      FileWrite(g_logFileHandle, "時間: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
      FileWrite(g_logFileHandle, "");
      FileClose(g_logFileHandle);
      g_logFileHandle = INVALID_HANDLE;
     }
  }

// 寫入日誌（同時輸出到檔案和 Experts 日誌）
void WriteLog(string message)
  {
   if(RM_ShowDebugLogs)
      Print(message);

   if(g_logFileHandle != INVALID_HANDLE)
      FileWrite(g_logFileHandle, TimeToString(TimeCurrent(), TIME_SECONDS), " ", message);
  }

//+------------------------------------------------------------------+
//| 記錄獲利收支到共用日誌
//| 
//| 參數：
//|   action: 動作類型（"收入"/"消費"/"歸零"）
//|   amount: 金額
//|   balance: 操作後的累積獲利餘額
//|   detail: 額外說明（可選）
//+------------------------------------------------------------------+
void LogProfitTransaction(string action, double amount, double balance, string detail = "")
  {
   if(g_logFileHandle == INVALID_HANDLE)
      return;

   string logLine = TimeToString(TimeCurrent(), TIME_SECONDS) + " [Recovery] " +
                    action + " " + DoubleToStr(amount, 2) +
                    " | 餘額=" + DoubleToStr(balance, 2);

   if(StringLen(detail) > 0)
      logLine += " | " + detail;

   FileWrite(g_logFileHandle, logLine);
   FileFlush(g_logFileHandle);  // 立即寫入磁碟
  }

//+------------------------------------------------------------------+
//| GV 操作函數                                                       |
//+------------------------------------------------------------------+

// 取得完整 GV 名稱（只包含組別，不含商品）
// 格式: REC_{GroupID}_{name}
// 這樣同組別的所有商品都共享同一組 GV，可跨商品恢復虧損
string GetGVFullName(string name)
  {
   string fullName = RM_GV_Prefix + RM_GroupID + "_" + name;

// GV 名稱長度檢查（MQL4 限制 63 字元）
   if(StringLen(fullName) > GV_MAX_LENGTH)
     {
      Print("[警告] GV 名稱過長 (", StringLen(fullName), " > ", GV_MAX_LENGTH, "): ", fullName);
      fullName = StringSubstr(fullName, 0, GV_MAX_LENGTH);
      Print("[警告] 已截斷為: ", fullName);
     }

   return fullName;
  }

// 寫入 GV
void WriteGV(string name, double value)
  {
   string fullName = GetGVFullName(name);
   GlobalVariableSet(fullName, value);
   if(RM_ShowDebugLogs)
      Print("[GV] 寫入 ", fullName, " = ", value);
  }

// 讀取 GV
double ReadGV(string name, double defaultValue = 0)
  {
   string fullName = GetGVFullName(name);
   if(GlobalVariableCheck(fullName))
      return GlobalVariableGet(fullName);
   return defaultValue;
  }

// 檢查 GV 存在
bool CheckGV(string name)
  {
   string fullName = GetGVFullName(name);
   return GlobalVariableCheck(fullName);
  }

// 刪除 GV
void DeleteGV(string name)
  {
   string fullName = GetGVFullName(name);
   if(GlobalVariableCheck(fullName))
      GlobalVariableDel(fullName);
  }

//+------------------------------------------------------------------+
//| 組別衝突檢測函數                                                  |
//+------------------------------------------------------------------+

// 產生唯一實例 ID
double GenerateInstanceId()
  {
// 使用時間戳 + 隨機數產生唯一 ID
   return (double)TimeCurrent() + MathRand() / 32768.0;
  }

// 檢查組別衝突
bool CheckGroupConflict()
  {
   if(!RM_CheckConflict)
      return false;

   string lockGV = GetGVFullName("RECOVERY_LOCK");

// 檢查是否已有同組別的 Recovery EA 運行
   if(GlobalVariableCheck(lockGV))
     {
      double existingId = GlobalVariableGet(lockGV);
      datetime lastUpdate = (datetime)ReadGV("LAST_UPDATE", 0);

      // 如果上次更新超過 60 秒，視為已停止
      if(TimeCurrent() - lastUpdate > 60)
        {
         Print("[Recovery] 偵測到舊的實例已停止，接管組別 ", RM_GroupID);
        }
      else
         if(existingId != g_instanceId && existingId != 0)
           {
            Print("[Recovery] 錯誤：組別 ", RM_GroupID, " 已有其他 Recovery EA 運行！");
            Print("[Recovery] 請使用不同的 GroupID 或停止另一個 EA");
            return true;
           }
     }

// 註冊自己
   GlobalVariableSet(lockGV, g_instanceId);
   return false;
  }

// 釋放組別鎖定
void ReleaseGroupLock()
  {
   string lockGV = GetGVFullName("RECOVERY_LOCK");
   if(GlobalVariableCheck(lockGV))
     {
      double existingId = GlobalVariableGet(lockGV);
      if(existingId == g_instanceId)
        {
         GlobalVariableDel(lockGV);
        }
     }
  }

//+------------------------------------------------------------------+
//| 初始化函數                                                        |
//+------------------------------------------------------------------+
int OnInit()
  {
// 初始化點值和小數位數
   g_digits = (int)MarketInfo(Symbol(), MODE_DIGITS);
   g_pointValue = MarketInfo(Symbol(), MODE_POINT);

// 產生唯一實例 ID
   g_instanceId = GenerateInstanceId();

// 開啟日誌檔案
   OpenLogFile();

// 檢查組別衝突
   if(CheckGroupConflict())
     {
      CloseLogFile();
      return(INIT_FAILED);
     }

// 讀取或初始化交易 ID
   g_transactionId = ReadGV("TRANSACTION_ID", 0);

// 初始化 GV 變數
   WriteGV("RECOVERY_STATE", STATE_R_IDLE);
   WriteGV("PROFIT_TARGET", 0.0);
   WriteGV("PARTIAL_LOSS", 0.0);
   WriteGV("RECOVERY_ACK_ID", 0.0);
   WriteGV("LAST_UPDATE", (double)TimeCurrent());

   g_isInitialized = true;
   g_recoveryState = STATE_R_IDLE;
   g_launchProcessed = false;

   Print("=== Recovery EA v3.10 初始化完成 ===");
   Print("組別 ID: ", RM_GroupID);
   Print("部分平倉手數: ", RM_PartialLots);
   Print("部分平倉止盈: ", RM_TakeProfitMoney);
   Print("GV 範例: ", GetGVFullName("PROFIT_TARGET"));
   Print("使用狀態機 + 雙向確認 + 組別隔離機制（跨商品共享）");
   if(StringLen(RM_LogFile) > 0)
      Print("日誌檔案: ", RM_LogFile);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| 反初始化函數                                                      |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   WriteGV("RECOVERY_STATE", STATE_R_IDLE);
   ReleaseGroupLock();
   CloseLogFile();
   DeleteChartPanel();
   Print("=== Recovery EA 已停止 (組別: ", RM_GroupID, ") ===");
  }


//+------------------------------------------------------------------+
//| 主要交易邏輯 - 狀態機驅動                                         |
//+------------------------------------------------------------------+
void OnTick()
  {
// 更新 UI 面板（每個 tick 都更新）
   UpdateChartPanel();

   if(!g_isInitialized)
      return;

// 更新時間檢查
   if(TimeCurrent() - g_lastUpdateTime < RM_UpdateInterval)
      return;
   g_lastUpdateTime = TimeCurrent();

// 檢查啟動條件
   if(!CheckLaunchCondition())
      return;

// 執行前置處理（只執行一次）
   if(!g_launchProcessed)
     {
      ExecuteLaunchProcessing();
      g_launchProcessed = true;
     }

// 掃描虧損倉位
   ScanLossPositions();

// 如果沒有虧損倉位，重置狀態
   if(g_lossOrderCount == 0)
     {
      ResetToIdle();
      return;
     }

// 檢查整體籃子止盈
   if(RM_UseBasketTP && CheckBasketTakeProfit())
     {
      return;
     }

// 執行狀態機邏輯
   ExecuteStateMachine();

// 更新 GV
   WriteGV("LAST_UPDATE", (double)TimeCurrent());
  }

//+------------------------------------------------------------------+
//| 狀態機核心邏輯                                                    |
//+------------------------------------------------------------------+
void ExecuteStateMachine()
  {
// 讀取 Grids EA 的狀態
   int gridsState = (int)ReadGV("GRIDS_STATE", STATE_G_IDLE);
   double gridsAckId = ReadGV("GRIDS_ACK_ID", 0);

   switch(g_recoveryState)
     {
      case STATE_R_IDLE:
         // 閒置狀態：發起新的獲利請求
         HandleStateIdle();
         break;

      case STATE_R_REQUESTING:
         // 請求狀態：等待 Grids 確認收到請求
         HandleStateRequesting(gridsState, gridsAckId);
         break;

      case STATE_R_WAITING:
         // 等待狀態：等待 Grids 累積足夠獲利
         HandleStateWaiting(gridsState, gridsAckId);
         break;

      case STATE_R_CONSUMING:
         // 消費狀態：執行部分平倉
         HandleStateConsuming();
         break;

      case STATE_R_CONFIRMING:
         // 確認狀態：等待 Grids 確認重置
         HandleStateConfirming(gridsState);
         break;
     }
  }

//+------------------------------------------------------------------+
//| 狀態處理：閒置                                                    |
//+------------------------------------------------------------------+
void HandleStateIdle()
  {
// 選擇當前要處理的訂單
   SelectCurrentOrders();

// 計算當前部分的虧損
   g_currentPartialLoss = CalculatePartialLoss();

   if(g_currentPartialLoss >= 0)
     {
      // 沒有虧損需要處理
      return;
     }

// 計算目標獲利 = |部分虧損| + 止盈緩衝
   g_profitTarget = MathAbs(g_currentPartialLoss) + RM_TakeProfitMoney;

// 遞增交易 ID
   g_transactionId = ReadGV("TRANSACTION_ID", 0) + 1;
   WriteGV("TRANSACTION_ID", g_transactionId);

// 發布獲利目標
   WriteGV("PROFIT_TARGET", g_profitTarget);
   WriteGV("PARTIAL_LOSS", g_currentPartialLoss);

// 更新狀態為請求中
   g_recoveryState = STATE_R_REQUESTING;
   WriteGV("RECOVERY_STATE", g_recoveryState);
   g_requestTime = TimeCurrent();

   if(RM_ShowDebugLogs)
      Print("[Recovery] 發起獲利請求 TxID=", g_transactionId,
            " 目標=", g_profitTarget, " 部分虧損=", g_currentPartialLoss);
  }


//+------------------------------------------------------------------+
//| 狀態處理：請求中                                                  |
//+------------------------------------------------------------------+
void HandleStateRequesting(int gridsState, double gridsAckId)
  {
// 檢查 Grids 是否確認了當前交易 ID
   if(gridsAckId == g_transactionId && gridsState >= STATE_G_ACCUMULATING)
     {
      // Grids 已確認，進入等待狀態
      g_recoveryState = STATE_R_WAITING;
      WriteGV("RECOVERY_STATE", g_recoveryState);

      if(RM_ShowDebugLogs)
         Print("[Recovery] Grids 已確認請求 TxID=", g_transactionId);
      return;
     }

// 檢查超時
   if(TimeCurrent() - g_requestTime > RM_AckTimeout)
     {
      Print("[Recovery] 警告：等待 Grids 確認超時，重新發送請求");
      // 重新發送請求（保持相同的 TxID）
      WriteGV("PROFIT_TARGET", g_profitTarget);
      WriteGV("RECOVERY_STATE", STATE_R_REQUESTING);
      g_requestTime = TimeCurrent();
     }
  }

//+------------------------------------------------------------------+
//| 狀態處理：等待獲利                                                |
//+------------------------------------------------------------------+
void HandleStateWaiting(int gridsState, double gridsAckId)
  {
// 驗證 TxID 仍然匹配
   if(gridsAckId != g_transactionId)
     {
      Print("[Recovery] 警告：TxID 不匹配，回到請求狀態");
      g_recoveryState = STATE_R_REQUESTING;
      WriteGV("RECOVERY_STATE", g_recoveryState);
      return;
     }

// 檢查 Grids 是否獲利就緒
   if(gridsState == STATE_G_READY)
     {
      // 讀取累積獲利
      double accumulatedProfit = ReadGV("ACCUMULATED_PROFIT", 0);

      if(accumulatedProfit >= g_profitTarget)
        {
         // 獲利達標，進入消費狀態
         g_recoveryState = STATE_R_CONSUMING;
         WriteGV("RECOVERY_STATE", g_recoveryState);

         if(RM_ShowDebugLogs)
            Print("[Recovery] 獲利達標! 累積=", accumulatedProfit,
                  " 目標=", g_profitTarget, " 開始執行平倉");
        }
     }
  }

//+------------------------------------------------------------------+
//| 狀態處理：消費獲利（執行平倉）                                    |
//+------------------------------------------------------------------+
void HandleStateConsuming()
  {
// 執行部分平倉
   bool closeSuccess = ExecutePartialClose();

   if(closeSuccess)
     {
      // 平倉成功，發送確認
      WriteGV("RECOVERY_ACK_ID", g_transactionId);

      // 進入確認狀態
      g_recoveryState = STATE_R_CONFIRMING;
      WriteGV("RECOVERY_STATE", g_recoveryState);

      if(RM_ShowDebugLogs)
         Print("[Recovery] 部分平倉完成，等待 Grids 重置");
     }
   else
     {
      // 平倉失敗，回到等待狀態重試
      Print("[Recovery] 部分平倉失敗，將重試");
      g_recoveryState = STATE_R_WAITING;
      WriteGV("RECOVERY_STATE", g_recoveryState);
     }
  }

//+------------------------------------------------------------------+
//| 狀態處理：確認重置                                                |
//+------------------------------------------------------------------+
void HandleStateConfirming(int gridsState)
  {
// 等待 Grids 確認並重置
   if(gridsState == STATE_G_ACKNOWLEDGED || gridsState == STATE_G_IDLE)
     {
      // Grids 已確認，回到閒置狀態
      g_recoveryState = STATE_R_IDLE;
      WriteGV("RECOVERY_STATE", g_recoveryState);
      WriteGV("PROFIT_TARGET", 0.0);

      if(RM_ShowDebugLogs)
         Print("[Recovery] 交易週期完成 TxID=", g_transactionId);
     }
  }

//+------------------------------------------------------------------+
//| 重置到閒置狀態                                                    |
//+------------------------------------------------------------------+
void ResetToIdle()
  {
   g_recoveryState = STATE_R_IDLE;
   WriteGV("RECOVERY_STATE", STATE_R_IDLE);
   WriteGV("PROFIT_TARGET", 0.0);
  }


//+------------------------------------------------------------------+
//| 檢查啟動條件                                                      |
//+------------------------------------------------------------------+
bool CheckLaunchCondition()
  {
   if(RM_LaunchType == 0)
      return true;

   double balance = AccountBalance();
   double equity = AccountEquity();

   if(balance <= 0)
      return false;

   if(RM_LaunchType == 1)
     {
      double drawdownPercent = (balance - equity) / balance * 100.0;
      return (drawdownPercent >= RM_LaunchThreshold);
     }

   if(RM_LaunchType == 2)
     {
      double drawdownMoney = balance - equity;
      return (drawdownMoney >= RM_LaunchThreshold);
     }

   return true;
  }

//+------------------------------------------------------------------+
//| 執行前置處理                                                      |
//+------------------------------------------------------------------+
void ExecuteLaunchProcessing()
  {
   Print("[Recovery] 執行前置處理...");

   if(RM_DeleteSLTP)
      DeleteAllSLTP();
   if(RM_DeletePendingAtLaunch)
      DeletePendingOrders();
   if(RM_CloseProfitAtLaunch)
      CloseProfitOrders();
   if(RM_UseLocking)
      ExecuteLocking();

   Print("[Recovery] 前置處理完成");
  }

//+------------------------------------------------------------------+
//| 刪除所有 SL 和 TP                                                 |
//+------------------------------------------------------------------+
void DeleteAllSLTP()
  {
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      if(!IsOrderToProcess(OrderMagicNumber()))
         continue;

      if(OrderStopLoss() != 0 || OrderTakeProfit() != 0)
        {
         bool result = OrderModify(OrderTicket(), OrderOpenPrice(), 0, 0, 0, clrNONE);
         if(!result && RM_ShowDebugLogs)
            Print("[Recovery] 刪除 SL/TP 失敗, Ticket=", OrderTicket(), " Error=", GetLastError());
        }
     }
   if(RM_ShowDebugLogs)
      Print("[Recovery] 已刪除所有 SL/TP");
  }

//+------------------------------------------------------------------+
//| 刪除掛單                                                          |
//+------------------------------------------------------------------+
void DeletePendingOrders()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      if(!IsOrderToProcess(OrderMagicNumber()))
         continue;

      if(OrderType() > OP_SELL)
        {
         bool result = OrderDelete(OrderTicket());
         if(!result && RM_ShowDebugLogs)
            Print("[Recovery] 刪除掛單失敗, Ticket=", OrderTicket(), " Error=", GetLastError());
        }
     }
   if(RM_ShowDebugLogs)
      Print("[Recovery] 已刪除掛單");
  }

//+------------------------------------------------------------------+
//| 關閉盈利訂單                                                      |
//+------------------------------------------------------------------+
void CloseProfitOrders()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      if(!IsOrderToProcess(OrderMagicNumber()))
         continue;
      if(OrderType() > OP_SELL)
         continue;

      double profit = OrderProfit() + OrderSwap() + OrderCommission();
      if(profit > 0)
        {
         double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
         bool result = OrderClose(OrderTicket(), OrderLots(), closePrice, RM_MaxSlippage, clrYellow);
         if(!result && RM_ShowDebugLogs)
            Print("[Recovery] 關閉盈利訂單失敗, Ticket=", OrderTicket(), " Error=", GetLastError());
        }
     }
   if(RM_ShowDebugLogs)
      Print("[Recovery] 已關閉盈利訂單");
  }

//+------------------------------------------------------------------+
//| 執行鎖倉                                                          |
//+------------------------------------------------------------------+
void ExecuteLocking()
  {
   double buyLots = 0, sellLots = 0;

   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      if(!IsOrderToProcess(OrderMagicNumber()))
         continue;

      if(OrderType() == OP_BUY)
         buyLots += OrderLots();
      else
         if(OrderType() == OP_SELL)
            sellLots += OrderLots();
     }

   double lockLots = MathAbs(buyLots - sellLots);

   if(lockLots < MarketInfo(Symbol(), MODE_MINLOT))
     {
      if(RM_ShowDebugLogs)
         Print("[Recovery] 無需鎖倉，手數已平衡");
      return;
     }

   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   lockLots = MathFloor(lockLots / lotStep) * lotStep;

   int orderType = (buyLots > sellLots) ? OP_SELL : OP_BUY;
   double price = (orderType == OP_BUY) ? Ask : Bid;

   int ticket = OrderSend(Symbol(), orderType, lockLots, price, RM_MaxSlippage,
                          0, 0, "Lock Order", RM_LockMagic, 0,
                          (orderType == OP_BUY) ? clrBlue : clrRed);

   if(ticket > 0)
     {
      WriteGV("LOCK_VOLUME", lockLots);
      Print("[Recovery] 鎖倉成功: ", (orderType == OP_BUY) ? "BUY" : "SELL", " 手數=", lockLots);
     }
   else
     {
      Print("[Recovery] 鎖倉失敗: ", GetLastError());
     }
  }


//+------------------------------------------------------------------+
//| 檢查訂單是否需要處理                                              |
//+------------------------------------------------------------------+
bool IsOrderToProcess(int magic)
  {
   if(RM_MagicSelection == 0)
      return true;

   if(RM_MagicSelection == 1)
     {
      if(magic == 0)
         return true;
      if(magic == RM_LockMagic)
         return true;
      if(IsMagicInList(magic))
         return true;
     }

   if(RM_MagicSelection == 2)
     {
      if(magic == RM_LockMagic)
         return true;
      if(IsMagicInList(magic))
         return true;
     }

   return false;
  }

//+------------------------------------------------------------------+
//| 檢查 MagicNumber 是否在列表中                                     |
//+------------------------------------------------------------------+
bool IsMagicInList(int magic)
  {
   string magicList = RM_MagicNumbers;
   string magicStr = IntegerToString(magic);

   if(StringFind(magicList, magicStr) >= 0)
      return true;

   return false;
  }

//+------------------------------------------------------------------+
//| 掃描虧損倉位                                                      |
//+------------------------------------------------------------------+
void ScanLossPositions()
  {
   g_totalLoss = 0;
   g_totalBuyLots = 0;
   g_totalSellLots = 0;
   g_lossOrderCount = 0;

   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      if(!IsOrderToProcess(OrderMagicNumber()))
         continue;
      if(OrderType() > OP_SELL)
         continue;

      double profit = OrderProfit() + OrderSwap() + OrderCommission();

      if(profit < 0)
        {
         g_totalLoss += profit;
         g_lossOrderCount++;
        }

      if(OrderType() == OP_BUY)
         g_totalBuyLots += OrderLots();
      else
         if(OrderType() == OP_SELL)
            g_totalSellLots += OrderLots();
     }
  }

//+------------------------------------------------------------------+
//| 選擇當前要處理的訂單                                              |
//+------------------------------------------------------------------+
void SelectCurrentOrders()
  {
   g_currentBuyTicket = 0;
   g_currentSellTicket = 0;

   double bestBuyLoss = 0;
   double bestSellLoss = 0;

   if(RM_FirstTicket > 0)
     {
      if(OrderSelect(RM_FirstTicket, SELECT_BY_TICKET, MODE_TRADES))
        {
         if(OrderType() == OP_BUY)
            g_currentBuyTicket = RM_FirstTicket;
         else
            if(OrderType() == OP_SELL)
               g_currentSellTicket = RM_FirstTicket;
        }
     }

   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      if(!IsOrderToProcess(OrderMagicNumber()))
         continue;
      if(OrderType() > OP_SELL)
         continue;

      double profit = OrderProfit() + OrderSwap() + OrderCommission();
      if(profit >= 0)
         continue;

      bool isBetter = false;

      if(RM_OrderSelector == 0)
        {
         if(OrderType() == OP_BUY && g_currentBuyTicket == 0)
            isBetter = (bestBuyLoss == 0 || profit > bestBuyLoss);
         else
            if(OrderType() == OP_SELL && g_currentSellTicket == 0)
               isBetter = (bestSellLoss == 0 || profit > bestSellLoss);
        }
      else
        {
         if(OrderType() == OP_BUY && g_currentBuyTicket == 0)
            isBetter = (bestBuyLoss == 0 || profit < bestBuyLoss);
         else
            if(OrderType() == OP_SELL && g_currentSellTicket == 0)
               isBetter = (bestSellLoss == 0 || profit < bestSellLoss);
        }

      if(isBetter)
        {
         if(OrderType() == OP_BUY)
           {
            g_currentBuyTicket = OrderTicket();
            bestBuyLoss = profit;
           }
         else
           {
            g_currentSellTicket = OrderTicket();
            bestSellLoss = profit;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| 計算部分虧損                                                      |
//+------------------------------------------------------------------+
double CalculatePartialLoss()
  {
   double partialLoss = 0;

   if(g_currentBuyTicket > 0 && OrderSelect(g_currentBuyTicket, SELECT_BY_TICKET, MODE_TRADES))
     {
      double orderLoss = OrderProfit() + OrderSwap() + OrderCommission();
      double orderLots = OrderLots();

      if(orderLots > 0 && orderLoss < 0)
        {
         double partialLots = MathMin(RM_PartialLots, orderLots);
         partialLoss += (orderLoss / orderLots) * partialLots;
        }
     }

   if(g_currentSellTicket > 0 && OrderSelect(g_currentSellTicket, SELECT_BY_TICKET, MODE_TRADES))
     {
      double orderLoss = OrderProfit() + OrderSwap() + OrderCommission();
      double orderLots = OrderLots();

      if(orderLots > 0 && orderLoss < 0)
        {
         double partialLots = MathMin(RM_PartialLots, orderLots);
         partialLoss += (orderLoss / orderLots) * partialLots;
        }
     }

   return partialLoss;
  }


//+------------------------------------------------------------------+
//| 執行部分平倉                                                      |
//+------------------------------------------------------------------+
bool ExecutePartialClose()
  {
   bool buyCloseSuccess = false;
   bool sellCloseSuccess = false;

// 平倉 Buy 部分
   if(g_currentBuyTicket > 0 && OrderSelect(g_currentBuyTicket, SELECT_BY_TICKET, MODE_TRADES))
     {
      double closeLots = MathMin(RM_PartialLots, OrderLots());
      closeLots = NormalizeLots(closeLots);

      if(closeLots >= MarketInfo(Symbol(), MODE_MINLOT))
        {
         buyCloseSuccess = OrderClose(g_currentBuyTicket, closeLots, Bid, RM_MaxSlippage, clrYellow);
         if(buyCloseSuccess)
            Print("[Recovery] Buy 部分平倉成功: ", closeLots, " 手");
         else
            Print("[Recovery] Buy 部分平倉失敗: ", GetLastError());
        }
      else
        {
         buyCloseSuccess = true;  // 手數太小，視為成功
        }
     }
   else
     {
      buyCloseSuccess = true;  // 沒有 Buy 訂單，視為成功
     }

// 平倉 Sell 部分
   if(g_currentSellTicket > 0 && OrderSelect(g_currentSellTicket, SELECT_BY_TICKET, MODE_TRADES))
     {
      double closeLots = MathMin(RM_PartialLots, OrderLots());
      closeLots = NormalizeLots(closeLots);

      if(closeLots >= MarketInfo(Symbol(), MODE_MINLOT))
        {
         sellCloseSuccess = OrderClose(g_currentSellTicket, closeLots, Ask, RM_MaxSlippage, clrYellow);
         if(sellCloseSuccess)
            Print("[Recovery] Sell 部分平倉成功: ", closeLots, " 手");
         else
            Print("[Recovery] Sell 部分平倉失敗: ", GetLastError());
        }
      else
        {
         sellCloseSuccess = true;
        }
     }
   else
     {
      sellCloseSuccess = true;
     }

   return (buyCloseSuccess && sellCloseSuccess);
  }

//+------------------------------------------------------------------+
//| 標準化手數                                                        |
//+------------------------------------------------------------------+
double NormalizeLots(double lots)
  {
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));

   return lots;
  }

//+------------------------------------------------------------------+
//| 檢查整體籃子止盈                                                  |
//+------------------------------------------------------------------+
bool CheckBasketTakeProfit()
  {
   double totalProfit = 0;

   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      if(!IsOrderToProcess(OrderMagicNumber()))
         continue;
      if(OrderType() > OP_SELL)
         continue;

      totalProfit += OrderProfit() + OrderSwap() + OrderCommission();
     }

   if(totalProfit >= RM_BasketTPMoney)
     {
      Print("[Recovery] 整體籃子止盈達標: ", totalProfit);
      CloseAllOrders();
      return true;
     }

   return false;
  }

//+------------------------------------------------------------------+
//| 關閉所有訂單                                                      |
//+------------------------------------------------------------------+
void CloseAllOrders()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      if(!IsOrderToProcess(OrderMagicNumber()))
         continue;
      if(OrderType() > OP_SELL)
         continue;

      double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
      bool result = OrderClose(OrderTicket(), OrderLots(), closePrice, RM_MaxSlippage, clrYellow);
      if(!result)
         Print("[Recovery] 關閉訂單失敗, Ticket=", OrderTicket(), " Error=", GetLastError());
     }

// 重置狀態
   g_launchProcessed = false;
   ResetToIdle();

   Print("[Recovery] 所有訂單已關閉，恢復完成");
  }

//+------------------------------------------------------------------+
//| UI 面板函數                                                       |
//+------------------------------------------------------------------+

// 更新圖表面板顯示
void UpdateChartPanel()
  {
   if(!RM_ShowPanel)
      return;

   string prefix = "Recovery_Panel_";
   int x = RM_PanelX;
   int y = RM_PanelY;
   int lineHeight = 18;

// 標題
   CreateLabel(prefix + "Title", "=== Recovery EA v3.10 ===", x, y, COLOR_ACTIVE);
   y += lineHeight + 5;

// 組別 ID
   CreateLabel(prefix + "GroupID", "組別: " + RM_GroupID, x, y, COLOR_NEUTRAL);
   y += lineHeight;

// 商品
   CreateLabel(prefix + "Symbol", "商品: " + Symbol(), x, y, COLOR_NEUTRAL);
   y += lineHeight;

// 虧損訂單數
   color lossColor = (g_lossOrderCount > 0) ? COLOR_LOSS : COLOR_NEUTRAL;
   CreateLabel(prefix + "LossCount", "虧損訂單: " + IntegerToString(g_lossOrderCount), x, y, lossColor);
   y += lineHeight;

// 總虧損金額
   color totalLossColor = (g_totalLoss < 0) ? COLOR_LOSS : COLOR_NEUTRAL;
   CreateLabel(prefix + "TotalLoss", "總虧損: " + DoubleToStr(g_totalLoss, 2), x, y, totalLossColor);
   y += lineHeight;

// Buy/Sell 手數
   CreateLabel(prefix + "Lots", "手數: Buy=" + DoubleToStr(g_totalBuyLots, 2) + " Sell=" + DoubleToStr(g_totalSellLots, 2), x, y, COLOR_NEUTRAL);
   y += lineHeight;

// 當前部分虧損
   color partialColor = (g_currentPartialLoss < 0) ? COLOR_LOSS : COLOR_NEUTRAL;
   CreateLabel(prefix + "PartialLoss", "部分虧損: " + DoubleToStr(g_currentPartialLoss, 2), x, y, partialColor);
   y += lineHeight;

// 目標獲利
   color targetColor = (g_profitTarget > 0) ? COLOR_STAGE1 : COLOR_NEUTRAL;
   CreateLabel(prefix + "Target", "目標獲利: " + DoubleToStr(g_profitTarget, 2), x, y, targetColor);
   y += lineHeight;

// 累積獲利（從 Grids 讀取）
   double accProfit = ReadGV("ACCUMULATED_PROFIT", 0);
   color accColor = (accProfit > 0) ? COLOR_PROFIT : (accProfit < 0) ? COLOR_LOSS : COLOR_NEUTRAL;
   CreateLabel(prefix + "AccProfit", "累積獲利: " + DoubleToStr(accProfit, 2), x, y, accColor);
   y += lineHeight;

// 進度百分比
   double progress = 0;
   if(g_profitTarget > 0)
      progress = MathMin(100.0, (accProfit / g_profitTarget) * 100.0);
   color progressColor = (progress >= 100) ? COLOR_PROFIT : COLOR_STAGE2;
   CreateLabel(prefix + "Progress", "進度: " + DoubleToStr(progress, 1) + "%", x, y, progressColor);
   y += lineHeight;

// 狀態
   string stateStr = GetStateString(g_recoveryState);
   color stateColor = GetStateColor(g_recoveryState);
   CreateLabel(prefix + "State", "狀態: " + stateStr, x, y, stateColor);
   y += lineHeight;

// Grids 狀態
   int gridsState = (int)ReadGV("GRIDS_STATE", 0);
   string gridsStateStr = GetGridsStateString(gridsState);
   color gridsColor = (gridsState > 0) ? COLOR_ACTIVE : COLOR_INACTIVE;
   CreateLabel(prefix + "GridsState", "Grids: " + gridsStateStr, x, y, gridsColor);
   y += lineHeight;

// 交易 ID
   CreateLabel(prefix + "TxID", "TxID: " + DoubleToStr(g_transactionId, 0), x, y, COLOR_NEUTRAL);
  }

// 取得 Recovery 狀態字串
string GetStateString(int state)
  {
   switch(state)
     {
      case STATE_R_IDLE:
         return "閒置";
      case STATE_R_REQUESTING:
         return "請求中";
      case STATE_R_WAITING:
         return "等待中";
      case STATE_R_CONSUMING:
         return "消費中";
      case STATE_R_CONFIRMING:
         return "確認中";
      default:
         return "未知";
     }
  }

// 取得 Recovery 狀態顏色
color GetStateColor(int state)
  {
   switch(state)
     {
      case STATE_R_IDLE:
         return COLOR_INACTIVE;
      case STATE_R_REQUESTING:
         return COLOR_STAGE1;
      case STATE_R_WAITING:
         return COLOR_STAGE2;
      case STATE_R_CONSUMING:
         return COLOR_STAGE3;
      case STATE_R_CONFIRMING:
         return COLOR_STAGE4;
      default:
         return COLOR_NEUTRAL;
     }
  }

// 取得 Grids 狀態字串
string GetGridsStateString(int state)
  {
   switch(state)
     {
      case STATE_G_IDLE:
         return "閒置";
      case STATE_G_ACCUMULATING:
         return "累積中";
      case STATE_G_READY:
         return "就緒";
      case STATE_G_ACKNOWLEDGED:
         return "已確認";
      default:
         return "未知";
     }
  }

// 創建文字標籤
void CreateLabel(string name, string text, int x, int y, color clr)
  {
   if(ObjectFind(name) < 0)
     {
      ObjectCreate(name, OBJ_LABEL, 0, 0, 0);
      ObjectSet(name, OBJPROP_CORNER, 0);
      ObjectSet(name, OBJPROP_XDISTANCE, x);
      ObjectSet(name, OBJPROP_YDISTANCE, y);
     }
   ObjectSetText(name, text, 10, "Arial", clr);
  }

// 刪除圖表面板
void DeleteChartPanel()
  {
   string prefix = "Recovery_Panel_";
   int total = ObjectsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(i);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(name);
     }
  }
//+------------------------------------------------------------------+
