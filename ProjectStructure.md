# 專案拆解架構說明

## 拆解後的專案結構

```
專案根目錄/
├── Libs/ (共享模組庫)
│   ├── EACore/          # EA 核心框架
│   ├── GridsCore/       # 網格交易核心
│   ├── TradeCore/       # 交易執行模組
│   ├── UI/              # 圖表介面模組
│   ├── RecoveryProfit/  # 獲利通訊模組
│   └── 其他輔助模組...
│
├── GridsEA_A/           # 網格交易 - 組別 A
│   ├── GridsEA_A.mq4    # 主程式
│   └── ConfigA.mqh      # 組別 A 專用配置
│
├── GridsEA_B/           # 網格交易 - 組別 B  
│   ├── GridsEA_B.mq4    # 主程式
│   └── ConfigB.mqh      # 組別 B 專用配置
│
├── MonitorEA/           # 多專案監控
│   └── MonitorEA.mq4    # 監控主程式
│
└── RecoveryEA/          # 回本策略（未實作）
    └── RecoveryEA.mq4
```

## 隔離機制設計

### 1. Magic Number 隔離
- **GridsEA_A**: 16000-16099
- **GridsEA_B**: 16100-16199  
- **RecoveryEA**: 16200-16299
- **MonitorEA**: 16300-16399

### 2. 全域變數隔離
- **GridsEA_A**: `GA_*` 前綴 (如 `GA_AccProfit`)
- **GridsEA_B**: `GB_*` 前綴 (如 `GB_AccProfit`)
- **RecoveryEA**: `REC_*` 前綴 (如 `REC_A_Status`)

### 3. UI 物件隔離
- **GridsEA_A**: `GA_Panel_*`, `GA_Arrow_*`
- **GridsEA_B**: `GB_Panel_*`, `GB_Arrow_*`
- **MonitorEA**: `MON_Panel_*`, `MON_Status_*`

### 4. 檔案隔離
- **GridsEA_A**: `GridsA.log`
- **GridsEA_B**: `GridsB.log`
- **MonitorEA**: `Monitor.log`

## 專案特色差異化

### GridsEA_A (保守型)
- **網格模式**: 逆向網格 (COUNTER)
- **間距**: 200 點
- **手數**: 0.01 起始
- **層級**: 10 層
- **風險**: 15% 最大回撤
- **策略**: SuperTrend 過濾
- **UI 位置**: 左上角 (10, 30)
- **顏色**: 藍色系

### GridsEA_B (積極型)  
- **網格模式**: 順向網格 (TREND)
- **間距**: 300 點
- **手數**: 0.02 起始
- **層級**: 8 層
- **風險**: 25% 最大回撤
- **策略**: BullsBears 過濾
- **UI 位置**: 右上角 (300, 30)
- **顏色**: 綠色系

### MonitorEA (監控型)
- **功能**: 多專案統一監控
- **顯示**: 各組別訂單、浮動、累積獲利
- **位置**: 右側 (600, 30)
- **更新**: 5 秒間隔

## 跨專案通訊

### 1. 獲利累積通訊
```mql4
// 各專案寫入自己的累積獲利
GlobalVariableSet("REC_A_AccProfit", accumulatedProfit);
GlobalVariableSet("REC_B_AccProfit", accumulatedProfit);

// MonitorEA 讀取所有組別的獲利
double profitA = GlobalVariableGet("REC_A_AccProfit");
double profitB = GlobalVariableGet("REC_B_AccProfit");
```

### 2. 狀態同步通訊
```mql4
// 專案狀態通訊
GlobalVariableSet("GA_Status", EA_STATUS_RUNNING);
GlobalVariableSet("GB_Status", EA_STATUS_PAUSED);

// 緊急停止信號
GlobalVariableSet("EMERGENCY_STOP", 1);
```

## 部署和使用

### 1. 編譯順序
```bash
# 先編譯各個專案
./compile.sh "GridsEA_A/GridsEA_A.mq4"
./compile.sh "GridsEA_B/GridsEA_B.mq4"  
./compile.sh "MonitorEA/MonitorEA.mq4"
```

### 2. 掛載順序
1. 先掛載 **GridsEA_A** 到 EURUSD 圖表
2. 再掛載 **GridsEA_B** 到 GBPUSD 圖表
3. 最後掛載 **MonitorEA** 到任一圖表進行監控

### 3. 參數調整
- 各專案有獨立的外部參數
- 可以針對不同商品調整不同策略
- 不會互相影響

## 優點總結

### ✅ 完全隔離
- Magic Number 不衝突
- UI 物件不重疊
- 全域變數不衝突
- 日誌檔案分離

### ✅ 策略多樣化
- 不同網格模式
- 不同風險等級
- 不同過濾策略
- 不同參數設定

### ✅ 統一監控
- 一個面板監控所有專案
- 即時顯示各組別狀態
- 總體獲利統計
- 異常狀態警示

### ✅ 維護簡單
- 共享 Libs 模組庫
- 配置檔案化管理
- 獨立除錯日誌
- 模組化升級

### ✅ 擴展容易
- 新增組別只需複製配置
- 調整 Magic Number 範圍
- 修改 UI 位置和顏色
- 添加新的監控項目

這個架構讓你可以同時運行多個不同策略的網格 EA，每個都有獨立的參數和風險控制，同時通過統一的監控面板掌握整體狀況。