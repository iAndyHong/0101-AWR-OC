//+------------------------------------------------------------------+
//|                                                  CHedgeClose.mqh |
//|                        對沖平倉模組 (Hedge Close Module)         |
//|                        從 Multi-Level_Grid_System v2.3 提取      |
//+------------------------------------------------------------------+
//| 【模組說明 - 供 Kiro AI 讀取】                                    |
//|                                                                   |
//| 功能：先下對沖單鎖住持倉，再使用 OrderCloseBy 互相平倉            |
//|       如果 OrderCloseBy 失敗，改用一般平倉作為備用方案            |
//|                                                                   |
//| 定位：這是「平倉方法」，由其他模組決定「何時平倉」                |
//|                                                                   |
//| 優點：                                                            |
//|   - OrderCloseBy 不需再次支付點差，減少成本                       |
//|   - 雙重保險：對沖平倉失敗時自動改用一般平倉                      |
//|   - 適合緊急出場、趨勢反轉、風險控制等情境                        |
//|   - Execute() 返回實際平倉獲利金額                                |
//|                                                                   |
//| 快速用法（一行完成）：                                            |
//|   double profit = CHedgeClose::CloseAll(MagicNumber);             |
//|   double profit = CHedgeClose::CloseAll(MagicNumber, 30, Symbol());|
//|                                                                   |
//| 標準用法（重複使用）：                                            |
//|   CHedgeClose hedge;                                              |
//|   hedge.Init(MagicNumber, 30, Symbol());                          |
//|   double profit = hedge.Execute();  // 返回實際平倉獲利           |
//|   hedge.Deinit();   // 結束時清理                                 |
//|                                                                   |
//| 參數說明：                                                        |
//|   magicNumber - 魔術數字 (0=所有訂單)                             |
//|   slippage    - 滑點容許值 (預設 30)                              |
//|   symbol      - 交易商品 (空字串=當前圖表商品)                    |
//|                                                                   |
//| 引用方式：#include "../Libs/HedgeClose/CHedgeClose.mqh"           |
//+------------------------------------------------------------------+
#property copyright "Forex Algo-Trader, Allan"
#property link      "https://t.me/Forex_Algo_Trader"
#property version   "1.11"
#property strict

//+------------------------------------------------------------------+
//| 對沖平倉類別
//+------------------------------------------------------------------+
class CHedgeClose
  {
private:
   // 設定參數
   int               m_magicNumber;           // 魔術數字
   string            m_symbol;                // 交易商品
   int               m_slippage;              // 滑點容許值
   bool              m_isInitialized;         // 是否已初始化
   double            m_totalProfit;           // 累計平倉獲利
   
   // 內部方法
   bool              MagicNoCheck(int magic, int orderMagic);
   bool              PlaceHedge();
   double            MultCloseBy();
   double            CloseAllOrders();
   int               CountRemainingOrders();
   double            GetOrderProfitByTicket(int ticket);

public:
                     CHedgeClose();
                    ~CHedgeClose();
   
   // 初始化與清理
   bool              Init(int magicNumber, 
                          int slippage = 30,
                          string symbol = "");
   void              Deinit();
   
   // 主要功能 - 返回實際平倉獲利
   double            Execute();
   
   // 快速呼叫（一行完成對沖平倉）- 返回實際平倉獲利
   static double     CloseAll(int magicNumber, int slippage = 30, string symbol = "");
  };

//+------------------------------------------------------------------+
//| 建構函數
//+------------------------------------------------------------------+
CHedgeClose::CHedgeClose()
  {
   m_magicNumber     = 0;
   m_symbol          = "";
   m_slippage        = 30;
   m_isInitialized   = false;
   m_totalProfit     = 0.0;
  }

//+------------------------------------------------------------------+
//| 解構函數
//+------------------------------------------------------------------+
CHedgeClose::~CHedgeClose()
  {
   Deinit();
  }

//+------------------------------------------------------------------+
//| 初始化
//+------------------------------------------------------------------+
bool CHedgeClose::Init(int magicNumber, 
                        int slippage = 30,
                        string symbol = "")
  {
   m_magicNumber   = magicNumber;
   m_slippage      = slippage;
   m_symbol        = (symbol == "") ? Symbol() : symbol;
   m_isInitialized = true;
   m_totalProfit   = 0.0;
   return true;
  }

//+------------------------------------------------------------------+
//| 清理資源
//+------------------------------------------------------------------+
void CHedgeClose::Deinit()
  {
   m_isInitialized = false;
  }

//+------------------------------------------------------------------+
//| 檢查 MagicNumber 是否匹配
//+------------------------------------------------------------------+
bool CHedgeClose::MagicNoCheck(int magic, int orderMagic)
  {
   return (magic <= 0 || magic == orderMagic);
  }

//+------------------------------------------------------------------+
//| 從歷史訂單取得獲利（用於 OrderCloseBy 後查詢）                    |
//+------------------------------------------------------------------+
double CHedgeClose::GetOrderProfitByTicket(int ticket)
  {
   if(OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY))
      return OrderProfit() + OrderSwap() + OrderCommission();
   return 0.0;
  }

//+------------------------------------------------------------------+
//| 下對沖單鎖住持倉
//| 計算多空手數差，下一張對沖單讓多空手數相等
//+------------------------------------------------------------------+
bool CHedgeClose::PlaceHedge()
  {
   double lots = 0;
   
   // 計算多空手數差：Buy 為正，Sell 為負
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         if(OrderType() <= OP_SELL && OrderSymbol() == m_symbol && MagicNoCheck(m_magicNumber, OrderMagicNumber()))
            lots += OrderType() ? -OrderLots() : OrderLots();  // OP_BUY=0 加, OP_SELL=1 減
   
   lots = NormalizeDouble(lots, 2);
   
   // 手數差為 0，已平衡
   if(lots == 0)
      return true;
   
   // 下對沖單
   int ticket = (lots > 0) 
      ? OrderSend(m_symbol, OP_SELL, lots, MarketInfo(m_symbol, MODE_BID), m_slippage, 0, 0, "HEDGE", m_magicNumber, 0, clrNONE)
      : OrderSend(m_symbol, OP_BUY, -lots, MarketInfo(m_symbol, MODE_ASK), m_slippage, 0, 0, "HEDGE", m_magicNumber, 0, clrNONE);
   
   if(ticket > 0)
     {
      Print("[CHedgeClose] 已對沖! ", (lots > 0 ? "SELL " : "BUY "), MathAbs(lots), " 手");
      return true;
     }
   
   Print("[CHedgeClose] 對沖失敗! Error: ", GetLastError());
   return false;
  }

//+------------------------------------------------------------------+
//| 對沖平倉（遞迴）- 返回累計獲利                                   |
//| 使用 OrderCloseBy 將多空單互相平倉                               |
//| 失敗時返回 -999999 表示需要改用備用方案                          |
//+------------------------------------------------------------------+
double CHedgeClose::MultCloseBy()
  {
   double totalProfit = 0.0;
   
   for(int i = OrdersTotal() - 1; i > 0; --i)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) &&
         OrderType() < 2 &&
         OrderSymbol() == m_symbol &&
         MagicNoCheck(m_magicNumber, OrderMagicNumber()))
        {
         int    firstTicket = OrderTicket();
         int    firstType   = OrderType();
         
         // 記錄平倉前的獲利（包含 swap 和 commission）
         double firstProfit = OrderProfit() + OrderSwap() + OrderCommission();
         
         // 尋找反向單
         for(int j = i - 1; j >= 0; --j)
           {
            if(OrderSelect(j, SELECT_BY_POS, MODE_TRADES) &&
               OrderType() < 2 &&
               OrderSymbol() == m_symbol &&
               MagicNoCheck(m_magicNumber, OrderMagicNumber()) &&
               OrderType() != firstType)
              {
               int secondTicket = OrderTicket();
               double secondProfit = OrderProfit() + OrderSwap() + OrderCommission();
               
               // 找到反向單，執行對沖平倉
               if(OrderCloseBy(firstTicket, secondTicket))
                 {
                  // 累計兩張單的獲利
                  totalProfit += firstProfit + secondProfit;
                  Print("[CHedgeClose] 對沖平倉: ", firstTicket, " <-> ", secondTicket, 
                        " 獲利: ", DoubleToString(firstProfit + secondProfit, 2));
                  
                  // 遞迴繼續，累加獲利
                  double recursiveProfit = MultCloseBy();
                  if(recursiveProfit < -999990)  // 遞迴失敗
                     return -999999.0;
                  return totalProfit + recursiveProfit;
                 }
               else
                 {
                  Print("[CHedgeClose] OrderCloseBy 失敗! Error: ", GetLastError());
                  return -999999.0;  // 失敗，改用備用方案
                 }
              }
           }
        }
     }
   return totalProfit;  // 全部完成
  }

//+------------------------------------------------------------------+
//| 一般平倉（備用方案）- 返回總獲利                                 |
//+------------------------------------------------------------------+
double CHedgeClose::CloseAllOrders()
  {
   double totalProfit = 0.0;
   int closedCount = 0;

   Print("[CHedgeClose] 啟用備用平倉...");

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != m_symbol)
         continue;
      if(!MagicNoCheck(m_magicNumber, OrderMagicNumber()))
         continue;
      if(OrderType() > OP_SELL)
         continue;

      double profit = OrderProfit() + OrderSwap() + OrderCommission();
      double price = (OrderType() == OP_BUY) ? MarketInfo(m_symbol, MODE_BID) : MarketInfo(m_symbol, MODE_ASK);

      if(OrderClose(OrderTicket(), OrderLots(), price, m_slippage, clrYellow))
        {
         totalProfit += profit;
         closedCount++;
        }
      else
         Print("[CHedgeClose] 平倉失敗: Ticket=", OrderTicket(), " Error=", GetLastError());
     }

   Print("[CHedgeClose] 備用平倉完成: ", closedCount, " 單, 獲利: ", DoubleToString(totalProfit, 2));
   return totalProfit;
  }

//+------------------------------------------------------------------+
//| 檢查剩餘訂單數量
//+------------------------------------------------------------------+
int CHedgeClose::CountRemainingOrders()
  {
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) &&
         OrderType() <= OP_SELL &&
         OrderSymbol() == m_symbol &&
         MagicNoCheck(m_magicNumber, OrderMagicNumber()))
         count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
//| 執行對沖平倉（主入口）- 返回實際平倉獲利                         |
//| 流程：1. 下對沖單 → 2. OrderCloseBy 遞迴平倉 → 3. 清理剩餘單子   |
//+------------------------------------------------------------------+
double CHedgeClose::Execute()
  {
   if(!m_isInitialized)
     {
      Print("[CHedgeClose] 模組尚未初始化");
      return 0.0;
     }
   
   m_totalProfit = 0.0;
   Print("[CHedgeClose] 開始執行對沖平倉...");
   
   // 步驟 1: 下對沖單讓多空平衡
   if(!PlaceHedge())
     {
      Print("[CHedgeClose] 對沖失敗，改用備用平倉");
      m_totalProfit = CloseAllOrders();
      Print("[CHedgeClose] 總獲利: ", DoubleToString(m_totalProfit, 2));
      return m_totalProfit;
     }
   
   // 步驟 2: 遞迴對沖平倉
   double closeByProfit = MultCloseBy();
   if(closeByProfit < -999990)
     {
      Print("[CHedgeClose] 對沖平倉失敗，改用備用平倉");
      m_totalProfit = CloseAllOrders();
      Print("[CHedgeClose] 總獲利: ", DoubleToString(m_totalProfit, 2));
      return m_totalProfit;
     }
   
   m_totalProfit = closeByProfit;
   
   // 步驟 3: 檢查是否還有剩餘單子（理論上不應該有）
   int remaining = CountRemainingOrders();
   if(remaining > 0)
     {
      Print("[CHedgeClose] 還有 ", remaining, " 張剩餘單子，執行清理...");
      m_totalProfit += CloseAllOrders();
     }
   
   Print("[CHedgeClose] 對沖平倉完成! 總獲利: ", DoubleToString(m_totalProfit, 2));
   return m_totalProfit;
  }

//+------------------------------------------------------------------+
//| 靜態快速呼叫（一行完成對沖平倉）- 返回實際平倉獲利               |
//| 適合其他 EA 直接使用，不需要先建立實例和初始化                   |
//| 用法：double profit = CHedgeClose::CloseAll(MagicNumber);        |
//+------------------------------------------------------------------+
double CHedgeClose::CloseAll(int magicNumber, int slippage = 30, string symbol = "")
  {
   CHedgeClose temp;
   temp.Init(magicNumber, slippage, symbol);
   return temp.Execute();
  }
//+------------------------------------------------------------------+
