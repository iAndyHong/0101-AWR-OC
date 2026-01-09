//+------------------------------------------------------------------+
//|                                                COrderManager.mqh |
//|                              訂單管理模組                         |
//+------------------------------------------------------------------+
//| 【模組說明 - 供 Kiro AI 讀取】                                    |
//|                                                                   |
//| 功能：統一管理訂單操作（開單、平倉、修改）                         |
//|                                                                   |
//| 主要方法：                                                        |
//|   - OpenOrder()      開立新訂單                                   |
//|   - CloseOrder()     平倉指定訂單                                 |
//|   - CloseAllOrders() 平倉所有訂單                                 |
//|   - ModifyOrder()    修改訂單停損停利                             |
//|                                                                   |
//| 引用方式：#include "../Libs/TradeCore/COrderManager_v2.2.mqh"          |
//+------------------------------------------------------------------+

#ifndef CORDERMANAGER_V21_MQH
#define CORDERMANAGER_V21_MQH

//+------------------------------------------------------------------+
//| 訂單管理類別                                                      |
//+------------------------------------------------------------------+
class COrderManager
{
private:
   int              m_magic;
   string           m_symbol;
   int              m_slippage;
   bool             m_initialized;
   bool             m_showDebugLogs;
   
   //--- 市場資訊緩存
   double           m_pointValue;
   int              m_digits;
   double           m_minLot;
   double           m_maxLot;
   double           m_lotStep;
   datetime         m_lastCacheUpdate;
   
   //--- 內部方法
   void             UpdateMarketCache();
   void             WriteLog(string message);
   void             WriteDebugLog(string message);
   string           GetErrorDescription(int errorCode);

public:
   //--- 建構/解構
                    COrderManager();
                   ~COrderManager();

   //--- 初始化
   bool             Init(int magic, string symbol = "", int slippage = 30);
   void             Deinit();

   //--- 訂單操作
   int              OpenOrder(int orderType, double lots, string comment = "");
   int              OpenOrderWithSLTP(int orderType, double lots, double sl, double tp, string comment = "");
   bool             CloseOrder(int ticket);
   double           CloseAllOrders();
   bool             ModifyOrder(int ticket, double sl, double tp);

   //--- 設定
   void             SetDebugLogs(bool enable) { m_showDebugLogs = enable; }
   void             SetSlippage(int slip)     { m_slippage = slip; }
   int              GetMagic()                { return m_magic; }
   string           GetSymbol()               { return m_symbol; }
   bool             IsInitialized()           { return m_initialized; }
};

//+------------------------------------------------------------------+
//| 建構函數                                                          |
//+------------------------------------------------------------------+
COrderManager::COrderManager()
{
   m_magic = 0;
   m_symbol = "";
   m_slippage = 30;
   m_initialized = false;
   m_showDebugLogs = false;
   m_pointValue = 0.0;
   m_digits = 0;
   m_minLot = 0.01;
   m_maxLot = 100.0;
   m_lotStep = 0.01;
   m_lastCacheUpdate = 0;
}

//+------------------------------------------------------------------+
//| 解構函數                                                          |
//+------------------------------------------------------------------+
COrderManager::~COrderManager()
{
   Deinit();
}

//+------------------------------------------------------------------+
//| 初始化                                                            |
//+------------------------------------------------------------------+
bool COrderManager::Init(int magic, string symbol = "", int slippage = 30)
{
   if(m_initialized)
      return true;

   m_magic = magic;
   m_symbol = (symbol == "") ? Symbol() : symbol;
   m_slippage = slippage;

   UpdateMarketCache();

   m_initialized = true;
   WriteDebugLog("訂單管理器初始化完成");

   return true;
}

//+------------------------------------------------------------------+
//| 反初始化                                                          |
//+------------------------------------------------------------------+
void COrderManager::Deinit()
{
   m_initialized = false;
}

//+------------------------------------------------------------------+
//| 更新市場資訊緩存                                                  |
//+------------------------------------------------------------------+
void COrderManager::UpdateMarketCache()
{
   datetime currentTime = TimeCurrent();
   if(currentTime - m_lastCacheUpdate < 10)
      return;

   m_pointValue = MarketInfo(m_symbol, MODE_POINT);
   m_digits = (int)MarketInfo(m_symbol, MODE_DIGITS);
   m_minLot = MarketInfo(m_symbol, MODE_MINLOT);
   m_maxLot = MarketInfo(m_symbol, MODE_MAXLOT);
   m_lotStep = MarketInfo(m_symbol, MODE_LOTSTEP);
   m_lastCacheUpdate = currentTime;
}

//+------------------------------------------------------------------+
//| 開單                                                              |
//+------------------------------------------------------------------+
int COrderManager::OpenOrder(int orderType, double lots, string comment = "")
{
   return OpenOrderWithSLTP(orderType, lots, 0, 0, comment);
}

//+------------------------------------------------------------------+
//| 開單（含停損停利）                                                |
//+------------------------------------------------------------------+
int COrderManager::OpenOrderWithSLTP(int orderType, double lots, double sl, double tp, string comment = "")
{
   if(!m_initialized)
   {
      WriteLog("訂單管理器未初始化");
      return -1;
   }

   UpdateMarketCache();

   // 驗證手數
   lots = MathFloor(lots / m_lotStep) * m_lotStep;
   if(lots < m_minLot) lots = m_minLot;
   if(lots > m_maxLot) lots = m_maxLot;
   lots = NormalizeDouble(lots, 2);

   // 取得價格
   double price = (orderType == OP_BUY) ? MarketInfo(m_symbol, MODE_ASK) : MarketInfo(m_symbol, MODE_BID);
   color arrowColor = (orderType == OP_BUY) ? clrBlue : clrRed;

   WriteDebugLog("準備開單 - 類型: " + (orderType == OP_BUY ? "BUY" : "SELL") +
                 "，手數: " + DoubleToString(lots, 2) +
                 "，價格: " + DoubleToString(price, m_digits));

   int ticket = OrderSend(m_symbol, orderType, lots, price, m_slippage, sl, tp,
                          comment, m_magic, 0, arrowColor);

   if(ticket < 0)
   {
      int error = GetLastError();
      WriteLog("開單失敗: " + GetErrorDescription(error) + " (錯誤碼: " + IntegerToString(error) + ")");
      return -1;
   }

   WriteLog("開單成功 #" + IntegerToString(ticket) + " " +
            (orderType == OP_BUY ? "BUY" : "SELL") + " " +
            DoubleToString(lots, 2) + " @ " + DoubleToString(price, m_digits));

   return ticket;
}

//+------------------------------------------------------------------+
//| 平倉指定訂單                                                      |
//+------------------------------------------------------------------+
bool COrderManager::CloseOrder(int ticket)
{
   if(!m_initialized)
      return false;

   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
   {
      WriteLog("找不到訂單 #" + IntegerToString(ticket));
      return false;
   }

   if(OrderCloseTime() > 0)
   {
      WriteDebugLog("訂單 #" + IntegerToString(ticket) + " 已平倉");
      return true;
   }

   double price = (OrderType() == OP_BUY) ? MarketInfo(m_symbol, MODE_BID) : MarketInfo(m_symbol, MODE_ASK);
   color arrowColor = (OrderType() == OP_BUY) ? clrRed : clrBlue;

   bool result = OrderClose(ticket, OrderLots(), price, m_slippage, arrowColor);

   if(!result)
   {
      int error = GetLastError();
      WriteLog("平倉失敗 #" + IntegerToString(ticket) + ": " + GetErrorDescription(error));
      return false;
   }

   WriteLog("平倉成功 #" + IntegerToString(ticket));
   return true;
}

//+------------------------------------------------------------------+
//| 平倉所有訂單                                                      |
//+------------------------------------------------------------------+
double COrderManager::CloseAllOrders()
{
   if(!m_initialized)
      return 0.0;

   double totalProfit = 0.0;
   int closedCount = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderMagicNumber() == m_magic && OrderSymbol() == m_symbol)
         {
            double profit = OrderProfit() + OrderSwap() + OrderCommission();
            if(CloseOrder(OrderTicket()))
            {
               totalProfit += profit;
               closedCount++;
            }
         }
      }
   }

   WriteLog("平倉完成，共 " + IntegerToString(closedCount) + " 單，獲利: " + DoubleToString(totalProfit, 2));
   return totalProfit;
}

//+------------------------------------------------------------------+
//| 修改訂單                                                          |
//+------------------------------------------------------------------+
bool COrderManager::ModifyOrder(int ticket, double sl, double tp)
{
   if(!m_initialized)
      return false;

   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
   {
      WriteLog("找不到訂單 #" + IntegerToString(ticket));
      return false;
   }

   sl = NormalizeDouble(sl, m_digits);
   tp = NormalizeDouble(tp, m_digits);

   bool result = OrderModify(ticket, OrderOpenPrice(), sl, tp, 0, clrYellow);

   if(!result)
   {
      int error = GetLastError();
      WriteLog("修改訂單失敗 #" + IntegerToString(ticket) + ": " + GetErrorDescription(error));
      return false;
   }

   WriteDebugLog("修改訂單成功 #" + IntegerToString(ticket) +
                 " SL=" + DoubleToString(sl, m_digits) +
                 " TP=" + DoubleToString(tp, m_digits));
   return true;
}

//+------------------------------------------------------------------+
//| 取得錯誤描述                                                      |
//+------------------------------------------------------------------+
string COrderManager::GetErrorDescription(int errorCode)
{
   switch(errorCode)
   {
      case 0:   return "無錯誤";
      case 134: return "資金不足";
      case 135: return "價格已改變";
      case 136: return "無報價";
      case 138: return "重新報價";
      case 146: return "交易上下文忙碌";
      case 148: return "訂單數量過多";
      default:  return "錯誤 " + IntegerToString(errorCode);
   }
}

//+------------------------------------------------------------------+
//| 日誌輸出                                                          |
//+------------------------------------------------------------------+
void COrderManager::WriteLog(string message)
{
   Print("[OrderManager] " + message);
}

//+------------------------------------------------------------------+
//| 除錯日誌輸出                                                      |
//+------------------------------------------------------------------+
void COrderManager::WriteDebugLog(string message)
{
   if(m_showDebugLogs)
      Print("[OrderManager][DEBUG] " + message);
}

#endif // CORDERMANAGER_V21_MQH
