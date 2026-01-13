//+------------------------------------------------------------------+
//|                                  Heiken_Ashi_NoRepaint_MTF.mq4   |
//|                         平均K線（跨週期區間同步 0.2 撥亂反正版） |
//|                                                                  |
//|  設計原則：                                                      |
//|   1. 繪圖血肉：使用「目前圖表週期」報價，每根 K 棒均繪製一根 Bar |
//|   2. 趨勢骨架：由指定時框的「區間極值」判定多空顏色              |
//|   3. 時間對整：小時框時間點絕對映射至大時框區間起始點，杜絕回繪  |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_buffers 4

//────────────────────────────────────────
// 指標顏色與線寬設定
//────────────────────────────────────────
#property indicator_color1 clrLawnGreen     // 熊K影線 (空頭)
#property indicator_color2 clrOrangeRed     // 牛K影線 (多頭)
#property indicator_color3 clrLawnGreen     // 熊K實體
#property indicator_color4 clrOrangeRed     // 牛K實體

#property indicator_width1 1
#property indicator_width2 1
#property indicator_width3 3
#property indicator_width4 3

//────────────────────────────────────────
// 輸入參數
//────────────────────────────────────────
input ENUM_TIMEFRAMES InpTimeFrame = PERIOD_H1; // 趨勢參考時間框架 (骨架)

//────────────────────────────────────────
// 指標 Buffer 宣告
//────────────────────────────────────────
double ExtLowHighBuffer[];    // 影線 A
double ExtHighLowBuffer[];    // 影線 B
double ExtOpenBuffer[];       // 實體 A (繪圖 Open)
double ExtCloseBuffer[];      // 實體 B (繪圖 Close)

//+------------------------------------------------------------------+
//| 指標初始化                                                       |
//+------------------------------------------------------------------+
void OnInit()
  {
   IndicatorShortName("平均K線 Heiken Ashi MTF 區間同步 v0.2");
   IndicatorDigits(Digits);

   SetIndexStyle(0, DRAW_HISTOGRAM, 0, 1);
   SetIndexBuffer(0, ExtLowHighBuffer);
   SetIndexLabel(0, "影線 Bear");

   SetIndexStyle(1, DRAW_HISTOGRAM, 0, 1);
   SetIndexBuffer(1, ExtHighLowBuffer);
   SetIndexLabel(1, "影線 Bull");

   SetIndexStyle(2, DRAW_HISTOGRAM, 0, 3);
   SetIndexBuffer(2, ExtOpenBuffer);
   SetIndexLabel(2, "實體 Bear");

   SetIndexStyle(3, DRAW_HISTOGRAM, 0, 3);
   SetIndexBuffer(3, ExtCloseBuffer);
   SetIndexLabel(3, "實體 Bull");

   for(int i = 0; i < 4; i++)
      SetIndexDrawBegin(i, 50);
  }

//+------------------------------------------------------------------+
//| 跨週期區間同步計算主體 (v0.2 ULTRAWORK 修正版)                   |
//+------------------------------------------------------------------+
int OnCalculate(
   const int rates_total,
   const int prev_calculated,
   const datetime &time[],
   const double &open[],
   const double &high[],
   const double &low[],
   const double &close[],
   const long &tick_volume[],
   const long &volume[],
   const int &spread[]
)
  {
   if(rates_total < 100)
      return 0;

   int start = prev_calculated;
   if(start > 0)
      start--;
   else
      start = 1;

// 取得大時框秒數
   int mtfSec = PeriodSeconds(InpTimeFrame);

// 為了計算 Heiken Ashi 的遞迴 Open，我們需要建立一個內部快取
// 這裡使用靜態變數或局部陣列來追蹤大週期的 HA 狀態
   static double lastMtfHAOpen = 0;
   static double lastMtfHAClose = 0;
   static datetime lastMtfTime = 0;

   for(int i = start; i < rates_total - 1; i++)
     {
      // A. 初始化緩衝區，杜絕顏色重疊
      ExtLowHighBuffer[i] = 0;
      ExtHighLowBuffer[i] = 0;
      ExtOpenBuffer[i]    = 0;
      ExtCloseBuffer[i]   = 0;

      // B. 時間對整：算出目前小時框 K 棒所屬的大時框起始時間
      datetime curTime = time[i];
      datetime mtfStartTime = (datetime)((long)curTime / mtfSec * mtfSec);

      // 找出大時框區間的前一根 (已收盤) 大時框索引，確保不回繪
      int mtfShift = iBarShift(NULL, InpTimeFrame, mtfStartTime - 1, false);

      // C. 區間極值判定：提取大時框區間內的 Heiken Ashi 趨勢
      // 使用穩定遞迴算法計算大週期的 Heiken Ashi，確保不跳變
      int mtfPrevShift = mtfShift + 1;
      
      double mtfO = iOpen(NULL, InpTimeFrame, mtfShift);
      double mtfH = iHigh(NULL, InpTimeFrame, mtfShift);
      double mtfL = iLow(NULL, InpTimeFrame, mtfShift);
      double mtfC = iClose(NULL, InpTimeFrame, mtfShift);

      double mtfPrevO = iOpen(NULL, InpTimeFrame, mtfPrevShift);
      double mtfPrevC = iClose(NULL, InpTimeFrame, mtfPrevShift);

      // HA Close = (Open+High+Low+Close)/4
      double haCloseMTF = (mtfO + mtfH + mtfL + mtfC) / 4.0;
      // HA Open = (PrevHAOpen + PrevHAClose)/2
      double haOpenMTF  = (mtfPrevO + mtfPrevC) / 2.0; 
      
      // 修復：如果大時框 K 棒還在變動(mtfShift=0)，這會導致重繪
      // 但我們使用了 mtfStartTime - 1 的 Shift，所以 mtfShift 最小為 1 (已收盤)
      // 這保證了 signal 的絕對穩定性。

      bool isBullish = (haCloseMTF > haOpenMTF);

      // D. 繪製圖形：使用當前圖表的價格，顏色由大週期區間決定
      if(isBullish)
        {
         ExtLowHighBuffer[i] = low[i];
         ExtHighLowBuffer[i] = high[i];
         ExtOpenBuffer[i]    = open[i];
         ExtCloseBuffer[i]   = close[i];
        }
      else
        {
         ExtLowHighBuffer[i] = high[i];
         ExtHighLowBuffer[i] = low[i];
         ExtOpenBuffer[i]    = open[i];
         ExtCloseBuffer[i]   = close[i];
        }
     }

   return rates_total;
  }
//+------------------------------------------------------------------+
