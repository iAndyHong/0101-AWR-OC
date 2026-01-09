//+------------------------------------------------------------------+
//|                                        CEACore_Performance.mqh |
//|                         EA 核心框架 - 效能優化版本                |
//+------------------------------------------------------------------+
//| 版本：2.1-Performance                                             |
//| 開發者：Kiro-1                                                   |
//| 基於：CEACore.mqh v2.0                                           |
//| 功能：Timer 優化、緩存機制、記憶體管理                            |
//| 狀態：開發中                                                     |
//| 更新日期：2025-01-04                                             |
//+------------------------------------------------------------------+

#ifndef CEACORE_PERFORMANCE_MQH
#define CEACORE_PERFORMANCE_MQH

#property version "2.1-Performance"

// 引入基礎模組（與原版本相同）
#include "CTimerManager.mqh"
#include "Utils.mqh"
#include "../TradeCore/CTradeCore.mqh"
#include "../TradeCore/CHedgeClose.mqh"
#include "../TradeCore/CProfitTrailingStop.mqh"
#include "../RecoveryProfit/CRecoveryProfit.mqh"
#include "../UI/CChartPanelCanvas.mqh"

//+------------------------------------------------------------------+
//| 效能優化版本的常數定義                                            |
//+------------------------------------------------------------------+
#ifndef EA_STATUS_INIT
#define EA_STATUS_INIT      0
#endif
#ifndef EA_STATUS_RUNNING
#define EA_STATUS_RUNNING   1
#endif
#ifndef EA_STATUS_PAUSED
#define EA_STATUS_PAUSED    2
#endif
#ifndef EA_STATUS_ERROR
#define EA_STATUS_ERROR     3
#endif
#ifndef EA_STATUS_CLOSING
#define EA_STATUS_CLOSING   4
#endif

#ifndef SIGNAL_NEUTRAL
#define SIGNAL_NEUTRAL      0
#endif
#ifndef SIGNAL_BUY
#define SIGNAL_BUY          1
#endif
#ifndef SIGNAL_SELL
#define SIGNAL_SELL        -1
#endif

// 效能優化專用常數
#define PERF_CACHE_INTERVAL     5      // 緩存更新間隔（秒）
#define PERF_BATCH_SIZE        50      // 批次處理大小
#define PERF_MEMORY_POOL_SIZE 100      // 記憶體池大小

//+------------------------------------------------------------------+
//| 效能優化版本的 EA 核心類別                                        |
//+------------------------------------------------------------------+
class CEACore_Performance
{
protected:
   //=== 原有模組（保持相容性）===
   CTradeCore             m_tradeCore;
   CHedgeClose            m_hedgeClose;
   CProfitTrailingStop    m_profitTrailing;
   CTradeArrowManager     m_arrowManager;
   CRecoveryProfit        m_recoveryProfit;
   CChartPanelCanvas      m_chartPanel;
   CTimerManager          m_timerManager;

   //=== 基本設定（與原版本相同）===
   int                    m_magic;
   string                 m_symbol;
   string                 m_groupId;
   int                    m_slippage;
   int                    m_status;
   string                 m_eaName;
   string                 m_eaVersion;

   //=== 效能優化新增：進階緩存系統 ===
   struct MarketCache
   {
      double minLot;
      double maxLot;
      double lotStep;
      double spread;
      double pointValue;
      int    digits;
      datetime lastUpdate;
      bool   isValid;
   };
   MarketCache            m_marketCache;
   
   struct OrderCache
   {
      int    count;
      double floatingProfit;
      double totalLots;
      datetime lastUpdate;
      bool   isValid;
   };
   OrderCache             m_orderCache;

   //=== 效能優化新增：批次處理系統 ===
   struct BatchOperation
   {
      int    operationType;  // 0=查詢, 1=更新, 2=計算
      int    priority;       // 優先級 1-10
      datetime scheduleTime; // 排程時間
      bool   completed;
   };
   BatchOperation         m_batchQueue[PERF_BATCH_SIZE];
   int                    m_batchQueueSize;

   //=== 效能優化新增：記憶體池管理 ===
   struct MemoryBlock
   {
      int    size;
      bool   inUse;
      void*  data;
   };
   MemoryBlock            m_memoryPool[PERF_MEMORY_POOL_SIZE];
   int                    m_memoryPoolUsed;

   //=== 效能優化新增：智能 Timer 系統 ===
   int                    m_adaptiveTimer1;     // 自適應 Timer1 間隔
   int                    m_adaptiveTimer2;     // 自適應 Timer2 間隔
   double                 m_systemLoad;         // 系統負載指標
   datetime               m_lastLoadCheck;      // 上次負載檢查時間

   //=== 效能優化方法 ===
   void                   InitPerformanceSystem();
   void                   UpdateMarketCache(bool force = false);
   void                   UpdateOrderCache(bool force = false);
   bool                   IsMarketCacheValid();
   bool                   IsOrderCacheValid();
   void                   ProcessBatchOperations();
   void                   AddBatchOperation(int type, int priority);
   void*                  AllocateMemory(int size);
   void                   FreeMemory(void* ptr);
   void                   UpdateSystemLoad();
   void                   AdaptiveTimerAdjustment();

   //=== 原有方法（保持相容性）===
   void                   WriteLog(string message);
   void                   WriteDebugLog(string message);
   void                   WriteError(string function, string message);
   void                   UpdateStatus(int newStatus);

public:
   //=== 建構/解構 ===
                          CEACore_Performance();
   virtual               ~CEACore_Performance();

   //=== 生命週期（與原版本相容）===
   virtual int            OnInitCore();
   virtual void           OnTickCore();
   virtual void           OnDeinitCore(int reason);
   virtual void           OnTimerCore();
   virtual void           OnChartEventCore(int id, long lparam, double dparam, string sparam);

   //=== 抽象方法（與原版本相同）===
   virtual int            GetTradeSignal()                      { return SIGNAL_NEUTRAL; }
   virtual bool           ShouldOpenFirst(int direction)        { return true; }
   virtual bool           ShouldAddPosition(int direction)      { return true; }
   virtual double         CalculateLots(int level)              { return 0.01; }
   virtual double         CalculateGridDistance(int level)      { return 500.0; }
   virtual void           OnCustomTimer(int timerId)            { }
   virtual void           OnCustomTick()                        { }
   virtual void           OnRiskTriggered()                     { }

   //=== 效能優化版本的新方法 ===
   double                 GetSystemLoad()                       { return m_systemLoad; }
   int                    GetCacheHitRate();
   int                    GetMemoryUsage();
   void                   EnablePerformanceMode(bool enable);
   void                   SetCacheInterval(int seconds);
   void                   OptimizeMemoryUsage();

   //=== 原有介面方法（保持相容性）===
   int                    OpenOrder(int orderType, double lots, string comment = "");
   bool                   CloseOrder(int ticket);
   double                 CloseAllOrders();
   double                 HedgeCloseAll();
   int                    CountOrders(int orderType = -1);
   double                 GetTotalLots(int orderType = -1);
   double                 GetFloatingProfit();
   double                 GetAveragePrice(int orderType);

   //=== 設定方法（與原版本相同）===
   void                   SetMagic(int magic)                   { m_magic = magic; }
   void                   SetSymbol(string symbol)              { m_symbol = symbol; }
   void                   SetGroupId(string groupId)            { m_groupId = groupId; }
   void                   SetEAName(string name)                { m_eaName = name; }
   void                   SetEAVersion(string version)          { m_eaVersion = version; }
   void                   SetDebugLogs(bool enable);
   void                   SetLogFile(string filename);

   //=== 狀態查詢（與原版本相同）===
   int                    GetStatus()                           { return m_status; }
   bool                   IsRunning()                           { return m_status == EA_STATUS_RUNNING; }
   int                    GetMagic()                            { return m_magic; }
   string                 GetSymbol()                           { return m_symbol; }
   string                 GetVersion()                          { return "2.1-Performance"; }
};

//+------------------------------------------------------------------+
//| 建構函數                                                          |
//+------------------------------------------------------------------+
CEACore_Performance::CEACore_Performance()
{
   // 原有初始化
   m_magic = 0;
   m_symbol = "";
   m_groupId = "A";
   m_slippage = 30;
   m_status = EA_STATUS_INIT;
   m_eaName = "CEACore_Performance";
   m_eaVersion = "2.1-Performance";

   // 效能優化初始化
   m_batchQueueSize = 0;
   m_memoryPoolUsed = 0;
   m_adaptiveTimer1 = 3;
   m_adaptiveTimer2 = 10;
   m_systemLoad = 0.0;
   m_lastLoadCheck = 0;

   // 初始化緩存
   m_marketCache.isValid = false;
   m_orderCache.isValid = false;

   WriteLog("CEACore_Performance v2.1 建構完成");
}

//+------------------------------------------------------------------+
//| 解構函數                                                          |
//+------------------------------------------------------------------+
CEACore_Performance::~CEACore_Performance()
{
   // 清理記憶體池
   for(int i = 0; i < PERF_MEMORY_POOL_SIZE; i++)
   {
      if(m_memoryPool[i].inUse && m_memoryPool[i].data != NULL)
      {
         // 清理記憶體（實際實作中需要適當的記憶體管理）
         m_memoryPool[i].inUse = false;
         m_memoryPool[i].data = NULL;
      }
   }
   WriteLog("CEACore_Performance 記憶體清理完成");
}

//+------------------------------------------------------------------+
//| 初始化效能系統                                                    |
//+------------------------------------------------------------------+
void CEACore_Performance::InitPerformanceSystem()
{
   WriteLog("=== 效能優化系統初始化 ===");
   
   // 初始化記憶體池
   for(int i = 0; i < PERF_MEMORY_POOL_SIZE; i++)
   {
      m_memoryPool[i].inUse = false;
      m_memoryPool[i].size = 0;
      m_memoryPool[i].data = NULL;
   }
   
   // 初始化批次佇列
   for(int i = 0; i < PERF_BATCH_SIZE; i++)
   {
      m_batchQueue[i].completed = true;
   }
   
   // 強制更新緩存
   UpdateMarketCache(true);
   UpdateOrderCache(true);
   
   WriteLog("效能優化系統初始化完成");
   WriteLog("記憶體池大小: " + IntegerToString(PERF_MEMORY_POOL_SIZE));
   WriteLog("批次處理大小: " + IntegerToString(PERF_BATCH_SIZE));
   WriteLog("緩存更新間隔: " + IntegerToString(PERF_CACHE_INTERVAL) + " 秒");
}

//+------------------------------------------------------------------+
//| 更新市場資訊緩存                                                  |
//+------------------------------------------------------------------+
void CEACore_Performance::UpdateMarketCache(bool force = false)
{
   datetime currentTime = TimeCurrent();
   
   if(!force && m_marketCache.isValid && 
      (currentTime - m_marketCache.lastUpdate) < PERF_CACHE_INTERVAL)
      return;
   
   m_marketCache.minLot = MarketInfo(m_symbol, MODE_MINLOT);
   m_marketCache.maxLot = MarketInfo(m_symbol, MODE_MAXLOT);
   m_marketCache.lotStep = MarketInfo(m_symbol, MODE_LOTSTEP);
   m_marketCache.spread = MarketInfo(m_symbol, MODE_SPREAD);
   m_marketCache.pointValue = MarketInfo(m_symbol, MODE_POINT);
   m_marketCache.digits = (int)MarketInfo(m_symbol, MODE_DIGITS);
   m_marketCache.lastUpdate = currentTime;
   m_marketCache.isValid = true;
   
   WriteDebugLog("市場資訊緩存已更新");
}

//+------------------------------------------------------------------+
//| 更新訂單統計緩存                                                  |
//+------------------------------------------------------------------+
void CEACore_Performance::UpdateOrderCache(bool force = false)
{
   datetime currentTime = TimeCurrent();
   
   if(!force && m_orderCache.isValid && 
      (currentTime - m_orderCache.lastUpdate) < PERF_CACHE_INTERVAL)
      return;
   
   m_orderCache.count = 0;
   m_orderCache.floatingProfit = 0.0;
   m_orderCache.totalLots = 0.0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderMagicNumber() == m_magic && OrderSymbol() == m_symbol)
         {
            m_orderCache.count++;
            m_orderCache.floatingProfit += OrderProfit() + OrderSwap() + OrderCommission();
            m_orderCache.totalLots += OrderLots();
         }
      }
   }
   
   m_orderCache.lastUpdate = currentTime;
   m_orderCache.isValid = true;
   
   WriteDebugLog("訂單統計緩存已更新: " + IntegerToString(m_orderCache.count) + " 筆訂單");
}

//+------------------------------------------------------------------+
//| 更新系統負載                                                      |
//+------------------------------------------------------------------+
void CEACore_Performance::UpdateSystemLoad()
{
   datetime currentTime = TimeCurrent();
   if(currentTime - m_lastLoadCheck < 10) // 每10秒檢查一次
      return;
   
   // 簡單的負載計算（基於訂單數量和更新頻率）
   double orderLoad = (double)m_orderCache.count / 100.0; // 假設100筆訂單為滿載
   double cacheLoad = m_marketCache.isValid && m_orderCache.isValid ? 0.0 : 0.5;
   
   m_systemLoad = MathMin(1.0, orderLoad + cacheLoad);
   m_lastLoadCheck = currentTime;
   
   WriteDebugLog("系統負載: " + DoubleToString(m_systemLoad * 100, 1) + "%");
}

//+------------------------------------------------------------------+
//| 自適應 Timer 調整                                                 |
//+------------------------------------------------------------------+
void CEACore_Performance::AdaptiveTimerAdjustment()
{
   UpdateSystemLoad();
   
   // 根據系統負載調整 Timer 間隔
   if(m_systemLoad > 0.8) // 高負載
   {
      m_adaptiveTimer1 = 5;  // 降低頻率
      m_adaptiveTimer2 = 15;
   }
   else if(m_systemLoad < 0.3) // 低負載
   {
      m_adaptiveTimer1 = 2;  // 提高頻率
      m_adaptiveTimer2 = 8;
   }
   else // 中等負載
   {
      m_adaptiveTimer1 = 3;  // 預設頻率
      m_adaptiveTimer2 = 10;
   }
   
   WriteDebugLog("自適應 Timer 調整: T1=" + IntegerToString(m_adaptiveTimer1) + 
                "s, T2=" + IntegerToString(m_adaptiveTimer2) + "s");
}

//+------------------------------------------------------------------+
//| 初始化（效能優化版本）                                            |
//+------------------------------------------------------------------+
int CEACore_Performance::OnInitCore()
{
   WriteLog("=== CEACore_Performance v2.1 初始化開始 ===");

   if(m_symbol == "") m_symbol = Symbol();

   // 初始化效能系統
   InitPerformanceSystem();

   // 原有初始化邏輯（簡化版）
   if(!m_tradeCore.Init(m_magic, m_symbol, m_slippage))
   {
      WriteError("OnInitCore", "交易核心初始化失敗");
      m_status = EA_STATUS_ERROR;
      return INIT_FAILED;
   }

   m_status = EA_STATUS_RUNNING;
   WriteLog("=== CEACore_Performance 初始化完成 ===");
   WriteLog("版本: " + m_eaVersion + "，Magic: " + IntegerToString(m_magic));
   WriteLog("效能優化功能已啟用");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| 主循環（效能優化版本）                                            |
//+------------------------------------------------------------------+
void CEACore_Performance::OnTickCore()
{
   if(m_status != EA_STATUS_RUNNING)
      return;

   // 效能優化：使用緩存資料
   UpdateMarketCache();
   UpdateOrderCache();
   
   // 處理批次操作
   ProcessBatchOperations();
   
   // 自適應 Timer 調整
   AdaptiveTimerAdjustment();

   // 原有邏輯
   OnCustomTick();
}

//+------------------------------------------------------------------+
//| 處理批次操作                                                      |
//+------------------------------------------------------------------+
void CEACore_Performance::ProcessBatchOperations()
{
   int processed = 0;
   datetime currentTime = TimeCurrent();
   
   for(int i = 0; i < PERF_BATCH_SIZE && processed < 5; i++) // 每次最多處理5個操作
   {
      if(!m_batchQueue[i].completed && m_batchQueue[i].scheduleTime <= currentTime)
      {
         // 處理批次操作（根據 operationType）
         switch(m_batchQueue[i].operationType)
         {
            case 0: // 查詢操作
               UpdateOrderCache(true);
               break;
            case 1: // 更新操作
               UpdateMarketCache(true);
               break;
            case 2: // 計算操作
               // 執行複雜計算
               break;
         }
         
         m_batchQueue[i].completed = true;
         processed++;
      }
   }
   
   if(processed > 0)
      WriteDebugLog("批次處理完成: " + IntegerToString(processed) + " 個操作");
}

//+------------------------------------------------------------------+
//| 取得緩存命中率                                                    |
//+------------------------------------------------------------------+
int CEACore_Performance::GetCacheHitRate()
{
   // 簡化的緩存命中率計算
   int hitRate = 0;
   if(m_marketCache.isValid) hitRate += 50;
   if(m_orderCache.isValid) hitRate += 50;
   return hitRate;
}

//+------------------------------------------------------------------+
//| 取得記憶體使用量                                                  |
//+------------------------------------------------------------------+
int CEACore_Performance::GetMemoryUsage()
{
   return (m_memoryPoolUsed * 100) / PERF_MEMORY_POOL_SIZE;
}

//+------------------------------------------------------------------+
//| 日誌輸出                                                          |
//+------------------------------------------------------------------+
void CEACore_Performance::WriteLog(string message)
{
   Print("[CEACore_Performance] " + message);
}

void CEACore_Performance::WriteDebugLog(string message)
{
   // 實作除錯日誌邏輯
   Print("[DEBUG-Performance] " + message);
}

//+------------------------------------------------------------------+
//| 其他必要方法的簡化實作                                            |
//+------------------------------------------------------------------+
int CEACore_Performance::OpenOrder(int orderType, double lots, string comment = "")
{
   return m_tradeCore.OpenOrder(orderType, lots, comment);
}

double CEACore_Performance::HedgeCloseAll()
{
   return m_hedgeClose.Execute();
}

int CEACore_Performance::CountOrders(int orderType = -1)
{
   UpdateOrderCache();
   if(orderType < 0)
      return m_orderCache.count;
   
   // 特定類型訂單計算（需要實際掃描）
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderMagicNumber() == m_magic && OrderSymbol() == m_symbol)
            if(OrderType() == orderType) count++;
      }
   }
   return count;
}

double CEACore_Performance::GetFloatingProfit()
{
   UpdateOrderCache();
   return m_orderCache.floatingProfit;
}

void CEACore_Performance::OnDeinitCore(int reason)
{
   WriteLog("=== CEACore_Performance 停止中 ===");
   m_status = EA_STATUS_CLOSING;
   WriteLog("=== CEACore_Performance 已停止 ===");
}

void CEACore_Performance::OnTimerCore()
{
   // 使用自適應 Timer 間隔
   // 實作 Timer 邏輯
}

void CEACore_Performance::OnChartEventCore(int id, long lparam, double dparam, string sparam)
{
   // 實作圖表事件處理
}

#endif // CEACORE_PERFORMANCE_MQH