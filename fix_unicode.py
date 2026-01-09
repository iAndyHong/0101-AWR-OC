#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""修改 Grids 1.18.mq4 的 WriteLog 函數，改用 FILE_UNICODE"""

with open('Grids 1.8/Grids 1.18.mq4', 'r', encoding='utf-8') as f:
    content = f.read()

# 修改 FILE_ANSI 為 FILE_UNICODE
content = content.replace(
    'int handle = FileOpen(actualLogFile, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);',
    'int handle = FileOpen(actualLogFile, FILE_READ | FILE_WRITE | FILE_TXT | FILE_UNICODE);'
)

with open('Grids 1.8/Grids 1.18.mq4', 'w', encoding='utf-8') as f:
    f.write(content)

print("已將 FILE_ANSI 改為 FILE_UNICODE")
