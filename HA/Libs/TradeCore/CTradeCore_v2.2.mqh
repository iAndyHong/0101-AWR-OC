//+------------------------------------------------------------------+
//|                                                   CTradeCore.mqh |
//|                              交易核心模組                         |
//+------------------------------------------------------------------+
//| 【模組說明 - 供 Kiro AI 讀取】                                    |
//|                                                                   |
//| 功能：整合所有交易相關功能，提供統一的交易介面                     |
//|                                                                   |
//| 整合模組：                                                        |
//|   - COrderManager    (訂單管理)                                   |
//|   - CRiskManager     (風險控制)                                   |
//|   - CPositionManager (持倉管理)                                   |
//|   - CTradeUtils      (交易工具函數)                               |
//|                                                                   |
//| 引用方式：#include "../Libs/TradeCore/CTradeCore_v2.2.mqh"             |
//+------------------------------------------------------------------+

#ifndef CTRADECORE_V21_MQH
#define CTRADECORE_V21_MQH

// 引入子模組
#include "COrderManager_v2.2.mqh"
#include "CRiskManager_v2.2.mqh"
#include "CPositionManager_v2.2.mqh"
#include "CTradeUtils_v2.2.mqh"

//+------------------------------------------------------------------+
//| 交易核心類別 - 整合所有交易功能                                   |
//+------------------------------------------------------------------+
class CTradeCore
{
protected:
   //--- 子模組
   COrderManager          m_orderManager;
   CRiskManager           m_riskManager;
   CPositionManager       m_positionManager;
   
   //--- 基本設定
   int                    m_magic;
   string                 m_symbol;
   int                    m_slippage;
   bool                   m_initialized;
   bool                   m_showDebugLogs;
   
   //--- 市場資訊緩存
   double                 m_pointValue;
   int                    m_digits;

   //--- 日誌
   void                   WriteLog(string message);
   void                   WriteDebugLog(string message);

public:
   //--- 建構/解構
                          CTradeCore();
                         ~CTradeCore();

   //--- 初始化
   bool                   Init(int magic, string symbol = "", int slippage = 30);
   void                   Deinit();

   //--- 訂單操作（委託給 COrderManager）
   int                    OpenOrder(int orderType, double lots, string comment = "");
   bool                   CloseOrder(int ticket);
   double                 CloseAllOrders();
   bool                   ModifyOrder(int ticket, double sl, double tp);

   //--- 持倉查詢（委託給 CPositionManager）
   int                    CountOrders(int orderType = -1);
   double                 GetTotalLots(int orderType = -1);
   double                 GetFloatingProfit();
   double                 GetAveragePrice(int orderType);
   int                    GetOrderTickets(int &tickets[], int orderType = -1);

   //--- 風險控制（委託給 CRiskManager）
   bool                   CheckDrawdown(double maxDrawdownPercent);
   bool                   CheckMaxLots(double maxLots);
   bool                   CheckSpread(double maxSpread);
   bool                   CheckMargin(double lots);

   //--- 工具函數（委託給 CTradeUtils）
   double                 ValidateLotSize(double lots);
   double                 NormalizePrice(double price);
   double                 PointsToPrice(double points);
   double                 PriceToPoints(double priceDiff);

   //--- 子模組存取
   COrderManager*         GetOrderManager()    { return GetPointer(m_orderManager); }
   CRiskManager*          GetRiskManager()     { return GetPointer(m_riskManager); }
   CPositionManager*      GetPositionManager() { return GetPointer(m_positionManager); }

   //--- 設定
   void                   SetDebugLogs(bool enable) { m_showDebugLogs = enable; }
   int                    GetMagic()                { return m_magic; }
   string                 GetSymbol()               { return m_symbol; }
   bool                   IsInitialized()           { return m_initialized; }
};

//+------------------------------------------------------------------+
//| 建構函數                                                          |
//+------------------------------------------------------------------+
CTradeCore::CTradeCore()
{
   m_magic = 0;
   m_symbol = "";
   m_slippage = 30;
   m_initialized = false;
   m_showDebugLogs = false;
   m_pointValue = 0.0;
   m_digits = 0;
}

//+------------------------------------------------------------------+
//| 解構函數                                                          |
//+------------------------------------------------------------------+
CTradeCore::~CTradeCore()
{
   Deinit();
}

//+------------------------------------------------------------------+
//| 初始化                                                            |
//+------------------------------------------------------------------+
bool CTradeCore::Init(int magic, string symbol = "", int slippage = 30)
{
   if(m_initialized)
   {
      WriteDebugLog("交易核心已初始化，跳過");
      return true;
   }

   m_magic = magic;
   m_symbol = (symbol == "") ? Symbol() : symbol;
   m_slippage = slippage;
   m_pointValue = MarketInfo(m_symbol, MODE_POINT);
   m_digits = (int)MarketInfo(m_symbol, MODE_DIGITS);

   // 初始化子模組
   if(!m_orderManager.Init(m_magic, m_symbol, m_slippage))
   {
      WriteLog("訂單管理器初始化失敗");
      return false;
   }

   if(!m_riskManager.Init(m_symbol))
   {
      WriteLog("風險管理器初始化失敗");
      return false;
   }

   if(!m_positionManager.Init(m_magic, m_symbol))
   {
      WriteLog("持倉管理器初始化失敗");
      return false;
   }

   m_initialized = true;
   WriteLog("交易核心初始化完成，Magic=" + IntegerToString(m_magic) + "，商品=" + m_symbol);

   return true;
}

//+------------------------------------------------------------------+
//| 反初始化                                                          |
//+------------------------------------------------------------------+
void CTradeCore::Deinit()
{
   if(!m_initialized)
      return;

   m_orderManager.Deinit();
   m_riskManager.Deinit();
   m_positionManager.Deinit();

   m_initialized = false;
   WriteLog("交易核心已清理");
}

//+------------------------------------------------------------------+
//| 開單                                                              |
//+------------------------------------------------------------------+
int CTradeCore::OpenOrder(int orderType, double lots, string comment = "")
{
   if(!m_initialized)
   {
      WriteLog("交易核心未初始化，無法開單");
      return -1;
   }

   return m_orderManager.OpenOrder(orderType, lots, comment);
}

//+------------------------------------------------------------------+
//| 平單                                                              |
//+------------------------------------------------------------------+
bool CTradeCore::CloseOrder(int ticket)
{
   if(!m_initialized)
      return false;

   return m_orderManager.CloseOrder(ticket);
}

//+------------------------------------------------------------------+
//| 平倉所有訂單                                                      |
//+------------------------------------------------------------------+
double CTradeCore::CloseAllOrders()
{
   if(!m_initialized)
      return 0.0;

   return m_orderManager.CloseAllOrders();
}

//+------------------------------------------------------------------+
//| 修改訂單                                                          |
//+------------------------------------------------------------------+
bool CTradeCore::ModifyOrder(int ticket, double sl, double tp)
{
   if(!m_initialized)
      return false;

   return m_orderManager.ModifyOrder(ticket, sl, tp);
}

//+------------------------------------------------------------------+
//| 計算訂單數量                                                      |
//+------------------------------------------------------------------+
int CTradeCore::CountOrders(int orderType = -1)
{
   if(!m_initialized)
      return 0;

   return m_positionManager.CountOrders(orderType);
}

//+------------------------------------------------------------------+
//| 取得總手數                                                        |
//+------------------------------------------------------------------+
double CTradeCore::GetTotalLots(int orderType = -1)
{
   if(!m_initialized)
      return 0.0;

   return m_positionManager.GetTotalLots(orderType);
}

//+------------------------------------------------------------------+
//| 取得浮動盈虧                                                      |
//+------------------------------------------------------------------+
double CTradeCore::GetFloatingProfit()
{
   if(!m_initialized)
      return 0.0;

   return m_positionManager.GetFloatingProfit();
}

//+------------------------------------------------------------------+
//| 取得平均價格                                                      |
//+------------------------------------------------------------------+
double CTradeCore::GetAveragePrice(int orderType)
{
   if(!m_initialized)
      return 0.0;

   return m_positionManager.GetAveragePrice(orderType);
}

//+------------------------------------------------------------------+
//| 取得訂單票號                                                      |
//+------------------------------------------------------------------+
int CTradeCore::GetOrderTickets(int &tickets[], int orderType = -1)
{
   if(!m_initialized)
      return 0;

   return m_positionManager.GetOrderTickets(tickets, orderType);
}

//+------------------------------------------------------------------+
//| 檢查回撤                                                          |
//+------------------------------------------------------------------+
bool CTradeCore::CheckDrawdown(double maxDrawdownPercent)
{
   if(!m_initialized)
      return true;

   return m_riskManager.CheckDrawdown(maxDrawdownPercent, GetFloatingProfit());
}

//+------------------------------------------------------------------+
//| 檢查最大手數                                                      |
//+------------------------------------------------------------------+
bool CTradeCore::CheckMaxLots(double maxLots)
{
   if(!m_initialized)
      return true;

   return m_riskManager.CheckMaxLots(maxLots, GetTotalLots());
}

//+------------------------------------------------------------------+
//| 檢查點差                                                          |
//+------------------------------------------------------------------+
bool CTradeCore::CheckSpread(double maxSpread)
{
   if(!m_initialized)
      return true;

   return m_riskManager.CheckSpread(maxSpread);
}

//+------------------------------------------------------------------+
//| 檢查保證金                                                        |
//+------------------------------------------------------------------+
bool CTradeCore::CheckMargin(double lots)
{
   if(!m_initialized)
      return false;

   return m_riskManager.CheckMargin(lots);
}

//+------------------------------------------------------------------+
//| 驗證手數                                                          |
//+------------------------------------------------------------------+
double CTradeCore::ValidateLotSize(double lots)
{
   return CTradeUtils::ValidateLotSize(lots, m_symbol);
}

//+------------------------------------------------------------------+
//| 標準化價格                                                        |
//+------------------------------------------------------------------+
double CTradeCore::NormalizePrice(double price)
{
   return CTradeUtils::NormalizePrice(price, m_symbol);
}

//+------------------------------------------------------------------+
//| 點數轉價格                                                        |
//+------------------------------------------------------------------+
double CTradeCore::PointsToPrice(double points)
{
   return CTradeUtils::PointsToPrice(points, m_symbol);
}

//+------------------------------------------------------------------+
//| 價格轉點數                                                        |
//+------------------------------------------------------------------+
double CTradeCore::PriceToPoints(double priceDiff)
{
   return CTradeUtils::PriceToPoints(priceDiff, m_symbol);
}

//+------------------------------------------------------------------+
//| 日誌輸出                                                          |
//+------------------------------------------------------------------+
void CTradeCore::WriteLog(string message)
{
   Print("[TradeCore] " + message);
}

//+------------------------------------------------------------------+
//| 除錯日誌輸出                                                      |
//+------------------------------------------------------------------+
void CTradeCore::WriteDebugLog(string message)
{
   if(m_showDebugLogs)
      Print("[TradeCore][DEBUG] " + message);
}

#endif // CTRADECORE_V21_MQH
