#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""修正 CChartPanel.mqh 的除以零問題"""

with open('Libs/UI/CChartPanel.mqh', 'r', encoding='utf-8') as f:
    content = f.read()

# 修正除以零問題
old_code = '''   // 7. 系統資訊 - 中性顏色
   string sysInfo = StringFormat("系統: %s / %s / 保證金%%=%.2f",
                                 (m_tradeMode != "") ? m_tradeMode : "未設定",
                                 (m_tradeSymbol != "") ? m_tradeSymbol : Symbol(),
                                 (AccountEquity() / AccountMargin()) * 100
                                 );'''

new_code = '''   // 7. 系統資訊 - 中性顏色
   double margin = AccountMargin();
   double marginPercent = (margin > 0) ? (AccountEquity() / margin) * 100 : 0.0;
   string sysInfo = StringFormat("系統: %s / %s / 保證金%%=%.2f",
                                 (m_tradeMode != "") ? m_tradeMode : "未設定",
                                 (m_tradeSymbol != "") ? m_tradeSymbol : Symbol(),
                                 marginPercent
                                 );'''

content = content.replace(old_code, new_code)

with open('Libs/UI/CChartPanel.mqh', 'w', encoding='utf-8') as f:
    f.write(content)

print("已修正除以零問題")
