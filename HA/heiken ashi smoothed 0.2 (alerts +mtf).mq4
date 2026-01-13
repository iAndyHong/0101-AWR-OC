//+------------------------------------------------------------------+
//|                               heiken ashi smoothed 0.2 MTF_CN.mq4|
//|                         平滑平均K線（跨週期繁體中文化版本）      |
//|                                                                  |
//|  設計原則：                                                      |
//|   1. 顏色互換：多頭呈現紅色，空頭呈現綠色 (對標您的設計稿)       |
//|   2. 全中文化：所有外部參數、日誌、註解均轉換為繁體中文          |
//|   3. 跨週期支援：支援多時框運算與平滑處理                        |
//+------------------------------------------------------------------+
#property copyright "www.forex-station.com"
#property link      "www.forex-station.com"
#property version   "0.20"

#property indicator_chart_window
#property indicator_buffers 8

//────────────────────────────────────────
// 指標顏色設定 (紅正綠負，8個緩衝區配置)
//────────────────────────────────────────
#property indicator_color1  clrOrangeRed    // 多頭影線 A
#property indicator_color2  clrOrangeRed    // 多頭影線 B
#property indicator_color3  clrOrangeRed    // 多頭實體 A
#property indicator_color4  clrOrangeRed    // 多頭實體 B
#property indicator_color5  clrLawnGreen     // 空頭影線 A
#property indicator_color6  clrLawnGreen     // 空頭影線 B
#property indicator_color7  clrLawnGreen     // 空頭實體 A
#property indicator_color8  clrLawnGreen     // 空頭實體 B

#property indicator_width1  1
#property indicator_width2  1
#property indicator_width3  3
#property indicator_width4  3
#property indicator_width5  1
#property indicator_width6  1
#property indicator_width7  3
#property indicator_width8  3
#property strict

//────────────────────────────────────────
// 枚舉定義
//────────────────────────────────────────
enum enMaTypes
  {
   ma_sma,    // 簡單移動平均 (SMA)
   ma_ema,    // 指數移動平均 (EMA)
   ma_smma,   // 平滑移動平均 (SMMA)
   ma_lwma,   // 線性加權移動平均 (LWMA)
   ma_tema,   // 三重指數移動平均 (TEMA)
   ma_hma     // 赫爾移動平均 (HMA)
  };

//────────────────────────────────────────
// 輸入參數 (已中文化並對齊)
//────────────────────────────────────────
extern ENUM_TIMEFRAMES TimeFrame        = PERIOD_CURRENT;    // 運算時間週期
extern enMaTypes       MaMetod          = ma_ema;            // 第一平滑模式 (MA1)
extern int             MaPeriod         = 6;                 // 第一平滑週期
extern enMaTypes       MaMetod2         = ma_lwma;           // 第二平滑模式 (MA2)
extern int             MaPeriod2        = 2;                 // 第二平滑週期
extern bool            alertsOn         = true;              // 開啟警報功能
extern bool            alertsOnCurrent  = false;             // 是否針對未收盤 K 棒警報
extern bool            alertsMessage    = true;              // 顯示彈出視窗訊息
extern bool            alertsSound      = false;             // 播放警報音效
extern bool            alertsNotify     = false;             // 發送手機推送通知
extern bool            alertsEmail      = false;             // 發送電子郵件通知
extern string          soundFile        = "alert2.wav";      // 警報音效檔名
extern bool            Interpolate      = true;              // 跨週期模式下是否執行平滑插值

//────────────────────────────────────────
// 全域緩衝區與變數
//────────────────────────────────────────
double ExtMapBuffer1[],ExtMapBuffer2[],ExtMapBuffer3[],ExtMapBuffer4[],ExtMapBuffer5[],ExtMapBuffer6[],ExtMapBuffer7[],ExtMapBuffer8[];
double ExtMapBuffer9[],ExtMapBuffer10[],ExtMapBuffer11[],ExtMapBuffer12[],trend[],count[];
string indicatorFileName;

// 跨週期調用宏定義 (同步 8 個繪圖緩衝區)
#define _mtfCall(_buff,_ind) iCustom(NULL,TimeFrame,indicatorFileName,PERIOD_CURRENT,MaMetod,MaPeriod,MaMetod2,MaPeriod2,alertsOn,alertsOnCurrent,alertsMessage,alertsSound,alertsNotify,alertsEmail,soundFile,_buff,_ind)

//+------------------------------------------------------------------+
//| 指標初始化                                                       |
//+------------------------------------------------------------------+
int init()
  {
   // 設定指標緩衝區數量 (8繪圖 + 4計算 + 1趨勢 + 1計數 = 14)
   IndicatorBuffers(14);
   
   // 繪圖緩衝區綁定 (配對直方圖：0-1, 2-3 為多頭；4-5, 6-7 為空頭)
   SetIndexBuffer(0, ExtMapBuffer1); SetIndexStyle(0, DRAW_HISTOGRAM); SetIndexLabel(0, "多頭影線 (Low)");
   SetIndexBuffer(1, ExtMapBuffer2); SetIndexStyle(1, DRAW_HISTOGRAM); SetIndexLabel(1, "多頭影線 (High)");
   SetIndexBuffer(2, ExtMapBuffer3); SetIndexStyle(2, DRAW_HISTOGRAM); SetIndexLabel(2, "多頭實體 (Open)");
   SetIndexBuffer(3, ExtMapBuffer4); SetIndexStyle(3, DRAW_HISTOGRAM); SetIndexLabel(3, "多頭實體 (Close)");
   
   SetIndexBuffer(4, ExtMapBuffer5); SetIndexStyle(4, DRAW_HISTOGRAM); SetIndexLabel(4, "空頭影線 (Low)");
   SetIndexBuffer(5, ExtMapBuffer6); SetIndexStyle(5, DRAW_HISTOGRAM); SetIndexLabel(5, "空頭影線 (High)");
   SetIndexBuffer(6, ExtMapBuffer7); SetIndexStyle(6, DRAW_HISTOGRAM); SetIndexLabel(6, "空頭實體 (Open)");
   SetIndexBuffer(7, ExtMapBuffer8); SetIndexStyle(7, DRAW_HISTOGRAM); SetIndexLabel(7, "空頭實體 (Close)");
   
   // 計算用緩衝區 (隱藏)
   SetIndexBuffer(8,  ExtMapBuffer9);
   SetIndexBuffer(9,  ExtMapBuffer10);
   SetIndexBuffer(10, ExtMapBuffer11);
   SetIndexBuffer(11, ExtMapBuffer12);
   SetIndexBuffer(12, trend);
   SetIndexBuffer(13, count);

   indicatorFileName = WindowExpertName();
   TimeFrame         = (ENUM_TIMEFRAMES)fmax(TimeFrame, _Period);
   
   return(0);
  }

//+------------------------------------------------------------------+
//| 指標反初始化                                                     |
//+------------------------------------------------------------------+
int deinit() { return(0); }

//+------------------------------------------------------------------+
//| 指標主計算程序                                                   |
//+------------------------------------------------------------------+
int start()
  {
   int i, counted_bars = IndicatorCounted();
   if(counted_bars < 0) return(-1);
   if(counted_bars > 0) counted_bars--;
   
   int limit = (int)fmin(Bars - counted_bars, Bars - 1);
   count[0] = (double)limit;

    // --- 處理跨週期數據同步 ---
    if(TimeFrame != _Period)
      {
       limit = (int)fmax(limit, fmin(Bars - 1, (int)(_mtfCall(13, 0) * TimeFrame / _Period)));
       for(i = limit; i >= 0 && !_StopFlag; i--)
         {
          int y = iBarShift(NULL, TimeFrame, Time[i]);
          ExtMapBuffer1[i] = _mtfCall(0, y);
          ExtMapBuffer2[i] = _mtfCall(1, y);
          ExtMapBuffer3[i] = _mtfCall(2, y);
          ExtMapBuffer4[i] = _mtfCall(3, y);
          ExtMapBuffer5[i] = _mtfCall(4, y);
          ExtMapBuffer6[i] = _mtfCall(5, y);
          ExtMapBuffer7[i] = _mtfCall(6, y);
          ExtMapBuffer8[i] = _mtfCall(7, y);

          // 如果開啟插值處理
          if(!Interpolate || (i > 0 && y == iBarShift(NULL, TimeFrame, Time[i - 1]))) continue;
          
          int n, k;
          datetime timeVal = iTime(NULL, TimeFrame, y);
          for(n = 1; (i + n) < Bars && Time[i + n] >= timeVal; n++) continue;
          for(k = 1; k < n && (i + n) < Bars && (i + k) < Bars; k++)
            {
             double fact = (double)k / n;
             ExtMapBuffer1[i+k] = ExtMapBuffer1[i] + (ExtMapBuffer1[i+n] - ExtMapBuffer1[i]) * fact;
             ExtMapBuffer2[i+k] = ExtMapBuffer2[i] + (ExtMapBuffer2[i+n] - ExtMapBuffer2[i]) * fact;
             ExtMapBuffer3[i+k] = ExtMapBuffer3[i] + (ExtMapBuffer3[i+n] - ExtMapBuffer3[i]) * fact;
             ExtMapBuffer4[i+k] = ExtMapBuffer4[i] + (ExtMapBuffer4[i+n] - ExtMapBuffer4[i]) * fact;
             ExtMapBuffer5[i+k] = ExtMapBuffer5[i] + (ExtMapBuffer5[i+n] - ExtMapBuffer5[i]) * fact;
             ExtMapBuffer6[i+k] = ExtMapBuffer6[i] + (ExtMapBuffer6[i+n] - ExtMapBuffer6[i]) * fact;
             ExtMapBuffer7[i+k] = ExtMapBuffer7[i] + (ExtMapBuffer7[i+n] - ExtMapBuffer7[i]) * fact;
             ExtMapBuffer8[i+k] = ExtMapBuffer8[i] + (ExtMapBuffer8[i+n] - ExtMapBuffer8[i]) * fact;
            }
         }
       return(0);
      }

    // --- 正常週期運算邏輯 ---
    for(int pos = limit; pos >= 0; pos--)
      {
       // 執行第一階段平滑 (MA1)
       double maOpen  = iCustomMa(MaMetod,  Open[pos],  MaPeriod, pos, 0);
       double maClose = iCustomMa(MaMetod,  Close[pos], MaPeriod, pos, 1);
       double maLow   = iCustomMa(MaMetod,  Low[pos],   MaPeriod, pos, 2);
       double maHigh  = iCustomMa(MaMetod,  High[pos],  MaPeriod, pos, 3);

       // 計算 Heiken Ashi 數值
       double haOpen = maOpen;
       if(pos < Bars - 1) 
          haOpen = (ExtMapBuffer9[pos + 1] + ExtMapBuffer10[pos + 1]) / 2.0;
          
       double haClose = (maOpen + maHigh + maLow + maClose) / 4.0;
       double haHigh  = fmax(maHigh, fmax(haOpen, haClose));
       double haLow   = fmin(maLow,  fmin(haOpen, haClose));

       // 存入初步計算緩衝區 (中間層)
       if(haOpen < haClose)
         {
          ExtMapBuffer11[pos] = haLow;
          ExtMapBuffer12[pos] = haHigh;
         }
       else
         {
          ExtMapBuffer11[pos] = haHigh;
          ExtMapBuffer12[pos] = haLow;
         }
       ExtMapBuffer9[pos]  = haOpen;
       ExtMapBuffer10[pos] = haClose;

       // 執行第二階段平滑 (MA2) 並填充最終數據
       double smLow   = iCustomMa(MaMetod2, ExtMapBuffer11[pos], MaPeriod2, pos, 4);
       double smHigh  = iCustomMa(MaMetod2, ExtMapBuffer12[pos], MaPeriod2, pos, 5);
       double smOpen  = iCustomMa(MaMetod2, ExtMapBuffer9[pos],  MaPeriod2, pos, 6);
       double smClose = iCustomMa(MaMetod2, ExtMapBuffer10[pos], MaPeriod2, pos, 7);
       
       // 更新趨勢狀態
       trend[pos] = (pos < Bars - 1) ? (smOpen < smClose ? 1 : (smOpen > smClose ? -1 : trend[pos + 1])) : 0;
       
       // 填充繪圖緩衝區
       // 0-3 作為基準 (多頭紅色)
       ExtMapBuffer1[pos] = smLow;
       ExtMapBuffer2[pos] = smHigh;
       ExtMapBuffer3[pos] = smOpen;
       ExtMapBuffer4[pos] = smClose;
       
       if(trend[pos] == -1) // 空頭 (綠色疊加)
         {
          ExtMapBuffer5[pos] = smLow;
          ExtMapBuffer6[pos] = smHigh;
          ExtMapBuffer7[pos] = smOpen;
          ExtMapBuffer8[pos] = smClose;
         }
       else // 多頭 (清空空頭緩衝區)
         {
          ExtMapBuffer5[pos] = EMPTY_VALUE;
          ExtMapBuffer6[pos] = EMPTY_VALUE;
          ExtMapBuffer7[pos] = EMPTY_VALUE;
          ExtMapBuffer8[pos] = EMPTY_VALUE;
         }
      }

   // --- 觸發警報邏輯 ---
   if(alertsOn)
     {
      int whichBar = 1;
      if(alertsOnCurrent) whichBar = 0;
      if(trend[whichBar] != trend[whichBar + 1])
        {
         if(trend[whichBar] == 1) doAlert("多頭趨勢反轉 (向上)");
         else doAlert("空頭趨勢反轉 (向下)");
        }
     }
     
   return(0);
  }

//+------------------------------------------------------------------+
//| 核心平滑演算法調度                                               |
//+------------------------------------------------------------------+
double iCustomMa(int mode, double price, double length, int r, int instanceNo = 0)
  {
   int bars = Bars;
   r = bars - r - 1;
   switch(mode)
     {
      case ma_sma:   return(iSma(price, (int)length, r, bars, instanceNo));
      case ma_ema:   return(iEma(price, length, r, bars, instanceNo));
      case ma_smma:  return(iSmma(price, (int)length, r, bars, instanceNo));
      case ma_lwma:  return(iLwma(price, length, r, bars, instanceNo));
      case ma_tema:  return(iTema(price, (int)length, r, bars, instanceNo));
      case ma_hma:   return(iHma(price, (int)length, r, bars, instanceNo));
      default:       return(price);
     }
  }

// --- 以下為各類 MA 的具體內部實作 ---
double workSma[][8];
double iSma(double price, int period, int r, int _bars, int instanceNo = 0)
  {
   if(ArrayRange(workSma, 0) != _bars) ArrayResize(workSma, _bars);
   int k; workSma[r][instanceNo] = price;
   double sum = 0;
   for(k = 0; k < period && (r - k) >= 0; k++) sum += workSma[r - k][instanceNo];
   return(sum / fmax(k, 1));
  }

double workEma[][8];
double iEma(double price, double period, int r, int _bars, int instanceNo = 0)
  {
   if(ArrayRange(workEma, 0) != _bars) ArrayResize(workEma, _bars);
   workEma[r][instanceNo] = price;
   if(r > 0 && period > 1) workEma[r][instanceNo] = workEma[r - 1][instanceNo] + (2.0 / (1.0 + period)) * (price - workEma[r - 1][instanceNo]);
   return(workEma[r][instanceNo]);
  }

double workSmma[][8];
double iSmma(double price, double period, int r, int _bars, int instanceNo = 0)
  {
   if(ArrayRange(workSmma, 0) != _bars) ArrayResize(workSmma, _bars);
   workSmma[r][instanceNo] = price;
   if(r > 0 && period > 1) workSmma[r][instanceNo] = workSmma[r - 1][instanceNo] + (price - workSmma[r - 1][instanceNo]) / period;
   return(workSmma[r][instanceNo]);
  }

double workLwma[][8];
double iLwma(double price, double period, int r, int _bars, int instanceNo = 0)
  {
   if(ArrayRange(workLwma, 0) != _bars) ArrayResize(workLwma, _bars);
   workLwma[r][instanceNo] = price;
   if(period <= 1) return(price);
   double sumw = 0, sum = 0;
   for(int k = 0; k < (int)period && (r - k) >= 0; k++) { double w = period - k; sumw += w; sum += w * workLwma[r - k][instanceNo]; }
   return(sum / fmax(sumw, 1));
  }

double workTema[][24];
double iTema(double price, double period, int r, int _bars, int instanceNo = 0)
  {
   if(ArrayRange(workTema, 0) != _bars) ArrayResize(workTema, _bars);
   int n = instanceNo * 3;
   double alpha = 2.0 / (1.0 + period);
   workTema[r][n] = price; workTema[r][n+1] = price; workTema[r][n+2] = price;
   if(r > 0)
     {
      workTema[r][n]   = workTema[r-1][n]   + alpha * (price - workTema[r-1][n]);
      workTema[r][n+1] = workTema[r-1][n+1] + alpha * (workTema[r][n]   - workTema[r-1][n+1]);
      workTema[r][n+2] = workTema[r-1][n+2] + alpha * (workTema[r][n+1] - workTema[r-1][n+2]);
      }
    return(workTema[r][n+2] + 3.0 * (workTema[r][n] - workTema[r][n+1]));
  }

double workHma[][16]; // 需要較多空間存放內部 LWMA 狀態
double iHma(double price, int period, int r, int _bars, int instanceNo = 0)
  {
   if(ArrayRange(workHma, 0) != _bars) ArrayResize(workHma, _bars);
   if(period <= 1) return(price);

   int n = instanceNo * 2;
   // HMA 公式: LWMA(2*LWMA(Price, n/2) - LWMA(Price, n), sqrt(n))
   double lwmaHalf = iLwmaHma(price, period / 2, r, _bars, n);
   double lwmaFull = iLwmaHma(price, period,     r, _bars, n + 1);
   
   double diff = 2.0 * lwmaHalf - lwmaFull;
   return(iLwmaHma(diff, (int)MathSqrt(period), r, _bars, n + 8)); // 使用偏移避免衝突
  }

double workLwmaHma[][24];
double iLwmaHma(double price, double period, int r, int _bars, int instanceNo = 0)
  {
   if(ArrayRange(workLwmaHma, 0) != _bars) ArrayResize(workLwmaHma, _bars);
   workLwmaHma[r][instanceNo] = price;
   if(period <= 1) return(price);
   double sumw = 0, sum = 0;
   for(int k = 0; k < (int)period && (r - k) >= 0; k++) { double w = period - k; sumw += w; sum += w * workLwmaHma[r - k][instanceNo]; }
   return(sum / fmax(sumw, 1));
  }

//+------------------------------------------------------------------+
//| 系統警報發送                                                     |
//+------------------------------------------------------------------+
void doAlert(string doWhat)
  {
   static string  previousAlert = "nothing";
   static datetime previousTime;
   if(previousAlert != doWhat || previousTime != Time[0])
     {
      previousAlert = doWhat; previousTime = Time[0];
      string message = StringConcatenate(Symbol(), " ", timeFrameToString(_Period), " 於 ", TimeToStr(TimeLocal(), TIME_SECONDS), " 平滑平均K線: ", doWhat);
      if(alertsMessage) Alert(message);
      if(alertsNotify)  SendNotification(message);
      if(alertsEmail)   SendMail(StringConcatenate(Symbol(), " 平滑平均K線"), message);
      if(alertsSound)   PlaySound(soundFile);
     }
  }

string timeFrameToString(int tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return("M1");
      case PERIOD_M5:  return("M5");
      case PERIOD_M15: return("M15");
      case PERIOD_M30: return("M30");
      case PERIOD_H1:  return("H1");
      case PERIOD_H4:  return("H4");
      case PERIOD_D1:  return("D1");
      case PERIOD_W1:  return("W1");
      case PERIOD_MN1: return("MN");
      default:         return("");
     }
  }
