//+------------------------------------------------------------------+
//|                                             CPositionManager.mqh |
//|                              持倉管理模組                         |
//+------------------------------------------------------------------+
//| 【模組說明 - 供 Kiro AI 讀取】                                    |
//|                                                                   |
//| 功能：統一管理持倉查詢（訂單計數、手數統計、盈虧計算）             |
//|                                                                   |
//| 主要方法：                                                        |
//|   - CountOrders()       計算訂單數量                              |
//|   - GetTotalLots()      取得總手數                                |
//|   - GetFloatingProfit() 取得浮動盈虧                              |
//|   - GetAveragePrice()   取得平均價格                              |
//|                                                                   |
//| 引用方式：#include "../Libs/TradeCore/CPositionManager_v2.2.mqh"       |
//+------------------------------------------------------------------+

#ifndef CPOSITIONMANAGER_V21_MQH
#define CPOSITIONMANAGER_V21_MQH

//+------------------------------------------------------------------+
//| 持倉管理類別                                                      |
//+------------------------------------------------------------------+
class CPositionManager
{
private:
   int              m_magic;
   string           m_symbol;
   bool             m_initialized;
   bool             m_showDebugLogs;
   
   //--- 緩存
   int              m_cachedOrderCount;
   double           m_cachedBuyLots;
   double           m_cachedSellLots;
   double           m_cachedFloatingProfit;
   datetime         m_lastCacheUpdate;
   
   //--- 內部方法
   void             UpdateCache();
   void             WriteLog(string message);
   void             WriteDebugLog(string message);

public:
   //--- 建構/解構
                    CPositionManager();
                   ~CPositionManager();

   //--- 初始化
   bool             Init(int magic, string symbol = "");
   void             Deinit();

   //--- 持倉查詢
   int              CountOrders(int orderType = -1);
   double           GetTotalLots(int orderType = -1);
   double           GetFloatingProfit();
   double           GetAveragePrice(int orderType);
   int              GetOrderTickets(int &tickets[], int orderType = -1);

   //--- 籃子資訊
   double           GetBuyLots()             { UpdateCache(); return m_cachedBuyLots; }
   double           GetSellLots()            { UpdateCache(); return m_cachedSellLots; }
   int              GetBuyCount();
   int              GetSellCount();

   //--- 設定
   void             SetDebugLogs(bool enable) { m_showDebugLogs = enable; }
   void             ForceUpdateCache()        { m_lastCacheUpdate = 0; UpdateCache(); }
   bool             IsInitialized()           { return m_initialized; }
};

//+------------------------------------------------------------------+
//| 建構函數                                                          |
//+------------------------------------------------------------------+
CPositionManager::CPositionManager()
{
   m_magic = 0;
   m_symbol = "";
   m_initialized = false;
   m_showDebugLogs = false;
   m_cachedOrderCount = 0;
   m_cachedBuyLots = 0.0;
   m_cachedSellLots = 0.0;
   m_cachedFloatingProfit = 0.0;
   m_lastCacheUpdate = 0;
}

//+------------------------------------------------------------------+
//| 解構函數                                                          |
//+------------------------------------------------------------------+
CPositionManager::~CPositionManager()
{
   Deinit();
}

//+------------------------------------------------------------------+
//| 初始化                                                            |
//+------------------------------------------------------------------+
bool CPositionManager::Init(int magic, string symbol = "")
{
   if(m_initialized)
      return true;

   m_magic = magic;
   m_symbol = (symbol == "") ? Symbol() : symbol;
   m_initialized = true;

   UpdateCache();
   WriteDebugLog("持倉管理器初始化完成");

   return true;
}

//+------------------------------------------------------------------+
//| 反初始化                                                          |
//+------------------------------------------------------------------+
void CPositionManager::Deinit()
{
   m_initialized = false;
}

//+------------------------------------------------------------------+
//| 更新緩存                                                          |
//+------------------------------------------------------------------+
void CPositionManager::UpdateCache()
{
   datetime currentTime = TimeCurrent();

   // 每秒更新一次
   if(currentTime - m_lastCacheUpdate < 1)
      return;

   m_cachedOrderCount = 0;
   m_cachedBuyLots = 0.0;
   m_cachedSellLots = 0.0;
   m_cachedFloatingProfit = 0.0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderMagicNumber() == m_magic && OrderSymbol() == m_symbol)
         {
            m_cachedOrderCount++;
            m_cachedFloatingProfit += OrderProfit() + OrderSwap() + OrderCommission();

            if(OrderType() == OP_BUY)
               m_cachedBuyLots += OrderLots();
            else if(OrderType() == OP_SELL)
               m_cachedSellLots += OrderLots();
         }
      }
   }

   m_lastCacheUpdate = currentTime;
}

//+------------------------------------------------------------------+
//| 計算訂單數量                                                      |
//+------------------------------------------------------------------+
int CPositionManager::CountOrders(int orderType = -1)
{
   if(!m_initialized)
      return 0;

   // 如果查詢所有訂單，使用緩存
   if(orderType < 0)
   {
      UpdateCache();
      return m_cachedOrderCount;
   }

   // 查詢特定類型
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderMagicNumber() == m_magic && OrderSymbol() == m_symbol)
         {
            if(OrderType() == orderType)
               count++;
         }
      }
   }

   return count;
}

//+------------------------------------------------------------------+
//| 取得總手數                                                        |
//+------------------------------------------------------------------+
double CPositionManager::GetTotalLots(int orderType = -1)
{
   if(!m_initialized)
      return 0.0;

   UpdateCache();

   if(orderType < 0)
      return m_cachedBuyLots + m_cachedSellLots;
   else if(orderType == OP_BUY)
      return m_cachedBuyLots;
   else if(orderType == OP_SELL)
      return m_cachedSellLots;

   return 0.0;
}

//+------------------------------------------------------------------+
//| 取得浮動盈虧                                                      |
//+------------------------------------------------------------------+
double CPositionManager::GetFloatingProfit()
{
   if(!m_initialized)
      return 0.0;

   UpdateCache();
   return m_cachedFloatingProfit;
}

//+------------------------------------------------------------------+
//| 取得平均價格                                                      |
//+------------------------------------------------------------------+
double CPositionManager::GetAveragePrice(int orderType)
{
   if(!m_initialized)
      return 0.0;

   double totalLots = 0.0;
   double totalValue = 0.0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderMagicNumber() == m_magic && OrderSymbol() == m_symbol)
         {
            if(OrderType() == orderType)
            {
               totalLots += OrderLots();
               totalValue += OrderOpenPrice() * OrderLots();
            }
         }
      }
   }

   if(totalLots <= 0)
      return 0.0;

   return totalValue / totalLots;
}

//+------------------------------------------------------------------+
//| 取得訂單票號                                                      |
//+------------------------------------------------------------------+
int CPositionManager::GetOrderTickets(int &tickets[], int orderType = -1)
{
   if(!m_initialized)
      return 0;

   ArrayResize(tickets, 0);
   int count = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderMagicNumber() == m_magic && OrderSymbol() == m_symbol)
         {
            if(orderType < 0 || OrderType() == orderType)
            {
               ArrayResize(tickets, count + 1);
               tickets[count] = OrderTicket();
               count++;
            }
         }
      }
   }

   return count;
}

//+------------------------------------------------------------------+
//| 取得買單數量                                                      |
//+------------------------------------------------------------------+
int CPositionManager::GetBuyCount()
{
   return CountOrders(OP_BUY);
}

//+------------------------------------------------------------------+
//| 取得賣單數量                                                      |
//+------------------------------------------------------------------+
int CPositionManager::GetSellCount()
{
   return CountOrders(OP_SELL);
}

//+------------------------------------------------------------------+
//| 日誌輸出                                                          |
//+------------------------------------------------------------------+
void CPositionManager::WriteLog(string message)
{
   Print("[PositionManager] " + message);
}

//+------------------------------------------------------------------+
//| 除錯日誌輸出                                                      |
//+------------------------------------------------------------------+
void CPositionManager::WriteDebugLog(string message)
{
   if(m_showDebugLogs)
      Print("[PositionManager][DEBUG] " + message);
}

#endif // CPOSITIONMANAGER_V21_MQH
