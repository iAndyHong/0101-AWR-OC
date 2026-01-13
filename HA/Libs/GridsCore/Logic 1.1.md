# CGridsCore v1.1 網格交易核心模組

## 版本更新說明

v1.1 新增「動態 0 線」機制，用於反向籃子的觸發線計算。

## 模組定位

將「網格交易邏輯」與「多空信號邏輯」分離，讓不同的信號算法可以共用同一套網格核心。

## v1.1 新增功能：動態 0 線機制

### 概念說明

傳統網格交易中，反向籃子的首單觸發依賴信號反轉。動態 0 線機制提供另一種觸發方式：

- **上漲趨勢時**：賣出 0 線 = 近 N 根 K 棒的低點（動態更新）
- **下跌趨勢時**：買入 0 線 = 近 N 根 K 棒的高點（動態更新）

當價格突破動態 0 線時，即觸發反向籃子的首單。

### 運作邏輯

1. **動態更新**：每個 tick 更新動態 0 線位置
2. **觸發條件**：
   - 有買入籃子時，價格跌破動態賣出 0 線 → 開啟賣出首單
   - 有賣出籃子時，價格突破動態買入 0 線 → 開啟買入首單
3. **重置機制**：
   - 開啟買入籃子時，重置賣出動態 0 線
   - 開啟賣出籃子時，重置買入動態 0 線
4. **加倉基準**：動態 0 線模式下，加倉距離以動態 0 線位置為基準計算

### 配置參數

```mql4
struct GridsCoreConfig
{
   // ... 其他參數 ...
   
   // 動態 0 線設定
   bool              enableDynamicZero;    // 啟用動態 0 線
   int               dynamicZeroBars;      // 回看 K 棒數量
};
```

### 外部參數範例

```mql4
sinput string  DZ_Help                   = "----------------";   // 動態 0 線設定
input  bool    DZ_EnableDynamicZero      = false;                // 啟用動態 0 線
input  int     DZ_LookbackBars           = 10;                   // 回看 K 棒數量
```

### 狀態查詢方法

```mql4
// 取得當前動態 0 線位置
double GetDynamicBuyZero();   // 買入動態 0 線
double GetDynamicSellZero();  // 賣出動態 0 線
```

## 架構設計

```
EA 檔案 (如 Grids 1.21.mq4)
    │
    ├── 配置 GridsCoreConfig（含動態 0 線設定）
    │
    └── 呼叫 CGridsCore
            │
            ├── 網格交易執行
            │   ├── 傳統模式：依據信號開單
            │   └── 動態 0 線模式：依據價格突破開單
            ├── 風險控制
            ├── 訂單管理
            └── 平倉回調
```

## 使用方式

### 1. 引入模組

```mql4
#include "../Libs/GridsCore/CGridsCore v1.1.mqh"
```

### 2. 配置動態 0 線

```mql4
GridsCoreConfig config;
// ... 基本設定 ...

// 動態 0 線設定
config.enableDynamicZero = true;   // 啟用
config.dynamicZeroBars = 10;       // 回看 10 根 K 棒
```

### 3. 初始化與執行

```mql4
CGridsCore g_gridsCore;

int OnInit()
{
   GridsCoreConfig config;
   // ... 設定配置 ...
   
   if(!g_gridsCore.Init(config))
      return INIT_FAILED;
   
   return INIT_SUCCEEDED;
}

void OnTick()
{
   g_gridsCore.Execute();
}

void OnDeinit(const int reason)
{
   g_gridsCore.Deinit();
}
```

## 動態 0 線 vs 傳統模式比較

### 傳統模式
- 首單觸發：依據信號（BullsBears、SuperTrend 等）
- 加倉基準：實際開倉價格
- 適用場景：趨勢明確的市場

### 動態 0 線模式
- 首單觸發：價格突破近 N 根 K 棒高低點
- 加倉基準：動態 0 線位置
- 適用場景：震盪市場、區間交易

## 注意事項

1. **向下相容**：`enableDynamicZero = false` 時，行為與 v1.0 完全相同
2. **參數建議**：`dynamicZeroBars` 建議設定 5-20，視交易週期而定
3. **搭配使用**：可與 SuperTrend 等信號模式同時使用，動態 0 線僅影響反向籃子觸發

## 版本資訊

- 建立日期：2025-01-03
- 版本：1.1
- 新增功能：動態 0 線機制
