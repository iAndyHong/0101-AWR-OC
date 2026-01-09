//+------------------------------------------------------------------+
//|                                                     CEACore.mqh |
//+------------------------------------------------------------------+
//| 【模組說明 - 供 Kiro AI 讀取】                                    |
//|                                                                   |
//| 功能：EA 中樞類別，整合所有 Libs 模組，提供統一的 EA 框架         |
//|                                                                   |
//| 使用方式：                                                        |
//|   1. 建立子類繼承 CEACore                                         |
//|   2. 實作抽象方法（GetTradeSignal 等）                            |
//|   3. 在 EA 主檔案中呼叫 OnInitCore/OnTickCore/OnDeinitCore       |
//|                                                                   |
//| 引用方式：#include "../Libs/EACore/CEACore_v2.1.mqh"              |
//+------------------------------------------------------------------+

#ifndef CEACORE_V21_MQH
#define CEACORE_V21_MQH

// 引入子模組
#include "CTimerManager_v2.1.mqh"
#include "Utils_v2.1.mqh"
#include "../TradeCore/CTradeCore_v2.1.mqh"
#include "../TradeCore/CHedgeClose_v2.1.mqh"
#include "../TradeCore/CProfitTrailingStop_v2.1.mqh"
#include "../RecoveryProfit/CRecoveryProfit_v2.1.mqh"
#include "../UI/CChartPanelCanvas_v2.1.mqh"

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

#ifndef SIGNAL_NEUTRAL
#define SIGNAL_NEUTRAL      0    // 中性信號
#endif
#ifndef SIGNAL_BUY
#define SIGNAL_BUY          1    // 買入信號
#endif
#ifndef SIGNAL_SELL
#define SIGNAL_SELL        -1    // 賣出信號
#endif

//+------------------------------------------------------------------+
//| 訂單統計結構                                                     |
//+------------------------------------------------------------------+
struct OrderStats
{
   int      count;            // 總訂單數
   int      buyCount;         // 買入數
   int      sellCount;        // 賣出數
   double   totalLots;        // 總手數
   double   buyLots;          // 買入手數
   double   sellLots;         // 賣出手數
   double   profit;           // 總盈虧
   double   buyProfit;        // 買入盈虧
   double   sellProfit;       // 賣出盈虧
};

//+------------------------------------------------------------------+
//| EA 中樞類別                                                       |
//+------------------------------------------------------------------+
class CEACore
{
protected:
   //=== 整合模組 ===
   CTradeCore             m_tradeCore;
   CHedgeClose            m_hedgeClose;
   CProfitTrailingStop    m_profitTrailing;
   CTradeArrowManager     m_arrowManager;
   CRecoveryProfit        m_recoveryProfit;
   CChartPanelCanvas      m_chartPanel;
   CTimerManager          m_timerManager;

   //=== 基本設定 ===
   int                    m_magic;
   string                 m_symbol;
   string                 m_groupId;
   int                    m_slippage;
   int                    m_status;
   string                 m_eaName;
   string                 m_eaVersion;

   //=== 風控參數 ===
   double                 m_maxDrawdown;
   double                 m_maxLots;
   double                 m_maxSpread;
   int                    m_maxOrders;

   //=== 模組啟用設定 ===
   bool                   m_enableHedgeClose;
   bool                   m_enableProfitTrailing;
   bool                   m_enableArrows;
   bool                   m_enableRecoveryProfit;
   bool                   m_enableChartPanel;
   bool                   m_enableTimer;

   //=== 獲利追蹤參數 ===
   double                 m_profitThreshold;
   double                 m_drawdownPercent;

   //=== 箭頭參數 ===
   int                    m_arrowDays;
   int                    m_arrowInterval;
   color                  m_arrowBuyColor;
   color                  m_arrowSellColor;
   color                  m_arrowHistBuyColor;
   color                  m_arrowHistSellColor;

   //=== UI 參數 ===
   int                    m_panelX;
   int                    m_panelY;
   int                    m_panelUpdateInterval;
   string                 m_panelPrefix;
   string                 m_panelSystemName;
   string                 m_panelSystemSymbol;

   //=== 日誌設定 ===
   bool                   m_showDebugLogs;
   string                 m_baseLogFile;
   string                 m_actualLogFile;

   //=== 市場資訊緩存（效能優化）===
   double                 m_cachedMinLot;
   double                 m_cachedMaxLot;
   double                 m_cachedLotStep;
   double                 m_cachedSpread;
   double                 m_cachedPointValue;
   int                    m_cachedDigits;
   datetime               m_lastSpreadUpdate;
   int                    m_spreadUpdateInterval;

   //=== 訂單統計緩存 (單次掃描優化) ===
   OrderStats             m_stats;
   datetime               m_lastOrderCacheUpdate;

   //=== 效能優化參數（Timer1/Timer2）===
   int                    m_timer1Interval;        // 盈虧掃描間隔（秒）
   int                    m_timer2Interval;        // UI/箭頭更新間隔（秒）
   int                    m_tickCounter;           // Tick 計數器
   int                    m_tickThreshold;         // Tick 閾值（預設 20）
   int                    m_lastHistoryCount;      // 歷史訂單數量記錄
   int                    m_lastOpenCount;         // 持倉訂單數量記錄
   datetime               m_lastOrderScanTime;     // 上次訂單掃描時間
   datetime               m_lastUIPanelUpdate;     // 上次 UI 更新時間
   datetime               m_lastArrowUpdate;       // 上次箭頭更新時間
   datetime               m_lastBarTime;           // 上次 K 線時間（測試模式用）
   int                    m_timer2Counter;         // Timer2 計數器（秒）

   //=== 本地累積獲利（獨立於 RecoveryProfit）===
   double                 m_localAccumulatedProfit;
   double                 m_lastBalance;           // 上次記錄的餘額

   //=== 內部方法 ===
   void                   WriteLog(string message);
   void                   WriteDebugLog(string message);
   void                   WriteError(string function, string message);
   void                   UpdateStatus(int newStatus);
   void                   InitMarketInfoCache();
   void                   UpdateSpreadCache();
   void                   UpdateOrderCache();
   bool                   ShouldUpdateOrderCache();
   bool                   ShouldUpdateUI();
   bool                   ShouldUpdateArrows();
   bool                   HasOrderCountChanged();

public:
   //=== 建構/解構 ===
                          CEACore();
   virtual               ~CEACore();

   //=== 生命週期（EA 主檔案呼叫）===
   virtual int            OnInitCore();
   virtual void           OnTickCore();
   virtual void           OnDeinitCore(int reason);
   virtual void           OnTimerCore();
   virtual void           OnChartEventCore(int id, long lparam, double dparam, string sparam);

   //=== 抽象方法（子類必須實作）===
   virtual int            GetTradeSignal()                      { return SIGNAL_NEUTRAL; }
   virtual bool           ShouldOpenFirst(int direction)        { return true; }
   virtual bool           ShouldAddPosition(int direction)      { return true; }
   virtual double         CalculateLots(int level)              { return 0.01; }
   virtual double         CalculateGridDistance(int level)      { return 500.0; }
   virtual void           OnCustomTimer(int timerId)            { }
   virtual void           OnCustomTick()                        { }
   virtual void           OnRiskTriggered()                     { }

   //=== 訂單管理（委託給 TradeCore）===
   int                    OpenOrder(int orderType, double lots, string comment = "");
   bool                   CloseOrder(int ticket);
   double                 CloseAllOrders();
   double                 HedgeCloseAll();
   int                    CountOrders(int orderType = -1);
   double                 GetTotalLots(int orderType = -1);
   double                 GetFloatingProfit();
   double                 GetAveragePrice(int orderType);
   OrderStats             GetOrderStats()                       { return m_stats; }

   //=== 風險控制 ===
   bool                   CheckRiskControl();
   bool                   CheckDrawdown();
   bool                   CheckMaxLots();
   bool                   CheckSpread();
   bool                   CheckMaxOrders();

   //=== 設定方法 - 基本 ===
   void                   SetMagic(int magic)                   { m_magic = magic; }
   void                   SetSymbol(string symbol)              { m_symbol = symbol; }
   void                   SetGroupId(string groupId)            { m_groupId = groupId; }
   void                   SetSlippage(int slip)                 { m_slippage = slip; }
   void                   SetEAName(string name)                { m_eaName = name; }
   void                   SetEAVersion(string version)          { m_eaVersion = version; }

   //=== 設定方法 - 風控 ===
   void                   SetMaxDrawdown(double dd)             { m_maxDrawdown = dd; }
   void                   SetMaxLots(double lots)               { m_maxLots = lots; }
   void                   SetMaxSpread(double spread)           { m_maxSpread = spread; }
   void                   SetMaxOrders(int orders)              { m_maxOrders = orders; }

   //=== 設定方法 - 模組啟用 ===
   void                   EnableHedgeClose(bool enable)         { m_enableHedgeClose = enable; }
   void                   EnableProfitTrailing(bool enable)     { m_enableProfitTrailing = enable; }
   void                   EnableArrows(bool enable)             { m_enableArrows = enable; }
   void                   EnableRecoveryProfit(bool enable)     { m_enableRecoveryProfit = enable; }
   void                   EnableChartPanel(bool enable)         { m_enableChartPanel = enable; }
   void                   EnableTimer(bool enable)              { m_enableTimer = enable; }

   //=== 設定方法 - 獲利追蹤 ===
   void                   SetProfitThreshold(double threshold)  { m_profitThreshold = threshold; }
   void                   SetDrawdownPercent(double percent)    { m_drawdownPercent = percent; }

   //=== 設定方法 - 箭頭 ===
   void                   SetArrowDays(int days)                { m_arrowDays = days; }
   void                   SetArrowInterval(int interval)        { m_arrowInterval = interval; }
   void                   SetArrowColors(color buy, color sell, color histBuy, color histSell);

   //=== 設定方法 - UI ===
   void                   SetPanelPosition(int x, int y)        { m_panelX = x; m_panelY = y; }
   void                   SetPanelUpdateInterval(int seconds)   { m_panelUpdateInterval = seconds; }
   void                   SetPanelPrefix(string prefix)         { m_panelPrefix = prefix; }
   void                   SetPanelSystemInfo(string name, string symbol);

   //=== 設定方法 - 日誌 ===
   void                   SetDebugLogs(bool enable)             { m_showDebugLogs = enable; }
   void                   SetLogFile(string filename);
   string                 GetActualLogFile()                    { return m_actualLogFile; }
   void                   DumpParameters(string params);
   void                   LogTrade(string action, double lots, double price, string remark = "");

   //=== 設定方法 - 緩存更新間隔 ===
   void                   SetSpreadUpdateInterval(int seconds)  { m_spreadUpdateInterval = seconds; }

   //=== 設定方法 - 效能優化（Timer1/Timer2）===
   void                   SetTimer1Interval(int seconds)        { m_timer1Interval = seconds; }
   void                   SetTimer2Interval(int seconds)        { m_timer2Interval = seconds; }
   void                   SetTickThreshold(int ticks)           { m_tickThreshold = ticks; }

   //=== 狀態查詢 ===
   int                    GetStatus()                           { return m_status; }
   bool                   IsRunning()                           { return m_status == EA_STATUS_RUNNING; }
   bool                   IsPaused()                            { return m_status == EA_STATUS_PAUSED; }
   bool                   IsError()                             { return m_status == EA_STATUS_ERROR; }
   int                    GetMagic()                            { return m_magic; }
   string                 GetSymbol()                           { return m_symbol; }
   string                 GetGroupId()                          { return m_groupId; }

   //=== 市場資訊查詢（使用緩存）===
   double                 GetMinLot()                           { return m_cachedMinLot; }
   double                 GetMaxLot()                           { return m_cachedMaxLot; }
   double                 GetLotStep()                          { return m_cachedLotStep; }
   double                 GetSpread()                           { UpdateSpreadCache(); return m_cachedSpread; }
   double                 GetPointValue()                       { return m_cachedPointValue; }
   int                    GetDigits()                           { return m_cachedDigits; }

   //=== 手數驗證（使用緩存）===
   double                 ValidateLotSize(double lots);

   //=== 模組存取 ===
   CTradeCore*            GetTradeCore()       { return GetPointer(m_tradeCore); }
   CHedgeClose*           GetHedgeClose()      { return GetPointer(m_hedgeClose); }
   CProfitTrailingStop*   GetProfitTrailing()  { return GetPointer(m_profitTrailing); }
   CTradeArrowManager*    GetArrowManager()    { return GetPointer(m_arrowManager); }
   CRecoveryProfit*       GetRecoveryProfit()  { return GetPointer(m_recoveryProfit); }
   CChartPanelCanvas*     GetChartPanel()      { return GetPointer(m_chartPanel); }
   CTimerManager*         GetTimerManager()    { return GetPointer(m_timerManager); }

   //=== 計時器管理 ===
   int                    AddTimer(string name, int intervalSeconds);
   bool                   RemoveTimer(int timerId);
   bool                   IsTimerTriggered(int timerId);

   //=== 獲利累積 ===
   void                   AddProfit(double profit);
   double                 GetAccumulatedProfit();
   void                   ResetProfit();

   //=== UI 面板操作 ===
   void                   UpdatePanel(bool forceUpdate = false);
   void                   CleanupPanel();

   //=== 暫停/恢復 ===
   void                   Pause();
   void                   Resume();
};


//+------------------------------------------------------------------+
//| 建構函數                                                          |
//+------------------------------------------------------------------+
CEACore::CEACore()
{
   m_magic = 0;
   m_symbol = "";
   m_groupId = "A";
   m_slippage = 30;
   m_status = EA_STATUS_INIT;
   m_eaName = "CEACore";
   m_eaVersion = "1.0";

   m_maxDrawdown = 20.0;
   m_maxLots = 10.0;
   m_maxSpread = 100.0;
   m_maxOrders = 100;

   m_enableHedgeClose = true;
   m_enableProfitTrailing = false;
   m_enableArrows = false;
   m_enableRecoveryProfit = false;
   m_enableChartPanel = true;
   m_enableTimer = true;

   m_profitThreshold = 10.0;
   m_drawdownPercent = 75.0;

   m_arrowDays = 5;
   m_arrowInterval = 10;
   m_arrowBuyColor = clrOrangeRed;
   m_arrowSellColor = clrLawnGreen;
   m_arrowHistBuyColor = clrDarkRed;
   m_arrowHistSellColor = clrDarkGreen;

   m_panelX = 72;
   m_panelY = 30;
   m_panelUpdateInterval = 10;
   m_panelPrefix = "";
   m_panelSystemName = "";
   m_panelSystemSymbol = "";

   m_showDebugLogs = false;
   m_baseLogFile = "";
   m_actualLogFile = "";

   m_cachedMinLot = 0.0;
   m_cachedMaxLot = 0.0;
   m_cachedLotStep = 0.0;
   m_cachedSpread = 0.0;
   m_cachedPointValue = 0.0;
   m_cachedDigits = 0;
   m_lastSpreadUpdate = 0;
   m_spreadUpdateInterval = 10;

   // 初始化統計
   m_stats.count = 0;
   m_stats.buyCount = 0;
   m_stats.sellCount = 0;
   m_stats.totalLots = 0.0;
   m_stats.buyLots = 0.0;
   m_stats.sellLots = 0.0;
   m_stats.profit = 0.0;
   m_stats.buyProfit = 0.0;
   m_stats.sellProfit = 0.0;
   m_lastOrderCacheUpdate = 0;

   m_timer1Interval = 3;
   m_timer2Interval = 10;
   m_tickCounter = 0;
   m_tickThreshold = 20;
   m_lastHistoryCount = 0;
   m_lastOpenCount = 0;
   m_lastOrderScanTime = 0;
   m_lastUIPanelUpdate = 0;
   m_lastArrowUpdate = 0;
   m_lastBarTime = 0;
   m_timer2Counter = 0;

   m_localAccumulatedProfit = 0.0;
   m_lastBalance = AccountBalance();
}

//+------------------------------------------------------------------+
//| 解構函數                                                          |
//+------------------------------------------------------------------+
CEACore::~CEACore()
{
}

//+------------------------------------------------------------------+
//| 檢查訂單數量是否變化 (輕量級檢查)                                 |
//+------------------------------------------------------------------+
bool CEACore::HasOrderCountChanged()
{
   int historyTotal = OrdersHistoryTotal();
   int openTotal = OrdersTotal();
   
   if(historyTotal != m_lastHistoryCount || openTotal != m_lastOpenCount)
   {
      m_lastHistoryCount = historyTotal;
      m_lastOpenCount = openTotal;
      return true;
   }
   return false;
}


//+------------------------------------------------------------------+
//| 檢查是否應該更新訂單緩存                                          |
//+------------------------------------------------------------------+
bool CEACore::ShouldUpdateOrderCache()
{
   if(HasOrderCountChanged())
      return true;
   
   datetime currentTime = TimeCurrent();
   if(currentTime - m_lastOrderScanTime >= m_timer1Interval)
      return true;
   
   if(m_tickCounter >= m_tickThreshold)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| 檢查是否應該更新 UI（由 OnTimerCore 呼叫）                        |
//+------------------------------------------------------------------+
bool CEACore::ShouldUpdateUI()
{
   if(IsTesting())
   {
      datetime currentBarTime = iTime(m_symbol, 0, 0);
      if(currentBarTime != m_lastBarTime)
      {
         m_lastBarTime = currentBarTime;
         return true;
      }
      return false;
   }
   return (m_timer2Counter >= m_timer2Interval);
}

//+------------------------------------------------------------------+
//| 檢查是否應該更新箭頭（由 OnTimerCore 呼叫）                       |
//+------------------------------------------------------------------+
bool CEACore::ShouldUpdateArrows()
{
   if(IsTesting())
   {
      datetime currentBarTime = iTime(m_symbol, 0, 0);
      return (currentBarTime != m_lastBarTime);
   }
   int arrowInterval = m_timer2Interval * 10;
   datetime currentTime = TimeCurrent();
   return (currentTime - m_lastArrowUpdate >= arrowInterval);
}

//+------------------------------------------------------------------+
//| 初始化市場資訊緩存                                                |
//+------------------------------------------------------------------+
void CEACore::InitMarketInfoCache()
{
   m_cachedMinLot = MarketInfo(m_symbol, MODE_MINLOT);
   m_cachedMaxLot = MarketInfo(m_symbol, MODE_MAXLOT);
   m_cachedLotStep = MarketInfo(m_symbol, MODE_LOTSTEP);
   m_cachedPointValue = MarketInfo(m_symbol, MODE_POINT);
   m_cachedDigits = (int)MarketInfo(m_symbol, MODE_DIGITS);
   m_cachedSpread = MarketInfo(m_symbol, MODE_SPREAD);
   m_lastSpreadUpdate = TimeCurrent();
}

//+------------------------------------------------------------------+
//| 更新點差緩存                                                      |
//+------------------------------------------------------------------+
void CEACore::UpdateSpreadCache()
{
   datetime currentTime = TimeCurrent();
   if(currentTime - m_lastSpreadUpdate >= m_spreadUpdateInterval)
   {
      m_cachedSpread = MarketInfo(m_symbol, MODE_SPREAD);
      m_lastSpreadUpdate = currentTime;
   }
}

//+------------------------------------------------------------------+
//| 更新訂單統計緩存 (單次掃描優化)                                    |
//+------------------------------------------------------------------+
void CEACore::UpdateOrderCache()
{
   if(!ShouldUpdateOrderCache())
      return;
   
   // 重置統計
   m_stats.count = 0;
   m_stats.buyCount = 0;
   m_stats.sellCount = 0;
   m_stats.totalLots = 0.0;
   m_stats.buyLots = 0.0;
   m_stats.sellLots = 0.0;
   m_stats.profit = 0.0;
   m_stats.buyProfit = 0.0;
   m_stats.sellProfit = 0.0;

   // 單次掃描所有訂單
   int total = OrdersTotal();
   for(int i = 0; i < total; i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderMagicNumber() == m_magic && OrderSymbol() == m_symbol)
         {
            double orderProfit = OrderProfit() + OrderSwap() + OrderCommission();
            double orderLots = OrderLots();
            int type = OrderType();

            m_stats.count++;
            m_stats.totalLots += orderLots;
            m_stats.profit += orderProfit;

            if(type == OP_BUY)
            {
               m_stats.buyCount++;
               m_stats.buyLots += orderLots;
               m_stats.buyProfit += orderProfit;
            }
            else if(type == OP_SELL)
            {
               m_stats.sellCount++;
               m_stats.sellLots += orderLots;
               m_stats.sellProfit += orderProfit;
            }
         }
      }
   }
   
   m_lastOrderScanTime = TimeCurrent();
   m_tickCounter = 0;
}

//+------------------------------------------------------------------+
//| 手數驗證                                                          |
//+------------------------------------------------------------------+
double CEACore::ValidateLotSize(double lots)
{
   lots = MathFloor(lots / m_cachedLotStep) * m_cachedLotStep;
   if(lots < m_cachedMinLot) lots = m_cachedMinLot;
   if(lots > m_cachedMaxLot)
   {
      WriteLog("手數過大，調整為最大值: " + DoubleToString(m_cachedMaxLot, 2));
      lots = m_cachedMaxLot;
   }
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| 設定 UI 面板系統資訊                                              |
//+------------------------------------------------------------------+
void CEACore::SetPanelSystemInfo(string name, string symbol)
{
   m_panelSystemName = name;
   m_panelSystemSymbol = symbol;
   if(m_enableChartPanel && m_chartPanel.IsInitialized())
      m_chartPanel.SetSystemInfo(name, symbol);
}


//+------------------------------------------------------------------+
//| 初始化                                                            |
//+------------------------------------------------------------------+
int CEACore::OnInitCore()
{
   WriteLog("=== " + m_eaName + " v" + m_eaVersion + " 初始化開始 ===");

   if(m_symbol == "") m_symbol = Symbol();

   InitMarketInfoCache();

   if(!m_tradeCore.Init(m_magic, m_symbol, m_slippage))
   {
      WriteError("OnInitCore", "交易核心初始化失敗");
      m_status = EA_STATUS_ERROR;
      return INIT_FAILED;
   }

   if(m_enableHedgeClose)
      m_hedgeClose.Init(m_magic, m_slippage, m_symbol);

   if(m_enableProfitTrailing)
      m_profitTrailing.Init(m_profitThreshold, m_drawdownPercent, m_magic, m_symbol);

   int arrowUpdateInterval = m_timer2Interval * 10;
   if(m_enableArrows)
      m_arrowManager.InitFull(m_symbol, m_eaName + "_", true, m_arrowDays, m_magic, arrowUpdateInterval,
                              m_arrowBuyColor, m_arrowSellColor, m_arrowHistBuyColor, m_arrowHistSellColor);

   if(m_enableRecoveryProfit)
   {
      m_recoveryProfit.Init(m_groupId, "REC_", m_symbol);
      m_recoveryProfit.SetDebugLogs(m_showDebugLogs);
   }

   if(m_enableChartPanel)
   {
      string prefix = (m_panelPrefix != "") ? m_panelPrefix : (m_eaName + "_");
      m_chartPanel.Init(prefix, m_panelX, m_panelY, m_timer2Interval);
      
      string sysName = (m_panelSystemName != "") ? m_panelSystemName : m_eaName;
      string sysSymbol = (m_panelSystemSymbol != "") ? m_panelSystemSymbol : m_symbol;
      m_chartPanel.SetSystemInfo(sysName, sysSymbol);
      m_chartPanel.SetEAVersion(m_eaVersion);
   }

   if(m_enableTimer)
      m_timerManager.Init(1);

   m_tickCounter = 0;
   m_timer2Counter = 0;
   m_lastOrderScanTime = TimeCurrent();
   m_lastUIPanelUpdate = TimeCurrent();
   m_lastArrowUpdate = TimeCurrent();
   m_lastBarTime = iTime(m_symbol, 0, 0);
   m_localAccumulatedProfit = 0.0;
   
   m_lastHistoryCount = OrdersHistoryTotal();
   m_lastOpenCount = OrdersTotal();
   m_lastBalance = AccountBalance();
   UpdateOrderCache();

   m_status = EA_STATUS_RUNNING;
   WriteLog("=== " + m_eaName + " 初始化完成 ===");
   WriteLog("Magic: " + IntegerToString(m_magic) + "，商品: " + m_symbol);
   WriteLog("效能設定: Timer1=" + IntegerToString(m_timer1Interval) + "秒, Timer2=" + 
            IntegerToString(m_timer2Interval) + "秒");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| 主循環（精簡版 - UI/箭頭更新移至 OnTimerCore）                    |
//+------------------------------------------------------------------+
void CEACore::OnTickCore()
{
   if(m_status != EA_STATUS_RUNNING)
      return;

   // 每一 tick 監控餘額變化 (自動捕捉手數變動以外的盈虧，如手動平倉)
   double currentBalance = AccountBalance();
   if(currentBalance != m_lastBalance)
   {
      double diff = currentBalance - m_lastBalance;
      // 只有當餘額變動是正向（獲利）或負向（虧損）時才記錄
      // 注意：需排除出入金的情況，通常小額變動可視為交易獲利
      if(MathAbs(diff) < AccountBalance() * 0.5) // 簡單過濾出入金
      {
         // 這裡不再主動呼叫 AddProfit，因為平倉動作後會更新 m_lastBalance
      }
      m_lastBalance = currentBalance;
   }

   m_tickCounter++;
   UpdateSpreadCache();
   UpdateOrderCache();

   if(!CheckRiskControl())
   {
      OnRiskTriggered();
      return;
   }

   // 獲利追蹤停利檢查
   if(m_enableProfitTrailing && m_profitTrailing.ShouldClose())
   {
      WriteLog("獲利追蹤停利觸發");
      double profit = HedgeCloseAll();
      AddProfit(profit);
      m_profitTrailing.Reset();
   }

   OnCustomTick();

   if(m_enableRecoveryProfit)
      m_recoveryProfit.OnTick();

   // 測試模式：UI/箭頭在 OnTick 更新
   if(IsTesting())
   {
      if(m_enableArrows && ShouldUpdateArrows())
      {
         m_arrowManager.ArrowOnTick();
         m_lastArrowUpdate = TimeCurrent();
      }
      if(m_enableChartPanel && ShouldUpdateUI())
      {
         double accProfit = m_enableRecoveryProfit ? m_recoveryProfit.GetAccumulatedProfit() : m_localAccumulatedProfit;
         m_chartPanel.SetAccumulatedProfit(accProfit);
         m_chartPanel.SetTradeInfo(m_magic);
         m_chartPanel.Update(true);
         m_lastUIPanelUpdate = TimeCurrent();
      }
   }

   if(m_enableTimer)
   {
      m_timerManager.CheckTimersOnTick();
      int triggeredIds[];
      int count = m_timerManager.GetTriggeredTimers(triggeredIds);
      for(int i = 0; i < count; i++)
         OnCustomTimer(triggeredIds[i]);
   }
}


//+------------------------------------------------------------------+
//| 反初始化                                                          |
//+------------------------------------------------------------------+
void CEACore::OnDeinitCore(int reason)
{
   WriteLog("=== " + m_eaName + " 停止中 ===");
   m_status = EA_STATUS_CLOSING;

   m_tradeCore.Deinit();
   if(m_enableHedgeClose) m_hedgeClose.Deinit();
   if(m_enableProfitTrailing) m_profitTrailing.Deinit();
   if(m_enableArrows) m_arrowManager.ArrowOnDeinit();
   if(m_enableRecoveryProfit) m_recoveryProfit.Deinit();
   if(m_enableChartPanel) m_chartPanel.Deinit();
   if(m_enableTimer) m_timerManager.Deinit();

   WriteLog("=== " + m_eaName + " 已停止 ===");
}

//+------------------------------------------------------------------+
//| 計時器事件（UI/箭頭更新在此執行）                                 |
//+------------------------------------------------------------------+
void CEACore::OnTimerCore()
{
   if(!m_enableTimer)
      return;

   m_timerManager.CheckTimers();

   int triggeredIds[];
   int count = m_timerManager.GetTriggeredTimers(triggeredIds);
   for(int i = 0; i < count; i++)
      OnCustomTimer(triggeredIds[i]);

   if(m_enableRecoveryProfit)
      m_recoveryProfit.OnTick();

   m_timer2Counter++;

   if(!IsTesting())
   {
      if(m_enableChartPanel && m_timer2Counter >= m_timer2Interval)
      {
         double accProfit = m_enableRecoveryProfit ? m_recoveryProfit.GetAccumulatedProfit() : m_localAccumulatedProfit;
         m_chartPanel.SetAccumulatedProfit(accProfit);
         m_chartPanel.SetTradeInfo(m_magic);
         m_chartPanel.Update(true);
         m_lastUIPanelUpdate = TimeCurrent();
         m_timer2Counter = 0;
      }

      if(m_enableArrows && ShouldUpdateArrows())
      {
         m_arrowManager.ArrowOnTick();
         m_lastArrowUpdate = TimeCurrent();
      }
   }
}

//+------------------------------------------------------------------+
//| 圖表事件                                                          |
//+------------------------------------------------------------------+
void CEACore::OnChartEventCore(int id, long lparam, double dparam, string sparam)
{
   if(id == CHARTEVENT_KEYDOWN && lparam == 46)
   {
      if(m_enableChartPanel)
      {
         m_chartPanel.Cleanup();
         WriteLog("已清理 UI 面板");
      }
   }
}

//+------------------------------------------------------------------+
//| 開單                                                              |
//+------------------------------------------------------------------+
int CEACore::OpenOrder(int orderType, double lots, string comment = "")
{
   return m_tradeCore.OpenOrder(orderType, lots, comment);
}

//+------------------------------------------------------------------+
//| 平倉指定訂單                                                      |
//+------------------------------------------------------------------+
bool CEACore::CloseOrder(int ticket)
{
   return m_tradeCore.CloseOrder(ticket);
}

//+------------------------------------------------------------------+
//| 平倉所有訂單                                                      |
//+------------------------------------------------------------------+
double CEACore::CloseAllOrders()
{
   return m_tradeCore.CloseAllOrders();
}

//+------------------------------------------------------------------+
//| 對沖平倉所有訂單（精準版：透過餘額差值計算獲利）                |
//+------------------------------------------------------------------+
double CEACore::HedgeCloseAll()
{
   double balanceBefore = AccountBalance();
   double profit = 0;
   
   if(m_enableHedgeClose)
      profit = m_hedgeClose.Execute();
   else
      profit = CloseAllOrders();
      
   double balanceAfter = AccountBalance();
   double realProfit = balanceAfter - balanceBefore;
   
   // 更新餘額記錄防止 OnTick 重複偵測
   m_lastBalance = balanceAfter;
   
   // 優先使用實質餘額變化作為獲利數據
   return realProfit;
}

//+------------------------------------------------------------------+
//| 計算訂單數量 (使用緩存優化)                                        |
//+------------------------------------------------------------------+
int CEACore::CountOrders(int orderType = -1)
{
   if(orderType < 0) return m_stats.count;
   if(orderType == OP_BUY) return m_stats.buyCount;
   if(orderType == OP_SELL) return m_stats.sellCount;
   
   return 0;
}

//+------------------------------------------------------------------+
//| 取得總手數 (使用緩存優化)                                          |
//+------------------------------------------------------------------+
double CEACore::GetTotalLots(int orderType = -1)
{
   if(orderType < 0) return m_stats.totalLots;
   if(orderType == OP_BUY) return m_stats.buyLots;
   if(orderType == OP_SELL) return m_stats.sellLots;
   
   return 0.0;
}

//+------------------------------------------------------------------+
//| 取得浮動盈虧（使用緩存）                                          |
//+------------------------------------------------------------------+
double CEACore::GetFloatingProfit()
{
   return m_stats.profit;
}

//+------------------------------------------------------------------+
//| 取得平均價格                                                      |
//+------------------------------------------------------------------+
double CEACore::GetAveragePrice(int orderType)
{
   return m_tradeCore.GetAveragePrice(orderType);
}


//+------------------------------------------------------------------+
//| 風險控制檢查                                                      |
//+------------------------------------------------------------------+
bool CEACore::CheckRiskControl()
{
   if(!CheckDrawdown()) return false;
   if(!CheckMaxLots()) return false;
   return true;
}

//+------------------------------------------------------------------+
//| 檢查回撤                                                          |
//+------------------------------------------------------------------+
bool CEACore::CheckDrawdown()
{
   if(m_maxDrawdown <= 0) return true;
   double profit = GetFloatingProfit();
   double balance = AccountBalance();
   if(balance <= 0) return true;
   double drawdownPercent = (profit / balance) * 100.0;
   return drawdownPercent >= -m_maxDrawdown;
}

//+------------------------------------------------------------------+
//| 檢查最大手數                                                      |
//+------------------------------------------------------------------+
bool CEACore::CheckMaxLots()
{
   if(m_maxLots <= 0) return true;
   return GetTotalLots() <= m_maxLots;
}

//+------------------------------------------------------------------+
//| 檢查點差                                                          |
//+------------------------------------------------------------------+
bool CEACore::CheckSpread()
{
   if(m_maxSpread <= 0) return true;
   return GetSpread() <= m_maxSpread;
}

//+------------------------------------------------------------------+
//| 檢查最大訂單數                                                    |
//+------------------------------------------------------------------+
bool CEACore::CheckMaxOrders()
{
   if(m_maxOrders <= 0) return true;
   return CountOrders() < m_maxOrders;
}

//+------------------------------------------------------------------+
//| 設定箭頭顏色                                                      |
//+------------------------------------------------------------------+
void CEACore::SetArrowColors(color buy, color sell, color histBuy, color histSell)
{
   m_arrowBuyColor = buy;
   m_arrowSellColor = sell;
   m_arrowHistBuyColor = histBuy;
   m_arrowHistSellColor = histSell;
}

//+------------------------------------------------------------------+
//| 新增計時器                                                        |
//+------------------------------------------------------------------+
int CEACore::AddTimer(string name, int intervalSeconds)
{
   if(!m_enableTimer) return -1;
   return m_timerManager.AddTimer(name, intervalSeconds);
}

//+------------------------------------------------------------------+
//| 移除計時器                                                        |
//+------------------------------------------------------------------+
bool CEACore::RemoveTimer(int timerId)
{
   if(!m_enableTimer) return false;
   return m_timerManager.RemoveTimer(timerId);
}

//+------------------------------------------------------------------+
//| 檢查計時器是否觸發                                                |
//+------------------------------------------------------------------+
bool CEACore::IsTimerTriggered(int timerId)
{
   if(!m_enableTimer) return false;
   return m_timerManager.IsTriggered(timerId);
}

//+------------------------------------------------------------------+
//| 新增獲利（同時更新本地累積和 RecoveryProfit）                     |
//+------------------------------------------------------------------+
void CEACore::AddProfit(double profit)
{
   // 如果傳入的 profit 為 0，則嘗試自動補抓餘額差值
   if(profit == 0)
   {
      double currentBalance = AccountBalance();
      profit = currentBalance - m_lastBalance;
      m_lastBalance = currentBalance;
   }
   else
   {
      // 如果有明確傳入 profit，則同步更新 lastBalance 避免 OnTick 誤判
      m_lastBalance = AccountBalance();
   }

   m_localAccumulatedProfit += profit;
   
   if(m_enableRecoveryProfit)
      m_recoveryProfit.AddProfit(profit);
   
   if(m_enableChartPanel)
      m_chartPanel.PrintPL(profit, TimeCurrent(), MarketInfo(m_symbol, MODE_BID));
}

//+------------------------------------------------------------------+
//| 取得累積獲利（優先使用 RecoveryProfit，否則使用本地累積）         |
//+------------------------------------------------------------------+
double CEACore::GetAccumulatedProfit()
{
   if(m_enableRecoveryProfit)
      return m_recoveryProfit.GetAccumulatedProfit();
   return m_localAccumulatedProfit;
}

//+------------------------------------------------------------------+
//| 重置獲利                                                          |
//+------------------------------------------------------------------+
void CEACore::ResetProfit()
{
   m_localAccumulatedProfit = 0.0;
   
   if(m_enableRecoveryProfit)
      m_recoveryProfit.ResetProfit();
   
   if(m_enableChartPanel)
      m_chartPanel.ResetProfitRecord();
}

//+------------------------------------------------------------------+
//| 更新 UI 面板                                                      |
//+------------------------------------------------------------------+
void CEACore::UpdatePanel(bool forceUpdate = false)
{
   if(!m_enableChartPanel) return;
   
   double accProfit = m_enableRecoveryProfit ? m_recoveryProfit.GetAccumulatedProfit() : m_localAccumulatedProfit;
   m_chartPanel.SetAccumulatedProfit(accProfit);
   m_chartPanel.SetTradeInfo(m_magic);
   m_chartPanel.Update(forceUpdate);
}

//+------------------------------------------------------------------+
//| 清理 UI 面板                                                      |
//+------------------------------------------------------------------+
void CEACore::CleanupPanel()
{
   if(!m_enableChartPanel) return;
   m_chartPanel.Cleanup();
   WriteLog("已清理 UI 面板");
}

//+------------------------------------------------------------------+
//| 暫停                                                              |
//+------------------------------------------------------------------+
void CEACore::Pause()
{
   if(m_status == EA_STATUS_RUNNING)
   {
      m_status = EA_STATUS_PAUSED;
      WriteLog("EA 已暫停");
   }
}

//+------------------------------------------------------------------+
//| 恢復                                                              |
//+------------------------------------------------------------------+
void CEACore::Resume()
{
   if(m_status == EA_STATUS_PAUSED)
   {
      m_status = EA_STATUS_RUNNING;
      WriteLog("EA 已恢復運行");
   }
}

//+------------------------------------------------------------------+
//| 設定日誌檔案名稱（實作動態後綴邏輯）                              |
//+------------------------------------------------------------------+
void CEACore::SetLogFile(string filename)
{
   m_baseLogFile = filename;
   if(filename == "") 
   {
      m_actualLogFile = "";
      return;
   }

   string name = filename;
   string ext = ".log";
   int dotPos = StringFind(filename, ".", 0);
   if(dotPos >= 0)
   {
      name = StringSubstr(filename, 0, dotPos);
      ext = StringSubstr(filename, dotPos);
   }

   if(IsTesting())
   {
      m_actualLogFile = name + "_Backtest" + ext;
      // 測試模式：先刪除舊檔案以便重新開始記錄
      if(FileIsExist(m_actualLogFile))
         FileDelete(m_actualLogFile);
   }
   else
   {
      m_actualLogFile = name + "_" + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
      // 取代不合法字元
      StringReplace(m_actualLogFile, ".", "");
      StringReplace(m_actualLogFile, ":", "");
      StringReplace(m_actualLogFile, " ", "-");
      m_actualLogFile = m_actualLogFile + ext;
   }
}

//+------------------------------------------------------------------+
//| Dump 外部參數至日誌                                               |
//+------------------------------------------------------------------+
void CEACore::DumpParameters(string params)
{
   if(m_actualLogFile == "") return;
   
   string header = "================================================\n";
   header += "EA Name: " + m_eaName + " v" + m_eaVersion + "\n";
   header += "Time: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\n";
   header += "--- Input Parameters ---\n";
   
   WriteLog(header + params + "\n================================================");
}

//+------------------------------------------------------------------+
//| 記錄進出場資訊                                                    |
//+------------------------------------------------------------------+
void CEACore::LogTrade(string action, double lots, double price, string remark = "")
{
   string msg = StringFormat("%-10s | Lots: %-6.2f | Price: %-10.5f | %s", 
                             action, lots, price, remark);
   WriteLog(msg);
}

//+------------------------------------------------------------------+
//| 更新狀態                                                          |
//+------------------------------------------------------------------+
void CEACore::UpdateStatus(int newStatus)
{
   if(m_status != newStatus)
   {
      m_status = newStatus;
      string statusText = "";
      switch(newStatus)
      {
         case EA_STATUS_INIT:    statusText = "初始化中"; break;
         case EA_STATUS_RUNNING: statusText = "正常運行"; break;
         case EA_STATUS_PAUSED:  statusText = "暫停交易"; break;
         case EA_STATUS_ERROR:   statusText = "錯誤狀態"; break;
         case EA_STATUS_CLOSING: statusText = "關閉中"; break;
         default:                statusText = "未知狀態"; break;
      }
      WriteLog("EA 狀態變更: " + statusText);
   }
}

//+------------------------------------------------------------------+
//| 日誌輸出                                                          |
//+------------------------------------------------------------------+
void CEACore::WriteLog(string message)
{
   if(m_actualLogFile == "") return;

   string fullMsg = message;
   Print("[" + m_eaName + "] " + fullMsg);

   // 使用 FILE_SHARE_READ | FILE_SHARE_WRITE 確保寫入時不會鎖住檔案，允許外部讀取
   int handle = FileOpen(m_actualLogFile, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(handle != INVALID_HANDLE)
   {
      FileSeek(handle, 0, SEEK_END);
      FileWriteString(handle, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + " | " + fullMsg + "\n");
      FileClose(handle);
   }
}

//+------------------------------------------------------------------+
//| 除錯日誌輸出 (效能優化：先判斷 flag)                             |
//+------------------------------------------------------------------+
void CEACore::WriteDebugLog(string message)
{
   if(m_showDebugLogs)
      WriteLog("[DEBUG] " + message);
}

//+------------------------------------------------------------------+
//| 錯誤日誌輸出                                                      |
//+------------------------------------------------------------------+
void CEACore::WriteError(string function, string message)
{
   WriteLog("[ERROR] " + function + "(): " + message);
}

#endif // CEACORE_V21_MQH
