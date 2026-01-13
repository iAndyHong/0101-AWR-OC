//+------------------------------------------------------------------+
//|                                          CTradeArrowManager.mqh  |
//|                        交易箭頭管理模組 (Trade Arrow Manager)    |
//+------------------------------------------------------------------+
//| 【模組說明 - 供 Kiro AI 讀取】                                    |
//|                                                                   |
//| 功能：在圖表上繪製開倉與歷史交易的箭頭標記                        |
//|       將 MT4 原生箭頭替換為代碼 108 的圓圈樣式                    |
//|       支援自訂顏色、回溯天數、更新頻率等設定                      |
//|                                                                   |
//| 標準用法：                                                        |
//|   CTradeArrowManager arrowManager;                                |
//|   arrowManager.InitFull(Symbol(), "MyEA_", true, 5, MagicNumber,  |
//|                         10, clrOrangeRed, clrLawnGreen,           |
//|                         clrDarkRed, clrDarkGreen);                |
//|   // 在 OnTick 中                                                 |
//|   arrowManager.ArrowOnTick();                                     |
//|   // 在 OnDeinit 中                                               |
//|   arrowManager.ArrowOnDeinit();                                   |
//|                                                                   |
//| 參數說明：                                                        |
//|   symbol      - 交易商品                                          |
//|   prefix      - 物件名稱前綴                                      |
//|   enable      - 是否啟用                                          |
//|   days        - 回溯天數                                          |
//|   magic       - 魔術數字 (0=全部)                                 |
//|   interval    - 更新間隔(秒)                                      |
//|   openBuy     - 開倉買單顏色                                      |
//|   openSell    - 開倉賣單顏色                                      |
//|   histBuy     - 歷史買單顏色                                      |
//|   histSell    - 歷史賣單顏色                                      |
//|                                                                   |
//| 引用方式：#include "../Libs/TradeArrowManager/CTradeArrowManager_v2.2.mqh"
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property version   "1.01"
#property strict

//+------------------------------------------------------------------+
//| 預設值常數定義
//+------------------------------------------------------------------+
#define ARROW_DEFAULT_CODE           108              // 預設箭頭代碼
#define ARROW_DEFAULT_INTERVAL       10               // 預設更新間隔(秒)
#define ARROW_DEFAULT_OPEN_BUY       clrOrangeRed     // 預設開倉買單顏色
#define ARROW_DEFAULT_OPEN_SELL      clrLawnGreen     // 預設開倉賣單顏色
#define ARROW_DEFAULT_HIST_BUY       clrDarkRed       // 預設歷史買單顏色
#define ARROW_DEFAULT_HIST_SELL      clrDarkGreen     // 預設歷史賣單顏色

//+------------------------------------------------------------------+
//| 交易箭頭管理類別
//+------------------------------------------------------------------+
class CTradeArrowManager
  {
private:
   string            m_prefix;              // 物件名稱前綴
   int               m_days;                // 回溯天數
   int               m_arrowCode;           // 箭頭代碼
   int               m_magicNumber;         // 魔術數字 (0=全部)
   string            m_symbol;              // 交易商品

   // 顏色設定
   color             m_openBuyColor;        // 開倉買單顏色
   color             m_openSellColor;       // 開倉賣單顏色
   color             m_historyBuyColor;     // 歷史買單顏色
   color             m_historySellColor;    // 歷史賣單顏色

   // 內部狀態
   datetime          m_lastUpdateTime;      // 最後更新時間
   int               m_arrowWidth;          // 箭頭寬度
   bool              m_autoUpdate;          // 自動更新開關
   int               m_updateInterval;      // 更新間隔(秒)
   datetime          m_lastBarTime;         // 最後K棒時間

public:
                     CTradeArrowManager();
                    ~CTradeArrowManager();

   // 初始化設定
   void              Init(string symbol, string prefix);
   void              InitFull(string symbol, string prefix, bool enable,
                              int days, int magic, int interval,
                              color openBuy, color openSell,
                              color histBuy, color histSell);
   void              ArrowOnInit(bool enableArrows);
   void              ArrowOnDeinit();
   void              SetDays(int days)                    { m_days = days; }
   void              SetArrowCode(int code)               { m_arrowCode = code; }
   void              SetMagicNumber(int magic)            { m_magicNumber = magic; }
   void              SetArrowWidth(int width)             { m_arrowWidth = width; }
   void              SetAutoUpdate(bool enable)           { m_autoUpdate = enable; }
   void              SetUpdateInterval(int seconds)       { m_updateInterval = seconds; }

   // 顏色設定
   void              SetOpenBuyColor(color clr)           { m_openBuyColor = clr; }
   void              SetOpenSellColor(color clr)          { m_openSellColor = clr; }
   void              SetHistoryBuyColor(color clr)        { m_historyBuyColor = clr; }
   void              SetHistorySellColor(color clr)       { m_historySellColor = clr; }
   void              SetColors(color openBuy, color openSell, color histBuy, color histSell);

   // 主要功能
   void              ArrowOnTick();
   void              ArrowOnTimer();
   void              Update();
   void              DrawCurrentOrders();
   void              DrawHistoryOrders();
   void              Cleanup();

   // 取得設定值
   int               GetDays()              const { return m_days; }
   int               GetArrowCode()         const { return m_arrowCode; }
   int               GetMagicNumber()       const { return m_magicNumber; }
   string            GetPrefix()            const { return m_prefix; }
   bool              GetAutoUpdate()        const { return m_autoUpdate; }

private:
   void              DrawArrow(string name, datetime time, double price, color clr);
   void              ModifyNativeArrow(int ticket, color clr);
   void              ModifyNativeTrendLine(int ticket, int orderType);
   void              CreateOrderArrow(int ticket, datetime time, double price, int orderType, color clr);
   void              CreateCloseArrow(int ticket, datetime time, double price, int closeType, color clr);
   void              HideNativeArrow(int ticket);
   void              HideAllNativeArrows();
   void              ReplaceNativeArrow(int ticket, color clr);
   bool              IsMagicMatch(int orderMagic);
   datetime          GetCutoffTime();
   bool              ArrowIsNewBar();
   bool              ShouldUpdate();
  };

//+------------------------------------------------------------------+
//| 建構函數
//+------------------------------------------------------------------+
CTradeArrowManager::CTradeArrowManager()
  {
   m_prefix           = "TradeArrow_";
   m_days             = 5;
   m_arrowCode        = ARROW_DEFAULT_CODE;
   m_magicNumber      = 0;
   m_symbol           = "";
   m_arrowWidth       = 1;

   m_openBuyColor     = ARROW_DEFAULT_OPEN_BUY;
   m_openSellColor    = ARROW_DEFAULT_OPEN_SELL;
   m_historyBuyColor  = ARROW_DEFAULT_HIST_BUY;
   m_historySellColor = ARROW_DEFAULT_HIST_SELL;

   m_lastUpdateTime   = 0;
   m_autoUpdate       = true;
   m_updateInterval   = ARROW_DEFAULT_INTERVAL;
   m_lastBarTime      = 0;
  }

//+------------------------------------------------------------------+
//| 解構函數
//+------------------------------------------------------------------+
CTradeArrowManager::~CTradeArrowManager()
  {
   Cleanup();
  }

//+------------------------------------------------------------------+
//| 基本初始化
//+------------------------------------------------------------------+
void CTradeArrowManager::Init(string symbol, string prefix)
  {
   m_symbol = (symbol == "" || symbol == NULL) ? Symbol() : symbol;
   m_prefix = prefix;
   m_lastBarTime = iTime(m_symbol, 0, 0);
  }

//+------------------------------------------------------------------+
//| 完整初始化
//+------------------------------------------------------------------+
void CTradeArrowManager::InitFull(string symbol, string prefix, bool enable,
                                   int days, int magic, int interval,
                                   color openBuy, color openSell,
                                   color histBuy, color histSell)
  {
   m_symbol = (symbol == "" || symbol == NULL) ? Symbol() : symbol;
   m_prefix = prefix;
   m_lastBarTime = iTime(m_symbol, 0, 0);
   
   m_days             = days;
   m_magicNumber      = magic;
   m_updateInterval   = interval;
   m_openBuyColor     = openBuy;
   m_openSellColor    = openSell;
   m_historyBuyColor  = histBuy;
   m_historySellColor = histSell;
   
   ArrowOnInit(enable);
  }

//+------------------------------------------------------------------+
//| EA OnInit() 中呼叫
//+------------------------------------------------------------------+
void CTradeArrowManager::ArrowOnInit(bool enableArrows)
  {
   m_autoUpdate = enableArrows;

   if(enableArrows)
     {
      HideAllNativeArrows();
      Update();
     }
  }

//+------------------------------------------------------------------+
//| EA OnDeinit() 中呼叫
//+------------------------------------------------------------------+
void CTradeArrowManager::ArrowOnDeinit()
  {
   Cleanup();
  }

//+------------------------------------------------------------------+
//| 設定所有顏色
//+------------------------------------------------------------------+
void CTradeArrowManager::SetColors(color openBuy, color openSell, color histBuy, color histSell)
  {
   m_openBuyColor     = openBuy;
   m_openSellColor    = openSell;
   m_historyBuyColor  = histBuy;
   m_historySellColor = histSell;
  }

//+------------------------------------------------------------------+
//| 檢測是否為新 K 棒
//+------------------------------------------------------------------+
bool CTradeArrowManager::ArrowIsNewBar()
  {
   datetime currentBarTime = iTime(m_symbol, 0, 0);
   if(currentBarTime != m_lastBarTime)
     {
      m_lastBarTime = currentBarTime;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| 判斷是否應該更新
//+------------------------------------------------------------------+
bool CTradeArrowManager::ShouldUpdate()
  {
   if(!m_autoUpdate)
      return false;

   if(IsTesting())
      return ArrowIsNewBar();

   if(m_updateInterval == 0)
      return ArrowIsNewBar();

   return (TimeCurrent() - m_lastUpdateTime >= m_updateInterval);
  }

//+------------------------------------------------------------------+
//| OnTick 處理
//+------------------------------------------------------------------+
void CTradeArrowManager::ArrowOnTick()
  {
   if(!m_autoUpdate)
      return;
   
   if(ShouldUpdate())
      Update();
  }

//+------------------------------------------------------------------+
//| OnTimer 處理
//+------------------------------------------------------------------+
void CTradeArrowManager::ArrowOnTimer()
  {
   if(ShouldUpdate())
      Update();
  }

//+------------------------------------------------------------------+
//| 更新箭頭
//+------------------------------------------------------------------+
void CTradeArrowManager::Update()
  {
   DrawCurrentOrders();
   DrawHistoryOrders();
   m_lastUpdateTime = TimeCurrent();
  }

//+------------------------------------------------------------------+
//| 取得截止時間
//+------------------------------------------------------------------+
datetime CTradeArrowManager::GetCutoffTime()
  {
   return TimeCurrent() - (m_days * 86400);
  }

//+------------------------------------------------------------------+
//| 檢查魔術數字是否匹配
//+------------------------------------------------------------------+
bool CTradeArrowManager::IsMagicMatch(int orderMagic)
  {
   return (m_magicNumber <= 0 || m_magicNumber == orderMagic);
  }

//+------------------------------------------------------------------+
//| 修改目前開倉訂單的原生箭頭
//+------------------------------------------------------------------+
void CTradeArrowManager::DrawCurrentOrders()
  {
   datetime cutoffTime = GetCutoffTime();
   int total = OrdersTotal();

   for(int i = 0; i < total; i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderSymbol() != m_symbol)
         continue;

      if(!IsMagicMatch(OrderMagicNumber()))
         continue;

      if(OrderOpenTime() < cutoffTime)
         continue;

      int orderType = OrderType();
      if(orderType > OP_SELL)
         continue;

      color clr = (orderType == OP_BUY) ? m_openBuyColor : m_openSellColor;
      ModifyNativeArrow(OrderTicket(), clr);
     }
  }

//+------------------------------------------------------------------+
//| 修改歷史訂單的原生箭頭和趨勢線
//+------------------------------------------------------------------+
void CTradeArrowManager::DrawHistoryOrders()
  {
   datetime cutoffTime = GetCutoffTime();
   int total = OrdersHistoryTotal();

   for(int i = 0; i < total; i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;

      if(OrderSymbol() != m_symbol)
         continue;

      int orderType = OrderType();
      if(orderType > OP_SELL)
         continue;

      if(!IsMagicMatch(OrderMagicNumber()))
         continue;

      if(OrderOpenTime() < cutoffTime)
         continue;

      int ticket = OrderTicket();
      
      color clr = (orderType == OP_BUY) ? m_historyBuyColor : m_historySellColor;
      ModifyNativeArrow(ticket, clr);
      ModifyNativeTrendLine(ticket, orderType);
     }
  }

//+------------------------------------------------------------------+
//| 修改 MT4 原生箭頭（設為背景物件，不遮擋 UI 面板）                    |
//+------------------------------------------------------------------+
void CTradeArrowManager::ModifyNativeArrow(int ticket, color clr)
  {
   string ticketStr = "#" + IntegerToString(ticket) + " ";
   int total = ObjectsTotal(0, -1);
   
   for(int i = 0; i < total; i++)
     {
      string objName = ObjectName(0, i, -1);
      
      if(StringFind(objName, ticketStr) != 0)
         continue;
      
      int objType = (int)ObjectGetInteger(0, objName, OBJPROP_TYPE);
      if(objType != OBJ_ARROW)
         continue;
      
      color arrowColor = clr;
      
      bool isCloseBy = (StringFind(objName, "close by") >= 0);
      
      bool isBuyOrder = (StringFind(objName, " buy ") >= 0) || 
                        (StringFind(objName, " buy close") >= 0) ||
                        (StringSubstr(objName, StringLen(objName) - 4) == " buy");
      bool isSellOrder = (StringFind(objName, " sell ") >= 0) || 
                         (StringFind(objName, " sell close") >= 0) ||
                         (StringSubstr(objName, StringLen(objName) - 5) == " sell");
      
      if(isCloseBy)
        {
         if(isBuyOrder)
            arrowColor = m_historySellColor;
         else if(isSellOrder)
            arrowColor = m_historyBuyColor;
        }
      else
        {
         arrowColor = clr;
        }
      
      ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, 108);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, arrowColor);
      ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, objName, OBJPROP_BACK, true);  // 設為背景物件
     }
  }

//+------------------------------------------------------------------+
//| 修改 MT4 原生趨勢線顏色（設為背景物件）                              |
//+------------------------------------------------------------------+
void CTradeArrowManager::ModifyNativeTrendLine(int ticket, int orderType)
  {
   string ticketStr = "#" + IntegerToString(ticket) + " ";
   int total = ObjectsTotal(0, -1);
   
   color lineColor = (orderType == OP_BUY) ? m_historyBuyColor : m_historySellColor;
   
   for(int i = 0; i < total; i++)
     {
      string objName = ObjectName(0, i, -1);
      
      if(StringFind(objName, ticketStr) != 0)
         continue;
      
      int objType = (int)ObjectGetInteger(0, objName, OBJPROP_TYPE);
      if(objType != OBJ_TREND)
         continue;
      
      ObjectSetInteger(0, objName, OBJPROP_COLOR, lineColor);
      ObjectSetInteger(0, objName, OBJPROP_BACK, true);  // 設為背景物件
     }
  }

//+------------------------------------------------------------------+
//| 建立開倉箭頭（設為背景物件）                                        |
//+------------------------------------------------------------------+
void CTradeArrowManager::CreateOrderArrow(int ticket, datetime time, double price, int orderType, color clr)
  {
   string name = m_prefix + "Open_" + IntegerToString(ticket);
   
   if(ObjectFind(0, name) >= 0)
      return;
   
   HideNativeArrow(ticket);
   
   if(!ObjectCreate(0, name, OBJ_ARROW, 0, time, price))
      return;
   
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 108);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);       // 設為背景物件
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   
   ENUM_ARROW_ANCHOR anchor = (orderType == OP_BUY) ? ANCHOR_TOP : ANCHOR_BOTTOM;
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
  }

//+------------------------------------------------------------------+
//| 建立平倉箭頭（設為背景物件）                                        |
//+------------------------------------------------------------------+
void CTradeArrowManager::CreateCloseArrow(int ticket, datetime time, double price, int closeType, color clr)
  {
   string name = m_prefix + "Close_" + IntegerToString(ticket);
   
   if(ObjectFind(0, name) >= 0)
      return;
   
   if(!ObjectCreate(0, name, OBJ_ARROW, 0, time, price))
      return;
   
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 108);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);       // 設為背景物件
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   
   ENUM_ARROW_ANCHOR anchor = (closeType == OP_BUY) ? ANCHOR_TOP : ANCHOR_BOTTOM;
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
  }

//+------------------------------------------------------------------+
//| 隱藏指定訂單的 MT4 原生箭頭
//+------------------------------------------------------------------+
void CTradeArrowManager::HideNativeArrow(int ticket)
  {
   string ticketStr = "#" + IntegerToString(ticket) + " ";
   int total = ObjectsTotal(0, -1);
   
   for(int i = total - 1; i >= 0; i--)
     {
      string objName = ObjectName(0, i, -1);
      
      if(StringFind(objName, ticketStr) != 0)
         continue;
      
      ObjectDelete(0, objName);
     }
  }

//+------------------------------------------------------------------+
//| 隱藏所有 MT4 原生箭頭
//+------------------------------------------------------------------+
void CTradeArrowManager::HideAllNativeArrows()
  {
   int total = ObjectsTotal(0, -1);
   
   for(int i = total - 1; i >= 0; i--)
     {
      string objName = ObjectName(0, i, -1);
      
      if(StringGetCharacter(objName, 0) != '#')
         continue;
      
      int objType = (int)ObjectGetInteger(0, objName, OBJPROP_TYPE);
      if(objType != OBJ_ARROW)
         continue;
      
      ObjectDelete(0, objName);
     }
  }

//+------------------------------------------------------------------+
//| 繪製箭頭物件（設為背景物件）                                        |
//+------------------------------------------------------------------+
void CTradeArrowManager::DrawArrow(string name, datetime time, double price, color clr)
  {
   if(ObjectCreate(0, name, OBJ_ARROW, 0, time, price))
     {
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 108);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);    // 設為背景物件
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }
  }

//+------------------------------------------------------------------+
//| 替換 MT4 原生箭頭（保留備用）
//+------------------------------------------------------------------+
void CTradeArrowManager::ReplaceNativeArrow(int ticket, color clr)
  {
  }

//+------------------------------------------------------------------+
//| 清理本 Class 建立的箭頭物件
//+------------------------------------------------------------------+
void CTradeArrowManager::Cleanup()
  {
   int total = ObjectsTotal(0, -1);

   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, -1);
      
      if(StringFind(name, m_prefix) == 0)
        {
         ObjectDelete(0, name);
        }
     }
  }
//+------------------------------------------------------------------+
