//+------------------------------------------------------------------+
//| Grids 2.4.mq4
//| Profit Generator EA v2.4
//| 整合 CEACore + CGridsCore 架構
//+------------------------------------------------------------------+
#property copyright "Recovery System"
#property link      ""
#property version   "2.4"
#property strict

//+------------------------------------------------------------------+
//| 引入核心模組 (v2.4 版本)
//+------------------------------------------------------------------+
#include "../Libs/EACore/CEACore_v2.4.mqh"
#include "../Libs/GridsCore/CGridsCore_v2.4.mqh"


//+------------------------------------------------------------------+
//| ENUM_BOOL 定義
//+------------------------------------------------------------------+
enum ENUM_BOOL
  {
   NO = 0,                       // 否
   YES = 1                       // 是
  };

//+------------------------------------------------------------------+
//| 外部參數
//+------------------------------------------------------------------+
sinput string  PG_Help0                  = "----------------";   // 組別設定 (重要)
input string   PG_GroupID                = "A";                  // 組別 ID
input int      PG_MagicNumber            = 16888;                // MagicNumber

sinput string  TF_Help                   = "----------------";   // 趨勢過濾設定
input ENUM_FILTER_MODE TF_FilterMode     = FILTER_HeikenAshi;    // 過濾模式
input int      TF_Timeframe              = 0;                    // 分析時間框架

sinput string  BB_Help                   = "----------------";   // BullsBears 設定
input int      BB_LookbackBars           = 4;                    // 回看 K 線數量
input double   BB_Threshold              = 5.0;                  // 力量差異閾值

sinput string  ST_Help                   = "----------------";   // Super Trend 設定
input int      ST_ATR_Period             = 10;                   // ATR 週期
input double   ST_Multiplier             = 1.2;                  // ATR 乘數
input ENUM_SIGNAL_MODE ST_SignalMode     = SIGNAL_MODE_TREND;    // 首單模式
input ENUM_AVERAGING_MODE ST_AveragingMode = AVERAGING_ANY;      // 加倉模式
input ENUM_BOOL ST_ShowLine              = YES;                  // 顯示趨勢線
input color    ST_BullColor              = clrOrangeRed;         // 上漲顏色
input color    ST_BearColor              = clrLawnGreen;         // 下跌顏色

sinput string  HK_Help                   = "----------------";   // Heiken Ashi 設定
input int      HK_MaPeriod               = 2;                    // 平滑週期
input ENUM_MA_METHOD HK_MaMethod         = MODE_LWMA;            // 平滑方法
input ENUM_SIGNAL_MODE HK_SignalMode     = SIGNAL_MODE_TREND;    // 首單模式
input ENUM_AVERAGING_MODE HK_AveragingMode = AVERAGING_ANY;      // 加倉模式

sinput string  PG_Help1                  = "----------------";   // 網格設定
input ENUM_GRID_MODE PG_GridMode         = GRID_MODE_TREND;      // 網格模式
input double   PG_GridStep               = 200.0;                // 網格間距 (點)
input double   PG_InitialLots            = 0.01;                 // 起始手數
input int      PG_MaxGridLevels          = 399;                  // 最大網格層數
input double   PG_TakeProfit             = 0.0;                  // 止盈金額

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
sinput string  PG_Help_Scaling           = "----------------";   // 獨立縮放設定 (0=不縮放)
input double   PG_CounterGridScaling     = 0.0;                  // 逆向間距縮放% (正=擴張，負=收縮)
input double   PG_CounterLotScaling      = 25.0;                 // 逆向手數縮放%
input double   PG_TrendGridScaling       = 0.0;                  // 順向間距縮放%
input double   PG_TrendLotScaling        = 25.0;                 // 順向手數縮放%

sinput string  OP_Help                   = "----------------";   // 訂單保護設定
input ENUM_BOOL OP_OneOrderPerBar        = NO;                   // 每根K線只開一單
input int      OP_Slippage               = 30;                   // 滑點容許值
input int      OP_MaxOrdersInWork        = 100;                  // 最大訂單數量

sinput string  PG_Help2                  = "----------------";   // 交易方向
input ENUM_TRADE_DIRECTION PG_TradeDirection = TRADE_BOTH;       // 交易方向

sinput string  PG_Help3                  = "----------------";   // 風險控制
input double   PG_MaxDrawdown            = 0.0;                  // 最大回撤停損 (%)
input double   PG_MaxLots                = 1.0;                  // 最大總手數
input double   PG_MaxSpread              = 250.0;                // 最大點差

sinput string  PG_Help5                  = "----------------";   // 獨立運行設定
input ENUM_BOOL PG_StandaloneMode        = YES;                  // 獨立運行模式

sinput string  PF_Help                   = "----------------";   // 效能優化設定
input int      PF_Timer1                 = 2;                    // 盈虧掃描間隔 (秒)
input int      PF_Timer2                 = 10;                   // UI/箭頭更新間隔 (秒)

sinput string  PG_Help6                  = "----------------";   // 除錯設定
input string   PG_LogFile                = "";                   // 日誌檔案（空=不建立）


sinput string  AR_Help                   = "----------------";   // 交易箭頭設定
input ENUM_BOOL AR_EnableArrows          = YES;                  // 啟用交易箭頭
input int      AR_ArrowDays              = 5;                    // 箭頭回溯天數
input color    AR_OpenBuyColor           = clrOrangeRed;         // 開倉買入顏色
input color    AR_OpenSellColor          = clrLawnGreen;         // 開倉賣出顏色
input color    AR_HistoryBuyColor        = clrDarkRed;           // 歷史買入顏色
input color    AR_HistorySellColor       = clrDarkGreen;         // 歷史賣出顏色

sinput string  PT_Help                   = "----------------";   // 獲利回跌停利設定
input ENUM_BOOL PT_EnableTrailing        = YES;                  // 啟用獲利回跌停利
input double   PT_ProfitThreshold        = 10.0;                 // 獲利閾值
input double   PT_DrawdownPercent        = 75.0;                 // 保留利潤百分比

//+------------------------------------------------------------------+
//| 全域變數
//+------------------------------------------------------------------+
CEACore        g_eaCore;
CGridsCore     g_gridsCore;

//+------------------------------------------------------------------+
//| 對沖平倉回調（由 CGridsCore 呼叫，執行對沖平倉）
//+------------------------------------------------------------------+
double OnRequestHedgeClose()
  {
   double profit = g_eaCore.HedgeCloseAll();
   g_eaCore.LogTrade("EXIT HEDGE", 0, MarketInfo(Symbol(), MODE_BID), StringFormat("Total Profit: %.2f", profit));
   return profit;
  }


//+------------------------------------------------------------------+
//| 平倉完成回調（由 CGridsCore 呼叫，通知獲利金額）
//+------------------------------------------------------------------+
void OnGridClose(double profit, datetime time, double price)
  {
   g_eaCore.AddProfit(profit);
   g_gridsCore.SetTradedThisSignal(true);
  }


//+------------------------------------------------------------------+
//| 輔助函數：Dump 所有外部參數
//+------------------------------------------------------------------+
string GetDumpedInputs()
  {
   string p = "";
   p += "PG_GroupID: " + PG_GroupID + "\n";
   p += "PG_MagicNumber: " + IntegerToString(PG_MagicNumber) + "\n";
   p += "TF_FilterMode: " + EnumToString(TF_FilterMode) + "\n";
   p += "PG_GridMode: " + EnumToString(PG_GridMode) + "\n";
   p += "PG_GridStep: " + DoubleToString(PG_GridStep, 1) + "\n";
   p += "PG_InitialLots: " + DoubleToString(PG_InitialLots, 2) + "\n";
   p += "PG_TakeProfit: " + DoubleToString(PG_TakeProfit, 2) + "\n";
   p += "OP_OneOrderPerBar: " + EnumToString(OP_OneOrderPerBar) + "\n";
   p += "PG_MaxDrawdown: " + DoubleToString(PG_MaxDrawdown, 2) + "\n";
   p += "PG_StandaloneMode: " + EnumToString(PG_StandaloneMode) + "\n";
   return p;
  }

//+------------------------------------------------------------------+
//| EA 初始化                                                        |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- 初始化 CEACore
   g_eaCore.SetMagic(PG_MagicNumber);
   g_eaCore.SetSymbol(Symbol());
   g_eaCore.SetLogFile(PG_LogFile);
   g_eaCore.DumpParameters(GetDumpedInputs());

   g_eaCore.SetGroupId(PG_GroupID);

   g_eaCore.SetSlippage(OP_Slippage);
   g_eaCore.SetEAName("Grids");
   g_eaCore.SetEAVersion("2.3");

   g_eaCore.SetMaxDrawdown(PG_MaxDrawdown);

   g_eaCore.SetMaxLots(PG_MaxLots);
   g_eaCore.SetMaxSpread(PG_MaxSpread);
   g_eaCore.SetMaxOrders(OP_MaxOrdersInWork);

   g_eaCore.EnableHedgeClose(true);
   g_eaCore.EnableProfitTrailing(PT_EnableTrailing == YES);
   g_eaCore.EnableArrows(AR_EnableArrows == YES);
   g_eaCore.EnableRecoveryProfit(PG_StandaloneMode == NO);
   g_eaCore.EnableChartPanel(true);
   g_eaCore.EnableTimer(true);

   g_eaCore.SetProfitThreshold(PT_ProfitThreshold);
   g_eaCore.SetDrawdownPercent(PT_DrawdownPercent);

// 效能優化設定
   g_eaCore.SetTimer1Interval(PF_Timer1);
   g_eaCore.SetTimer2Interval(PF_Timer2);

   g_eaCore.SetArrowDays(AR_ArrowDays);
   g_eaCore.SetArrowColors(AR_OpenBuyColor, AR_OpenSellColor, AR_HistoryBuyColor, AR_HistorySellColor);

   bool enableLogs = (PG_LogFile != "");
   g_eaCore.SetDebugLogs(enableLogs);
// g_eaCore.SetLogFile(PG_LogFile); // 已移至最上方以便 DumpParameters

   if(g_eaCore.OnInitCore() != INIT_SUCCEEDED)
     {
      Print("[Grids 2.3] CEACore 初始化失敗");
      return INIT_FAILED;
     }

//--- 初始化 CGridsCore
   GridsCoreConfig config;
   config.magicNumber     = PG_MagicNumber;
   config.symbol          = Symbol();
   config.slippage        = OP_Slippage;
   config.logFile         = g_eaCore.GetActualLogFile(); // 傳入實際日誌路徑
   config.gridMode        = PG_GridMode;

   config.gridStep        = PG_GridStep;
   config.initialLots     = PG_InitialLots;
   config.maxGridLevels   = PG_MaxGridLevels;
   config.takeProfit      = PG_TakeProfit;
   config.oneOrderPerBar  = (OP_OneOrderPerBar == YES);

// 獨立縮放設定（0 = 不縮放）
   config.counterGridScaling  = PG_CounterGridScaling;
   config.counterLotScaling   = PG_CounterLotScaling;
   config.trendGridScaling    = PG_TrendGridScaling;
   config.trendLotScaling     = PG_TrendLotScaling;

   config.tradeDirection  = PG_TradeDirection;
   config.maxOrdersInWork = OP_MaxOrdersInWork;
   config.maxSpread       = PG_MaxSpread;
   config.maxLots         = PG_MaxLots;
   config.filterMode      = TF_FilterMode;
   config.filterTimeframe = TF_Timeframe;
   config.bbLookbackBars  = BB_LookbackBars;
   config.bbThreshold     = BB_Threshold;
   config.stAtrPeriod     = ST_ATR_Period;
   config.stMultiplier    = ST_Multiplier;
   config.stSignalMode    = ST_SignalMode;
   config.stAveragingMode = ST_AveragingMode;
   config.stShowLine      = (ST_ShowLine == YES);
   config.stBullColor     = ST_BullColor;
   config.stBearColor     = ST_BearColor;
// Heiken Ashi 參數
   config.heikenMaPeriod       = HK_MaPeriod;
   config.heikenMaMethod      = HK_MaMethod;
   config.heikenSignalMode     = HK_SignalMode;
   config.heikenAveragingMode = HK_AveragingMode;
   config.heikenThreshold     = 0.0;  // 預設不使用閾值
   config.showDebugLogs       = enableLogs;

   if(!g_gridsCore.Init(config))
     {
      Print("[Grids 2.3] CGridsCore 初始化失敗");
      return INIT_FAILED;
     }

// 設定回調函數
   g_gridsCore.SetOnRequestCloseCallback(OnRequestHedgeClose);
   g_gridsCore.SetOnCloseCallback(OnGridClose);

   Print("[Grids 2.3] EA 初始化完成 - 組別: ", PG_GroupID, ", Magic: ", PG_MagicNumber);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| EA 反初始化                                                      |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- 反初始化
   g_eaCore.OnDeinitCore(reason);
   g_gridsCore.Deinit();
   Print("[Grids 2.3] EA 已卸載，原因: ", reason);
  }


//+------------------------------------------------------------------+
//| EA 主循環                                                        |
//+------------------------------------------------------------------+
void OnTick()
  {
   g_eaCore.OnTickCore();

   if(!g_eaCore.IsRunning())
      return;

// 使用優化後的 Execute，傳入預先掃描好的訂單統計數據
   g_gridsCore.Execute(g_eaCore.GetOrderStats());
  }


//+------------------------------------------------------------------+
//| 定時器事件                                                       |
//+------------------------------------------------------------------+
void OnTimer()
  {
   g_eaCore.OnTimerCore();
  }

//+------------------------------------------------------------------+
//| 圖表事件                                                         |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam)
  {
   g_eaCore.OnChartEventCore(id, lparam, dparam, sparam);
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
