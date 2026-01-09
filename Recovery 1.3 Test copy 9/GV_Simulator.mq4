//+------------------------------------------------------------------+
//|                                                 GV_Simulator.mq4 |
//|                        模擬 Grids EA 的 GV 通訊                   |
//|                        用於測試 Recovery EA 的狀態機              |
//+------------------------------------------------------------------+
#property copyright "Test Tool"
#property link      ""
#property version   "1.00"
#property strict
#property script_show_inputs

//+------------------------------------------------------------------+
//| 輸入參數                                                          |
//+------------------------------------------------------------------+
input string   GroupID           = "A";           // 組別 ID
input int      SimulateState     = 2;             // Grids 狀態 (0=閒置, 1=累積中, 2=就緒, 3=已確認)
input double   SimulateProfit    = 100.0;         // 模擬累積獲利
input bool     AutoAck           = true;          // 自動確認 Recovery 請求
input string   GV_Prefix         = "REC_";        // GV 前綴

//+------------------------------------------------------------------+
//| 腳本主函數                                                        |
//+------------------------------------------------------------------+
void OnStart()
  {
   string prefix = GV_Prefix + GroupID + "_";
   
   Print("=== GV 模擬器啟動 ===");
   Print("組別: ", GroupID);
   Print("GV 前綴: ", prefix);
   
   // 讀取當前 Recovery 狀態
   double recoveryState = 0;
   double profitTarget = 0;
   double transactionId = 0;
   
   if(GlobalVariableCheck(prefix + "RECOVERY_STATE"))
      recoveryState = GlobalVariableGet(prefix + "RECOVERY_STATE");
   if(GlobalVariableCheck(prefix + "PROFIT_TARGET"))
      profitTarget = GlobalVariableGet(prefix + "PROFIT_TARGET");
   if(GlobalVariableCheck(prefix + "TRANSACTION_ID"))
      transactionId = GlobalVariableGet(prefix + "TRANSACTION_ID");
   
   Print("--- 當前 Recovery 狀態 ---");
   Print("Recovery 狀態: ", GetRecoveryStateString((int)recoveryState));
   Print("獲利目標: ", DoubleToStr(profitTarget, 2));
   Print("交易 ID: ", DoubleToStr(transactionId, 0));
   
   // 設定 Grids 狀態
   GlobalVariableSet(prefix + "GRIDS_STATE", SimulateState);
   Print("--- 設定 Grids 狀態 ---");
   Print("Grids 狀態: ", GetGridsStateString(SimulateState));
   
   // 設定累積獲利
   GlobalVariableSet(prefix + "ACCUMULATED_PROFIT", SimulateProfit);
   Print("累積獲利: ", DoubleToStr(SimulateProfit, 2));
   
   // 自動確認 Recovery 的請求
   if(AutoAck && transactionId > 0)
     {
      GlobalVariableSet(prefix + "GRIDS_ACK_ID", transactionId);
      Print("已確認交易 ID: ", DoubleToStr(transactionId, 0));
     }
   
   Print("=== GV 模擬完成 ===");
   Print("");
   Print("提示：");
   Print("- 狀態 0 (閒置): Recovery 會發起新請求");
   Print("- 狀態 1 (累積中): Recovery 等待獲利累積");
   Print("- 狀態 2 (就緒): 如果獲利達標，Recovery 會執行平倉");
   Print("- 狀態 3 (已確認): Recovery 會重置到閒置狀態");
  }

//+------------------------------------------------------------------+
//| 取得 Recovery 狀態字串                                            |
//+------------------------------------------------------------------+
string GetRecoveryStateString(int state)
  {
   switch(state)
     {
      case 0: return "閒置";
      case 1: return "請求中";
      case 2: return "等待中";
      case 3: return "消費中";
      case 4: return "確認中";
      default: return "未知";
     }
  }

//+------------------------------------------------------------------+
//| 取得 Grids 狀態字串                                               |
//+------------------------------------------------------------------+
string GetGridsStateString(int state)
  {
   switch(state)
     {
      case 0: return "閒置";
      case 1: return "累積中";
      case 2: return "就緒";
      case 3: return "已確認";
      default: return "未知";
     }
  }
//+------------------------------------------------------------------+
