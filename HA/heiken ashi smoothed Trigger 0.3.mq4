//------------------------------------------------------------------
// Heiken Ashi Smoothed V0.3 (Alerts + MTF + Trend-Based Safe Exit)
// 提升版本：0.3
// 核心功能：維持 Andy 原版 Heiken Ashi 演算法 (無 ATR)
// 附加功能：趨勢反轉觸發安全退出 + 每日自動重啟 (含冷卻時間)
// 修改者：Sisyphus (for Andy)
// 日期：2026-01-15
//------------------------------------------------------------------

#property copyright "Andy's Customized"
#property link      ""
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_color1  clrRoyalBlue
#property indicator_color2  clrRed
#property indicator_color3  clrRoyalBlue
#property indicator_color4  clrRed
#property indicator_width1  1
#property indicator_width2  1
#property indicator_width3  3
#property indicator_width4  3
#property strict

//--- 常舉定義
enum enMaTypes { ma_sma, ma_ema, ma_smma, ma_lwma, ma_tema, ma_hma };
enum TimeMode  { SERVER_TIME = 0, LOCAL_TIME = 1 };
enum ExitReason { EXIT_NONE = 0, EXIT_TREND_CHANGE = 1, EXIT_AUTORESTART = 2 };

//--- HA Smoothed 核心參數 (維持 0.2 版)
extern string          _HA_Settings_     = "=== HA Smoothed 核心參數 ===";
extern ENUM_TIMEFRAMES TimeFrame         = PERIOD_CURRENT;    // 使用時區
extern enMaTypes       MaMetod           = ma_ema;            // 第一層 MA 方法
extern int             MaPeriod          = 3;                 // 第一層 MA 週期
extern enMaTypes       MaMetod2          = ma_hma;            // 第二層 MA 方法
extern int             MaPeriod2         = 2;                 // 第二層 MA 週期
extern bool            Interpolate       = true;              // 多時區平滑處理

//--- 提取自 V1.3 的安全退出與冷卻參數 (根據多空轉換)
extern string          _Exit_Settings_   = "=== 趨勢退出與冷卻時間 ===";
extern bool            Enable_TrendExit  = true;              // 啟用趨勢反轉退出
extern int             ExitCode_Trend    = 90;                // 趨勢反轉退出碼 (<=0 停用)
extern int             Cooldown_Seconds  = 3600;              // 退出後的冷卻秒數

extern string          _Restart_Settings_= "=== 自動重啟設定 ===";
extern bool            Enable_AutoRestart = false;             // 啟用每日定時重啟
extern int             RestartHour        = 0;                // 重啟小時
extern int             RestartMinute      = 15;               // 重啟分鐘
extern TimeMode        TimeBasis          = LOCAL_TIME  ;      // 時間基準
extern int             MinDelayMinutes    = 1;                // 隨機延遲最小(分)
extern int             MaxDelayMinutes    = 15;               // 隨機延遲最大(分)
extern int             ExitCode_Restart   = 99;               // 定時重啟退出碼

//--- 內部緩衝區與變數
double ExtMapBuffer1[],ExtMapBuffer2[],ExtMapBuffer3[],ExtMapBuffer4[],ExtMapBuffer5[],ExtMapBuffer6[],ExtMapBuffer7[],ExtMapBuffer8[],trend[],count[];
string indicatorFileName;
string GV_PREFIX, GV_LAST_EXIT_TIME, GV_LAST_TREND, GV_RESTART_DATE, GV_RESTART_DELAY;

#define _mtfCall(_buff,_ind) iCustom(NULL,TimeFrame,indicatorFileName,PERIOD_CURRENT,MaMetod,MaPeriod,MaMetod2,MaPeriod2,Interpolate,Enable_TrendExit,ExitCode_Trend,Cooldown_Seconds,Enable_AutoRestart,RestartHour,RestartMinute,TimeBasis,MinDelayMinutes,MaxDelayMinutes,ExitCode_Restart,_buff,_ind)

//+------------------------------------------------------------------+
//| 初始化函數                                                       |
//+------------------------------------------------------------------+
int init()
  {
   IndicatorBuffers(10);
   SetIndexBuffer(0,ExtMapBuffer1);
   SetIndexStyle(0,DRAW_HISTOGRAM);
   SetIndexBuffer(1,ExtMapBuffer2);
   SetIndexStyle(1,DRAW_HISTOGRAM);
   SetIndexBuffer(2,ExtMapBuffer3);
   SetIndexStyle(2,DRAW_HISTOGRAM);
   SetIndexBuffer(3,ExtMapBuffer4);
   SetIndexStyle(3,DRAW_HISTOGRAM);
   SetIndexBuffer(4,ExtMapBuffer5);
   SetIndexBuffer(5,ExtMapBuffer6);
   SetIndexBuffer(6,ExtMapBuffer7);
   SetIndexBuffer(7,ExtMapBuffer8);
   SetIndexBuffer(8,trend);
   SetIndexBuffer(9,count);

   indicatorFileName = WindowExpertName();
   TimeFrame         = (ENUM_TIMEFRAMES)fmax(TimeFrame,_Period);

// 初始化全域變數名稱 (與 ATR 版本機制相同)
   GV_PREFIX         = StringFormat("HA_V3_EXIT_%s_%d_", Symbol(), _Period);
   GV_LAST_EXIT_TIME = GV_PREFIX + "TIME";
   GV_LAST_TREND     = GV_PREFIX + "TREND";
   GV_RESTART_DATE   = GV_PREFIX + "RESTART_DATE";
   GV_RESTART_DELAY  = GV_PREFIX + "RESTART_DELAY";

   if(!GlobalVariableCheck(GV_LAST_TREND))
      GlobalVariableSet(GV_LAST_TREND, 0);

   if(Enable_AutoRestart)
      EventSetTimer(60);

   return(0);
  }

//+------------------------------------------------------------------+
//| 反初始化函數                                                     |
//+------------------------------------------------------------------+
int deinit() { EventKillTimer(); return(0); }

//+------------------------------------------------------------------+
//| 主計算函數 (維持 Andy 的 Heiken Ashi 演算法)                     |
//+------------------------------------------------------------------+
int start()
  {
   int i,counted_bars=IndicatorCounted();
   if(counted_bars<0)
      return(-1);
   if(counted_bars>0)
      counted_bars--;
   int limit = (int)fmin(Bars-counted_bars,Bars-1);
   count[0]=limit;

//--- MTF 處理 (維持原版)
   if(TimeFrame!=_Period)
     {
      limit = (int)fmax(limit,fmin(Bars-1,_mtfCall(9,0)*TimeFrame/_Period));
      for(i=limit; i>=0 && !_StopFlag; i--)
        {
         int y = iBarShift(NULL,TimeFrame,Time[i]);
         ExtMapBuffer1[i] = _mtfCall(0,y);
         ExtMapBuffer2[i] = _mtfCall(1,y);
         ExtMapBuffer3[i] = _mtfCall(2,y);
         ExtMapBuffer4[i] = _mtfCall(3,y);

         if(!Interpolate || (i>0 && y==iBarShift(NULL,TimeFrame,Time[i-1])))
            continue;
#define _interpolate(buff) buff[i+k] = buff[i]+(buff[i+n]-buff[i])*k/n
         int n,k;
         datetime time = iTime(NULL,TimeFrame,y);
         for(n = 1; (i+n)<Bars && Time[i+n] >= time; n++)
            continue;
         for(k = 1; k<n && (i+n)<Bars && (i+k)<Bars; k++)
           {
            _interpolate(ExtMapBuffer1);
            _interpolate(ExtMapBuffer2);
            _interpolate(ExtMapBuffer3);
            _interpolate(ExtMapBuffer4);
           }
        }
      return(0);
     }

//--- 本地計算：Andy 的 Heiken Ashi 演算法核心 (不可更動)
   for(int pos=limit; pos >= 0; pos--)
     {
      double maOpen  = iCustomMa(MaMetod,Open[pos], MaPeriod,pos,0);
      double maClose = iCustomMa(MaMetod,Close[pos],MaPeriod,pos,1);
      double maLow   = iCustomMa(MaMetod,Low[pos],  MaPeriod,pos,2);
      double maHigh  = iCustomMa(MaMetod,High[pos], MaPeriod,pos,3);

      double haOpen  = maOpen;
      if(pos<Bars-1)
         haOpen  = (ExtMapBuffer5[pos+1]+ExtMapBuffer6[pos+1])/2;
      double haClose = (maOpen+maHigh+maLow+maClose)/4;
      double haHigh  = fmax(maHigh,fmax(haOpen, haClose));
      double haLow   = fmin(maLow, fmin(haOpen, haClose));

      if(haOpen<haClose)
        {
         ExtMapBuffer7[pos]=haLow;
         ExtMapBuffer8[pos]=haHigh;
        }
      else
        {
         ExtMapBuffer7[pos]=haHigh;
         ExtMapBuffer8[pos]=haLow;
        }
      ExtMapBuffer5[pos]=haOpen;
      ExtMapBuffer6[pos]=haClose;

      ExtMapBuffer1[pos]=iCustomMa(MaMetod2,ExtMapBuffer7[pos],MaPeriod2,pos,4);
      ExtMapBuffer2[pos]=iCustomMa(MaMetod2,ExtMapBuffer8[pos],MaPeriod2,pos,5);
      ExtMapBuffer3[pos]=iCustomMa(MaMetod2,ExtMapBuffer5[pos],MaPeriod2,pos,6);
      ExtMapBuffer4[pos]=iCustomMa(MaMetod2,ExtMapBuffer6[pos],MaPeriod2,pos,7);

      // 趨勢判定：1 = 多 (藍), -1 = 空 (紅)
      trend[pos] = (pos<Bars-1) ? (ExtMapBuffer3[pos]<ExtMapBuffer4[pos]) ? 1 : (ExtMapBuffer3[pos]>ExtMapBuffer4[pos]) ? -1 : trend[pos+1] : 0;
     }

//--- 導入：趨勢反轉觸發安全退出 (不使用任何 ATR)
   if(Enable_TrendExit && ExitCode_Trend > 0)
     {
      int currentTrend = (int)trend[1];
      int lastRecordedTrend = (int)GlobalVariableGet(GV_LAST_TREND);

      // 當趨勢發生明確的多空切換且非初始狀態
      if(currentTrend != 0 && lastRecordedTrend != 0 && currentTrend != lastRecordedTrend)
        {
         // 檢查退出冷卻時間
         datetime lastExitTime = (datetime)GlobalVariableGet(GV_LAST_EXIT_TIME);
         if(TimeCurrent() - lastExitTime >= Cooldown_Seconds)
           {
            GlobalVariableSet(GV_LAST_TREND, currentTrend); // 更新紀錄
            SafeShutdown(EXIT_TREND_CHANGE);
           }
        }

      // 若為初次啟動，同步趨勢狀態
      if(lastRecordedTrend == 0 && currentTrend != 0)
        {
         GlobalVariableSet(GV_LAST_TREND, currentTrend);
        }
     }

//--- 原版通知邏輯
   UpdateChartComment();
   return(0);
}

//+------------------------------------------------------------------+
//| 安全退出與自動重啟實作                                           |
//+------------------------------------------------------------------+
void SafeShutdown(ExitReason reason)
  {
   int code = (reason == EXIT_TREND_CHANGE) ? ExitCode_Trend : ExitCode_Restart;
   if(code <= 0)
      return;

   datetime now = TimeCurrent();
   GlobalVariableSet(GV_LAST_EXIT_TIME, (double)now);

   string msg = (reason == EXIT_TREND_CHANGE) ? "趨勢反轉退出" : "定時自動重啟";
   Print(StringFormat("【系統通知】%s, 執行退出代碼: %d", msg, code));
   Alert(StringFormat("系統即將關閉：%s", msg));

   Sleep(500);
   TerminalClose(code);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTimer()
  {
   if(!Enable_AutoRestart || ExitCode_Restart <= 0)
      return;

   datetime now = (TimeBasis == SERVER_TIME ? TimeCurrent() : TimeLocal());
   MqlDateTime t;
   TimeToStruct(now, t);

   int todayNum = t.year*10000 + t.mon*100 + t.day;
   int savedDate = (int)GlobalVariableGet(GV_RESTART_DATE);
   int delay_sec;

   if(savedDate != todayNum)
     {
      MathSrand((int)TimeLocal());
      delay_sec = (MinDelayMinutes + MathRand() % (MaxDelayMinutes - MinDelayMinutes + 1)) * 60;
      GlobalVariableSet(GV_RESTART_DELAY, delay_sec);
      GlobalVariableSet(GV_RESTART_DATE, todayNum);
     }
   else
      delay_sec = (int)GlobalVariableGet(GV_RESTART_DELAY);

   MqlDateTime targetStruct = t;
   targetStruct.hour = RestartHour;
   targetStruct.min = RestartMinute;
   targetStruct.sec = 0;
   datetime triggerTime = StructToTime(targetStruct) + delay_sec;

   if(now >= triggerTime && now < triggerTime + 300)
     {
      SafeShutdown(EXIT_AUTORESTART);
     }
  }

//+------------------------------------------------------------------+
//| MA 計算引擎實作 (與 0.2 版完全相同)                             |
//+------------------------------------------------------------------+
#define _maInstances 8
#define _maWorkBufferx1 8
#define _maWorkBufferx2 16
#define _maWorkBufferx3 24

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double iCustomMa(int mode, double price, double length, int r, int instanceNo=0)
  {
   int bars = Bars;
   r = bars-r-1;
   switch(mode)
     {
      case ma_sma:
         return(iSma(price,(int)length,r,bars,instanceNo));
      case ma_ema:
         return(iEma(price,length,r,bars,instanceNo));
      case ma_smma:
         return(iSmma(price,length,r,bars,instanceNo));
      case ma_lwma:
         return(iLwma(price,length,r,bars,instanceNo));
      case ma_tema:
         return(iTema(price,length,r,bars,instanceNo));
      case ma_hma:
         return(iHma(price,(int)length,r,bars,instanceNo));
      default:
         return(price);
     }
  }

double workSma[][_maWorkBufferx2];
double iSma(double price, int period, int r, int _bars, int instanceNo=0)
  {
   if(ArrayRange(workSma,0)!= _bars)
      ArrayResize(workSma,_bars);
   instanceNo *= 2;
   int k;
   workSma[r][instanceNo+0] = price;
   workSma[r][instanceNo+1] = price;
   for(k=1; k<period && (r-k)>=0; k++)
      workSma[r][instanceNo+1] += workSma[r-k][instanceNo+0];
   workSma[r][instanceNo+1] /= 1.0*k;
   return(workSma[r][instanceNo+1]);
  }

double workEma[][_maWorkBufferx1];
double iEma(double price, double period, int r, int _bars, int instanceNo=0)
  {
   if(ArrayRange(workEma,0)!= _bars)
      ArrayResize(workEma,_bars);
   workEma[r][instanceNo] = price;
   if(r>0 && period>1)
      workEma[r][instanceNo] = workEma[r-1][instanceNo]+(2.0/(1.0+period))*(price-workEma[r-1][instanceNo]);
   return(workEma[r][instanceNo]);
  }

double workSmma[][_maWorkBufferx1];
double iSmma(double price, double period, int r, int _bars, int instanceNo=0)
  {
   if(ArrayRange(workSmma,0)!= _bars)
      ArrayResize(workSmma,_bars);
   workSmma[r][instanceNo] = price;
   if(r>1 && period>1)
      workSmma[r][instanceNo] = workSmma[r-1][instanceNo]+(price-workSmma[r-1][instanceNo])/period;
   return(workSmma[r][instanceNo]);
  }

double workLwma[][_maWorkBufferx1];
double iLwma(double price, double period, int r, int _bars, int instanceNo=0)
  {
   if(ArrayRange(workLwma,0)!= _bars)
      ArrayResize(workLwma,_bars);
   workLwma[r][instanceNo] = price;
   if(period<=1)
      return(price);
   double sumw = period, sum = period*price;
   for(int k=1; k<period && (r-k)>=0; k++)
     {
      double weight = period-k;
      sumw += weight;
      sum += weight*workLwma[r-k][instanceNo];
     }
   return(sum/sumw);
  }

double workTema[][_maWorkBufferx3];
double iTema(double price, double period, int r, int bars, int instanceNo=0)
  {
   if(period<=1)
      return(price);
   if(ArrayRange(workTema,0)!= bars)
      ArrayResize(workTema,bars);
   instanceNo*=3;
   workTema[r][0+instanceNo] = price;
   workTema[r][1+instanceNo] = price;
   workTema[r][2+instanceNo] = price;
   double alpha = 2.0 / (1.0+period);
   if(r>0)
     {
      workTema[r][0+instanceNo] = workTema[r-1][0+instanceNo]+alpha*(price-workTema[r-1][0+instanceNo]);
      workTema[r][1+instanceNo] = workTema[r-1][1+instanceNo]+alpha*(workTema[r][0+instanceNo]-workTema[r-1][1+instanceNo]);
      workTema[r][2+instanceNo] = workTema[r-1][2+instanceNo]+alpha*(workTema[r][1+instanceNo]-workTema[r-1][2+instanceNo]);
     }
   return(workTema[r][2+instanceNo]+3.0*(workTema[r][0+instanceNo]-workTema[r][1+instanceNo]));
  }

double workHma[][16];
double iHma(double price, int period, int r, int _bars, int instanceNo=0)
  {
   if(ArrayRange(workHma,0)!= _bars)
      ArrayResize(workHma,_bars);
   if(period <= 1)
      return(price);
   int n = instanceNo * 2;
   double lwmaHalf = iLwmaHma(price, period / 2, r, _bars, n);
   double lwmaFull = iLwmaHma(price, period,     r, _bars, n + 1);
   double diff = 2.0 * lwmaHalf - lwmaFull;
   return(iLwmaHma(diff, (int)MathSqrt(period), r, _bars, n + 8));
  }

double workLwmaHma[][24];
double iLwmaHma(double price, double period, int r, int _bars, int instanceNo=0)
  {
   if(ArrayRange(workLwmaHma,0)!= _bars)
      ArrayResize(workLwmaHma,_bars);
   workLwmaHma[r][instanceNo] = price;
   if(period <= 1)
      return(price);
   double sumw = 0, sum = 0;
   for(int k = 0; k < (int)period && (r - k) >= 0; k++)
     {
      double w = period - k;
      sumw += w;
      sum += w * workLwmaHma[r - k][instanceNo];
     }
   return(sum / fmax(sumw, 1));
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void UpdateChartComment()
  {
   string trendStr = (trend[0] == 1) ? "多頭 (藍)" : (trend[0] == -1) ? "空頭 (紅)" : "判定中";
   Comment(StringFormat("【HA Smoothed V0.3】\n當前趨勢：%s\n時區：%s\n多空反轉退出：%s\n每日重啟時間：%02d:%02d",
                        trendStr, timeFrameToString(_Period), (Enable_TrendExit?"開啟":"關閉"), RestartHour, RestartMinute));
  }

string sTfTable[] = {"M1","M5","M15","M30","H1","H4","D1","W1","MN"};
int    iTfTable[] = {1,5,15,30,60,240,1440,10080,43200};
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string timeFrameToString(int tf)
  {
   for(int i=ArraySize(iTfTable)-1; i>=0; i--)
      if(tf==iTfTable[i])
         return(sTfTable[i]);
   return("");
  }
//+------------------------------------------------------------------+
