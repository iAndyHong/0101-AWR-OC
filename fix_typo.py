#!/usr/bin/env python3
# 修正 CChartPanel.mqh 中的打字錯誤

file_path = "Libs/UI/CChartPanel.mqh"

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 修正打字錯誤: -lStats.count -> - sellStats.count
content = content.replace('-lStats.count', '- sellStats.count')

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("已修正打字錯誤: -lStats.count -> - sellStats.count")
