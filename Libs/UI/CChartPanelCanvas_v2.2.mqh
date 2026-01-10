//+------------------------------------------------------------------+
//|                                             CChartPanelCanvas.mqh |
//|                        圖表面板管理模組 - CCanvas 版本             |
//|                        測試結束時用 OBJ_LABEL 保留完整 UI          |
//+------------------------------------------------------------------+
#property copyright "Andy's Trading Libs"
#property version   "1.18"
#property strict

#include <Canvas/Canvas.mqh>
#include "CTradeArrowManager_v2.2.mqh"

struct TradeStatsCanvas
  {
   double            lots;
   double            avgPrice;
   double            profit;
   int               count;
  };

class CChartPanelCanvas
  {
private:
   // Canvas 物件
   CCanvas           m_canvas;
   string            m_prefix;
   string            m_canvasName;
   bool              m_initialized;

   // 面板位置與尺寸
   int               m_baseX;
   int               m_baseY;
   int               m_width;
   int               m_height;
   int               m_margin;
   int               m_lineHeight;
   long              m_zOrder;
   long              m_PLzOrder;

   // 字型設定
   string            m_fontName;
   int               m_titleFontSize;
   int               m_fontSize;
   int               m_PLfontSize;

   // UI 顏色
   color             m_clrProfit;
   color             m_clrLoss;
   color             m_clrNeutral;
   color             m_clrTitle;
   color             m_clrSection;
   color             m_clrText;
   color             m_clrBorder;
   color             m_clrActive;
   color             m_clrDanger;
   color             m_clrChartPL;


   // 背景設定
   color             m_bgColor;
   int               m_bgAlpha;

   // 更新控制
   int               m_updateInterval;
   datetime          m_lastUpdate;

   // 交易資訊
   double            m_maxProfit;
   double            m_maxLoss;
   double            m_lowestMarginPct;
   double            m_currentProfit;
   double            m_accumulatedProfit;
   string            m_tradeMode;
   string            m_tradeSymbol;
   string            m_eaVersion;
   int               m_magicNumber;

   // 均價線控制
   bool              m_enableAvgLines;

   // 私有方法
   uint              GetProfitColorARGB(double profit);
   color             GetProfitColor(double profit);
   void              CalculateTradeStats(int magicNumber, int orderType, TradeStatsCanvas &stats);
   double            CalculateCombinedAvgPrice(TradeStatsCanvas &buyStats, TradeStatsCanvas &sellStats);
   void              CreateLabel(string name, int x, int y, string text, color clr, int fontSize);
   void              SaveAsLabels();  // 將 Canvas 內容保存為 OBJ_LABEL

public:
                     CChartPanelCanvas();
                    ~CChartPanelCanvas();

   bool              Init(string prefix, int x = 20, int y = 20, int updateInterval = 5);
   void              Deinit();
   void              Cleanup();

   bool              Update(bool forceUpdate = false);
   void              Redraw();

   void              SetTradeInfo(int magicNumber);
   void              SetSystemInfo(string tradeMode, string tradeSymbol);
   void              SetEAVersion(string version);
   void              SetAccumulatedProfit(double profit);
   void              SetCurrentProfit(double profit);

   void              RecordClosedProfit(double profit);
   void              RecordFloatingLoss(double loss);
   void              RecordMarginLevel(double marginPct);
   void              ResetProfitRecord();
   void              ResetAllProfitRecord();

   void              PrintPL(double profit, datetime time, double price);

   // 均價線功能
   void              EnableAvgLines(bool enable)  { m_enableAvgLines = enable; }
   bool              IsAvgLinesEnabled()          { return m_enableAvgLines; }
   void              DrawAvgLines();

   bool              IsInitialized()        { return m_initialized; }
   string            GetPrefix()            { return m_prefix; }
   double            GetMaxProfit()         { return m_maxProfit; }
   double            GetMaxLoss()           { return m_maxLoss; }
   double            GetLowestMarginPct()   { return m_lowestMarginPct; }
   double            GetCurrentProfit()     { return m_currentProfit; }
   double            GetAccumulatedProfit() { return m_accumulatedProfit; }
  };


//+------------------------------------------------------------------+
//| 建構函數                                                          |
//+------------------------------------------------------------------+
CChartPanelCanvas::CChartPanelCanvas()
  {
   m_prefix = "";
   m_canvasName = "";
   m_initialized = false;
   m_baseX = 20;
   m_baseY = 20;
   m_width = 390;
   m_height = 240;
   m_margin = 10;
   m_lineHeight = 20;
   m_zOrder = LONG_MAX;
   m_PLzOrder = 100;
   m_fontName = "Arial";
   m_titleFontSize = 18;
   m_fontSize = 16;
   m_PLfontSize = 8;
   m_clrProfit = clrOrangeRed;
   m_clrLoss = clrLawnGreen;
   m_clrNeutral = clrDimGray;
   m_clrTitle = clrGold;
   m_clrSection = clrYellow;
   m_clrText = clrWhite;
   m_clrBorder = clrGray;
   m_clrActive = clrGold;
   m_clrDanger = clrRed;
   m_clrChartPL = clrYellow;
   m_bgColor = C'30,30,30';
   m_bgAlpha = 128;
   m_updateInterval = 5;
   m_lastUpdate = 0;
   m_maxProfit = 0.0;
   m_maxLoss = 0.0;
   m_lowestMarginPct = 0.0;
   m_currentProfit = 0.0;
   m_accumulatedProfit = 0.0;
   m_tradeMode = "";
   m_tradeSymbol = "";
   m_eaVersion = "";
   m_magicNumber = 0;
   m_enableAvgLines = true;
  }

CChartPanelCanvas::~CChartPanelCanvas() { }


//+------------------------------------------------------------------+
//| 建立 OBJ_LABEL                                                    |
//+------------------------------------------------------------------+
void CChartPanelCanvas::CreateLabel(string name, int x, int y, string text, color clr, int fontSize)
  {
   string objName = "GridsResult_" + name;
   if(ObjectFind(0, objName) >= 0) ObjectDelete(0, objName);
   ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, objName, OBJPROP_FONT, m_fontName);
   ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
   ObjectSetString(0, objName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
  }


//+------------------------------------------------------------------+
//| 初始化面板                                                         |
//+------------------------------------------------------------------+
bool CChartPanelCanvas::Init(string prefix, int x = 20, int y = 20, int updateInterval = 5)
  {
   if(prefix == "") return false;
   m_prefix = prefix + "Canvas_";
   m_canvasName = m_prefix + "Panel";
   m_baseX = x;
   m_baseY = y;
   m_updateInterval = updateInterval;
   m_lastUpdate = 0;
   if(ObjectFind(0, m_canvasName) >= 0) ObjectDelete(0, m_canvasName);
   if(!m_canvas.CreateBitmapLabel(m_canvasName, m_baseX, m_baseY, m_width, m_height, COLOR_FORMAT_ARGB_NORMALIZE))
     {
      Print("錯誤: 無法建立 Canvas 面板");
      return false;
     }
   ObjectSetInteger(0, m_canvasName, OBJPROP_ZORDER, m_zOrder);
   m_canvas.FontSet(m_fontName, m_fontSize);
   m_initialized = true;
   Print("[CChartPanelCanvas] 面板初始化完成");
   return true;
  }

//+------------------------------------------------------------------+
//| 取得盈虧顏色 ARGB                                                  |
//+------------------------------------------------------------------+
uint CChartPanelCanvas::GetProfitColorARGB(double profit)
  {
   if(profit > 0) return ColorToARGB(m_clrProfit);
   else if(profit < 0) return ColorToARGB(m_clrLoss);
   else return ColorToARGB(m_clrNeutral);
  }

//+------------------------------------------------------------------+
//| 取得盈虧顏色                                                       |
//+------------------------------------------------------------------+
color CChartPanelCanvas::GetProfitColor(double profit)
  {
   if(profit > 0) return m_clrProfit;
   else if(profit < 0) return m_clrLoss;
   else return m_clrNeutral;
  }


//+------------------------------------------------------------------+
//| 繪製多空均價線                                                     |
//+------------------------------------------------------------------+
void CChartPanelCanvas::DrawAvgLines()
  {
   if(!m_initialized || !m_enableAvgLines) return;

   // 計算多空統計
   TradeStatsCanvas buyStats, sellStats;
   CalculateTradeStats(m_magicNumber, OP_BUY, buyStats);
   CalculateTradeStats(m_magicNumber, OP_SELL, sellStats);

   string buyLineName = m_prefix + "AvgLine_Buy";
   string sellLineName = m_prefix + "AvgLine_Sell";

   // 多頭均價線
   if(buyStats.lots > 0 && buyStats.avgPrice > 0)
     {
      if(ObjectFind(0, buyLineName) < 0)
         ObjectCreate(0, buyLineName, OBJ_HLINE, 0, 0, buyStats.avgPrice);
      else
         ObjectSetDouble(0, buyLineName, OBJPROP_PRICE, buyStats.avgPrice);

      ObjectSetInteger(0, buyLineName, OBJPROP_COLOR, m_clrProfit);
      ObjectSetInteger(0, buyLineName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, buyLineName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, buyLineName, OBJPROP_BACK, true);
      ObjectSetInteger(0, buyLineName, OBJPROP_SELECTABLE, false);
      ObjectSetString(0, buyLineName, OBJPROP_TOOLTIP, "多頭均價: " + DoubleToString(buyStats.avgPrice, (int)MarketInfo(Symbol(), MODE_DIGITS)));
     }
   else
     {
      if(ObjectFind(0, buyLineName) >= 0)
         ObjectDelete(0, buyLineName);
     }

   // 空頭均價線
   if(sellStats.lots > 0 && sellStats.avgPrice > 0)
     {
      if(ObjectFind(0, sellLineName) < 0)
         ObjectCreate(0, sellLineName, OBJ_HLINE, 0, 0, sellStats.avgPrice);
      else
         ObjectSetDouble(0, sellLineName, OBJPROP_PRICE, sellStats.avgPrice);

      ObjectSetInteger(0, sellLineName, OBJPROP_COLOR, m_clrLoss);
      ObjectSetInteger(0, sellLineName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, sellLineName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, sellLineName, OBJPROP_BACK, true);
      ObjectSetInteger(0, sellLineName, OBJPROP_SELECTABLE, false);
      ObjectSetString(0, sellLineName, OBJPROP_TOOLTIP, "空頭均價: " + DoubleToString(sellStats.avgPrice, (int)MarketInfo(Symbol(), MODE_DIGITS)));
     }
   else
     {
      if(ObjectFind(0, sellLineName) >= 0)
         ObjectDelete(0, sellLineName);
     }
  }


//+------------------------------------------------------------------+
//| 將 Canvas 內容保存為 OBJ_LABEL（測試結束時呼叫）                    |
//+------------------------------------------------------------------+
void CChartPanelCanvas::SaveAsLabels()
  {
   // 建立背景框
   string bgName = "GridsResult_Background";
   if(ObjectFind(0, bgName) >= 0) ObjectDelete(0, bgName);
   ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, m_baseX);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, m_baseY);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, m_width);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, m_height);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, m_bgColor);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bgName, OBJPROP_COLOR, m_clrBorder);
   ObjectSetInteger(0, bgName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, bgName, OBJPROP_BACK, false);
   ObjectSetInteger(0, bgName, OBJPROP_ZORDER, m_zOrder - 1);
   ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);

   // 計算交易統計
   TradeStatsCanvas buyStats, sellStats;
   CalculateTradeStats(m_magicNumber, OP_BUY, buyStats);
   CalculateTradeStats(m_magicNumber, OP_SELL, sellStats);
   double totalProfit = buyStats.profit + sellStats.profit;
   double lotsDiff = buyStats.lots - sellStats.lots;
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   double balance = AccountBalance();
   double equity = AccountEquity();
   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);

   int x = m_baseX + m_margin;
   int y = m_baseY + m_margin;
   int row = 0;
   int lineH = 18;

   // 標題
   string title = "Grids AI";
   if(m_eaVersion != "") title = "Grids AI v" + m_eaVersion + " - 測試結果";
   CreateLabel("L" + IntegerToString(row), x, y + row * lineH, title, m_clrTitle, 14);
   row += 2;

   // 表頭
   CreateLabel("L" + IntegerToString(row), x, y + row * lineH, "持倉:      均價           盈虧       手數    筆數", m_clrSection, 11);
   row++;

   // 多頭
   string buyAvg = (buyStats.avgPrice > 0) ? DoubleToStr(buyStats.avgPrice, digits) : "-";
   string buyRow = StringFormat("多頭   %12s   %8.2f   %6.2f   %3d", buyAvg, buyStats.profit, buyStats.lots, buyStats.count);
   CreateLabel("L" + IntegerToString(row), x, y + row * lineH, buyRow, GetProfitColor(buyStats.profit), 11);
   row++;

   // 空頭
   string sellAvg = (sellStats.avgPrice > 0) ? DoubleToStr(sellStats.avgPrice, digits) : "-";
   string sellRow = StringFormat("空頭   %12s   %8.2f   %6.2f   %3d", sellAvg, sellStats.profit, sellStats.lots, sellStats.count);
   CreateLabel("L" + IntegerToString(row), x, y + row * lineH, sellRow, GetProfitColor(sellStats.profit), 11);
   row++;

   // 合計
   string lotsDiffStr = (lotsDiff >= 0) ? ("+" + DoubleToStr(lotsDiff, 2)) : DoubleToStr(lotsDiff, 2);
   string totalRow = StringFormat("合計                  %8.2f   %7s", totalProfit, lotsDiffStr);
   CreateLabel("L" + IntegerToString(row), x, y + row * lineH, totalRow, GetProfitColor(totalProfit), 11);
   row += 2;

   // 分隔線
   CreateLabel("L" + IntegerToString(row), x, y + row * lineH, "─────────────────────────────────────", m_clrNeutral, 11);
   row++;

   // 紀錄
   CreateLabel("L" + IntegerToString(row), x, y + row * lineH, "紀錄:", m_clrSection, 11);
   row++;
   string recordInfo = StringFormat("最高獲利: %.2f / 最大虧損: %.2f", m_maxProfit, m_maxLoss);
   CreateLabel("L" + IntegerToString(row), x, y + row * lineH, recordInfo, GetProfitColor(m_currentProfit), 11);
   row++;

   // 保證金
   color clrMargin = (marginLevel > 500) ? m_clrActive : ((marginLevel > 200) ? m_clrNeutral : m_clrDanger);
   string marginInfo = StringFormat("保證金水平: %.1f%% / 最低: %.1f%%", marginLevel, m_lowestMarginPct);
   CreateLabel("L" + IntegerToString(row), x, y + row * lineH, marginInfo, clrMargin, 11);
   row++;

   // 帳戶
   string accountInfo = StringFormat("餘額: %.2f / 淨值: %.2f / 累積: %.2f", balance, equity, m_accumulatedProfit);
   CreateLabel("L" + IntegerToString(row), x, y + row * lineH, accountInfo, GetProfitColor(m_accumulatedProfit), 11);
   row++;

   // 系統
   string sysInfo = StringFormat("系統: %s / %s", (m_tradeMode != "") ? m_tradeMode : "未設定", (m_tradeSymbol != "") ? m_tradeSymbol : Symbol());
   CreateLabel("L" + IntegerToString(row), x, y + row * lineH, sysInfo, m_clrNeutral, 11);

   ChartRedraw(0);
   Print("[CChartPanelCanvas] 已建立 OBJ_LABEL 保留測試結果");
  }


//+------------------------------------------------------------------+
//| 停止面板（測試模式時保存為 OBJ_LABEL）                              |
//+------------------------------------------------------------------+
void CChartPanelCanvas::Deinit()
  {
   // 清理均價線
   if(m_prefix != "")
     {
      string buyLineName = m_prefix + "AvgLine_Buy";
      string sellLineName = m_prefix + "AvgLine_Sell";
      if(ObjectFind(0, buyLineName) >= 0) ObjectDelete(0, buyLineName);
      if(ObjectFind(0, sellLineName) >= 0) ObjectDelete(0, sellLineName);
     }

   if(IsTesting())
     {
      Update(true);
      SaveAsLabels();
     }
   m_initialized = false;
   Print("[CChartPanelCanvas] 面板已停止");
  }

//+------------------------------------------------------------------+
//| 清理面板                                                           |
//+------------------------------------------------------------------+
void CChartPanelCanvas::Cleanup()
  {
   m_canvas.Destroy();
   if(m_prefix != "")
     {
      int total = ObjectsTotal();
      for(int i = total - 1; i >= 0; i--)
        {
         string objName = ObjectName(i);
         if(StringFind(objName, m_prefix) == 0) ObjectDelete(0, objName);
        }
     }
   ChartRedraw();
   Print("[CChartPanelCanvas] 面板已清理");
  }

//+------------------------------------------------------------------+
//| 計算交易統計                                                       |
//+------------------------------------------------------------------+
void CChartPanelCanvas::CalculateTradeStats(int magicNumber, int orderType, TradeStatsCanvas &stats)
  {
   stats.lots = 0.0; stats.avgPrice = 0.0; stats.profit = 0.0; stats.count = 0;
   double totalLots = 0.0, weightedPrice = 0.0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(magicNumber > 0 && OrderMagicNumber() != magicNumber) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderType() != orderType) continue;
      double lots = OrderLots();
      totalLots += lots;
      weightedPrice += OrderOpenPrice() * lots;
      stats.profit += OrderProfit() + OrderSwap() + OrderCommission();
      stats.count++;
     }
   stats.lots = totalLots;
   if(totalLots > 0) stats.avgPrice = weightedPrice / totalLots;
  }

//+------------------------------------------------------------------+
//| 計算合併均價                                                       |
//+------------------------------------------------------------------+
double CChartPanelCanvas::CalculateCombinedAvgPrice(TradeStatsCanvas &buyStats, TradeStatsCanvas &sellStats)
  {
   double totalLots = buyStats.lots + sellStats.lots;
   if(totalLots <= 0) return 0.0;
   return ((buyStats.avgPrice * buyStats.lots) + (sellStats.avgPrice * sellStats.lots)) / totalLots;
  }


//+------------------------------------------------------------------+
//| 設定方法                                                          |
//+------------------------------------------------------------------+
void CChartPanelCanvas::SetSystemInfo(string tradeMode, string tradeSymbol)
  { m_tradeMode = tradeMode; m_tradeSymbol = tradeSymbol; }

void CChartPanelCanvas::SetEAVersion(string version)
  { m_eaVersion = version; }

void CChartPanelCanvas::SetAccumulatedProfit(double profit)
  { m_accumulatedProfit = profit; }

void CChartPanelCanvas::SetCurrentProfit(double profit)
  { m_currentProfit = profit; if(profit < 0) RecordFloatingLoss(profit); }

//+------------------------------------------------------------------+
//| 紀錄管理                                                           |
//+------------------------------------------------------------------+
void CChartPanelCanvas::RecordClosedProfit(double profit)
  { if(profit > m_maxProfit) m_maxProfit = profit; }

void CChartPanelCanvas::RecordFloatingLoss(double loss)
  { double absLoss = (loss > 0) ? -loss : loss; if(absLoss < m_maxLoss) m_maxLoss = absLoss; }

void CChartPanelCanvas::RecordMarginLevel(double marginPct)
  { if(marginPct > 0 && (m_lowestMarginPct == 0.0 || marginPct < m_lowestMarginPct)) m_lowestMarginPct = marginPct; }

void CChartPanelCanvas::ResetProfitRecord() { m_currentProfit = 0.0; }

void CChartPanelCanvas::ResetAllProfitRecord()
  { m_maxProfit = 0.0; m_maxLoss = 0.0; m_lowestMarginPct = 0.0; m_currentProfit = 0.0; }

//+------------------------------------------------------------------+
//| 在圖表上顯示盈虧標籤                                               |
//+------------------------------------------------------------------+
void CChartPanelCanvas::PrintPL(double profit, datetime time, double price)
  {
   RecordClosedProfit(profit);
   string objName = m_prefix + "PL_" + IntegerToString(time) + "_" + DoubleToStr(price, 5);
   if(ObjectFind(0, objName) >= 0) ObjectDelete(0, objName);
   ObjectCreate(0, objName, OBJ_TEXT, 0, time, price);
   ObjectSetString(0, objName, OBJPROP_TEXT, "  PL=" + DoubleToStr(profit, 2));
   ObjectSetString(0, objName, OBJPROP_FONT, m_fontName);
   ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, m_PLfontSize);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, (price>=0? m_clrChartPL : clrLime));
   ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, objName, OBJPROP_BACK, true);
  }

//+------------------------------------------------------------------+
//| 設定交易資訊                                                       |
//+------------------------------------------------------------------+
void CChartPanelCanvas::SetTradeInfo(int magicNumber)
  {
   if(!m_initialized) return;
   m_magicNumber = magicNumber;
   TradeStatsCanvas buyStats, sellStats;
   CalculateTradeStats(magicNumber, OP_BUY, buyStats);
   CalculateTradeStats(magicNumber, OP_SELL, sellStats);
   double totalProfit = buyStats.profit + sellStats.profit;
   SetCurrentProfit(totalProfit);
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   RecordMarginLevel(marginLevel);

   // 繪製均價線
   DrawAvgLines();
  }



//+------------------------------------------------------------------+
//| 更新面板顯示                                                       |
//+------------------------------------------------------------------+
bool CChartPanelCanvas::Update(bool forceUpdate = false)
  {
   if(!m_initialized) return false;
   datetime currentTime = TimeCurrent();
   if(!forceUpdate && (currentTime - m_lastUpdate < m_updateInterval)) return false;
   m_lastUpdate = currentTime;

   TradeStatsCanvas buyStats = {0}, sellStats = {0};
   
   // 單次掃描優化：同時計算多空統計
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(m_magicNumber > 0 && OrderMagicNumber() != m_magicNumber) continue;
      if(OrderSymbol() != Symbol()) continue;
      
      int type = OrderType();
      double lots = OrderLots();
      double p = OrderProfit() + OrderSwap() + OrderCommission();
      
      if(type == OP_BUY)
        {
         buyStats.lots += lots;
         buyStats.avgPrice += OrderOpenPrice() * lots;
         buyStats.profit += p;
         buyStats.count++;
        }
      else if(type == OP_SELL)
        {
         sellStats.lots += lots;
         sellStats.avgPrice += OrderOpenPrice() * lots;
         sellStats.profit += p;
         sellStats.count++;
        }
     }
   if(buyStats.lots > 0) buyStats.avgPrice /= buyStats.lots;
   if(sellStats.lots > 0) sellStats.avgPrice /= sellStats.lots;

   double totalLots = buyStats.lots + sellStats.lots;
   double totalProfit = buyStats.profit + sellStats.profit;
   double lotsDiff = buyStats.lots - sellStats.lots;
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   double balance = AccountBalance();
   double equity = AccountEquity();
   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);

   SetCurrentProfit(totalProfit);
   RecordMarginLevel(marginLevel);
   DrawAvgLines();

   m_canvas.Erase(ColorToARGB(clrBlack, 0));
   m_canvas.FillRectangle(0, 0, m_width, m_height, ColorToARGB(m_bgColor, (uchar)m_bgAlpha));
   m_canvas.Rectangle(0, 0, m_width - 1, m_height - 1, ColorToARGB(m_clrBorder));

   int x = m_margin;
   int y = m_margin;
   int col1 = x, col2 = x + 120, col3 = x + 220, col4 = x + 295, col5 = x + 360;

   // 標題
   m_canvas.FontSet(m_fontName, m_titleFontSize);
   string title = (m_eaVersion != "") ? "Grids AI v" + m_eaVersion : "Grids AI";
   m_canvas.TextOut(col1, y, title, ColorToARGB(m_clrTitle));
   y += m_lineHeight + 5;

   m_canvas.FontSet(m_fontName, m_fontSize);

   // 表頭
   m_canvas.TextOut(col1, y, "持倉:", ColorToARGB(m_clrSection));
   m_canvas.TextOut(col2 - m_canvas.TextWidth("均價"), y, "均價", ColorToARGB(m_clrSection));
   m_canvas.TextOut(col3 - m_canvas.TextWidth("盈虧"), y, "盈虧", ColorToARGB(m_clrSection));
   m_canvas.TextOut(col4 - m_canvas.TextWidth("手數"), y, "手數", ColorToARGB(m_clrSection));
   m_canvas.TextOut(col5 - m_canvas.TextWidth("筆數"), y, "筆數", ColorToARGB(m_clrSection));
   y += m_lineHeight;

   // 多頭
   m_canvas.TextOut(col1, y, "多頭", ColorToARGB(m_clrText));
   string val2 = (buyStats.avgPrice > 0) ? DoubleToStr(buyStats.avgPrice, digits) : "-";
   m_canvas.TextOut(col2 - m_canvas.TextWidth(val2), y, val2, ColorToARGB(m_clrText));
   string val3 = StringFormat("%.2f", buyStats.profit);
   m_canvas.TextOut(col3 - m_canvas.TextWidth(val3), y, val3, GetProfitColorARGB(buyStats.profit));
   string val4 = StringFormat("%.2f", buyStats.lots);
   m_canvas.TextOut(col4 - m_canvas.TextWidth(val4), y, val4, ColorToARGB(m_clrText));
   string val5 = IntegerToString(buyStats.count);
   m_canvas.TextOut(col5 - m_canvas.TextWidth(val5), y, val5, ColorToARGB(m_clrText));
   y += m_lineHeight;

   // 空頭
   m_canvas.TextOut(col1, y, "空頭", ColorToARGB(m_clrText));
   val2 = (sellStats.avgPrice > 0) ? DoubleToStr(sellStats.avgPrice, digits) : "-";
   m_canvas.TextOut(col2 - m_canvas.TextWidth(val2), y, val2, ColorToARGB(m_clrText));
   val3 = StringFormat("%.2f", sellStats.profit);
   m_canvas.TextOut(col3 - m_canvas.TextWidth(val3), y, val3, GetProfitColorARGB(sellStats.profit));
   val4 = StringFormat("%.2f", sellStats.lots);
   m_canvas.TextOut(col4 - m_canvas.TextWidth(val4), y, val4, ColorToARGB(m_clrText));
   val5 = IntegerToString(sellStats.count);
   m_canvas.TextOut(col5 - m_canvas.TextWidth(val5), y, val5, ColorToARGB(m_clrText));
   y += m_lineHeight + 3;

   // 合計
   m_canvas.TextOut(col1, y, "合計", ColorToARGB(m_clrSection));
   val3 = StringFormat("%.2f", totalProfit);
   m_canvas.TextOut(col3 - m_canvas.TextWidth(val3), y, val3, GetProfitColorARGB(totalProfit));
   string lotsDiffStr = (lotsDiff >= 0) ? ("+" + StringFormat("%.2f", lotsDiff)) : StringFormat("%.2f", lotsDiff);
   m_canvas.TextOut(col4 - m_canvas.TextWidth(lotsDiffStr), y, lotsDiffStr, ColorToARGB(m_clrText));
   y += m_lineHeight + 8;

   // 分隔線
   m_canvas.Line(x, y, m_width - x, y, ColorToARGB(m_clrBorder));
   y += 8;

   // 紀錄
   m_canvas.TextOut(col1, y, "紀錄:", ColorToARGB(m_clrSection));
   y += m_lineHeight;
   string recordInfo = StringFormat("最高獲利: %.2f / 最大虧損: %.2f", m_maxProfit, m_maxLoss);
   m_canvas.TextOut(col1, y, recordInfo, GetProfitColorARGB(m_currentProfit));
   y += m_lineHeight;

   // 保證金
   color clrMargin = (marginLevel > 500) ? m_clrActive : ((marginLevel > 200) ? m_clrNeutral : m_clrDanger);
   string marginInfo = StringFormat("保證金水平: %.1f%% / 最低: %.1f%%", marginLevel, m_lowestMarginPct);
   m_canvas.TextOut(col1, y, marginInfo, ColorToARGB(clrMargin));
   y += m_lineHeight;

   // 帳戶
   string accountInfo = StringFormat("餘額: %.2f / 淨值: %.2f / 累積: %.2f", balance, equity, m_accumulatedProfit);
   m_canvas.TextOut(col1, y, accountInfo, GetProfitColorARGB(m_accumulatedProfit));
   y += m_lineHeight + 5;

   // 系統
   string sysInfo = StringFormat("系統: %s / %s", (m_tradeMode != "") ? m_tradeMode : "未設定", (m_tradeSymbol != "") ? m_tradeSymbol : Symbol());
   m_canvas.TextOut(col1, y, sysInfo, ColorToARGB(m_clrNeutral));
   y += m_lineHeight;

   // 動態調整高度
   int requiredHeight = y + m_margin;
   if(requiredHeight != m_height && requiredHeight > 100)
     {
      m_height = requiredHeight;
      m_canvas.Destroy();
      if(!m_canvas.CreateBitmapLabel(m_canvasName, m_baseX, m_baseY, m_width, m_height, COLOR_FORMAT_ARGB_NORMALIZE))
        { Print("錯誤: 無法重新建立 Canvas 面板"); return false; }
      ObjectSetInteger(0, m_canvasName, OBJPROP_ZORDER, m_zOrder);
      m_canvas.FontSet(m_fontName, m_fontSize);
      Update(true);
      return true;
     }

   m_canvas.Update();
   return true;
  }

//+------------------------------------------------------------------+
//| 強制重繪                                                          |
//+------------------------------------------------------------------+
void CChartPanelCanvas::Redraw()
  { Update(true); }
//+------------------------------------------------------------------+
