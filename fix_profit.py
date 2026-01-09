#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""修改 Grids 1.17.mq4 使用實際平倉獲利"""

with open('Grids 1.7/Grids 1.17.mq4', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. 修改 CheckRiskControl 函數 - 使用實際獲利
old_risk = '''   if(drawdownPercent < -PG_MaxDrawdown)
     {
      WriteLog(StringFormat("回撤保護觸發: %.2f%% (限制: %.1f%%)", MathAbs(drawdownPercent), PG_MaxDrawdown));

      // 使用 HedgeClose 模組平倉
      g_hedgeClose.Execute();

      // 顯示 PL 並重置網格
      g_chartPanel.PrintPL(profit, TimeCurrent(), MarketInfo(Symbol(), MODE_BID));
      ResetAllBaskets();

      return false;
     }'''

new_risk = '''   if(drawdownPercent < -PG_MaxDrawdown)
     {
      WriteLog(StringFormat("回撤保護觸發: %.2f%% (限制: %.1f%%)", MathAbs(drawdownPercent), PG_MaxDrawdown));

      // 使用 HedgeClose 模組平倉，取得實際獲利
      double actualProfit = g_hedgeClose.Execute();
      
      // 累積實際獲利到 RecoveryProfit
      g_recoveryProfit.AddProfit(actualProfit);

      // 顯示 PL 並重置網格
      g_chartPanel.PrintPL(actualProfit, TimeCurrent(), MarketInfo(Symbol(), MODE_BID));
      ResetAllBaskets();

      return false;
     }'''

content = content.replace(old_risk, new_risk)

# 2. 修改 CheckTakeProfitClose 函數 - 獲利追蹤停利
old_trailing = '''   // 檢查獲利追蹤停利（使用 ProfitTrailingStop 模組）
   if(PT_EnableTrailing == YES && g_profitTrailing.ShouldClose())
     {
      WriteLog("獲利追蹤停利觸發");
      g_hedgeClose.Execute();
      g_chartPanel.PrintPL(profit, TimeCurrent(), MarketInfo(Symbol(), MODE_BID));
      ResetAllBaskets();
      g_profitTrailing.Reset();
      return;
     }'''

new_trailing = '''   // 檢查獲利追蹤停利（使用 ProfitTrailingStop 模組）
   if(PT_EnableTrailing == YES && g_profitTrailing.ShouldClose())
     {
      WriteLog("獲利追蹤停利觸發");
      double actualProfit = g_hedgeClose.Execute();
      g_recoveryProfit.AddProfit(actualProfit);
      g_chartPanel.PrintPL(actualProfit, TimeCurrent(), MarketInfo(Symbol(), MODE_BID));
      ResetAllBaskets();
      g_profitTrailing.Reset();
      return;
     }'''

content = content.replace(old_trailing, new_trailing)

# 3. 修改 CheckTakeProfitClose 函數 - 固定止盈
old_fixed = '''   // 檢查固定止盈
   if(PG_TakeProfit > 0 && profit >= PG_TakeProfit)
     {
      WriteLog("固定止盈觸發: " + DoubleToString(profit, 2));
      g_hedgeClose.Execute();
      g_chartPanel.PrintPL(profit, TimeCurrent(), MarketInfo(Symbol(), MODE_BID));
      ResetAllBaskets();
      return;
     }'''

new_fixed = '''   // 檢查固定止盈
   if(PG_TakeProfit > 0 && profit >= PG_TakeProfit)
     {
      WriteLog("固定止盈觸發: " + DoubleToString(profit, 2));
      double actualProfit = g_hedgeClose.Execute();
      g_recoveryProfit.AddProfit(actualProfit);
      g_chartPanel.PrintPL(actualProfit, TimeCurrent(), MarketInfo(Symbol(), MODE_BID));
      ResetAllBaskets();
      return;
     }'''

content = content.replace(old_fixed, new_fixed)

# 4. 修改 CheckTakeProfitClose 函數 - 獨立模式止盈
old_standalone = '''   // 檢查獨立模式止盈
   if(PG_StandaloneMode == YES && PG_StandaloneTP > 0 && profit >= PG_StandaloneTP)
     {
      WriteLog("獨立模式止盈觸發: " + DoubleToString(profit, 2));
      g_hedgeClose.Execute();
      g_chartPanel.PrintPL(profit, TimeCurrent(), MarketInfo(Symbol(), MODE_BID));
      ResetAllBaskets();
      return;
     }'''

new_standalone = '''   // 檢查獨立模式止盈
   if(PG_StandaloneMode == YES && PG_StandaloneTP > 0 && profit >= PG_StandaloneTP)
     {
      WriteLog("獨立模式止盈觸發: " + DoubleToString(profit, 2));
      double actualProfit = g_hedgeClose.Execute();
      g_recoveryProfit.AddProfit(actualProfit);
      g_chartPanel.PrintPL(actualProfit, TimeCurrent(), MarketInfo(Symbol(), MODE_BID));
      ResetAllBaskets();
      return;
     }'''

content = content.replace(old_standalone, new_standalone)

# 5. 移除 OnTick 中舊的浮動獲利累積邏輯
old_ontick = '''   // 累積獲利到 RecoveryProfit（當平倉時）
   static double lastProfit = 0.0;
   double currentProfit = CalculateFloatingProfit();
   if(CountGridOrders() == 0 && lastProfit != 0.0)
     {
      g_recoveryProfit.AddProfit(lastProfit);
      lastProfit = 0.0;
     }
   else
     {
      lastProfit = currentProfit;
     }'''

new_ontick = '''   // 獲利累積已在各平倉函數中處理（使用實際平倉獲利）'''

content = content.replace(old_ontick, new_ontick)

# 6. 更新版本號
content = content.replace('version   "1.17"', 'version   "1.18"')
content = content.replace('Grids EA v1.17', 'Grids EA v1.18')

with open('Grids 1.7/Grids 1.17.mq4', 'w', encoding='utf-8') as f:
    f.write(content)

print("修改完成!")
