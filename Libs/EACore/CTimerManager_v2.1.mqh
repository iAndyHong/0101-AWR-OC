//+------------------------------------------------------------------+
//|                                               CTimerManager.mqh  |
//|                              計時器管理模組                       |
//+------------------------------------------------------------------+
//| 【模組說明 - 供 Kiro AI 讀取】                                    |
//|                                                                   |
//| 功能：管理多個獨立計時器，突破 MT4 單一 EventSetTimer 限制        |
//|                                                                   |
//| 快速用法：                                                        |
//|   CTimerManager timer;                                            |
//|   timer.Init(1);  // 基礎間隔 1 秒                                |
//|   int id = timer.AddTimer("UI更新", 5);  // 每 5 秒觸發           |
//|   timer.CheckTimers();  // 在 OnTimer 中呼叫                      |
//|                                                                   |
//| 引用方式：#include "../Libs/EACore/CTimerManager_v2.1.mqh"             |
//+------------------------------------------------------------------+

#ifndef CTIMERMANAGER_V21_MQH
#define CTIMERMANAGER_V21_MQH

//+------------------------------------------------------------------+
//| 計時器項目結構                                                    |
//+------------------------------------------------------------------+
struct TimerItem
{
   int      id;              // 計時器 ID
   int      interval;        // 間隔秒數
   datetime lastTrigger;     // 上次觸發時間
   bool     enabled;         // 是否啟用
   string   name;            // 計時器名稱（除錯用）
   bool     triggered;       // 本次是否觸發（供外部查詢）
};

//+------------------------------------------------------------------+
//| 計時器管理類別                                                    |
//+------------------------------------------------------------------+
class CTimerManager
{
private:
   TimerItem        m_timers[];          // 計時器陣列
   int              m_timerCount;        // 計時器數量
   int              m_baseInterval;      // 基礎間隔秒數
   int              m_nextId;            // 下一個可用 ID
   bool             m_initialized;       // 初始化狀態
   bool             m_showDebugLogs;     // 顯示除錯日誌

   //--- 內部方法
   int              FindTimerIndex(int timerId);
   void             WriteLog(string message);
   void             WriteDebugLog(string message);

public:
   //--- 建構/解構
                    CTimerManager();
                   ~CTimerManager();

   //--- 初始化
   bool             Init(int baseIntervalSeconds = 1);
   void             Deinit();

   //--- 計時器管理
   int              AddTimer(string name, int intervalSeconds);
   bool             RemoveTimer(int timerId);
   bool             EnableTimer(int timerId, bool enable);
   bool             SetInterval(int timerId, int seconds);
   bool             ResetTimer(int timerId);

   //--- 計時器檢查（在 OnTimer 或 OnTick 中呼叫）
   void             CheckTimers();
   void             CheckTimersOnTick();

   //--- 狀態查詢
   bool             IsTriggered(int timerId);
   bool             IsEnabled(int timerId);
   int              GetInterval(int timerId);
   string           GetTimerName(int timerId);
   int              GetTimerCount()        { return m_timerCount; }
   int              GetBaseInterval()      { return m_baseInterval; }
   bool             IsInitialized()        { return m_initialized; }

   //--- 設定
   void             SetDebugLogs(bool enable) { m_showDebugLogs = enable; }

   //--- 取得所有觸發的計時器 ID
   int              GetTriggeredTimers(int &triggeredIds[]);
};

//+------------------------------------------------------------------+
//| 建構函數                                                          |
//+------------------------------------------------------------------+
CTimerManager::CTimerManager()
{
   m_timerCount = 0;
   m_baseInterval = 1;
   m_nextId = 1;
   m_initialized = false;
   m_showDebugLogs = false;
   ArrayResize(m_timers, 0);
}

//+------------------------------------------------------------------+
//| 解構函數                                                          |
//+------------------------------------------------------------------+
CTimerManager::~CTimerManager()
{
   Deinit();
}

//+------------------------------------------------------------------+
//| 初始化                                                            |
//+------------------------------------------------------------------+
bool CTimerManager::Init(int baseIntervalSeconds = 1)
{
   if(m_initialized)
   {
      WriteDebugLog("計時器管理器已初始化，跳過");
      return true;
   }

   if(baseIntervalSeconds < 1)
      baseIntervalSeconds = 1;

   m_baseInterval = baseIntervalSeconds;
   m_timerCount = 0;
   m_nextId = 1;
   ArrayResize(m_timers, 0);

   // 設定 MT4 計時器
   if(!EventSetTimer(m_baseInterval))
   {
      WriteLog("設定系統計時器失敗");
      return false;
   }

   m_initialized = true;
   WriteLog("計時器管理器初始化完成，基礎間隔: " + IntegerToString(m_baseInterval) + " 秒");

   return true;
}

//+------------------------------------------------------------------+
//| 反初始化                                                          |
//+------------------------------------------------------------------+
void CTimerManager::Deinit()
{
   if(!m_initialized)
      return;

   EventKillTimer();
   ArrayResize(m_timers, 0);
   m_timerCount = 0;
   m_initialized = false;

   WriteLog("計時器管理器已清理");
}

//+------------------------------------------------------------------+
//| 新增計時器                                                        |
//+------------------------------------------------------------------+
int CTimerManager::AddTimer(string name, int intervalSeconds)
{
   if(!m_initialized)
   {
      WriteLog("計時器管理器未初始化，無法新增計時器");
      return -1;
   }

   if(intervalSeconds < 1)
      intervalSeconds = 1;

   // 擴展陣列
   int newSize = m_timerCount + 1;
   ArrayResize(m_timers, newSize);

   // 設定新計時器
   m_timers[m_timerCount].id = m_nextId;
   m_timers[m_timerCount].name = name;
   m_timers[m_timerCount].interval = intervalSeconds;
   m_timers[m_timerCount].lastTrigger = TimeCurrent();
   m_timers[m_timerCount].enabled = true;
   m_timers[m_timerCount].triggered = false;

   int assignedId = m_nextId;
   m_nextId++;
   m_timerCount++;

   WriteDebugLog("新增計時器 [" + name + "] ID=" + IntegerToString(assignedId) +
                 "，間隔=" + IntegerToString(intervalSeconds) + "秒");

   return assignedId;
}

//+------------------------------------------------------------------+
//| 移除計時器                                                        |
//+------------------------------------------------------------------+
bool CTimerManager::RemoveTimer(int timerId)
{
   int index = FindTimerIndex(timerId);
   if(index < 0)
   {
      WriteDebugLog("找不到計時器 ID=" + IntegerToString(timerId));
      return false;
   }

   string name = m_timers[index].name;

   // 移動後面的元素
   for(int i = index; i < m_timerCount - 1; i++)
   {
      m_timers[i] = m_timers[i + 1];
   }

   m_timerCount--;
   ArrayResize(m_timers, m_timerCount);

   WriteDebugLog("移除計時器 [" + name + "] ID=" + IntegerToString(timerId));

   return true;
}

//+------------------------------------------------------------------+
//| 啟用/停用計時器                                                   |
//+------------------------------------------------------------------+
bool CTimerManager::EnableTimer(int timerId, bool enable)
{
   int index = FindTimerIndex(timerId);
   if(index < 0)
      return false;

   m_timers[index].enabled = enable;

   WriteDebugLog("計時器 [" + m_timers[index].name + "] " +
                 (enable ? "已啟用" : "已停用"));

   return true;
}

//+------------------------------------------------------------------+
//| 設定計時器間隔                                                    |
//+------------------------------------------------------------------+
bool CTimerManager::SetInterval(int timerId, int seconds)
{
   int index = FindTimerIndex(timerId);
   if(index < 0)
      return false;

   if(seconds < 1)
      seconds = 1;

   m_timers[index].interval = seconds;

   WriteDebugLog("計時器 [" + m_timers[index].name + "] 間隔設為 " +
                 IntegerToString(seconds) + " 秒");

   return true;
}

//+------------------------------------------------------------------+
//| 重置計時器（重新計時）                                            |
//+------------------------------------------------------------------+
bool CTimerManager::ResetTimer(int timerId)
{
   int index = FindTimerIndex(timerId);
   if(index < 0)
      return false;

   m_timers[index].lastTrigger = TimeCurrent();
   m_timers[index].triggered = false;

   return true;
}

//+------------------------------------------------------------------+
//| 檢查計時器（在 OnTimer 中呼叫）                                   |
//+------------------------------------------------------------------+
void CTimerManager::CheckTimers()
{
   if(!m_initialized || m_timerCount == 0)
      return;

   datetime currentTime = TimeCurrent();

   for(int i = 0; i < m_timerCount; i++)
   {
      // 重置觸發狀態
      m_timers[i].triggered = false;

      if(!m_timers[i].enabled)
         continue;

      // 檢查是否達到間隔
      int elapsed = (int)(currentTime - m_timers[i].lastTrigger);
      if(elapsed >= m_timers[i].interval)
      {
         m_timers[i].triggered = true;
         m_timers[i].lastTrigger = currentTime;

         WriteDebugLog("計時器觸發 [" + m_timers[i].name + "] ID=" +
                       IntegerToString(m_timers[i].id));
      }
   }
}

//+------------------------------------------------------------------+
//| 檢查計時器（在 OnTick 中呼叫，適用於測試器）                      |
//+------------------------------------------------------------------+
void CTimerManager::CheckTimersOnTick()
{
   // 與 CheckTimers 相同邏輯，但可在 OnTick 中使用
   CheckTimers();
}

//+------------------------------------------------------------------+
//| 查詢計時器是否觸發                                                |
//+------------------------------------------------------------------+
bool CTimerManager::IsTriggered(int timerId)
{
   int index = FindTimerIndex(timerId);
   if(index < 0)
      return false;

   return m_timers[index].triggered;
}

//+------------------------------------------------------------------+
//| 查詢計時器是否啟用                                                |
//+------------------------------------------------------------------+
bool CTimerManager::IsEnabled(int timerId)
{
   int index = FindTimerIndex(timerId);
   if(index < 0)
      return false;

   return m_timers[index].enabled;
}

//+------------------------------------------------------------------+
//| 取得計時器間隔                                                    |
//+------------------------------------------------------------------+
int CTimerManager::GetInterval(int timerId)
{
   int index = FindTimerIndex(timerId);
   if(index < 0)
      return -1;

   return m_timers[index].interval;
}

//+------------------------------------------------------------------+
//| 取得計時器名稱                                                    |
//+------------------------------------------------------------------+
string CTimerManager::GetTimerName(int timerId)
{
   int index = FindTimerIndex(timerId);
   if(index < 0)
      return "";

   return m_timers[index].name;
}

//+------------------------------------------------------------------+
//| 取得所有觸發的計時器 ID                                           |
//+------------------------------------------------------------------+
int CTimerManager::GetTriggeredTimers(int &triggeredIds[])
{
   int count = 0;
   ArrayResize(triggeredIds, 0);

   for(int i = 0; i < m_timerCount; i++)
   {
      if(m_timers[i].triggered)
      {
         ArrayResize(triggeredIds, count + 1);
         triggeredIds[count] = m_timers[i].id;
         count++;
      }
   }

   return count;
}

//+------------------------------------------------------------------+
//| 尋找計時器索引                                                    |
//+------------------------------------------------------------------+
int CTimerManager::FindTimerIndex(int timerId)
{
   for(int i = 0; i < m_timerCount; i++)
   {
      if(m_timers[i].id == timerId)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| 日誌輸出                                                          |
//+------------------------------------------------------------------+
void CTimerManager::WriteLog(string message)
{
   Print("[TimerManager] " + message);
}

//+------------------------------------------------------------------+
//| 除錯日誌輸出                                                      |
//+------------------------------------------------------------------+
void CTimerManager::WriteDebugLog(string message)
{
   if(m_showDebugLogs)
      Print("[TimerManager][DEBUG] " + message);
}

#endif // CTIMERMANAGER_V21_MQH
