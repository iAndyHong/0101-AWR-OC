//+------------------------------------------------------------------+
//|                                                     Recovery.mq4 |
//|                                    Recovery Manager EA v1.20     |
//|                         負責虧損管理與部分平倉的專家顧問           |
//|                         使用狀態機 + 雙向確認機制確保 GV 安全      |
//|                         v1.00: 新增 GroupID 組別隔離機制          |
//|                         v1.10: 動態掃描 + 平衡保護機制            |
//|                               - 單筆動態掃描取代一多一空配對      |
//|                               - 失衡保護避免單邊過度平倉          |
//|                               - 等待期間動態重新評估目標          |
//|                         v1.11: 測試模式                           |
//|                               - 虛擬訂單模擬（無需真實持倉）      |
//|                               - 跳過 Grids 通訊檢查               |
//|                               - 自動模擬獲利達標                  |
//|                         v1.20: 動態盈虧回饋 + 對沖獲利平倉        |
//|                               - OrderStats 結構即時分類盈虧      |
//|                               - 對沖獲利配對平倉（不消耗額度）    |
//|                               - 跳過已轉盈訂單                    |
//|                               - 動態調整目標獲利                  |
//|                               - 線條顏色反映盈虧狀態              |
//+------------------------------------------------------------------+
#property copyright "Recovery System"
#property link      ""
#property version   "1.30"
#property strict

//+------------------------------------------------------------------+
//| 常數定義
//+------------------------------------------------------------------+
// 版本號常數（與 #property version 同步）
#define EA_VERSION            "1.20"

// GV 名稱最大長度常數
#define GV_MAX_LENGTH         63

// UI 顏色常數
#define COLOR_PROFIT          clrRed                              // 獲利顏色
#define COLOR_LOSS            clrLime                             // 虧損顏色
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
//| 枚舉定義
//+------------------------------------------------------------------+
// 通用布林枚舉
enum ENUM_BOOL
  {
   NO  = 0,                        // 否
   YES = 1                         // 是
  };

// 訂單處理順序
enum ENUM_ORDER_SEL
  {
   SEL_EASY = 0,                   // 簡單優先
   SEL_HARD = 1                    // 困難優先
  };

// MagicNumber 群組選擇
enum ENUM_MAGIC_SEL
  {
   MAGIC_ALL    = 0,               // 全部訂單
   MAGIC_MANUAL = 1,               // 手動+本EA
   MAGIC_SELF   = 2                // 僅本EA
  };

// 啟動類型
enum ENUM_LAUNCH
  {
   LAUNCH_NOW     = 0,             // 立即啟動
   LAUNCH_DD_PCT  = 1,             // 回撤%啟動
   LAUNCH_DD_MONEY = 2             // 回撤金額啟動
  };

// 停用其他EA模式
enum ENUM_DISABLE_EA
  {
   DISABLE_NONE   = 0,             // 不停用
   DISABLE_SYMBOL = 1,             // 同商品
   DISABLE_ALL    = 2              // 全部
  };

//+------------------------------------------------------------------+
//| 外部參數                                                          |
//+------------------------------------------------------------------+

// ===== 組別設定 (重要！) =====
sinput string  RM_Help0                  = "----------------";   // 組別設定 (重要)
input string   RM_GroupID                = "A";                  // 組別 ID (A-Z 或 1-99)
input ENUM_BOOL RM_CrossSymbol           = NO;                   // 跨商品模式
input string   RM_TargetSymbol           = "";                   // 目標商品 (跨商品時使用)

// ===== 訂單識別設定 =====
sinput string  RM_Help1                  = "----------------";   // 訂單識別設定
input ENUM_ORDER_SEL RM_OrderSelector    = SEL_EASY;             // 處理順序
input ENUM_MAGIC_SEL RM_MagicSelection   = MAGIC_ALL;            // MagicNumber 群組
input string   RM_MagicNumbers           = "0";                  // 要恢復的 MagicNumber (逗號分隔)
input int      RM_FirstTicket            = 0;                    // 優先處理的訂單 Ticket (0=不使用)

// ===== 動態掃描設定 (v1.10 新增) =====
sinput string  RM_Help1b                 = "----------------";   // 動態掃描設定 (v1.10)
input ENUM_BOOL RM_DynamicScan           = YES;                  // 啟用動態掃描 (單筆模式)
input double   RM_MaxImbalance           = 0.1;                  // 最大多空失衡手數 (平衡保護)
input int      RM_RescanInterval         = 5;                    // 重新掃描間隔 (秒)
input double   RM_SwitchThreshold        = 20.0;                 // 切換閾值 (%)

// ===== v1.20 新增：動態盈虧回饋設定 =====
sinput string  RM_Help1c                 = "----------------";   // 動態盈虧回饋 (v1.20)
input ENUM_BOOL RM_EnableHedgeProfit     = YES;                  // 啟用對沖獲利平倉
input ENUM_BOOL RM_SkipProfitOrders      = YES;                  // 跳過已轉盈訂單
input ENUM_BOOL RM_DynamicTargetAdjust   = YES;                  // 動態調整目標獲利

// ===== 前置處理設定 =====
sinput string  RM_Help2                  = "----------------";   // 前置處理設定
input ENUM_BOOL RM_UseLocking            = YES;                  // 啟用鎖倉
input ENUM_BOOL RM_DeleteSLTP            = YES;                  // 刪除 SL 和 TP
input ENUM_BOOL RM_CloseProfitAtLaunch   = NO;                   // 啟動時關閉盈利訂單
input ENUM_BOOL RM_DeletePendingAtLaunch = NO;                   // 啟動時刪除掛單

// ===== 啟動設定 =====
sinput string  RM_Help3                  = "----------------";   // 啟動設定
input ENUM_LAUNCH RM_LaunchType          = LAUNCH_NOW;           // 啟動類型
input double   RM_LaunchThreshold        = 35.0;                 // 啟動閾值
input ENUM_DISABLE_EA RM_DisableOtherEAs = DISABLE_NONE;         // 停用其他EA

// ===== 部分平倉設定 (核心) =====
sinput string  RM_Help4                  = "----------------";   // 部分平倉設定
input double   RM_PartialLots            = 0.01;                 // 每次平倉手數
input double   RM_TakeProfitMoney        = 2.0;                  // 部分平倉止盈金額

// ===== 整體止盈設定 =====
sinput string  RM_Help5                  = "----------------";   // 整體止盈設定
input ENUM_BOOL RM_UseBasketTP           = YES;                  // 啟用整體籃子止盈
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
input ENUM_BOOL RM_CheckConflict         = YES;                  // 檢查組別衝突

// ===== UI 顯示設定 =====
sinput string  RM_Help9                  = "----------------";   // UI 顯示設定
input ENUM_BOOL RM_ShowPanel             = YES;                  // 顯示資訊面板
input int      RM_PanelX                 = 10;                   // 面板 X 座標
input int      RM_PanelY                 = 30;                   // 面板 Y 座標

// ===== 除錯設定 =====
sinput string  RM_Help8                  = "----------------";   // 除錯設定
input ENUM_BOOL RM_ShowDebugLogs         = YES;                  // 顯示除錯日誌 [測試版預設開啟]
input ENUM_BOOL RM_EnableSharedLog       = YES;                  // 啟用共用日誌檔

//+------------------------------------------------------------------+
//| [TEST] 測試模式設定 (v1.11 新增)                                  |
//| 此區塊所有參數僅用於測試，實盤請關閉 RM_TestMode                  |
//+------------------------------------------------------------------+
sinput string  RM_HelpTest               = "====== 測試模式 ======";   // [TEST] 測試模式設定
input ENUM_BOOL RM_TestMode              = YES;                  // [TEST] 啟用測試模式 (實盤請關閉!)
input ENUM_BOOL RM_TestSkipGrids         = YES;                  // [TEST] 跳過 Grids 通訊 (獨立測試)
input int      RM_TestAutoProfit         = 2;                    // [TEST] 自動模擬獲利 (秒後, 0=手動)
input int      RM_TestMaxRounds          = 0;                    // [TEST] 最大測試輪數 (0=無限)

// [TEST] 虛擬訂單網格設定
sinput string  RM_HelpTestGrid           = "----------------";   // [TEST] 虛擬訂單網格
input int      RM_TestBuyCount           = 3;                    // [TEST] Buy 訂單數量 (往上)
input int      RM_TestSellCount          = 3;                    // [TEST] Sell 訂單數量 (往下)
input double   RM_TestGridGap            = 500.0;                // [TEST] 網格間距 (點)
input double   RM_TestLotsPerOrder       = 0.02;                 // [TEST] 每筆訂單手數

//+------------------------------------------------------------------+
//| [TEST] 虛擬訂單結構定義                                           |
//+------------------------------------------------------------------+
struct VirtualOrder
  {
   int            ticket;           // 虛擬 Ticket (99001, 99002...)
   int            type;             // OP_BUY 或 OP_SELL
   double         lots;             // 原始手數
   double         openPrice;        // 開倉價格
   double         profit;           // 浮動損益
   double         remainLots;       // 剩餘手數
   bool           isClosed;         // 是否已完全平倉
   string         lineName;         // 圖表水平線名稱
  };

//+------------------------------------------------------------------+
//| v1.20 新增：訂單統計結構                                          |
//| 即時分類訂單盈虧狀態，用於對沖獲利平倉和動態調整                  |
//+------------------------------------------------------------------+
struct OrderStats
  {
   double         buyProfitLots;    // Buy 獲利訂單總手數
   double         buyLossLots;      // Buy 虧損訂單總手數
   double         sellProfitLots;   // Sell 獲利訂單總手數
   double         sellLossLots;     // Sell 虧損訂單總手數
   double         buyProfitAmount;  // Buy 獲利金額
   double         buyLossAmount;    // Buy 虧損金額
   double         sellProfitAmount; // Sell 獲利金額
   double         sellLossAmount;   // Sell 虧損金額
   int            buyProfitCount;   // Buy 獲利訂單數
   int            buyLossCount;     // Buy 虧損訂單數
   int            sellProfitCount;  // Sell 獲利訂單數
   int            sellLossCount;    // Sell 虧損訂單數
  };

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
int            g_currentTicket          = 0;                     // 當前處理的訂單 (v1.10: 單筆模式)
int            g_currentOrderType       = -1;                    // 當前訂單類型 (OP_BUY/OP_SELL)

// 舊版相容變數（保留但不再主要使用）
int            g_currentBuyTicket       = 0;                     // 當前處理的 Buy 訂單
int            g_currentSellTicket      = 0;                     // 當前處理的 Sell 訂單

// 動態掃描變數 (v1.10 新增)
datetime       g_lastRescanTime         = 0;                     // 最後重新掃描時間
double         g_closedBuyLots          = 0.0;                   // 已平倉 Buy 手數（用於平衡追蹤）
double         g_closedSellLots         = 0.0;                   // 已平倉 Sell 手數（用於平衡追蹤）

// v1.20 新增：訂單統計和對沖獲利變數
OrderStats     g_orderStats;                                     // 訂單統計結構
int            g_hedgeProfitCount       = 0;                     // 對沖獲利平倉次數
double         g_hedgeProfitAmount      = 0.0;                   // 對沖獲利平倉總金額

//+------------------------------------------------------------------+
//| [TEST] 測試模式全域變數 (v1.11 新增)                              |
//+------------------------------------------------------------------+
datetime       g_testStartTime          = 0;                     // [TEST] 測試開始時間
int            g_testRoundCount         = 0;                     // [TEST] 測試輪數計數
bool           g_testProfitSimulated    = false;                 // [TEST] 是否已模擬獲利
bool           g_testCompleted          = false;                 // [TEST] 測試是否已完成
VirtualOrder   g_virtualOrders[];                                // [TEST] 虛擬訂單陣列
int            g_virtualOrderCount      = 0;                     // [TEST] 虛擬訂單總數
int            g_virtualClosedCount     = 0;                     // [TEST] 已平倉訂單數

// 輔助變數
double         g_pointValue             = 0.0;                   // 點值
int            g_digits                 = 0;                     // 小數位數
double         g_instanceId             = 0.0;                   // EA 實例 ID


//+------------------------------------------------------------------+
//| 日誌檔案操作函數                                                  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 開啟共用日誌檔案
//+------------------------------------------------------------------+
void OpenLogFile()
  {
   if(RM_EnableSharedLog == NO)
      return;

   long chartId = ChartID();
   string chartIdStr = IntegerToString(chartId);
   int len = StringLen(chartIdStr);
   string chartIdSuffix = (len >= 5) ? StringSubstr(chartIdStr, len - 5, 5) : chartIdStr;

   WriteGV("LOG", StringToDouble(chartIdSuffix));

   g_sharedLogFileName = "Group[" + RM_GroupID + "]_" + chartIdSuffix + ".log";

   // FILE_SHARE_READ 允許外部工具同時讀取日誌檔案
   g_logFileHandle = FileOpen(g_sharedLogFileName, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(g_logFileHandle == INVALID_HANDLE)
      g_logFileHandle = FileOpen(g_sharedLogFileName, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE);
   else
      FileSeek(g_logFileHandle, 0, SEEK_END);

   if(g_logFileHandle == INVALID_HANDLE)
     {
      Print("[Recovery] 無法開啟共用日誌檔案: ", g_sharedLogFileName, " Error=", GetLastError());
     }
   else
     {
      FileWrite(g_logFileHandle, "");
      FileWrite(g_logFileHandle, "=== Recovery EA v" + EA_VERSION + " 啟動 ===");
      FileWrite(g_logFileHandle, "時間: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
      FileWrite(g_logFileHandle, "組別: ", RM_GroupID);
      FileWrite(g_logFileHandle, "商品: ", Symbol());
      FileWrite(g_logFileHandle, "動態掃描: ", (RM_DynamicScan == YES ? "啟用" : "停用"));
      
      // v1.20 新增功能日誌
      FileWrite(g_logFileHandle, "對沖獲利平倉: ", (RM_EnableHedgeProfit == YES ? "啟用" : "停用"));
      FileWrite(g_logFileHandle, "跳過已轉盈訂單: ", (RM_SkipProfitOrders == YES ? "啟用" : "停用"));
      FileWrite(g_logFileHandle, "動態調整目標: ", (RM_DynamicTargetAdjust == YES ? "啟用" : "停用"));

      // [TEST] 測試模式日誌
      if(RM_TestMode == YES)
        {
         FileWrite(g_logFileHandle, "");
         FileWrite(g_logFileHandle, "********** [TEST] 測試模式已啟用 **********");
         FileWrite(g_logFileHandle, "[TEST] 虛擬訂單: Buy=", IntegerToString(RM_TestBuyCount), " Sell=", IntegerToString(RM_TestSellCount));
         FileWrite(g_logFileHandle, "[TEST] 網格間距: ", DoubleToStr(RM_TestGridGap, 0), " 點");
         FileWrite(g_logFileHandle, "[TEST] 每筆手數: ", DoubleToStr(RM_TestLotsPerOrder, 2));
         FileWrite(g_logFileHandle, "[TEST] 跳過 Grids: ", (RM_TestSkipGrids == YES ? "是" : "否"));
         FileWrite(g_logFileHandle, "[TEST] 自動獲利: ", (RM_TestAutoProfit > 0 ? IntegerToString(RM_TestAutoProfit) + " 秒" : "手動"));
         FileWrite(g_logFileHandle, "**********************************************");
        }

      FileWrite(g_logFileHandle, "");
      FileFlush(g_logFileHandle);  // 強制寫入磁碟
      Print("[Recovery] 共用日誌檔案: ", g_sharedLogFileName);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CloseLogFile()
  {
   if(g_logFileHandle != INVALID_HANDLE)
     {
      FileWrite(g_logFileHandle, "");
      FileWrite(g_logFileHandle, "=== Recovery EA 停止 ===");
      FileWrite(g_logFileHandle, "時間: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
      // v1.20: 記錄對沖獲利統計
      if(g_hedgeProfitCount > 0)
        {
         FileWrite(g_logFileHandle, "對沖獲利平倉: ", IntegerToString(g_hedgeProfitCount), " 次, 總額: ", DoubleToStr(g_hedgeProfitAmount, 2));
        }
      FileWrite(g_logFileHandle, "");
      FileClose(g_logFileHandle);
      g_logFileHandle = INVALID_HANDLE;
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void WriteLog(string message)
  {
   if(RM_ShowDebugLogs == YES)
      Print(message);

   if(g_logFileHandle != INVALID_HANDLE)
     {
      FileWrite(g_logFileHandle, TimeToString(TimeCurrent(), TIME_SECONDS), " ", message);
      FileFlush(g_logFileHandle);  // 強制寫入磁碟
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
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
   FileFlush(g_logFileHandle);
  }

//+------------------------------------------------------------------+
//| [TEST] 虛擬訂單管理函數                                           |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| [TEST] 初始化虛擬訂單網格                                         |
//+------------------------------------------------------------------+
void InitVirtualOrders()
  {
   if(RM_TestMode == NO)
      return;

   // 計算總訂單數
   g_virtualOrderCount = RM_TestBuyCount + RM_TestSellCount;
   g_virtualClosedCount = 0;

   if(g_virtualOrderCount <= 0)
     {
      Print("[TEST] 警告：虛擬訂單數量為 0");
      return;
     }

   // 調整陣列大小
   ArrayResize(g_virtualOrders, g_virtualOrderCount);

   // 取得當前價格作為基準
   double basePrice = (Ask + Bid) / 2.0;
   double gap = RM_TestGridGap * g_pointValue;
   int ticketBase = 99001;
   int idx = 0;

   // 建立 Buy 訂單（往上）
   for(int i = 0; i < RM_TestBuyCount; i++)
     {
      g_virtualOrders[idx].ticket     = ticketBase + idx;
      g_virtualOrders[idx].type       = OP_BUY;
      g_virtualOrders[idx].lots       = RM_TestLotsPerOrder;
      g_virtualOrders[idx].openPrice  = basePrice + (i + 1) * gap;
      g_virtualOrders[idx].profit     = 0;  // 由 UpdateVirtualOrderProfits() 動態計算
      g_virtualOrders[idx].remainLots = RM_TestLotsPerOrder;
      g_virtualOrders[idx].isClosed   = false;
      g_virtualOrders[idx].lineName   = "VOrder_" + IntegerToString(g_virtualOrders[idx].ticket);
      idx++;
     }

   // 建立 Sell 訂單（往下）
   for(int i = 0; i < RM_TestSellCount; i++)
     {
      g_virtualOrders[idx].ticket     = ticketBase + idx;
      g_virtualOrders[idx].type       = OP_SELL;
      g_virtualOrders[idx].lots       = RM_TestLotsPerOrder;
      g_virtualOrders[idx].openPrice  = basePrice - (i + 1) * gap;
      g_virtualOrders[idx].profit     = 0;  // 由 UpdateVirtualOrderProfits() 動態計算
      g_virtualOrders[idx].remainLots = RM_TestLotsPerOrder;
      g_virtualOrders[idx].isClosed   = false;
      g_virtualOrders[idx].lineName   = "VOrder_" + IntegerToString(g_virtualOrders[idx].ticket);
      idx++;
     }

   // 繪製所有虛擬訂單的水平線
   DrawAllVirtualOrderLines();

   Print("[TEST] 虛擬訂單初始化完成: Buy=", RM_TestBuyCount, " Sell=", RM_TestSellCount);
   WriteLog("[TEST] 虛擬訂單網格: " + IntegerToString(g_virtualOrderCount) + " 筆");
  }

//+------------------------------------------------------------------+
//| [TEST] 繪製所有虛擬訂單水平線                                     |
//+------------------------------------------------------------------+
void DrawAllVirtualOrderLines()
  {
   for(int i = 0; i < g_virtualOrderCount; i++)
     {
      DrawVirtualOrderLine(i);
     }
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| [TEST] 繪製單筆虛擬訂單水平線                                     |
//| v1.20: 根據盈虧狀態決定線條顏色                                   |
//+------------------------------------------------------------------+
void DrawVirtualOrderLine(int idx)
  {
   if(idx < 0 || idx >= g_virtualOrderCount)
      return;

   string name = g_virtualOrders[idx].lineName;
   double price = g_virtualOrders[idx].openPrice;
   
   // v1.20: 根據盈虧狀態決定顏色
   color lineColor;
   if(g_virtualOrders[idx].isClosed)
      lineColor = clrDimGray;           // 已平倉：灰色
   else if(g_virtualOrders[idx].profit >= 0)
      lineColor = clrLime;              // 獲利：綠色
   else
      lineColor = clrOrange;            // 虧損：橘色

   // 刪除舊線（如果存在）
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   // 建立水平線
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);

   // 設定標籤
   string typeStr = (g_virtualOrders[idx].type == OP_BUY) ? "B" : "S";
   string profitStr = (g_virtualOrders[idx].profit >= 0) ? "+" : "";
   string label = typeStr + IntegerToString(idx + 1) + " " + 
                  DoubleToStr(g_virtualOrders[idx].remainLots, 2) + "/" +
                  DoubleToStr(g_virtualOrders[idx].lots, 2) + " " +
                  profitStr + DoubleToStr(g_virtualOrders[idx].profit, 2);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, label);
  }

//+------------------------------------------------------------------+
//| [TEST] 刪除所有虛擬訂單水平線                                     |
//+------------------------------------------------------------------+
void DeleteAllVirtualOrderLines()
  {
   for(int i = 0; i < g_virtualOrderCount; i++)
     {
      string name = g_virtualOrders[i].lineName;
      if(ObjectFind(0, name) >= 0)
         ObjectDelete(0, name);
     }
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| [TEST] 取得虛擬訂單統計                                           |
//+------------------------------------------------------------------+
void GetVirtualOrderStats(double &totalLoss, double &buyLots, double &sellLots, int &orderCount)
  {
   totalLoss = 0;
   buyLots = 0;
   sellLots = 0;
   orderCount = 0;

   for(int i = 0; i < g_virtualOrderCount; i++)
     {
      if(g_virtualOrders[i].isClosed)
         continue;

      // 計算剩餘手數的比例虧損
      double ratio = g_virtualOrders[i].remainLots / g_virtualOrders[i].lots;
      totalLoss += g_virtualOrders[i].profit * ratio;
      orderCount++;

      if(g_virtualOrders[i].type == OP_BUY)
         buyLots += g_virtualOrders[i].remainLots;
      else
         sellLots += g_virtualOrders[i].remainLots;
     }
  }

//+------------------------------------------------------------------+
//| [TEST] 選擇最佳虛擬訂單                                           |
//| v1.20: 加入跳過已轉盈訂單邏輯                                     |
//+------------------------------------------------------------------+
int SelectBestVirtualOrder()
  {
   int bestIdx = -1;
   double bestPartialLoss = 0;

   // 計算多空失衡
   double buyLots = 0, sellLots = 0;
   for(int i = 0; i < g_virtualOrderCount; i++)
     {
      if(g_virtualOrders[i].isClosed)
         continue;
      if(g_virtualOrders[i].type == OP_BUY)
         buyLots += g_virtualOrders[i].remainLots;
      else
         sellLots += g_virtualOrders[i].remainLots;
     }

   double imbalance = buyLots - sellLots;
   bool forceDirection = (MathAbs(imbalance) > RM_MaxImbalance);
   int forcedType = (imbalance > 0) ? OP_BUY : OP_SELL;

   // 掃描所有未平倉訂單
   for(int i = 0; i < g_virtualOrderCount; i++)
     {
      if(g_virtualOrders[i].isClosed)
         continue;
      if(g_virtualOrders[i].remainLots <= 0)
         continue;

      // v1.20: 跳過已轉盈訂單
      if(RM_SkipProfitOrders == YES && g_virtualOrders[i].profit >= 0)
         continue;

      // 平衡保護
      if(forceDirection && g_virtualOrders[i].type != forcedType)
         continue;

      // 計算部分虧損
      double ratio = MathMin(RM_PartialLots, g_virtualOrders[i].remainLots) / g_virtualOrders[i].lots;
      double partialLoss = g_virtualOrders[i].profit * ratio;

      // 選擇虧損最小的（簡單優先）
      bool isBetter = false;
      if(RM_OrderSelector == SEL_EASY)
         isBetter = (bestIdx < 0 || partialLoss > bestPartialLoss);
      else
         isBetter = (bestIdx < 0 || partialLoss < bestPartialLoss);

      if(isBetter)
        {
         bestIdx = i;
         bestPartialLoss = partialLoss;
        }
     }

   return bestIdx;
  }

//+------------------------------------------------------------------+
//| [TEST] 執行虛擬訂單部分平倉                                       |
//+------------------------------------------------------------------+
bool CloseVirtualOrderPartial(int idx, double lots)
  {
   if(idx < 0 || idx >= g_virtualOrderCount)
      return false;

   if(g_virtualOrders[idx].isClosed)
      return false;

   // 扣減手數
   double closeLots = MathMin(lots, g_virtualOrders[idx].remainLots);
   g_virtualOrders[idx].remainLots -= closeLots;

   // 檢查是否完全平倉
   if(g_virtualOrders[idx].remainLots <= 0.001)
     {
      g_virtualOrders[idx].remainLots = 0;
      g_virtualOrders[idx].isClosed = true;
      g_virtualClosedCount++;
     }

   // 更新圖表線條顏色
   DrawVirtualOrderLine(idx);
   ChartRedraw();

   string typeStr = (g_virtualOrders[idx].type == OP_BUY) ? "Buy" : "Sell";
   WriteLog("[TEST] 虛擬平倉: " + typeStr + " #" + IntegerToString(g_virtualOrders[idx].ticket) +
            " 平倉=" + DoubleToStr(closeLots, 2) + " 剩餘=" + DoubleToStr(g_virtualOrders[idx].remainLots, 2) +
            (g_virtualOrders[idx].isClosed ? " [已清空]" : ""));

   return true;
  }

//+------------------------------------------------------------------+
//| [TEST] 檢查是否所有虛擬訂單都已平倉                               |
//+------------------------------------------------------------------+
bool IsAllVirtualOrdersClosed()
  {
   return (g_virtualClosedCount >= g_virtualOrderCount);
  }

//+------------------------------------------------------------------+
//| [TEST] 更新虛擬訂單浮動損益                                       |
//| 根據當前市價動態計算每筆虛擬訂單的浮動損益                        |
//+------------------------------------------------------------------+
void UpdateVirtualOrderProfits()
  {
   if(RM_TestMode == NO || g_virtualOrderCount <= 0)
      return;

   // 取得當前報價
   double bid = MarketInfo(Symbol(), MODE_BID);
   double ask = MarketInfo(Symbol(), MODE_ASK);
   
   // 取得點值（用於計算損益）
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   
   // 計算每點價值係數
   double pointValueCoef = tickValue / tickSize;

   for(int i = 0; i < g_virtualOrderCount; i++)
     {
      if(g_virtualOrders[i].isClosed)
         continue;

      double priceDiff = 0;
      
      if(g_virtualOrders[i].type == OP_BUY)
        {
         // Buy 訂單：profit = (Bid - openPrice) × remainLots × 點值係數
         priceDiff = bid - g_virtualOrders[i].openPrice;
        }
      else
        {
         // Sell 訂單：profit = (openPrice - Ask) × remainLots × 點值係數
         priceDiff = g_virtualOrders[i].openPrice - ask;
        }
      
      // 計算浮動損益
      g_virtualOrders[i].profit = priceDiff * g_virtualOrders[i].remainLots * pointValueCoef;
     }
     
   // v1.20: 更新線條顏色（每次價格變動後）
   DrawAllVirtualOrderLines();
  }

//+------------------------------------------------------------------+
//| GV 操作函數                                                       |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string GetGVFullName(string name)
  {
   string fullName = RM_GV_Prefix + RM_GroupID + "_" + name;

   if(StringLen(fullName) > GV_MAX_LENGTH)
     {
      Print("[警告] GV 名稱過長 (", StringLen(fullName), " > ", GV_MAX_LENGTH, "): ", fullName);
      fullName = StringSubstr(fullName, 0, GV_MAX_LENGTH);
     }

   return fullName;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void WriteGV(string name, double value)
  {
   string fullName = GetGVFullName(name);
   GlobalVariableSet(fullName, value);
   if(RM_ShowDebugLogs == YES)
      Print("[GV] 寫入 ", fullName, " = ", value);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double ReadGV(string name, double defaultValue = 0)
  {
   string fullName = GetGVFullName(name);
   if(GlobalVariableCheck(fullName))
      return GlobalVariableGet(fullName);
   return defaultValue;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CheckGV(string name)
  {
   string fullName = GetGVFullName(name);
   return GlobalVariableCheck(fullName);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DeleteGV(string name)
  {
   string fullName = GetGVFullName(name);
   if(GlobalVariableCheck(fullName))
      GlobalVariableDel(fullName);
  }

//+------------------------------------------------------------------+
//| 組別衝突檢測函數                                                  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GenerateInstanceId()
  {
   return (double)TimeCurrent() + MathRand() / 32768.0;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CheckGroupConflict()
  {
   if(RM_CheckConflict == NO)
      return false;

   string lockGV = GetGVFullName("RECOVERY_LOCK");

   if(GlobalVariableCheck(lockGV))
     {
      double existingId = GlobalVariableGet(lockGV);
      datetime lastUpdate = (datetime)ReadGV("LAST_UPDATE", 0);

      if(TimeCurrent() - lastUpdate > 60)
        {
         Print("[Recovery] 偵測到舊的實例已停止，接管組別 ", RM_GroupID);
        }
      else
         if(existingId != g_instanceId && existingId != 0)
           {
            Print("[Recovery] 錯誤：組別 ", RM_GroupID, " 已有其他 Recovery EA 運行！");
            return true;
           }
     }

   GlobalVariableSet(lockGV, g_instanceId);
   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ReleaseGroupLock()
  {
   string lockGV = GetGVFullName("RECOVERY_LOCK");
   if(GlobalVariableCheck(lockGV))
     {
      double existingId = GlobalVariableGet(lockGV);
      if(existingId == g_instanceId)
         GlobalVariableDel(lockGV);
     }
  }

//+------------------------------------------------------------------+
//| v1.20 新增：更新訂單統計結構                                      |
//+------------------------------------------------------------------+
void UpdateOrderStats()
  {
   // 重置統計
   g_orderStats.buyProfitLots = 0;
   g_orderStats.buyLossLots = 0;
   g_orderStats.sellProfitLots = 0;
   g_orderStats.sellLossLots = 0;
   g_orderStats.buyProfitAmount = 0;
   g_orderStats.buyLossAmount = 0;
   g_orderStats.sellProfitAmount = 0;
   g_orderStats.sellLossAmount = 0;
   g_orderStats.buyProfitCount = 0;
   g_orderStats.buyLossCount = 0;
   g_orderStats.sellProfitCount = 0;
   g_orderStats.sellLossCount = 0;

   // 測試模式：從虛擬訂單統計
   if(RM_TestMode == YES)
     {
      for(int i = 0; i < g_virtualOrderCount; i++)
        {
         if(g_virtualOrders[i].isClosed) continue;
         
         double profit = g_virtualOrders[i].profit;
         double lots = g_virtualOrders[i].remainLots;
         
         if(g_virtualOrders[i].type == OP_BUY)
           {
            if(profit >= 0)
              { g_orderStats.buyProfitLots += lots; g_orderStats.buyProfitAmount += profit; g_orderStats.buyProfitCount++; }
            else
              { g_orderStats.buyLossLots += lots; g_orderStats.buyLossAmount += profit; g_orderStats.buyLossCount++; }
           }
         else
           {
            if(profit >= 0)
              { g_orderStats.sellProfitLots += lots; g_orderStats.sellProfitAmount += profit; g_orderStats.sellProfitCount++; }
            else
              { g_orderStats.sellLossLots += lots; g_orderStats.sellLossAmount += profit; g_orderStats.sellLossCount++; }
           }
        }
      return;
     }
  }

//+------------------------------------------------------------------+
//| v1.20 新增：嘗試對沖獲利平倉                                      |
//| 當 Buy 和 Sell 都有獲利訂單時，配對平倉（不消耗 Grids 額度）      |
//+------------------------------------------------------------------+
bool TryHedgeProfitClose()
  {
   if(RM_EnableHedgeProfit == NO)
      return false;
      
   // 檢查是否有可配對的獲利訂單
   if(g_orderStats.buyProfitCount <= 0 || g_orderStats.sellProfitCount <= 0)
      return false;
      
   // 執行對沖獲利平倉
   return ExecuteHedgeProfitClose();
  }

//+------------------------------------------------------------------+
//| v1.20 新增：執行對沖獲利平倉                                      |
//+------------------------------------------------------------------+
bool ExecuteHedgeProfitClose()
  {
   // 測試模式：虛擬訂單對沖平倉
   if(RM_TestMode == YES)
     {
      int buyIdx = -1, sellIdx = -1;
      double minLots = 999999;
      
      // 找到獲利的 Buy 和 Sell 訂單
      for(int i = 0; i < g_virtualOrderCount; i++)
        {
         if(g_virtualOrders[i].isClosed) continue;
         if(g_virtualOrders[i].profit < 0) continue;
         
         if(g_virtualOrders[i].type == OP_BUY && buyIdx < 0)
            buyIdx = i;
         else if(g_virtualOrders[i].type == OP_SELL && sellIdx < 0)
            sellIdx = i;
            
         if(buyIdx >= 0 && sellIdx >= 0) break;
        }
      
      if(buyIdx < 0 || sellIdx < 0)
         return false;
         
      // 計算可平倉手數（取較小值）
      double closeLots = MathMin(g_virtualOrders[buyIdx].remainLots, g_virtualOrders[sellIdx].remainLots);
      double totalProfit = g_virtualOrders[buyIdx].profit + g_virtualOrders[sellIdx].profit;
      
      // 執行虛擬平倉
      CloseVirtualOrderPartial(buyIdx, closeLots);
      CloseVirtualOrderPartial(sellIdx, closeLots);
      
      // 更新統計
      g_hedgeProfitCount++;
      g_hedgeProfitAmount += totalProfit;
      
      WriteLog("[v1.20] 對沖獲利平倉: Buy#" + IntegerToString(g_virtualOrders[buyIdx].ticket) +
               " + Sell#" + IntegerToString(g_virtualOrders[sellIdx].ticket) +
               " 手數=" + DoubleToStr(closeLots, 2) + " 獲利=" + DoubleToStr(totalProfit, 2));
      return true;
     }
   
   return false;
  }

//+------------------------------------------------------------------+
//| 初始化函數                                                        |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_digits = (int)MarketInfo(Symbol(), MODE_DIGITS);
   g_pointValue = MarketInfo(Symbol(), MODE_POINT);

   g_instanceId = GenerateInstanceId();

   OpenLogFile();

   if(CheckGroupConflict())
     {
      CloseLogFile();
      return(INIT_FAILED);
     }

   g_transactionId = ReadGV("TRANSACTION_ID", 0);

   WriteGV("RECOVERY_STATE", STATE_R_IDLE);
   WriteGV("PROFIT_TARGET", 0.0);
   WriteGV("PARTIAL_LOSS", 0.0);
   WriteGV("RECOVERY_ACK_ID", 0.0);
   WriteGV("LAST_UPDATE", (double)TimeCurrent());

   g_isInitialized = true;
   g_recoveryState = STATE_R_IDLE;
   g_launchProcessed = false;
   g_closedBuyLots = 0.0;
   g_closedSellLots = 0.0;
   g_testStartTime = TimeCurrent();
   g_testRoundCount = 0;
   g_testProfitSimulated = false;
   g_testCompleted = false;
   
   // v1.20: 初始化對沖獲利統計
   g_hedgeProfitCount = 0;
   g_hedgeProfitAmount = 0.0;

   Print("=== Recovery EA v" + EA_VERSION + " 初始化完成 ===");
   Print("組別 ID: ", RM_GroupID);
   Print("動態掃描: ", (RM_DynamicScan == YES ? "啟用" : "停用"));
   Print("平衡保護閾值: ", RM_MaxImbalance, " 手");
   Print("部分平倉手數: ", RM_PartialLots);
   Print("GV 範例: ", GetGVFullName("PROFIT_TARGET"));
   
   // v1.20 新增功能提示
   Print("對沖獲利平倉: ", (RM_EnableHedgeProfit == YES ? "啟用" : "停用"));
   Print("跳過已轉盈訂單: ", (RM_SkipProfitOrders == YES ? "啟用" : "停用"));
   Print("動態調整目標: ", (RM_DynamicTargetAdjust == YES ? "啟用" : "停用"));

   // 測試模式提示 (v1.11)
   if(RM_TestMode == YES)
     {
      Print("========================================");
      Print("*** 測試模式已啟用 ***");
      Print("虛擬訂單: Buy=", RM_TestBuyCount, " Sell=", RM_TestSellCount);
      Print("網格間距: ", RM_TestGridGap, " 點");
      Print("每筆手數: ", RM_TestLotsPerOrder);
      Print("跳過 Grids 通訊: ", (RM_TestSkipGrids == YES ? "是" : "否"));
      if(RM_TestAutoProfit > 0)
         Print("自動模擬獲利: ", RM_TestAutoProfit, " 秒後");
      if(RM_TestMaxRounds > 0)
         Print("最大測試輪數: ", RM_TestMaxRounds);
      else
         Print("最大測試輪數: 無限 (直到全部平倉)");
      Print("========================================");

      // 初始化虛擬訂單網格
      InitVirtualOrders();
     }

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
   
   // [TEST] 清理虛擬訂單線條
   if(RM_TestMode == YES)
      DeleteAllVirtualOrderLines();
   
   Print("=== Recovery EA 已停止 (組別: ", RM_GroupID, ") ===");
  }

//+------------------------------------------------------------------+
//| 主要交易邏輯 - 狀態機驅動                                         |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!g_isInitialized)
     {
      UpdateChartPanel();
      return;
     }

   // [TEST] 更新虛擬訂單浮動損益
   if(RM_TestMode == YES)
      UpdateVirtualOrderProfits();

   // [TEST] 測試完成後停止執行（但仍更新 UI）
   if(RM_TestMode == YES && g_testCompleted)
     {
      UpdateChartPanel();
      return;
     }

   if(TimeCurrent() - g_lastUpdateTime < RM_UpdateInterval)
     {
      UpdateChartPanel();
      return;
     }
   g_lastUpdateTime = TimeCurrent();

   if(!CheckLaunchCondition())
     {
      UpdateChartPanel();
      return;
     }

   if(!g_launchProcessed)
     {
      ExecuteLaunchProcessing();
      g_launchProcessed = true;
     }

   ScanLossPositions();
   
   // v1.20: 更新訂單統計
   UpdateOrderStats();

   if(g_lossOrderCount == 0)
     {
      ResetToIdle();
      UpdateChartPanel();
      return;
     }

   if(RM_UseBasketTP == YES && CheckBasketTakeProfit())
     {
      UpdateChartPanel();
      return;
     }

   ExecuteStateMachine();

   WriteGV("LAST_UPDATE", (double)TimeCurrent());
   
   // UI 更新放在最後，確保顯示最新數據
   UpdateChartPanel();
  }

//+------------------------------------------------------------------+
//| 狀態機核心邏輯                                                    |
//+------------------------------------------------------------------+
void ExecuteStateMachine()
  {
   int gridsState = (int)ReadGV("GRIDS_STATE", STATE_G_IDLE);
   double gridsAckId = ReadGV("GRIDS_ACK_ID", 0);

   switch(g_recoveryState)
     {
      case STATE_R_IDLE:
         HandleStateIdle();
         break;

      case STATE_R_REQUESTING:
         HandleStateRequesting(gridsState, gridsAckId);
         break;

      case STATE_R_WAITING:
         HandleStateWaiting(gridsState, gridsAckId);
         break;

      case STATE_R_CONSUMING:
         HandleStateConsuming();
         break;

      case STATE_R_CONFIRMING:
         HandleStateConfirming(gridsState);
         break;
     }
  }

//+------------------------------------------------------------------+
//| 狀態處理：閒置 - 發起新的獲利請求                                 |
//| v1.20: 加入對沖獲利平倉和動態調整目標獲利                         |
//+------------------------------------------------------------------+
void HandleStateIdle()
  {
   // v1.20: 優先嘗試對沖獲利平倉（不消耗 Grids 額度）
   if(TryHedgeProfitClose())
     {
      // 對沖平倉成功，檢查是否還有虧損訂單
      ScanLossPositions();
      UpdateOrderStats();
      if(g_lossOrderCount == 0)
         return;
     }

   // 選擇當前要處理的訂單（使用動態掃描或傳統模式）
   if(RM_DynamicScan == YES)
      SelectBestOrder();      // v1.10: 單筆動態掃描
   else
      SelectCurrentOrders();  // 傳統: 一多一空配對

   // 計算當前部分的虧損
   g_currentPartialLoss = CalculatePartialLoss();

   if(g_currentPartialLoss >= 0)
      return;

   // 計算目標獲利 = |部分虧損| + 止盈緩衝
   g_profitTarget = MathAbs(g_currentPartialLoss) + RM_TakeProfitMoney;
   
   // v1.20: 動態調整目標獲利（根據訂單盈虧變化）
   if(RM_DynamicTargetAdjust == YES)
     {
      double profitOffset = g_orderStats.buyProfitAmount + g_orderStats.sellProfitAmount;
      if(profitOffset > 0)
        {
         double adjustedTarget = g_profitTarget - (profitOffset * 0.5);
         if(adjustedTarget > RM_TakeProfitMoney)
           {
            WriteLog("[v1.20] 動態調整目標: " + DoubleToStr(g_profitTarget, 2) + " -> " + DoubleToStr(adjustedTarget, 2));
            g_profitTarget = adjustedTarget;
           }
        }
     }

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
   g_lastRescanTime = TimeCurrent();

   string orderInfo = RM_DynamicScan ?
                      ("單筆 Ticket=" + IntegerToString(g_currentTicket) + " " + (g_currentOrderType == OP_BUY ? "Buy" : "Sell")) :
                      ("配對 Buy=" + IntegerToString(g_currentBuyTicket) + " Sell=" + IntegerToString(g_currentSellTicket));

   WriteLog("[Recovery] 發起獲利請求 TxID=" + DoubleToStr(g_transactionId, 0) +
            " 目標=" + DoubleToStr(g_profitTarget, 2) + " " + orderInfo);
  }

//+------------------------------------------------------------------+
//| 狀態處理：請求中 - 等待 Grids 確認                                |
//+------------------------------------------------------------------+
void HandleStateRequesting(int gridsState, double gridsAckId)
  {
   // [TEST] 測試模式：跳過 Grids 確認，直接進入等待狀態
   if(RM_TestMode == YES && RM_TestSkipGrids == YES)
     {
      g_recoveryState = STATE_R_WAITING;
      WriteGV("RECOVERY_STATE", g_recoveryState);
      WriteLog("[TEST] 跳過 Grids 確認，直接進入等待狀態");
      return;
     }

   // ===== 正常模式 =====
   if(gridsAckId == g_transactionId && gridsState >= STATE_G_ACCUMULATING)
     {
      g_recoveryState = STATE_R_WAITING;
      WriteGV("RECOVERY_STATE", g_recoveryState);
      WriteLog("[Recovery] Grids 已確認請求 TxID=" + DoubleToStr(g_transactionId, 0));
      return;
     }

   if(TimeCurrent() - g_requestTime > RM_AckTimeout)
     {
      Print("[Recovery] 警告：等待 Grids 確認超時，重新發送請求");
      WriteGV("PROFIT_TARGET", g_profitTarget);
      WriteGV("RECOVERY_STATE", STATE_R_REQUESTING);
      g_requestTime = TimeCurrent();
     }
  }

//+------------------------------------------------------------------+
//| 狀態處理：等待獲利 - 包含動態重新評估 (v1.10)                     |
//+------------------------------------------------------------------+
void HandleStateWaiting(int gridsState, double gridsAckId)
  {
   // ===== 測試模式：跳過 Grids 通訊檢查 =====
   if(RM_TestMode == YES && RM_TestSkipGrids == YES)
     {
      // 檢查是否啟用自動模擬獲利
      if(RM_TestAutoProfit > 0 && !g_testProfitSimulated)
        {
         if(TimeCurrent() - g_requestTime >= RM_TestAutoProfit)
           {
            // v1.20: 自動模擬獲利改為亂數 10~50
            int randomProfit = 10 + MathRand() % 41;
            WriteGV("ACCUMULATED_PROFIT", g_profitTarget + randomProfit);
            WriteGV("GRIDS_STATE", STATE_G_READY);
            g_testProfitSimulated = true;
            Print("[測試模式] 自動模擬獲利達標: ", DoubleToStr(g_profitTarget + randomProfit, 2));
           }
        }

      // 檢查模擬的累積獲利
      double accumulatedProfit = ReadGV("ACCUMULATED_PROFIT", 0);
      if(accumulatedProfit >= g_profitTarget)
        {
         g_recoveryState = STATE_R_CONSUMING;
         WriteGV("RECOVERY_STATE", g_recoveryState);
         Print("[測試模式] 獲利達標，進入消費狀態");
        }
      return;
     }

   // ===== 正常模式 =====
   if(gridsAckId != g_transactionId)
     {
      Print("[Recovery] 警告：TxID 不匹配，回到請求狀態");
      g_recoveryState = STATE_R_REQUESTING;
      WriteGV("RECOVERY_STATE", g_recoveryState);
      return;
     }

   // v1.10: 動態重新評估 - 檢查是否有更好的訂單
   if(RM_DynamicScan == YES && TimeCurrent() - g_lastRescanTime >= RM_RescanInterval)
     {
      g_lastRescanTime = TimeCurrent();
      TryRescanForBetterTarget();
     }

   // 檢查 Grids 是否獲利就緒
   if(gridsState == STATE_G_READY)
     {
      double accumulatedProfit = ReadGV("ACCUMULATED_PROFIT", 0);

      if(accumulatedProfit >= g_profitTarget)
        {
         g_recoveryState = STATE_R_CONSUMING;
         WriteGV("RECOVERY_STATE", g_recoveryState);

         WriteLog("[Recovery] 獲利達標! 累積=" + DoubleToStr(accumulatedProfit, 2) +
                  " 目標=" + DoubleToStr(g_profitTarget, 2));
        }
     }
  }

//+------------------------------------------------------------------+
//| 動態重新評估：檢查是否有更好的目標 (v1.10 新增)                   |
//+------------------------------------------------------------------+
void TryRescanForBetterTarget()
  {
   // 保存當前狀態
   int oldTicket = g_currentTicket;
   int oldOrderType = g_currentOrderType;
   double oldTarget = g_profitTarget;

   // 重新掃描
   SelectBestOrder();
   double newPartialLoss = CalculatePartialLoss();

   if(newPartialLoss >= 0)
     {
      // 沒有虧損訂單了，恢復原狀態
      g_currentTicket = oldTicket;
      g_currentOrderType = oldOrderType;
      return;
     }

   double newTarget = MathAbs(newPartialLoss) + RM_TakeProfitMoney;

   // 檢查是否值得切換（新目標需低於舊目標一定百分比）
   double threshold = oldTarget * (1.0 - RM_SwitchThreshold / 100.0);

   if(newTarget < threshold && g_currentTicket != oldTicket)
     {
      // 切換到新目標
      g_profitTarget = newTarget;
      g_currentPartialLoss = newPartialLoss;
      WriteGV("PROFIT_TARGET", g_profitTarget);
      WriteGV("PARTIAL_LOSS", g_currentPartialLoss);

      WriteLog("[Recovery] 動態切換目標: " + DoubleToStr(oldTarget, 2) + " -> " +
               DoubleToStr(newTarget, 2) + " Ticket=" + IntegerToString(g_currentTicket));

      // 檢查是否已累積的獲利已經足夠新目標
      double accumulatedProfit = ReadGV("ACCUMULATED_PROFIT", 0);
      if(accumulatedProfit >= g_profitTarget)
        {
         WriteLog("[Recovery] 累積獲利已達新目標，直接進入消費狀態");
         g_recoveryState = STATE_R_CONSUMING;
         WriteGV("RECOVERY_STATE", g_recoveryState);
        }
     }
   else
     {
      // 不切換，恢復原狀態
      g_currentTicket = oldTicket;
      g_currentOrderType = oldOrderType;
     }
  }

//+------------------------------------------------------------------+
//| 狀態處理：消費獲利（執行平倉）                                    |
//+------------------------------------------------------------------+
void HandleStateConsuming()
  {
   bool closeSuccess = false;

   if(RM_DynamicScan == YES)
      closeSuccess = ExecuteSingleClose();    // v1.10: 單筆平倉
   else
      closeSuccess = ExecutePartialClose();   // 傳統: 配對平倉

   if(closeSuccess)
     {
      WriteGV("RECOVERY_ACK_ID", g_transactionId);
      g_recoveryState = STATE_R_CONFIRMING;
      WriteGV("RECOVERY_STATE", g_recoveryState);
      WriteLog("[Recovery] 部分平倉完成，等待 Grids 重置");
     }
   else
     {
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
   // [TEST] 測試模式：直接完成確認
   if(RM_TestMode == YES && RM_TestSkipGrids == YES)
     {
      g_recoveryState = STATE_R_IDLE;
      WriteGV("RECOVERY_STATE", g_recoveryState);
      WriteGV("PROFIT_TARGET", 0.0);
      WriteLog("[TEST] 交易週期完成 TxID=" + DoubleToStr(g_transactionId, 0));
      return;
     }

   // ===== 正常模式 =====
   if(gridsState == STATE_G_ACKNOWLEDGED || gridsState == STATE_G_IDLE)
     {
      g_recoveryState = STATE_R_IDLE;
      WriteGV("RECOVERY_STATE", g_recoveryState);
      WriteGV("PROFIT_TARGET", 0.0);
      WriteLog("[Recovery] 交易週期完成 TxID=" + DoubleToStr(g_transactionId, 0));
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
//| 單筆動態掃描：選擇最佳訂單 (v1.10 新增)                           |
//| v1.20: 加入跳過已轉盈訂單邏輯                                     |
//+------------------------------------------------------------------+
void SelectBestOrder()
  {
   g_currentTicket = 0;
   g_currentOrderType = -1;
   g_currentBuyTicket = 0;
   g_currentSellTicket = 0;

   // ===== 測試模式：使用虛擬訂單陣列 =====
   if(RM_TestMode == YES)
     {
      int bestIdx = SelectBestVirtualOrder();
      if(bestIdx >= 0)
        {
         g_currentTicket = g_virtualOrders[bestIdx].ticket;
         g_currentOrderType = g_virtualOrders[bestIdx].type;
         
         if(g_currentOrderType == OP_BUY)
            g_currentBuyTicket = g_currentTicket;
         else
            g_currentSellTicket = g_currentTicket;
        }

      if(RM_ShowDebugLogs == YES)
         Print("[測試模式] 選擇虛擬訂單: ",
               (g_currentOrderType == OP_BUY ? "Buy" : "Sell"),
               " Ticket=", g_currentTicket);
      return;
     }

   // ===== 正常模式 =====
   double bestPartialLoss = 0;
   int bestTicket = 0;
   int bestOrderType = -1;

   // 優先處理指定的 Ticket
   if(RM_FirstTicket > 0)
     {
      if(OrderSelect(RM_FirstTicket, SELECT_BY_TICKET, MODE_TRADES))
        {
         double profit = OrderProfit() + OrderSwap() + OrderCommission();
         if(profit < 0 && OrderType() <= OP_SELL)
           {
            g_currentTicket = RM_FirstTicket;
            g_currentOrderType = OrderType();
            return;
           }
        }
     }

   // 計算當前多空手數差（用於平衡保護）
   double imbalance = g_totalBuyLots - g_totalSellLots;
   bool forceDirection = false;
   int forcedType = -1;

   // 平衡保護：如果失衡超過閾值，強制選擇較多的那一邊
   if(MathAbs(imbalance) > RM_MaxImbalance)
     {
      forceDirection = true;
      forcedType = (imbalance > 0) ? OP_BUY : OP_SELL;

      if(RM_ShowDebugLogs == YES)
         Print("[Recovery] 平衡保護啟動: 失衡=", DoubleToStr(imbalance, 2),
               " 強制平倉 ", (forcedType == OP_BUY ? "Buy" : "Sell"));
     }

   // 掃描所有虧損訂單
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
      
      // v1.20: 跳過已轉盈訂單
      if(RM_SkipProfitOrders == YES && profit >= 0)
         continue;
         
      if(profit >= 0)
         continue;

      // 如果啟用平衡保護且強制方向，只考慮該方向的訂單
      if(forceDirection && OrderType() != forcedType)
         continue;

      // 計算此訂單的部分虧損
      double orderLots = OrderLots();
      double partialLots = MathMin(RM_PartialLots, orderLots);
      double partialLoss = (profit / orderLots) * partialLots;

      // 根據選擇模式判斷是否更好
      bool isBetter = false;
      if(RM_OrderSelector == SEL_EASY)
         isBetter = (bestTicket == 0 || partialLoss > bestPartialLoss);
      else
         isBetter = (bestTicket == 0 || partialLoss < bestPartialLoss);

      if(isBetter)
        {
         bestTicket = OrderTicket();
         bestOrderType = OrderType();
         bestPartialLoss = partialLoss;
        }
     }

   g_currentTicket = bestTicket;
   g_currentOrderType = bestOrderType;

   // 為了相容性，也設定舊版變數
   if(bestOrderType == OP_BUY)
      g_currentBuyTicket = bestTicket;
   else if(bestOrderType == OP_SELL)
      g_currentSellTicket = bestTicket;
  }

//+------------------------------------------------------------------+
//| 傳統模式：選擇一多一空配對                                        |
//+------------------------------------------------------------------+
void SelectCurrentOrders()
  {
   g_currentBuyTicket = 0;
   g_currentSellTicket = 0;
   g_currentTicket = 0;
   g_currentOrderType = -1;

   double bestBuyLoss = 0;
   double bestSellLoss = 0;

   if(RM_FirstTicket > 0)
     {
      if(OrderSelect(RM_FirstTicket, SELECT_BY_TICKET, MODE_TRADES))
        {
         if(OrderType() == OP_BUY)
            g_currentBuyTicket = RM_FirstTicket;
         else if(OrderType() == OP_SELL)
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

      if(RM_OrderSelector == SEL_EASY)
        {
         if(OrderType() == OP_BUY && g_currentBuyTicket == 0)
            isBetter = (bestBuyLoss == 0 || profit > bestBuyLoss);
         else if(OrderType() == OP_SELL && g_currentSellTicket == 0)
            isBetter = (bestSellLoss == 0 || profit > bestSellLoss);
        }
      else
        {
         if(OrderType() == OP_BUY && g_currentBuyTicket == 0)
            isBetter = (bestBuyLoss == 0 || profit < bestBuyLoss);
         else if(OrderType() == OP_SELL && g_currentSellTicket == 0)
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

   // ===== 測試模式：從虛擬訂單計算部分虧損 =====
   if(RM_TestMode == YES)
     {
      for(int i = 0; i < g_virtualOrderCount; i++)
        {
         if(g_virtualOrders[i].ticket == g_currentTicket && !g_virtualOrders[i].isClosed)
           {
            double ratio = MathMin(RM_PartialLots, g_virtualOrders[i].remainLots) / g_virtualOrders[i].lots;
            partialLoss = g_virtualOrders[i].profit * ratio;
            break;
           }
        }

      if(RM_ShowDebugLogs == YES)
         Print("[測試模式] 計算部分虧損: ", DoubleToStr(partialLoss, 2));

      return partialLoss;
     }

   // ===== 正常模式 =====
   if(RM_DynamicScan == YES)
     {
      if(g_currentTicket > 0 && OrderSelect(g_currentTicket, SELECT_BY_TICKET, MODE_TRADES))
        {
         double orderLoss = OrderProfit() + OrderSwap() + OrderCommission();
         double orderLots = OrderLots();

         if(orderLots > 0 && orderLoss < 0)
           {
            double pLots = MathMin(RM_PartialLots, orderLots);
            partialLoss = (orderLoss / orderLots) * pLots;
           }
        }
     }
   else
     {
      if(g_currentBuyTicket > 0 && OrderSelect(g_currentBuyTicket, SELECT_BY_TICKET, MODE_TRADES))
        {
         double orderLoss = OrderProfit() + OrderSwap() + OrderCommission();
         double orderLots = OrderLots();

         if(orderLots > 0 && orderLoss < 0)
           {
            double pLots = MathMin(RM_PartialLots, orderLots);
            partialLoss += (orderLoss / orderLots) * pLots;
           }
        }

      if(g_currentSellTicket > 0 && OrderSelect(g_currentSellTicket, SELECT_BY_TICKET, MODE_TRADES))
        {
         double orderLoss = OrderProfit() + OrderSwap() + OrderCommission();
         double orderLots = OrderLots();

         if(orderLots > 0 && orderLoss < 0)
           {
            double pLots = MathMin(RM_PartialLots, orderLots);
            partialLoss += (orderLoss / orderLots) * pLots;
           }
        }
     }

   return partialLoss;
  }

//+------------------------------------------------------------------+
//| 單筆平倉 (v1.10 新增)                                             |
//+------------------------------------------------------------------+
bool ExecuteSingleClose()
  {
   // ===== 測試模式：執行虛擬訂單平倉 =====
   if(RM_TestMode == YES)
     {
      int closedIdx = -1;
      for(int i = 0; i < g_virtualOrderCount; i++)
        {
         if(g_virtualOrders[i].ticket == g_currentTicket && !g_virtualOrders[i].isClosed)
           {
            CloseVirtualOrderPartial(i, RM_PartialLots);
            closedIdx = i;
            break;
           }
        }

      string orderTypeStr = (g_currentOrderType == OP_BUY) ? "Buy" : "Sell";
      Print("[測試模式] 虛擬平倉執行");
      Print("  類型: ", orderTypeStr);
      Print("  Ticket: ", g_currentTicket);
      Print("  平倉手數: ", DoubleToStr(RM_PartialLots, 2));
      Print("  消費獲利: ", DoubleToStr(g_profitTarget, 2));

      g_testRoundCount++;
      g_testProfitSimulated = false;

      double balance = ReadGV("ACCUMULATED_PROFIT", 0) - g_profitTarget;
      LogProfitTransaction("消費(測試)", g_profitTarget, balance,
                           orderTypeStr + " #" + IntegerToString(g_currentTicket) + " " + DoubleToStr(RM_PartialLots, 2) + " 手");

      if(IsAllVirtualOrdersClosed())
        {
         g_testCompleted = true;
         Print("*** [TEST] 所有虛擬訂單已平倉完成! 輪數: ", g_testRoundCount, " ***");
         WriteLog("[TEST] 所有虛擬訂單已平倉，共執行 " + IntegerToString(g_testRoundCount) + " 輪");
        }
      else if(RM_TestMaxRounds > 0 && g_testRoundCount >= RM_TestMaxRounds)
        {
         g_testCompleted = true;
         Print("*** [TEST] 達到最大測試輪數! 輪數: ", g_testRoundCount, " ***");
         WriteLog("[TEST] 達到最大輪數，共執行 " + IntegerToString(g_testRoundCount) + " 輪");
        }

      return true;
     }

   // ===== 正常模式 =====
   if(g_currentTicket <= 0)
     {
      Print("[Recovery] 錯誤：無有效的訂單 Ticket");
      return false;
     }

   if(!OrderSelect(g_currentTicket, SELECT_BY_TICKET, MODE_TRADES))
     {
      Print("[Recovery] 錯誤：無法選擇訂單 Ticket=", g_currentTicket);
      return false;
     }

   double closeLots = MathMin(RM_PartialLots, OrderLots());
   closeLots = NormalizeLots(closeLots);

   if(closeLots < MarketInfo(Symbol(), MODE_MINLOT))
     {
      Print("[Recovery] 手數太小，視為成功");
      return true;
     }

   double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
   string orderTypeStr = (OrderType() == OP_BUY) ? "Buy" : "Sell";

   bool result = OrderClose(g_currentTicket, closeLots, closePrice, RM_MaxSlippage, clrYellow);

   if(result)
     {
      Print("[Recovery] ", orderTypeStr, " 部分平倉成功: ", closeLots, " 手 Ticket=", g_currentTicket);
      if(OrderType() == OP_BUY)
         g_closedBuyLots += closeLots;
      else
         g_closedSellLots += closeLots;

      double balance = ReadGV("ACCUMULATED_PROFIT", 0) - g_profitTarget;
      LogProfitTransaction("消費", g_profitTarget, balance,
                           orderTypeStr + " " + DoubleToStr(closeLots, 2) + " 手");
     }
   else
      Print("[Recovery] ", orderTypeStr, " 部分平倉失敗: ", GetLastError(), " Ticket=", g_currentTicket);

   return result;
  }

//+------------------------------------------------------------------+
//| 傳統配對平倉                                                      |
//+------------------------------------------------------------------+
bool ExecutePartialClose()
  {
   // ===== 測試模式 =====
   if(RM_TestMode == YES)
     {
      Print("[測試模式] 模擬配對平倉成功");
      g_testRoundCount++;
      g_testProfitSimulated = false;

      double balance = ReadGV("ACCUMULATED_PROFIT", 0) - g_profitTarget;
      LogProfitTransaction("消費(測試)", g_profitTarget, balance, "配對 " + DoubleToStr(RM_PartialLots * 2, 2) + " 手");

      if(RM_TestMaxRounds > 0 && g_testRoundCount >= RM_TestMaxRounds)
        {
         g_testCompleted = true;
         Print("*** [TEST] 測試完成! 輪數: ", g_testRoundCount, " ***");
        }
      return true;
     }

   // ===== 正常模式 =====
   bool buyCloseSuccess = false;
   bool sellCloseSuccess = false;

   if(g_currentBuyTicket > 0 && OrderSelect(g_currentBuyTicket, SELECT_BY_TICKET, MODE_TRADES))
     {
      double closeLots = MathMin(RM_PartialLots, OrderLots());
      closeLots = NormalizeLots(closeLots);
      if(closeLots >= MarketInfo(Symbol(), MODE_MINLOT))
        {
         buyCloseSuccess = OrderClose(g_currentBuyTicket, closeLots, Bid, RM_MaxSlippage, clrYellow);
         if(buyCloseSuccess) g_closedBuyLots += closeLots;
        }
      else buyCloseSuccess = true;
     }
   else buyCloseSuccess = true;

   if(g_currentSellTicket > 0 && OrderSelect(g_currentSellTicket, SELECT_BY_TICKET, MODE_TRADES))
     {
      double closeLots = MathMin(RM_PartialLots, OrderLots());
      closeLots = NormalizeLots(closeLots);
      if(closeLots >= MarketInfo(Symbol(), MODE_MINLOT))
        {
         sellCloseSuccess = OrderClose(g_currentSellTicket, closeLots, Ask, RM_MaxSlippage, clrYellow);
         if(sellCloseSuccess) g_closedSellLots += closeLots;
        }
      else sellCloseSuccess = true;
     }
   else sellCloseSuccess = true;

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
//| 檢查啟動條件                                                      |
//+------------------------------------------------------------------+
bool CheckLaunchCondition()
  {
   if(RM_LaunchType == LAUNCH_NOW) return true;

   double balance = AccountBalance();
   double equity = AccountEquity();
   if(balance <= 0) return false;

   if(RM_LaunchType == LAUNCH_DD_PCT)
     {
      double drawdownPercent = (balance - equity) / balance * 100.0;
      return (drawdownPercent >= RM_LaunchThreshold);
     }

   if(RM_LaunchType == LAUNCH_DD_MONEY)
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
   if(RM_DeleteSLTP == YES) DeleteAllSLTP();
   if(RM_DeletePendingAtLaunch == YES) DeletePendingOrders();
   if(RM_CloseProfitAtLaunch == YES) CloseProfitOrders();
   if(RM_UseLocking == YES) ExecuteLocking();
   Print("[Recovery] 前置處理完成");
  }

//+------------------------------------------------------------------+
//| 刪除所有 SL 和 TP                                                 |
//+------------------------------------------------------------------+
void DeleteAllSLTP()
  {
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(!IsOrderToProcess(OrderMagicNumber())) continue;
      if(OrderStopLoss() != 0 || OrderTakeProfit() != 0)
        {
         bool result = OrderModify(OrderTicket(), OrderOpenPrice(), 0, 0, 0, clrNONE);
         if(!result && RM_ShowDebugLogs) Print("[Recovery] 刪除 SL/TP 失敗, Ticket=", OrderTicket());
        }
     }
  }

//+------------------------------------------------------------------+
//| 刪除掛單                                                          |
//+------------------------------------------------------------------+
void DeletePendingOrders()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(!IsOrderToProcess(OrderMagicNumber())) continue;
      if(OrderType() > OP_SELL)
        {
         bool result = OrderDelete(OrderTicket());
         if(!result && RM_ShowDebugLogs) Print("[Recovery] 刪除掛單失敗, Ticket=", OrderTicket());
        }
     }
  }

//+------------------------------------------------------------------+
//| 關閉盈利訂單                                                      |
//+------------------------------------------------------------------+
void CloseProfitOrders()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(!IsOrderToProcess(OrderMagicNumber())) continue;
      if(OrderType() > OP_SELL) continue;

      double profit = OrderProfit() + OrderSwap() + OrderCommission();
      if(profit > 0)
        {
         double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
         bool result = OrderClose(OrderTicket(), OrderLots(), closePrice, RM_MaxSlippage, clrYellow);
         if(!result && RM_ShowDebugLogs) Print("[Recovery] 關閉盈利訂單失敗, Ticket=", OrderTicket());
        }
     }
  }

//+------------------------------------------------------------------+
//| 執行鎖倉                                                          |
//+------------------------------------------------------------------+
void ExecuteLocking()
  {
   double buyLots = 0, sellLots = 0;

   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(!IsOrderToProcess(OrderMagicNumber())) continue;
      if(OrderType() == OP_BUY) buyLots += OrderLots();
      else if(OrderType() == OP_SELL) sellLots += OrderLots();
     }

   double lockLots = MathAbs(buyLots - sellLots);
   if(lockLots < MarketInfo(Symbol(), MODE_MINLOT))
     {
      if(RM_ShowDebugLogs == YES) Print("[Recovery] 無需鎖倉，手數已平衡");
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
      Print("[Recovery] 鎖倉失敗: ", GetLastError());
  }

//+------------------------------------------------------------------+
//| 檢查訂單是否需要處理                                              |
//+------------------------------------------------------------------+
bool IsOrderToProcess(int magic)
  {
   if(RM_MagicSelection == MAGIC_ALL) return true;

   if(RM_MagicSelection == MAGIC_MANUAL)
     {
      if(magic == 0) return true;
      if(magic == RM_LockMagic) return true;
      if(IsMagicInList(magic)) return true;
     }

   if(RM_MagicSelection == MAGIC_SELF)
     {
      if(magic == RM_LockMagic) return true;
      if(IsMagicInList(magic)) return true;
     }

   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsMagicInList(int magic)
  {
   string magicList = RM_MagicNumbers;
   string magicStr = IntegerToString(magic);
   if(StringFind(magicList, magicStr) >= 0) return true;
   return false;
  }

//+------------------------------------------------------------------+
//| 掃描虧損倉位                                                      |
//+------------------------------------------------------------------+
void ScanLossPositions()
  {
   // ===== 測試模式 =====
   if(RM_TestMode == YES)
     {
      GetVirtualOrderStats(g_totalLoss, g_totalBuyLots, g_totalSellLots, g_lossOrderCount);
      return;
     }

   // ===== 正常模式 =====
   g_totalLoss = 0;
   g_totalBuyLots = 0;
   g_totalSellLots = 0;
   g_lossOrderCount = 0;

   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(!IsOrderToProcess(OrderMagicNumber())) continue;
      if(OrderType() > OP_SELL) continue;

      double profit = OrderProfit() + OrderSwap() + OrderCommission();
      if(profit < 0)
        {
         g_totalLoss += profit;
         g_lossOrderCount++;
        }

      if(OrderType() == OP_BUY) g_totalBuyLots += OrderLots();
      else if(OrderType() == OP_SELL) g_totalSellLots += OrderLots();
     }
  }

//+------------------------------------------------------------------+
//| 檢查整體籃子止盈                                                  |
//+------------------------------------------------------------------+
bool CheckBasketTakeProfit()
  {
   double totalProfit = 0;

   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(!IsOrderToProcess(OrderMagicNumber())) continue;
      if(OrderType() > OP_SELL) continue;
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
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(!IsOrderToProcess(OrderMagicNumber())) continue;
      if(OrderType() > OP_SELL) continue;

      double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
      bool result = OrderClose(OrderTicket(), OrderLots(), closePrice, RM_MaxSlippage, clrYellow);
      if(!result) Print("[Recovery] 關閉訂單失敗, Ticket=", OrderTicket(), " Error=", GetLastError());
     }

   g_launchProcessed = false;
   ResetToIdle();
   Print("[Recovery] 所有訂單已關閉，恢復完成");
  }

//+------------------------------------------------------------------+
//| UI 面板函數                                                       |
//+------------------------------------------------------------------+
void UpdateChartPanel()
  {
   if(RM_ShowPanel == NO) return;

   string prefix = "Recovery_Panel_";
   int x = RM_PanelX;
   int y = RM_PanelY;
   int lineHeight = 18;

   // 標題
   string title = (RM_TestMode == YES) ? "=== Recovery v" + EA_VERSION + " [測試] ===" : "=== Recovery v" + EA_VERSION + " ===";
   color titleColor = (RM_TestMode == YES) ? clrOrange : COLOR_ACTIVE;
   CreateLabel(prefix + "Title", title, x, y, titleColor);
   y += lineHeight + 5;

   // 測試模式提示
   if(RM_TestMode == YES)
     {
      if(g_testCompleted)
        {
         CreateLabel(prefix + "TestMode", "*** 測試完成! ***", x, y, clrLime);
         y += lineHeight;
         CreateLabel(prefix + "TestRound", "平倉: " + IntegerToString(g_virtualClosedCount) + "/" + IntegerToString(g_virtualOrderCount) + " 輪數: " + IntegerToString(g_testRoundCount), x, y, clrLime);
         y += lineHeight;
        }
      else
        {
         CreateLabel(prefix + "TestMode", "*** 測試模式 ***", x, y, clrOrange);
         y += lineHeight;
         CreateLabel(prefix + "TestRound", "訂單: " + IntegerToString(g_virtualClosedCount) + "/" + IntegerToString(g_virtualOrderCount) + " 輪數: " + IntegerToString(g_testRoundCount), x, y, clrOrange);
         y += lineHeight;
        }
     }

   CreateLabel(prefix + "GroupID", "組別: " + RM_GroupID, x, y, COLOR_NEUTRAL);
   y += lineHeight;

   CreateLabel(prefix + "Symbol", "商品: " + Symbol(), x, y, COLOR_NEUTRAL);
   y += lineHeight;

   string scanMode = RM_DynamicScan ? "動態掃描" : "配對模式";
   CreateLabel(prefix + "ScanMode", "模式: " + scanMode, x, y, COLOR_ACTIVE);
   y += lineHeight;

   color lossColor = (g_lossOrderCount > 0) ? COLOR_LOSS : COLOR_NEUTRAL;
   CreateLabel(prefix + "LossCount", "虧損訂單: " + IntegerToString(g_lossOrderCount), x, y, lossColor);
   y += lineHeight;

   color totalLossColor = (g_totalLoss < 0) ? COLOR_LOSS : COLOR_NEUTRAL;
   CreateLabel(prefix + "TotalLoss", "總虧損: " + DoubleToStr(g_totalLoss, 2), x, y, totalLossColor);
   y += lineHeight;

   double imbalance = g_totalBuyLots - g_totalSellLots;
   color lotsColor = (MathAbs(imbalance) > RM_MaxImbalance) ? COLOR_STAGE1 : COLOR_NEUTRAL;
   CreateLabel(prefix + "Lots", "手數: B=" + DoubleToStr(g_totalBuyLots, 2) + " S=" + DoubleToStr(g_totalSellLots, 2), x, y, lotsColor);
   y += lineHeight;

   string imbalanceStr = (imbalance >= 0 ? "+" : "") + DoubleToStr(imbalance, 2);
   color imbColor = (MathAbs(imbalance) > RM_MaxImbalance) ? COLOR_LOSS : COLOR_NEUTRAL;
   CreateLabel(prefix + "Imbalance", "失衡: " + imbalanceStr, x, y, imbColor);
   y += lineHeight;

   // 當前處理訂單
   string currentOrder = "";
   if(RM_DynamicScan == YES)
     {
      if(g_currentTicket > 0)
         currentOrder = (g_currentOrderType == OP_BUY ? "Buy" : "Sell") + " #" + IntegerToString(g_currentTicket);
      else
         currentOrder = "無";
     }
   else
      currentOrder = "B#" + IntegerToString(g_currentBuyTicket) + " S#" + IntegerToString(g_currentSellTicket);
   CreateLabel(prefix + "CurrentOrder", "處理中: " + currentOrder, x, y, COLOR_NEUTRAL);
   y += lineHeight;

   color partialColor = (g_currentPartialLoss < 0) ? COLOR_LOSS : COLOR_NEUTRAL;
   CreateLabel(prefix + "PartialLoss", "部分虧損: " + DoubleToStr(g_currentPartialLoss, 2), x, y, partialColor);
   y += lineHeight;

   color targetColor = (g_profitTarget > 0) ? COLOR_STAGE1 : COLOR_NEUTRAL;
   CreateLabel(prefix + "Target", "目標獲利: " + DoubleToStr(g_profitTarget, 2), x, y, targetColor);
   y += lineHeight;

   double accProfit = ReadGV("ACCUMULATED_PROFIT", 0);
   color accColor = (accProfit > 0) ? COLOR_PROFIT : (accProfit < 0) ? COLOR_LOSS : COLOR_NEUTRAL;
   CreateLabel(prefix + "AccProfit", "累積獲利: " + DoubleToStr(accProfit, 2), x, y, accColor);
   y += lineHeight;

   double progress = 0;
   if(g_profitTarget > 0) progress = MathMin(100.0, (accProfit / g_profitTarget) * 100.0);
   color progressColor = (progress >= 100) ? COLOR_PROFIT : COLOR_STAGE2;
   CreateLabel(prefix + "Progress", "進度: " + DoubleToStr(progress, 1) + "%", x, y, progressColor);
   y += lineHeight;

   string stateStr = GetStateString(g_recoveryState);
   color stateColor = GetStateColor(g_recoveryState);
   CreateLabel(prefix + "State", "狀態: " + stateStr, x, y, stateColor);
   y += lineHeight;

   int gridsState = (int)ReadGV("GRIDS_STATE", 0);
   string gridsStateStr = GetGridsStateString(gridsState);
   color gridsColor = (gridsState > 0) ? COLOR_ACTIVE : COLOR_INACTIVE;
   CreateLabel(prefix + "GridsState", "Grids: " + gridsStateStr, x, y, gridsColor);
   y += lineHeight;

   // v1.20: 對沖獲利統計
   if(g_hedgeProfitCount > 0)
     {
      CreateLabel(prefix + "HedgeProfit", "對沖獲利: " + IntegerToString(g_hedgeProfitCount) + "次 $" + DoubleToStr(g_hedgeProfitAmount, 2), x, y, clrLime);
      y += lineHeight;
     }

   CreateLabel(prefix + "TxID", "TxID: " + DoubleToStr(g_transactionId, 0), x, y, COLOR_NEUTRAL);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string GetStateString(int state)
  {
   switch(state)
     {
      case STATE_R_IDLE: return "閒置";
      case STATE_R_REQUESTING: return "請求中";
      case STATE_R_WAITING: return "等待中";
      case STATE_R_CONSUMING: return "消費中";
      case STATE_R_CONFIRMING: return "確認中";
      default: return "未知";
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
color GetStateColor(int state)
  {
   switch(state)
     {
      case STATE_R_IDLE: return COLOR_INACTIVE;
      case STATE_R_REQUESTING: return COLOR_STAGE1;
      case STATE_R_WAITING: return COLOR_STAGE2;
      case STATE_R_CONSUMING: return COLOR_STAGE3;
      case STATE_R_CONFIRMING: return COLOR_STAGE4;
      default: return COLOR_NEUTRAL;
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string GetGridsStateString(int state)
  {
   switch(state)
     {
      case STATE_G_IDLE: return "閒置";
      case STATE_G_ACCUMULATING: return "累積中";
      case STATE_G_READY: return "就緒";
      case STATE_G_ACKNOWLEDGED: return "已確認";
      default: return "未知";
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DeleteChartPanel()
  {
   string prefix = "Recovery_Panel_";
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
     }
  }
//+------------------------------------------------------------------+
