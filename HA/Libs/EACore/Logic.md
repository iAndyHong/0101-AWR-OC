# EACore EA 核心模組

## 模組概述

EACore 是 EA 中樞架構模組，整合所有 Libs 模組，提供統一的 EA 開發框架。

## 檔案結構

```
Libs/EACore/
├── CEACore.mqh           ← 中樞類別（主入口）
├── CTimerManager.mqh     ← 計時器管理
├── Utils.mqh             ← 工具函數
├── EABase.mqh            ← 參考用
└── Logic.md              ← 本文件
```

## 快速使用

### 步驟 1：建立子類

```mql4
#include "../Libs/EACore/CEACore.mqh"

class CMyEA : public CEACore
{
public:
   // 實作抽象方法
   virtual int GetTradeSignal() override
   {
      // 你的多空判斷邏輯
      return SIGNAL_NEUTRAL;
   }
   
   virtual bool ShouldOpenFirst(int direction) override
   {
      // 你的首單條件
      return true;
   }
   
   virtual void OnCustomTick() override
   {
      // 你的自訂 OnTick 邏輯
   }
};
```

### 步驟 2：在 EA 主檔案中使用

```mql4
CMyEA g_ea;

int OnInit()
{
   // 設定參數
   g_ea.SetMagic(12345);
   g_ea.SetEAName("MyEA");
   g_ea.SetEAVersion("1.0");
   g_ea.SetMaxDrawdown(20.0);
   
   // 啟用模組
   g_ea.EnableChartPanel(true);
   g_ea.EnableArrows(true);
   
   return g_ea.OnInitCore();
}

void OnTick()   { g_ea.OnTickCore(); }
void OnTimer()  { g_ea.OnTimerCore(); }
void OnDeinit(const int reason) { g_ea.OnDeinitCore(reason); }
```

## CEACore 類別說明

### 整合模組

- `CTradeCore` - 交易核心（訂單/風控/持倉）
- `CHedgeClose` - 對沖平倉
- `CProfitTrailingStop` - 獲利追蹤停利
- `CTradeArrowManager` - 交易箭頭
- `CRecoveryProfit` - 獲利通訊
- `CChartPanelCanvas` - UI 面板
- `CTimerManager` - 計時器管理

### 抽象方法（子類實作）

- `GetTradeSignal()` - 返回多空信號
  - `SIGNAL_BUY` = 1
  - `SIGNAL_SELL` = -1
  - `SIGNAL_NEUTRAL` = 0

- `ShouldOpenFirst(direction)` - 判斷是否開首單

- `ShouldAddPosition(direction)` - 判斷是否加倉

- `CalculateLots(level)` - 計算指定層級手數

- `CalculateGridDistance(level)` - 計算指定層級間距

- `OnCustomTick()` - 自訂 OnTick 邏輯

- `OnCustomTimer(timerId)` - 自訂計時器回調

- `OnRiskTriggered()` - 風險觸發時的處理

### 設定方法

**基本設定**
- `SetMagic(int)` - 設定 Magic Number
- `SetSymbol(string)` - 設定交易商品
- `SetGroupId(string)` - 設定組別 ID
- `SetSlippage(int)` - 設定滑點
- `SetEAName(string)` - 設定 EA 名稱
- `SetEAVersion(string)` - 設定 EA 版本

**風控設定**
- `SetMaxDrawdown(double)` - 設定最大回撤 %
- `SetMaxLots(double)` - 設定最大手數
- `SetMaxSpread(double)` - 設定最大點差
- `SetMaxOrders(int)` - 設定最大訂單數

**模組啟用**
- `EnableHedgeClose(bool)` - 啟用對沖平倉
- `EnableProfitTrailing(bool)` - 啟用獲利追蹤
- `EnableArrows(bool)` - 啟用交易箭頭
- `EnableRecoveryProfit(bool)` - 啟用獲利通訊
- `EnableChartPanel(bool)` - 啟用 UI 面板
- `EnableTimer(bool)` - 啟用計時器

**獲利追蹤設定**
- `SetProfitThreshold(double)` - 設定獲利閾值
- `SetDrawdownPercent(double)` - 設定保留利潤 %

**UI 設定**
- `SetPanelPosition(int x, int y)` - 設定面板位置
- `SetPanelUpdateInterval(int)` - 設定更新間隔

**日誌設定**
- `SetDebugLogs(bool)` - 啟用除錯日誌
- `SetLogFile(string)` - 設定日誌檔案

### 訂單管理

- `OpenOrder(type, lots, comment)` - 開單
- `CloseOrder(ticket)` - 平倉指定訂單
- `CloseAllOrders()` - 平倉所有訂單
- `HedgeCloseAll()` - 對沖平倉所有訂單
- `CountOrders(type)` - 計算訂單數
- `GetTotalLots(type)` - 取得總手數
- `GetFloatingProfit()` - 取得浮動盈虧
- `GetAveragePrice(type)` - 取得平均價格

### 風險控制

- `CheckRiskControl()` - 綜合風險檢查
- `CheckDrawdown()` - 檢查回撤
- `CheckMaxLots()` - 檢查手數
- `CheckSpread()` - 檢查點差
- `CheckMaxOrders()` - 檢查訂單數

### 計時器管理

- `AddTimer(name, seconds)` - 新增計時器
- `RemoveTimer(timerId)` - 移除計時器
- `IsTimerTriggered(timerId)` - 檢查是否觸發

### 獲利管理

- `AddProfit(profit)` - 新增獲利
- `GetAccumulatedProfit()` - 取得累積獲利
- `ResetProfit()` - 重置獲利

### 狀態控制

- `Pause()` - 暫停 EA
- `Resume()` - 恢復 EA
- `IsRunning()` - 是否運行中
- `IsPaused()` - 是否暫停中

## CTimerManager 計時器管理

### 使用範例

```mql4
class CMyEA : public CEACore
{
private:
   int m_uiTimerId;
   int m_syncTimerId;
   
public:
   virtual int OnInitCore() override
   {
      CEACore::OnInitCore();
      
      // 註冊計時器
      m_uiTimerId = AddTimer("UI更新", 1);
      m_syncTimerId = AddTimer("同步", 5);
      
      return INIT_SUCCEEDED;
   }
   
   virtual void OnCustomTimer(int timerId) override
   {
      if(timerId == m_uiTimerId)
         UpdateUI();
      else if(timerId == m_syncTimerId)
         SyncData();
   }
};
```

## 完整範例：網格 EA

```mql4
#include "../Libs/EACore/CEACore.mqh"

input double   PG_GridStep      = 500.0;
input double   PG_InitialLots   = 0.01;
input double   PG_LotMultiplier = 1.2;
input int      PG_MaxLevels     = 10;
input int      PG_MagicNumber   = 16888;

class CGridsEA : public CEACore
{
private:
   double   m_gridStep;
   double   m_lotMultiplier;
   int      m_maxLevels;
   int      m_buyLevel;
   int      m_sellLevel;
   double   m_buyBasePrice;
   double   m_sellBasePrice;
   
public:
   CGridsEA()
   {
      m_gridStep = 500.0;
      m_lotMultiplier = 1.2;
      m_maxLevels = 10;
      m_buyLevel = 0;
      m_sellLevel = 0;
      m_buyBasePrice = 0.0;
      m_sellBasePrice = 0.0;
   }
   
   void SetGridStep(double step)       { m_gridStep = step; }
   void SetLotMultiplier(double mult)  { m_lotMultiplier = mult; }
   void SetMaxLevels(int levels)       { m_maxLevels = levels; }
   
   virtual int GetTradeSignal() override
   {
      return SIGNAL_NEUTRAL;  // 網格不依賴信號
   }
   
   virtual double CalculateLots(int level) override
   {
      if(level <= 1) return PG_InitialLots;
      return PG_InitialLots * MathPow(m_lotMultiplier, level - 1);
   }
   
   virtual void OnCustomTick() override
   {
      // 網格交易邏輯
      ExecuteGridLogic();
   }
   
   void ExecuteGridLogic()
   {
      // 實作網格加倉邏輯...
   }
};

CGridsEA g_ea;

int OnInit()
{
   g_ea.SetMagic(PG_MagicNumber);
   g_ea.SetEAName("GridsEA");
   g_ea.SetEAVersion("2.0");
   g_ea.SetGridStep(PG_GridStep);
   g_ea.SetLotMultiplier(PG_LotMultiplier);
   g_ea.SetMaxLevels(PG_MaxLevels);
   
   g_ea.EnableChartPanel(true);
   g_ea.EnableHedgeClose(true);
   
   return g_ea.OnInitCore();
}

void OnTick()   { g_ea.OnTickCore(); }
void OnTimer()  { g_ea.OnTimerCore(); }
void OnDeinit(const int reason) { g_ea.OnDeinitCore(reason); }
```

## 版本紀錄

- v1.0 (2025-12-31) - 初版建立
