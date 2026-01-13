//+------------------------------------------------------------------+
//|                                        CProfitTrailingStop.mqh   |
//|                        獲利回跌停利模組 (Profit Trailing Stop)   |
//|                        從 Multi-Level_Grid_System v2.3 提取      |
//+------------------------------------------------------------------+
//| 【模組說明 - 供 Kiro AI 讀取】                                    |
//|                                                                   |
//| 功能：當浮動獲利達到閾值後啟動追蹤，獲利回跌到指定百分比時觸發    |
//|       平倉，實現「保護利潤」的目的                                |
//|                                                                   |
//| 定位：這是「平倉條件」，決定「何時平倉」                          |
//|       可搭配 CHedgeClose 作為「平倉方法」                         |
//|                                                                   |
//| 標準用法：                                                        |
//|   CProfitTrailingStop g_profitTrailing;                           |
//|   g_profitTrailing.Init(100.0, 75.0, MagicNumber, Symbol());      |
//|   // 在 OnTick 中                                                 |
//|   if(g_profitTrailing.ShouldClose()) { /* 執行平倉 */ }           |
//|   g_profitTrailing.Deinit();                                      |
//|                                                                   |
//| 參數說明：                                                        |
//|   profitThreshold - 獲利閾值，達到此金額時啟動追蹤                |
//|   drawdownPercent - 保留利潤百分比 (75 = 保留 75%)                |
//|   magicNumber     - 魔術數字                                      |
//|   symbol          - 交易商品 (空字串=當前圖表商品)                |
//|                                                                   |
//| 引用方式：#include "../Libs/ProfitTrailingStop/CProfitTrailingStop_v2.2.mqh"
//+------------------------------------------------------------------+
#property copyright "Forex Algo-Trader, Allan"
#property link      "https://t.me/Forex_Algo_Trader"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| 獲利回跌停利類別
//+------------------------------------------------------------------+
class CProfitTrailingStop
  {
private:
   // 設定參數
   double            m_profitThreshold;       // 獲利閾值（啟動點）
   double            m_drawdownPercent;       // 獲利回跌百分比（保留利潤 %）
   int               m_magicNumber;           // 魔術數字
   string            m_symbol;                // 交易商品
   
   // 狀態變數
   bool              m_isActive;              // 追蹤是否啟動
   double            m_peakProfit;            // 峰值獲利
   bool              m_isInitialized;         // 是否已初始化
   
   // 內部方法
   double            CalculateFloatingProfit();
   void              CloseAllPositions();

public:
                     CProfitTrailingStop();
                    ~CProfitTrailingStop();
   
   // 初始化與清理
   bool              Init(double profitThreshold, 
                          double drawdownPercent, 
                          int magicNumber, 
                          string symbol = "");
   void              Deinit();
   
   // 主要功能
   bool              Check();                    // 檢查並執行停利邏輯
   bool              ShouldClose();              // 只檢查是否應該平倉（不執行）
   void              Reset();                    // 重置狀態
   
   // 狀態查詢
   bool              IsActive()           { return m_isActive; }
   double            GetPeakProfit()      { return m_peakProfit; }
   double            GetThreshold()       { return m_profitThreshold; }
   double            GetDrawdownPercent() { return m_drawdownPercent; }
   double            GetDrawdownLevel();
   
   // 參數設定
   void              SetProfitThreshold(double value)  { m_profitThreshold = value; }
   void              SetDrawdownPercent(double value)  { m_drawdownPercent = value; }
  };

//+------------------------------------------------------------------+
//| 建構函數
//+------------------------------------------------------------------+
CProfitTrailingStop::CProfitTrailingStop()
  {
   m_profitThreshold = 0;
   m_drawdownPercent = 0;
   m_magicNumber     = 0;
   m_symbol          = "";
   m_isActive        = false;
   m_peakProfit      = 0;
   m_isInitialized   = false;
  }

//+------------------------------------------------------------------+
//| 解構函數
//+------------------------------------------------------------------+
CProfitTrailingStop::~CProfitTrailingStop()
  {
   Deinit();
  }

//+------------------------------------------------------------------+
//| 初始化
//+------------------------------------------------------------------+
bool CProfitTrailingStop::Init(double profitThreshold, 
                                double drawdownPercent, 
                                int magicNumber, 
                                string symbol = "")
  {
   if(profitThreshold <= 0)
     {
      Print("[CProfitTrailingStop] 錯誤: profitThreshold 必須大於 0");
      return false;
     }
   
   if(drawdownPercent <= 0 || drawdownPercent > 100)
     {
      Print("[CProfitTrailingStop] 錯誤: drawdownPercent 必須在 0-100 之間");
      return false;
     }
   
   m_profitThreshold = profitThreshold;
   m_drawdownPercent = drawdownPercent;
   m_magicNumber     = magicNumber;
   m_symbol          = (symbol == "") ? Symbol() : symbol;
   
   m_isActive      = false;
   m_peakProfit    = 0;
   m_isInitialized = true;
   
   Print("[CProfitTrailingStop] 初始化完成 - 閾值: ", m_profitThreshold, 
         " / 保留: ", m_drawdownPercent, "% / Magic: ", m_magicNumber);
   
   return true;
  }

//+------------------------------------------------------------------+
//| 清理資源
//+------------------------------------------------------------------+
void CProfitTrailingStop::Deinit()
  {
   if(m_isInitialized)
     {
      Print("[CProfitTrailingStop] 模組已卸載");
      m_isInitialized = false;
     }
  }

//+------------------------------------------------------------------+
//| 檢查並執行停利邏輯
//+------------------------------------------------------------------+
bool CProfitTrailingStop::Check()
  {
   if(!m_isInitialized)
     {
      Print("[CProfitTrailingStop] 警告: 模組尚未初始化");
      return false;
     }
   
   double currentProfit = CalculateFloatingProfit();
   
   if(currentProfit == 0)
     {
      if(m_isActive)
        {
         Print("[CProfitTrailingStop] 無持倉，重置追蹤狀態");
         Reset();
        }
      return false;
     }
   
   if(!m_isActive && currentProfit >= m_profitThreshold)
     {
      m_isActive   = true;
      m_peakProfit = currentProfit;
      Print("[CProfitTrailingStop] 追蹤啟動! 當前獲利: ", currentProfit);
     }
   
   if(m_isActive)
     {
      if(currentProfit > m_peakProfit)
         m_peakProfit = currentProfit;
      
      double drawdownLevel = m_peakProfit * (m_drawdownPercent / 100.0);
      
      if(currentProfit < drawdownLevel)
        {
         Print("[CProfitTrailingStop] 觸發平倉! 峰值: ", m_peakProfit, 
               " / 門檻: ", drawdownLevel, " / 當前: ", currentProfit);
         
         CloseAllPositions();
         Reset();
         return true;
        }
     }
   
   return false;
  }

//+------------------------------------------------------------------+
//| 重置狀態
//+------------------------------------------------------------------+
void CProfitTrailingStop::Reset()
  {
   m_isActive   = false;
   m_peakProfit = 0;
  }

//+------------------------------------------------------------------+
//| 只檢查是否應該平倉（不執行平倉）
//+------------------------------------------------------------------+
bool CProfitTrailingStop::ShouldClose()
  {
   if(!m_isInitialized)
      return false;
   
   double currentProfit = CalculateFloatingProfit();
   
   if(currentProfit == 0)
     {
      if(m_isActive)
         Reset();
      return false;
     }
   
   if(!m_isActive && currentProfit >= m_profitThreshold)
     {
      m_isActive   = true;
      m_peakProfit = currentProfit;
      Print("[CProfitTrailingStop] 追蹤啟動! 當前獲利: ", currentProfit);
     }
   
   if(m_isActive)
     {
      if(currentProfit > m_peakProfit)
         m_peakProfit = currentProfit;
      
      double drawdownLevel = m_peakProfit * (m_drawdownPercent / 100.0);
      
      if(currentProfit < drawdownLevel)
        {
         Print("[CProfitTrailingStop] 應該平倉! 峰值: ", m_peakProfit, 
               " / 門檻: ", drawdownLevel, " / 當前: ", currentProfit);
         return true;
        }
     }
   
   return false;
  }

//+------------------------------------------------------------------+
//| 取得當前平倉觸發價位
//+------------------------------------------------------------------+
double CProfitTrailingStop::GetDrawdownLevel()
  {
   if(!m_isActive)
      return 0;
   
   return m_peakProfit * (m_drawdownPercent / 100.0);
  }

//+------------------------------------------------------------------+
//| 計算當前浮動獲利
//+------------------------------------------------------------------+
double CProfitTrailingStop::CalculateFloatingProfit()
  {
   double totalProfit = 0;
   
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == m_symbol && OrderMagicNumber() == m_magicNumber)
            totalProfit += OrderProfit() + OrderSwap() + OrderCommission();
        }
     }
   
   return totalProfit;
  }

//+------------------------------------------------------------------+
//| 平掉所有部位
//+------------------------------------------------------------------+
void CProfitTrailingStop::CloseAllPositions()
  {
   Print("[CProfitTrailingStop] 開始平倉...");
   
   int closedCount = 0;
   int failedCount = 0;
   
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == m_symbol && OrderMagicNumber() == m_magicNumber)
           {
            double price = (OrderType() == OP_BUY) ? 
                           MarketInfo(m_symbol, MODE_BID) : 
                           MarketInfo(m_symbol, MODE_ASK);
            
            bool result = OrderClose(OrderTicket(), OrderLots(), price, 3, clrNONE);
            
            if(result)
              {
               closedCount++;
               Print("[CProfitTrailingStop] 已平倉 Ticket: ", OrderTicket());
              }
            else
              {
               failedCount++;
               Print("[CProfitTrailingStop] 平倉失敗 Ticket: ", OrderTicket(), 
                     " 錯誤: ", GetLastError());
              }
           }
        }
     }
   
   Print("[CProfitTrailingStop] 平倉完成 - 成功: ", closedCount, " / 失敗: ", failedCount);
  }
//+------------------------------------------------------------------+
