#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""移除 Grids 1.18.mq4 中的除錯代碼"""

with open('Grids 1.8/Grids 1.18.mq4', 'r', encoding='utf-8') as f:
    content = f.read()

# 修復 OnDeinit - 移除除錯代碼和 ExpertRemove()
old_ondeinit = '''void OnDeinit(const int reason)
  {
     int objCount = 0;
   for(int i = ObjectsTotal() - 1; i >= 0; i--)
     {
      string name = ObjectName(i);
      if(StringFind(name, "GridsAI_") == 0)
         objCount++;
     }
   Print("[DEBUG] OnDeinit start，GridsAI_ 物件數量: ", objCount);
  ExpertRemove();
   // 清理 SuperTrend 線'''

new_ondeinit = '''void OnDeinit(const int reason)
  {
   // 清理 SuperTrend 線'''

content = content.replace(old_ondeinit, new_ondeinit)

# 修復 OnTick - 移除結尾的除錯代碼
old_ontick_end = '''   g_chartPanel.Update();

   // 除錯：追蹤 UI 物件數量
   int objCount = 0;
   for(int i = ObjectsTotal() - 1; i >= 0; i--)
     {
      string name = ObjectName(i);
      if(StringFind(name, "GridsAI_") == 0)
         objCount++;
     }
   Print("[DEBUG] OnTick 結束，GridsAI_ 物件數量: ", objCount);
  }'''

new_ontick_end = '''   g_chartPanel.Update();
  }'''

content = content.replace(old_ontick_end, new_ontick_end)

with open('Grids 1.8/Grids 1.18.mq4', 'w', encoding='utf-8') as f:
    f.write(content)

print("已移除除錯代碼")
