//+------------------------------------------------------------------+
//|                                                   Grids 1.20.mq4 |
//|                                    Profit Generator EA v1.20     |
//|                         整合 CEACore + CGridsCore 架構            |
//+------------------------------------------------------------------+
#property copyright "Recovery System"
#property link      ""
#property version   "1.20"
#property strict

//+------------------------------------------------------------------+
//| 引入核心模組                                                     |
//+------------------------------------------------------------------+
#include "../Libs/EACore/CEACore.mqh"
#include "../Libs/GridsCore/CGridsCore.mqh"

//+------------------------------------------------------------------+
//| ENUM_BOOL 定義                                                   |
//+------------------------------------------------------------------+
enum ENUM_BOOL
  {
   NO = 0,                       // 否
   YES = 1                       // 是
  };

//+------------------------------------------------------------------+
//| 外部參數                                                         |
//+------------------------------------------------------------------+
sinput string  PG_Help0                  = "----------------";   // 組別設定 (重要)
input string   PG_GroupID                = "A";                  // 組別 ID
input int      PG_MagicNumber            = 16888;                // MagicNumber

sinput string  TF_Help                   = "----------------";   // 趨勢過濾設定
input ENUM_FILTER_MODE TF_FilterMode     = FILTER_SUPERTREND;    // 過濾模式
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

sinput string  PG_Help1                  = "----------------";   // 網格設定
input ENUM_GRID_MODE PG_GridMode         = GRID_MODE_COUNTER;    // 網格模式
input double   PG_GridStep               = 200.0;                // 網格間距 (點)
input double   PG_InitialLots            = 0.01;                 // 起始手數
input int      PG_MaxGridLevels          = 99;                   // 最大網格層數
input double   PG_TakeProfit             = 0.0;                  // 止盈金額

sinput string  PG_Help_Scaling           = "----------------";   // 獨立縮放設定 (0=不縮放)
input double   PG_CounterGridScaling     = 0.0;                  // 逆向間距縮放% (正=擴張，負=收縮)
input double   PG_CounterLotScaling      = 25.0;                 // 逆向手數縮放%
input double   PG_TrendGridScaling       = 0.0;                  // 順向間距縮放%
input double   PG_TrendLotScaling        = 25.0;                 // 順向手數縮放%

sinput string  OP_Help                   = "----------------";   // 訂單保護設定
input ENUM_BOOL OP_OneOrderPerBar        = YES;                  // 每根K線只開一單
input int      OP_Slippage               = 30;                   // 滑點容許值
input int      OP_MaxOrdersInWork        = 100;                  // 最大訂單數量

sinput string  PG_Help2                  = "----------------";   // 交易方向
input ENUM_TRADE_DIRECTION PG_TradeDirection = TRADE_BOTH;       // 交易方向

sinput string  PG_Help3                  = "----------------";   // 風險控制
input double   PG_MaxDrawdown            = 20.0;                 // 最大回撤 (%)
input double   PG_MaxLots                = 1.0;                  // 最大總手數
input double   PG_MaxSpread              = 250.0;                // 最大點差

sinput string  PG_Help5                  = "----------------";   // 獨立運行設定
input ENUM_BOOL PG_StandaloneMode        = YES;                  // 獨立運行模式

sinput string  PF_Help                   = "----------------";   // 效能優化設定
input int      PF_Timer1                 = 2;                    // 盈虧掃描間隔 (秒)
input int      PF_Timer2                 = 10;                   // UI/箭頭更新間隔 (秒)

sinput string  PG_Help6                  = "----------------";   // 除錯設定
input ENUM_BOOL PG_ShowDebugLogs         = NO;                   // 顯示除錯日誌
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
//| 全域變數                                                         |
//+------------------------------------------------------------------+
CEACore        g_eaCore;
CGridsCore     g_gridsCore;

//+------------------------------------------------------------------+
//| 對沖平倉回調（由 CGridsCore 呼叫，執行對沖平倉）                  |
//+------------------------------------------------------------------+
double OnRequestHedgeClose()
  {
   return g_eaCore.HedgeCloseAll();
  }

//+------------------------------------------------------------------+
//| 平倉完成回調（由 CGridsCore 呼叫，通知獲利金額）                  |
//+------------------------------------------------------------------+
void OnGridClose(double profit, datetime time, double price)
  {
   g_eaCore.AddProfit(profit);
   g_gridsCore.SetTradedThisSignal(true);
  }


//+------------------------------------------------------------------+
//| EA 初始化                                                        |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- 初始化 CEACore
   g_eaCore.SetMagic(PG_MagicNumber);
   g_eaCore.SetSymbol(Symbol());
   g_eaCore.SetGroupId(PG_GroupID);
   g_eaCore.SetSlippage(OP_Slippage);
   g_eaCore.SetEAName("Grids");
   g_eaCore.SetEAVersion("1.20");
   
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
   
   g_eaCore.SetDebugLogs(PG_ShowDebugLogs == YES);
   g_eaCore.SetLogFile(PG_LogFile);
   
   if(g_eaCore.OnInitCore() != INIT_SUCCEEDED)
     {
      Print("[Grids 1.20] CEACore 初始化失敗");
      return INIT_FAILED;
     }
   
   //--- 初始化 CGridsCore
   GridsCoreConfig config;
   config.magicNumber     = PG_MagicNumber;
   config.symbol          = Symbol();
   config.slippage        = OP_Slippage;
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
   config.showDebugLogs   = (PG_ShowDebugLogs == YES);
   
   if(!g_gridsCore.Init(config))
     {
      Print("[Grids 1.20] CGridsCore 初始化失敗");
      return INIT_FAILED;
     }
   
   // 設定回調函數
   g_gridsCore.SetOnRequestCloseCallback(OnRequestHedgeClose);
   g_gridsCore.SetOnCloseCallback(OnGridClose);
   
   Print("[Grids 1.20] EA 初始化完成 - 組別: ", PG_GroupID, ", Magic: ", PG_MagicNumber);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| EA 反初始化                                                      |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_gridsCore.Deinit();
   g_eaCore.OnDeinitCore(reason);
   Print("[Grids 1.20] EA 已卸載，原因: ", reason);
  }

//+------------------------------------------------------------------+
//| EA 主循環                                                        |
//+------------------------------------------------------------------+
void OnTick()
  {
   g_eaCore.OnTickCore();
   
   if(!g_eaCore.IsRunning())
      return;
   
   g_gridsCore.Execute();
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
