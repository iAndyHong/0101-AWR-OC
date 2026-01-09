//+------------------------------------------------------------------+
//|                                                   MonitorEA.mq4 |
//|                              多專案監控 EA                        |
//+------------------------------------------------------------------+
#property copyright "Recovery System"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| 引入模組                                                         |
//+------------------------------------------------------------------+
#include "../Libs/UI/CChartPanelCanvas.mqh"
#include "../Libs/RecoveryProfit/CRecoveryProfit.mqh"

//+------------------------------------------------------------------+
//| 外部參數                                                         |
//+------------------------------------------------------------------+
sinput string  MON_Help0                 = "----------------";   // 監控設定
input string   MON_MonitorGroups         = "A,B";               // 監控組別（逗號分隔）
input int      MON_UpdateInterval        = 5;                   // 更新間隔（秒）
input int      MON_MagicNumber           = 16301;               // Monitor Magic

sinput string  MON_Help1                 = "----------------";   // UI 設定
input int      MON_PanelX                = 600;                 // 面板 X 位置
input int      MON_PanelY                = 30;                  // 面板 Y 位置
input color    MON_ProfitColor           = clrLime;             // 獲利顏色
input color    MON_LossColor             = clrRed;              // 虧損顏色

sinput string  MON_Help2                 = "----------------";   // 除錯設定
input ENUM_BOOL MON_ShowDebugLogs        = NO;                  // 除錯日誌

//+------------------------------------------------------------------+
//| ENUM_BOOL 定義                                                   |
//+------------------------------------------------------------------+
enum ENUM_BOOL
{
   NO = 0,
   YES = 1
};

//+------------------------------------------------------------------+
//| 全域變數                                                         |
//+------------------------------------------------------------------+
CChartPanelCanvas  g_monitorPanel;
string             g_groupList[];
int                g_groupCount;
datetime           g_lastUpdate;

//+------------------------------------------------------------------+
//| 解析監控組別                                                     |
//+------------------------------------------------------------------+
void ParseMonitorGroups()
{
   string groups = MON_MonitorGroups;
   g_groupCount = 0;
   
   while(StringFind(groups, ",") >= 0)
   {
      int pos = StringFind(groups, ",");
      string group = StringSubstr(groups, 0, pos);
      StringTrimLeft(group);
      StringTrimRight(group);
      
      if(group != "")
      {
         ArrayResize(g_groupList, g_groupCount + 1);
         g_groupList[g_groupCount] = group;
         g_groupCount++;
      }
      
      groups = StringSubstr(groups, pos + 1);
   }
   
   // 處理最後一個組別
   StringTrimLeft(groups);
   StringTrimRight(groups);
   if(groups != "")
   {
      ArrayResize(g_groupList, g_groupCount + 1);
      g_groupList[g_groupCount] = groups;
      g_groupCount++;
   }
}

//+------------------------------------------------------------------+
//| 取得組別統計資訊                                                 |
//+------------------------------------------------------------------+
string GetGroupStats(string groupId)
{
   int orders = 0;
   double profit = 0.0;
   double lots = 0.0;
   
   // 掃描所有訂單
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         // 根據 Magic Number 範圍判斷組別
         int magic = OrderMagicNumber();
         bool belongsToGroup = false;
         
         if(groupId == "A" && magic >= 16000 && magic <= 16099)
            belongsToGroup = true;
         else if(groupId == "B" && magic >= 16100 && magic <= 16199)
            belongsToGroup = true;
         // 可以繼續添加其他組別的判斷
         
         if(belongsToGroup && OrderSymbol() == Symbol())
         {
            orders++;
            profit += OrderProfit() + OrderSwap() + OrderCommission();
            lots += OrderLots();
         }
      }
   }
   
   // 取得累積獲利（從 GV）
   string gvName = "REC_" + groupId + "_AccProfit";
   double accProfit = GlobalVariableGet(gvName);
   
   // 格式化統計資訊
   string stats = "組別 " + groupId + ": ";
   stats += "訂單=" + IntegerToString(orders);
   stats += ", 手數=" + DoubleToString(lots, 2);
   stats += ", 浮動=" + DoubleToString(profit, 2);
   stats += ", 累積=" + DoubleToString(accProfit, 2);
   
   return stats;
}

//+------------------------------------------------------------------+
//| 更新監控面板                                                     |
//+------------------------------------------------------------------+
void UpdateMonitorPanel()
{
   if(TimeCurrent() - g_lastUpdate < MON_UpdateInterval)
      return;
   
   g_monitorPanel.SetLine("Title", "=== 多專案監控 ===", clrWhite);
   g_monitorPanel.SetLine("Time", "更新時間: " + TimeToString(TimeCurrent()), clrYellow);
   
   double totalFloating = 0.0;
   double totalAccumulated = 0.0;
   int totalOrders = 0;
   
   // 顯示各組別統計
   for(int i = 0; i < g_groupCount; i++)
   {
      string groupId = g_groupList[i];
      string stats = GetGroupStats(groupId);
      
      // 計算顏色
      string gvName = "REC_" + groupId + "_AccProfit";
      double accProfit = GlobalVariableGet(gvName);
      color lineColor = (accProfit >= 0) ? MON_ProfitColor : MON_LossColor;
      
      g_monitorPanel.SetLine("Group_" + groupId, stats, lineColor);
      
      totalAccumulated += accProfit;
   }
   
   // 顯示總計
   g_monitorPanel.SetLine("Separator", "------------------------", clrGray);
   color totalColor = (totalAccumulated >= 0) ? MON_ProfitColor : MON_LossColor;
   g_monitorPanel.SetLine("Total", "總累積獲利: " + DoubleToString(totalAccumulated, 2), totalColor);
   
   // 顯示系統狀態
   g_monitorPanel.SetLine("Status", "監控狀態: 正常運行", clrLime);
   
   g_monitorPanel.Update(true);
   g_lastUpdate = TimeCurrent();
}

//+------------------------------------------------------------------+
//| EA 初始化                                                        |
//+------------------------------------------------------------------+
int OnInit()
{
   ParseMonitorGroups();
   
   if(g_groupCount == 0)
   {
      Print("[MonitorEA] 沒有指定監控組別");
      return INIT_FAILED;
   }
   
   // 初始化監控面板
   g_monitorPanel.Init("MON_Panel_", MON_PanelX, MON_PanelY, MON_UpdateInterval);
   g_monitorPanel.SetSystemInfo("多專案監控", Symbol());
   
   g_lastUpdate = 0;
   
   Print("[MonitorEA] 初始化完成，監控組別: ", MON_MonitorGroups);
   Print("[MonitorEA] 監控組別數量: ", g_groupCount);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| EA 主循環                                                        |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdateMonitorPanel();
}

//+------------------------------------------------------------------+
//| EA 反初始化                                                      |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   g_monitorPanel.Deinit();
   Print("[MonitorEA] 監控已停止");
}

//+------------------------------------------------------------------+
//| 圖表事件                                                         |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam)
{
   if(id == CHARTEVENT_KEYDOWN && lparam == 46) // Delete 鍵
   {
      g_monitorPanel.Cleanup();
      Print("[MonitorEA] 已清理監控面板");
   }
}