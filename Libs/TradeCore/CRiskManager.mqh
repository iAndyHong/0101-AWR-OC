//+------------------------------------------------------------------+
//|                                                 CRiskManager.mqh |
//|                              風險管理模組                         |
//+------------------------------------------------------------------+
//| 【模組說明 - 供 Kiro AI 讀取】                                    |
//|                                                                   |
//| 功能：統一管理風險控制（回撤、手數、點差、保證金）                 |
//|                                                                   |
//| 主要方法：                                                        |
//|   - CheckDrawdown()  檢查回撤是否超限                             |
//|   - CheckMaxLots()   檢查總手數是否超限                           |
//|   - CheckSpread()    檢查點差是否超限                             |
//|   - CheckMargin()    檢查保證金是否足夠                           |
//|                                                                   |
//| 引用方式：#include "../Libs/TradeCore/CRiskManager.mqh"           |
//+------------------------------------------------------------------+

#ifndef CRISKMANAGER_MQH
#define CRISKMANAGER_MQH

//+------------------------------------------------------------------+
//| 風險管理類別                                                      |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
   string           m_symbol;
   bool             m_initialized;
   bool             m_showDebugLogs;
   
   //--- 緩存
   double           m_cachedSpread;
   datetime         m_lastSpreadUpdate;
   
   //--- 內部方法
   void             WriteLog(string message);
   void             WriteDebugLog(string message);

public:
   //--- 建構/解構
                    CRiskManager();
                   ~CRiskManager();

   //--- 初始化
   bool             Init(string symbol = "");
   void             Deinit();

   //--- 風險檢查
   bool             CheckDrawdown(double maxDrawdownPercent, double floatingProfit);
   bool             CheckMaxLots(double maxLots, double currentLots);
   bool             CheckSpread(double maxSpread);
   bool             CheckMargin(double lots);
   bool             CheckMaxOrders(int maxOrders, int currentOrders);

   //--- 風險計算
   double           CalculateDrawdownPercent(double floatingProfit);
   double           CalculateRiskPercent(double lots);
   double           GetCurrentSpread();

   //--- 設定
   void             SetDebugLogs(bool enable) { m_showDebugLogs = enable; }
   bool             IsInitialized()           { return m_initialized; }
};

//+------------------------------------------------------------------+
//| 建構函數                                                          |
//+------------------------------------------------------------------+
CRiskManager::CRiskManager()
{
   m_symbol = "";
   m_initialized = false;
   m_showDebugLogs = false;
   m_cachedSpread = 0.0;
   m_lastSpreadUpdate = 0;
}

//+------------------------------------------------------------------+
//| 解構函數                                                          |
//+------------------------------------------------------------------+
CRiskManager::~CRiskManager()
{
   Deinit();
}

//+------------------------------------------------------------------+
//| 初始化                                                            |
//+------------------------------------------------------------------+
bool CRiskManager::Init(string symbol = "")
{
   if(m_initialized)
      return true;

   m_symbol = (symbol == "") ? Symbol() : symbol;
   m_initialized = true;

   WriteDebugLog("風險管理器初始化完成");
   return true;
}

//+------------------------------------------------------------------+
//| 反初始化                                                          |
//+------------------------------------------------------------------+
void CRiskManager::Deinit()
{
   m_initialized = false;
}

//+------------------------------------------------------------------+
//| 檢查回撤                                                          |
//+------------------------------------------------------------------+
bool CRiskManager::CheckDrawdown(double maxDrawdownPercent, double floatingProfit)
{
   if(!m_initialized || maxDrawdownPercent <= 0)
      return true;

   double balance = AccountBalance();
   if(balance <= 0)
      return true;

   double drawdownPercent = (floatingProfit / balance) * 100.0;

   if(drawdownPercent < -maxDrawdownPercent)
   {
      WriteLog("回撤超限: " + DoubleToString(MathAbs(drawdownPercent), 2) +
               "% > " + DoubleToString(maxDrawdownPercent, 1) + "%");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| 檢查最大手數                                                      |
//+------------------------------------------------------------------+
bool CRiskManager::CheckMaxLots(double maxLots, double currentLots)
{
   if(!m_initialized || maxLots <= 0)
      return true;

   if(currentLots >= maxLots)
   {
      WriteLog("手數超限: " + DoubleToString(currentLots, 2) +
               " >= " + DoubleToString(maxLots, 2));
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| 檢查點差                                                          |
//+------------------------------------------------------------------+
bool CRiskManager::CheckSpread(double maxSpread)
{
   if(!m_initialized || maxSpread <= 0)
      return true;

   double spread = GetCurrentSpread();

   if(spread > maxSpread)
   {
      WriteDebugLog("點差過大: " + DoubleToString(spread, 1) +
                    " > " + DoubleToString(maxSpread, 1));
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| 檢查保證金                                                        |
//+------------------------------------------------------------------+
bool CRiskManager::CheckMargin(double lots)
{
   if(!m_initialized)
      return false;

   double requiredMargin = MarketInfo(m_symbol, MODE_MARGINREQUIRED) * lots;
   double freeMargin = AccountFreeMargin();

   // 保留 20% 緩衝
   if(requiredMargin > freeMargin * 0.8)
   {
      WriteLog("保證金不足: 需要 " + DoubleToString(requiredMargin, 2) +
               "，可用 " + DoubleToString(freeMargin, 2));
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| 檢查最大訂單數                                                    |
//+------------------------------------------------------------------+
bool CRiskManager::CheckMaxOrders(int maxOrders, int currentOrders)
{
   if(!m_initialized || maxOrders <= 0)
      return true;

   if(currentOrders >= maxOrders)
   {
      WriteDebugLog("訂單數超限: " + IntegerToString(currentOrders) +
                    " >= " + IntegerToString(maxOrders));
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| 計算回撤百分比                                                    |
//+------------------------------------------------------------------+
double CRiskManager::CalculateDrawdownPercent(double floatingProfit)
{
   double balance = AccountBalance();
   if(balance <= 0)
      return 0.0;

   return (floatingProfit / balance) * 100.0;
}

//+------------------------------------------------------------------+
//| 計算風險百分比                                                    |
//+------------------------------------------------------------------+
double CRiskManager::CalculateRiskPercent(double lots)
{
   double balance = AccountBalance();
   if(balance <= 0)
      return 0.0;

   double tickValue = MarketInfo(m_symbol, MODE_TICKVALUE);
   double riskPerPip = lots * tickValue;

   // 假設 100 點止損
   double potentialLoss = riskPerPip * 100;
   return (potentialLoss / balance) * 100.0;
}

//+------------------------------------------------------------------+
//| 取得當前點差                                                      |
//+------------------------------------------------------------------+
double CRiskManager::GetCurrentSpread()
{
   datetime currentTime = TimeCurrent();

   // 每秒更新一次
   if(currentTime - m_lastSpreadUpdate >= 1)
   {
      m_cachedSpread = MarketInfo(m_symbol, MODE_SPREAD);
      m_lastSpreadUpdate = currentTime;
   }

   return m_cachedSpread;
}

//+------------------------------------------------------------------+
//| 日誌輸出                                                          |
//+------------------------------------------------------------------+
void CRiskManager::WriteLog(string message)
{
   Print("[RiskManager] " + message);
}

//+------------------------------------------------------------------+
//| 除錯日誌輸出                                                      |
//+------------------------------------------------------------------+
void CRiskManager::WriteDebugLog(string message)
{
   if(m_showDebugLogs)
      Print("[RiskManager][DEBUG] " + message);
}

#endif // CRISKMANAGER_MQH
