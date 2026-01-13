//+------------------------------------------------------------------+
//|                                                  CTradeUtils.mqh |
//|                              交易工具函數模組                     |
//+------------------------------------------------------------------+
//| 【模組說明 - 供 Kiro AI 讀取】                                    |
//|                                                                   |
//| 功能：提供交易相關的靜態工具函數                                   |
//|                                                                   |
//| 主要方法（靜態）：                                                |
//|   - ValidateLotSize()  驗證並調整手數                             |
//|   - NormalizePrice()   標準化價格                                 |
//|   - PointsToPrice()    點數轉價格差                               |
//|   - PriceToPoints()    價格差轉點數                               |
//|   - GetPointValue()    取得點值                                   |
//|   - IsNewBar()         檢查是否為新 K 棒                          |
//|                                                                   |
//| 引用方式：#include "../Libs/TradeCore/CTradeUtils.mqh"            |
//+------------------------------------------------------------------+

#ifndef CTRADEUTILS_MQH
#define CTRADEUTILS_MQH

//+------------------------------------------------------------------+
//| 交易工具類別（靜態方法）                                          |
//+------------------------------------------------------------------+
class CTradeUtils
{
private:
   static datetime    s_lastBarTime;

public:
   //--- 手數相關
   static double      ValidateLotSize(double lots, string symbol = "");
   static double      GetMinLot(string symbol = "");
   static double      GetMaxLot(string symbol = "");
   static double      GetLotStep(string symbol = "");

   //--- 價格相關
   static double      NormalizePrice(double price, string symbol = "");
   static int         GetDigits(string symbol = "");

   //--- 點數轉換
   static double      GetPointValue(string symbol = "");
   static double      PointsToPrice(double points, string symbol = "");
   static double      PriceToPoints(double priceDiff, string symbol = "");

   //--- 市場資訊
   static double      GetSpread(string symbol = "");
   static double      GetAsk(string symbol = "");
   static double      GetBid(string symbol = "");

   //--- K 棒相關
   static bool        IsNewBar(string symbol = "", int timeframe = 0);
   static datetime    GetBarTime(string symbol = "", int timeframe = 0, int shift = 0);

   //--- 錯誤處理
   static string      GetErrorDescription(int errorCode);
   static bool        IsRetryableError(int errorCode);
};

// 靜態變數初始化
datetime CTradeUtils::s_lastBarTime = 0;

//+------------------------------------------------------------------+
//| 驗證手數                                                          |
//+------------------------------------------------------------------+
double CTradeUtils::ValidateLotSize(double lots, string symbol = "")
{
   if(symbol == "") symbol = Symbol();

   double minLot = MarketInfo(symbol, MODE_MINLOT);
   double maxLot = MarketInfo(symbol, MODE_MAXLOT);
   double lotStep = MarketInfo(symbol, MODE_LOTSTEP);

   // 調整到合法的手數步長
   lots = MathFloor(lots / lotStep) * lotStep;

   // 確保在允許範圍內
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;

   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| 取得最小手數                                                      |
//+------------------------------------------------------------------+
double CTradeUtils::GetMinLot(string symbol = "")
{
   if(symbol == "") symbol = Symbol();
   return MarketInfo(symbol, MODE_MINLOT);
}

//+------------------------------------------------------------------+
//| 取得最大手數                                                      |
//+------------------------------------------------------------------+
double CTradeUtils::GetMaxLot(string symbol = "")
{
   if(symbol == "") symbol = Symbol();
   return MarketInfo(symbol, MODE_MAXLOT);
}

//+------------------------------------------------------------------+
//| 取得手數步長                                                      |
//+------------------------------------------------------------------+
double CTradeUtils::GetLotStep(string symbol = "")
{
   if(symbol == "") symbol = Symbol();
   return MarketInfo(symbol, MODE_LOTSTEP);
}

//+------------------------------------------------------------------+
//| 標準化價格                                                        |
//+------------------------------------------------------------------+
double CTradeUtils::NormalizePrice(double price, string symbol = "")
{
   if(symbol == "") symbol = Symbol();
   int digits = (int)MarketInfo(symbol, MODE_DIGITS);
   return NormalizeDouble(price, digits);
}

//+------------------------------------------------------------------+
//| 取得小數位數                                                      |
//+------------------------------------------------------------------+
int CTradeUtils::GetDigits(string symbol = "")
{
   if(symbol == "") symbol = Symbol();
   return (int)MarketInfo(symbol, MODE_DIGITS);
}

//+------------------------------------------------------------------+
//| 取得點值                                                          |
//+------------------------------------------------------------------+
double CTradeUtils::GetPointValue(string symbol = "")
{
   if(symbol == "") symbol = Symbol();
   return MarketInfo(symbol, MODE_POINT);
}

//+------------------------------------------------------------------+
//| 點數轉價格差                                                      |
//+------------------------------------------------------------------+
double CTradeUtils::PointsToPrice(double points, string symbol = "")
{
   if(symbol == "") symbol = Symbol();
   double pointValue = MarketInfo(symbol, MODE_POINT);
   int digits = (int)MarketInfo(symbol, MODE_DIGITS);

   // 處理 5 位數報價
   if(digits == 5 || digits == 3)
      pointValue *= 10;

   return points * pointValue;
}

//+------------------------------------------------------------------+
//| 價格差轉點數                                                      |
//+------------------------------------------------------------------+
double CTradeUtils::PriceToPoints(double priceDiff, string symbol = "")
{
   if(symbol == "") symbol = Symbol();
   double pointValue = MarketInfo(symbol, MODE_POINT);
   int digits = (int)MarketInfo(symbol, MODE_DIGITS);

   // 處理 5 位數報價
   if(digits == 5 || digits == 3)
      pointValue *= 10;

   if(pointValue <= 0)
      return 0.0;

   return priceDiff / pointValue;
}

//+------------------------------------------------------------------+
//| 取得點差                                                          |
//+------------------------------------------------------------------+
double CTradeUtils::GetSpread(string symbol = "")
{
   if(symbol == "") symbol = Symbol();
   return MarketInfo(symbol, MODE_SPREAD);
}

//+------------------------------------------------------------------+
//| 取得賣價                                                          |
//+------------------------------------------------------------------+
double CTradeUtils::GetAsk(string symbol = "")
{
   if(symbol == "") symbol = Symbol();
   return MarketInfo(symbol, MODE_ASK);
}

//+------------------------------------------------------------------+
//| 取得買價                                                          |
//+------------------------------------------------------------------+
double CTradeUtils::GetBid(string symbol = "")
{
   if(symbol == "") symbol = Symbol();
   return MarketInfo(symbol, MODE_BID);
}

//+------------------------------------------------------------------+
//| 檢查是否為新 K 棒                                                 |
//+------------------------------------------------------------------+
bool CTradeUtils::IsNewBar(string symbol = "", int timeframe = 0)
{
   if(symbol == "") symbol = Symbol();
   if(timeframe == 0) timeframe = Period();

   datetime currentBarTime = iTime(symbol, timeframe, 0);

   if(currentBarTime != s_lastBarTime)
   {
      s_lastBarTime = currentBarTime;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| 取得 K 棒時間                                                     |
//+------------------------------------------------------------------+
datetime CTradeUtils::GetBarTime(string symbol = "", int timeframe = 0, int shift = 0)
{
   if(symbol == "") symbol = Symbol();
   if(timeframe == 0) timeframe = Period();

   return iTime(symbol, timeframe, shift);
}

//+------------------------------------------------------------------+
//| 取得錯誤描述                                                      |
//+------------------------------------------------------------------+
string CTradeUtils::GetErrorDescription(int errorCode)
{
   switch(errorCode)
   {
      case 0:   return "無錯誤";
      case 1:   return "無錯誤，但結果未知";
      case 2:   return "一般錯誤";
      case 3:   return "無效的交易參數";
      case 4:   return "交易伺服器忙碌";
      case 5:   return "舊版客戶端";
      case 6:   return "無連線";
      case 7:   return "權限不足";
      case 8:   return "請求過於頻繁";
      case 64:  return "帳戶被禁用";
      case 65:  return "無效的帳戶";
      case 128: return "交易超時";
      case 129: return "無效的價格";
      case 130: return "無效的停損";
      case 131: return "無效的手數";
      case 132: return "市場已關閉";
      case 133: return "交易被禁用";
      case 134: return "資金不足";
      case 135: return "價格已改變";
      case 136: return "無報價";
      case 137: return "經紀商忙碌";
      case 138: return "重新報價";
      case 139: return "訂單被鎖定";
      case 140: return "只允許買入";
      case 141: return "請求過多";
      case 145: return "修改被禁止";
      case 146: return "交易上下文忙碌";
      case 147: return "到期日被禁止";
      case 148: return "訂單數量過多";
      case 149: return "對沖被禁止";
      case 150: return "違反 FIFO 規則";
      default:  return "未知錯誤 " + IntegerToString(errorCode);
   }
}

//+------------------------------------------------------------------+
//| 檢查是否為可重試的錯誤                                            |
//+------------------------------------------------------------------+
bool CTradeUtils::IsRetryableError(int errorCode)
{
   switch(errorCode)
   {
      case 4:   // 交易伺服器忙碌
      case 6:   // 無連線
      case 8:   // 請求過於頻繁
      case 128: // 交易超時
      case 135: // 價格已改變
      case 136: // 無報價
      case 137: // 經紀商忙碌
      case 138: // 重新報價
      case 146: // 交易上下文忙碌
         return true;
      default:
         return false;
   }
}

#endif // CTRADEUTILS_MQH
