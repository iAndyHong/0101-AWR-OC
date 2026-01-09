# Libs 模組並行開發架構

## 目標
讓多個 Kiro IDE 實例可以同時開發不同的 Libs 模組，各自推進版本而不互相衝突。

## 當前 Libs 模組清單

```
Libs/
├── EACore/              # EA 核心框架
├── GridsCore/           # 網格交易核心  
├── TradeCore/           # 交易執行模組
├── UI/                  # 圖表介面模組
├── RecoveryProfit/      # 獲利通訊模組
├── HedgeClose/          # 對沖平倉模組
└── ProfitTrailingStop/  # 獲利追蹤模組
```

## 拆分方案：版本分支開發

### 方案一：版本後綴開發模式

每個模組建立開發版本，多人同時開發不同版本：

```
Libs/
├── EACore/
│   ├── CEACore.mqh           # 穩定版本
│   ├── CEACore_v2.mqh        # Kiro-1 開發版本
│   └── CEACore_v3.mqh        # Kiro-2 開發版本
├── GridsCore/
│   ├── CGridsCore.mqh        # 穩定版本
│   ├── CGridsCore_v2.mqh     # Kiro-1 開發版本
│   └── CGridsCore_v3.mqh     # Kiro-2 開發版本
└── UI/
    ├── CChartPanel.mqh       # 穩定版本
    ├── CChartPanel_v2.mqh    # Kiro-1 開發版本
    └── CChartPanel_v3.mqh    # Kiro-2 開發版本
```

### 方案二：開發者分支模式

每個開發者有自己的模組副本：

```
Libs/
├── EACore/
│   ├── CEACore.mqh           # 主版本
│   ├── CEACore_Andy.mqh      # Andy 開發版
│   ├── CEACore_Dev1.mqh      # 開發者1 版本
│   └── CEACore_Dev2.mqh      # 開發者2 版本
├── GridsCore/
│   ├── CGridsCore.mqh        # 主版本
│   ├── CGridsCore_Andy.mqh   # Andy 開發版
│   └── CGridsCore_Dev1.mqh   # 開發者1 版本
```

### 方案三：功能分支模式（推薦）

按功能特性建立分支版本：

```
Libs/
├── EACore/
│   ├── CEACore.mqh              # 穩定版本
│   ├── CEACore_Performance.mqh  # 效能優化版本
│   ├── CEACore_NewFeatures.mqh  # 新功能開發版本
│   └── CEACore_BugFix.mqh       # 錯誤修復版本
├── GridsCore/
│   ├── CGridsCore.mqh           # 穩定版本
│   ├── CGridsCore_Advanced.mqh  # 進階功能版本
│   └── CGridsCore_Scaling.mqh   # 縮放功能版本
```

## 版本管理機制

### 1. 版本標識系統

每個開發版本都有明確的標識：

```mql4
//+------------------------------------------------------------------+
//|                                            CEACore_Performance.mqh |
//|                         EA 核心框架 - 效能優化版本                |
//+------------------------------------------------------------------+
//| 版本：2.1-Performance                                             |
//| 開發者：Kiro-1                                                   |
//| 基於：CEACore.mqh v2.0                                           |
//| 功能：Timer 優化、緩存機制、記憶體管理                            |
//| 狀態：開發中                                                     |
//+------------------------------------------------------------------+

#ifndef CEACORE_PERFORMANCE_MQH
#define CEACORE_PERFORMANCE_MQH

#property version "2.1-Performance"
```

### 2. 相容性介面

所有版本保持相同的公開介面：

```mql4
// 所有版本都必須實現相同的核心介面
class CEACore_Base
{
public:
   virtual int    OnInitCore() = 0;
   virtual void   OnTickCore() = 0;
   virtual void   OnDeinitCore(int reason) = 0;
   // ... 其他核心方法
};

// 各版本繼承基礎介面
class CEACore_Performance : public CEACore_Base
{
   // 效能優化實現
};

class CEACore_NewFeatures : public CEACore_Base  
{
   // 新功能實現
};
```

### 3. 測試 EA 配置

每個版本都有對應的測試 EA：

```
TestEAs/
├── TestEA_CEACore_Performance.mq4
├── TestEA_CGridsCore_Advanced.mq4
├── TestEA_UI_NewDesign.mq4
└── TestEA_Integration.mq4
```

## 並行開發工作流程

### 階段1：模組分配
- **Kiro-1**：負責 EACore 效能優化
- **Kiro-2**：負責 GridsCore 進階功能  
- **Kiro-3**：負責 UI 模組重設計
- **Andy**：負責整合測試和版本合併

### 階段2：獨立開發
每個 Kiro 實例：
1. 複製穩定版本為開發版本
2. 在開發版本上進行功能開發
3. 建立對應的測試 EA
4. 獨立測試和驗證

### 階段3：版本合併
1. 各開發版本完成後進行整合測試
2. 解決版本間的相容性問題
3. 合併優秀功能到主版本
4. 更新穩定版本

## 衝突避免機制

### 1. 檔案命名規範
```
原檔案：CEACore.mqh
開發版：CEACore_[功能名稱].mqh
測試版：CEACore_Test_[日期].mqh
備份版：CEACore_Backup_[日期].mqh
```

### 2. 類別命名規範
```mql4
// 原類別
class CEACore { ... }

// 開發版類別
class CEACore_Performance { ... }
class CEACore_NewFeatures { ... }
class CEACore_BugFix { ... }
```

### 3. 全域變數隔離
```mql4
// 原版本
#define CEACORE_VERSION "2.0"

// 開發版本
#define CEACORE_PERFORMANCE_VERSION "2.1-Perf"
#define CEACORE_NEWFEATURES_VERSION "2.1-New"
```

## 整合測試策略

### 1. 單元測試
每個模組版本都有獨立的測試 EA：
```mql4
// TestEA_CEACore_Performance.mq4
#include "../Libs/EACore/CEACore_Performance.mqh"

CEACore_Performance g_eaCore;

int OnInit()
{
   // 測試效能優化功能
   return g_eaCore.OnInitCore();
}
```

### 2. 整合測試
測試不同版本模組的組合：
```mql4
// TestEA_Integration.mq4
#include "../Libs/EACore/CEACore_Performance.mqh"
#include "../Libs/GridsCore/CGridsCore_Advanced.mqh"
#include "../Libs/UI/CChartPanel_NewDesign.mqh"

// 測試模組間的相容性
```

### 3. 回歸測試
確保新版本不會破壞現有功能：
```mql4
// TestEA_Regression.mq4
// 使用標準測試案例驗證所有核心功能
```

## 版本發布流程

### 1. 開發完成
- 功能開發完成
- 單元測試通過
- 文檔更新完成

### 2. 整合測試
- 與其他模組相容性測試
- 整合測試通過
- 效能測試通過

### 3. 版本合併
- 將優秀功能合併到主版本
- 更新版本號
- 建立發布標籤

### 4. 清理舊版本
- 保留穩定版本
- 清理過時的開發版本
- 更新文檔

這個架構讓多個 Kiro IDE 可以同時開發不同的模組功能，各自推進版本而不會互相干擾。