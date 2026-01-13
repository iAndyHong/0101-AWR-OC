//+------------------------------------------------------------------+
//|                                            CRecoveryProfit.mqh   |
//|                        Recovery 獲利通訊模組                      |
//+------------------------------------------------------------------+
#property copyright "Andy's Trading System"
#property version   "1.03"
#property strict

#ifndef __CRECOVERYPROFIT_MQH__
#define __CRECOVERYPROFIT_MQH__

#ifndef STATE_G_IDLE
   #define STATE_G_IDLE          0
#endif
#ifndef STATE_G_ACCUMULATING
   #define STATE_G_ACCUMULATING  1
#endif
#ifndef STATE_G_READY
   #define STATE_G_READY         2
#endif
#ifndef STATE_G_ACKNOWLEDGED
   #define STATE_G_ACKNOWLEDGED  3
#endif
#ifndef STATE_R_IDLE
   #define STATE_R_IDLE          0
#endif
#ifndef STATE_R_REQUESTING
   #define STATE_R_REQUESTING    1
#endif
#ifndef STATE_R_WAITING
   #define STATE_R_WAITING       2
#endif
#ifndef STATE_R_CONSUMING
   #define STATE_R_CONSUMING     3
#endif
#ifndef STATE_R_CONFIRMING
   #define STATE_R_CONFIRMING    4
#endif
#ifndef GV_MAX_LENGTH
   #define GV_MAX_LENGTH         63
#endif

class CRecoveryProfit
  {
private:
   string            m_groupId;
   string            m_gvPrefix;
   string            m_symbol;
   bool              m_crossSymbol;
   bool              m_showDebugLogs;
   bool              m_isInitialized;
   int               m_gridsState;
   double            m_currentTxId;
   double            m_profitTarget;
   double            m_accumulatedProfit;
   double            m_localGV_AccumulatedProfit;
   double            m_localGV_GridsState;
   double            m_localGV_GridsAckId;
   double            m_localGV_LastUpdate;
   double            m_localGV_TransactionId;
   double            m_localGV_ProfitTarget;
   double            m_localGV_RecoveryState;
   double            m_localGV_RecoveryAckId;

   string            GetGVFullName(string name);
   double            GetLocalGV(string name);
   void              SetLocalGV(string name, double value);
   void              HandleStateIdle(int recoveryState, double txId);
   void              HandleStateAccumulating(int recoveryState, double txId);
   void              HandleStateReady(int recoveryState, double recoveryAckId);
   void              HandleStateAcknowledged(int recoveryState);
   void              ResetToIdle();

public:
                     CRecoveryProfit();
                    ~CRecoveryProfit();
   bool              Init(string groupId, string gvPrefix = "REC_", string symbol = "");
   void              SetCrossSymbol(bool crossSymbol) { m_crossSymbol = crossSymbol; }
   void              SetDebugLogs(bool showLogs) { m_showDebugLogs = showLogs; }
   void              WriteGV(string name, double value);
   double            ReadGV(string name, double defaultValue = 0);
   bool              CheckGV(string name);
   void              DeleteGV(string name);
   void              OnTick();
   void              ExecuteStateMachine();
   void              AddProfit(double profit);
   void              ResetProfit();
   double            GetAccumulatedProfit() { return m_accumulatedProfit; }
   double            GetProfitTarget() { return m_profitTarget; }
   int               GetState() { return m_gridsState; }
   string            GetStateString();
   bool              IsAccumulating() { return m_gridsState == STATE_G_ACCUMULATING; }
   bool              IsReady() { return m_gridsState == STATE_G_READY; }
   bool              IsIdle() { return m_gridsState == STATE_G_IDLE; }
   bool              HasTarget() { return m_profitTarget > 0; }
   void              Deinit();
  };

CRecoveryProfit::CRecoveryProfit()
  {
   m_groupId = "A";
   m_gvPrefix = "REC_";
   m_symbol = "";
   m_crossSymbol = false;
   m_showDebugLogs = false;
   m_isInitialized = false;
   m_gridsState = STATE_G_IDLE;
   m_currentTxId = 0;
   m_profitTarget = 0;
   m_accumulatedProfit = 0;
   m_localGV_AccumulatedProfit = 0;
   m_localGV_GridsState = 0;
   m_localGV_GridsAckId = 0;
   m_localGV_LastUpdate = 0;
   m_localGV_TransactionId = 0;
   m_localGV_ProfitTarget = 0;
   m_localGV_RecoveryState = 0;
   m_localGV_RecoveryAckId = 0;
  }

CRecoveryProfit::~CRecoveryProfit() { Deinit(); }

bool CRecoveryProfit::Init(string groupId, string gvPrefix = "REC_", string symbol = "")
  {
   m_groupId = groupId;
   m_gvPrefix = gvPrefix;
   m_symbol = (symbol == "") ? Symbol() : symbol;
   
   // 回測時不從 GV 讀取（保持累積值），實盤時從 GV 讀取
   if(!IsTesting())
      m_accumulatedProfit = ReadGV("ACCUMULATED_PROFIT", 0.0);
   // 回測時 m_accumulatedProfit 保持原值（不重置）
   
   WriteGV("GRIDS_STATE", STATE_G_IDLE);
   WriteGV("GRIDS_ACK_ID", 0.0);
   WriteGV("LAST_UPDATE", (double)TimeCurrent());
   m_gridsState = STATE_G_IDLE;
   m_currentTxId = 0;
   m_isInitialized = true;
   Print("[RecoveryProfit] Init 完成, 累積獲利=", m_accumulatedProfit);
   return true;
  }

void CRecoveryProfit::Deinit()
  {
   if(m_isInitialized)
     {
      WriteGV("GRIDS_STATE", STATE_G_IDLE);
      m_isInitialized = false;
     }
  }

string CRecoveryProfit::GetGVFullName(string name)
  {
   string fullName;
   if(m_crossSymbol)
      fullName = m_gvPrefix + m_groupId + "_X_" + name;
   else
      fullName = m_gvPrefix + m_groupId + "_" + name;
   if(StringLen(fullName) > GV_MAX_LENGTH)
      fullName = StringSubstr(fullName, 0, GV_MAX_LENGTH);
   return fullName;
  }

double CRecoveryProfit::GetLocalGV(string name)
  {
   if(name == "ACCUMULATED_PROFIT") return m_localGV_AccumulatedProfit;
   if(name == "GRIDS_STATE") return m_localGV_GridsState;
   if(name == "GRIDS_ACK_ID") return m_localGV_GridsAckId;
   if(name == "LAST_UPDATE") return m_localGV_LastUpdate;
   if(name == "TRANSACTION_ID") return m_localGV_TransactionId;
   if(name == "PROFIT_TARGET") return m_localGV_ProfitTarget;
   if(name == "RECOVERY_STATE") return m_localGV_RecoveryState;
   if(name == "RECOVERY_ACK_ID") return m_localGV_RecoveryAckId;
   return 0.0;
  }

void CRecoveryProfit::SetLocalGV(string name, double value)
  {
   if(name == "ACCUMULATED_PROFIT") { m_localGV_AccumulatedProfit = value; return; }
   if(name == "GRIDS_STATE") { m_localGV_GridsState = value; return; }
   if(name == "GRIDS_ACK_ID") { m_localGV_GridsAckId = value; return; }
   if(name == "LAST_UPDATE") { m_localGV_LastUpdate = value; return; }
   if(name == "TRANSACTION_ID") { m_localGV_TransactionId = value; return; }
   if(name == "PROFIT_TARGET") { m_localGV_ProfitTarget = value; return; }
   if(name == "RECOVERY_STATE") { m_localGV_RecoveryState = value; return; }
   if(name == "RECOVERY_ACK_ID") { m_localGV_RecoveryAckId = value; return; }
  }

void CRecoveryProfit::WriteGV(string name, double value)
  {
   SetLocalGV(name, value);
   if(IsTesting()) return;
   string fullName = GetGVFullName(name);
   GlobalVariableSet(fullName, value);
  }

double CRecoveryProfit::ReadGV(string name, double defaultValue = 0)
  {
   if(IsTesting()) return GetLocalGV(name);
   string fullName = GetGVFullName(name);
   if(GlobalVariableCheck(fullName))
      return GlobalVariableGet(fullName);
   return defaultValue;
  }

bool CRecoveryProfit::CheckGV(string name)
  {
   if(IsTesting()) return (GetLocalGV(name) != 0.0);
   string fullName = GetGVFullName(name);
   return GlobalVariableCheck(fullName);
  }

void CRecoveryProfit::DeleteGV(string name)
  {
   SetLocalGV(name, 0.0);
   if(IsTesting()) return;
   string fullName = GetGVFullName(name);
   if(GlobalVariableCheck(fullName))
      GlobalVariableDel(fullName);
  }

void CRecoveryProfit::OnTick()
  {
   if(!m_isInitialized) return;
   ExecuteStateMachine();
   WriteGV("LAST_UPDATE", (double)TimeCurrent());
  }

void CRecoveryProfit::ExecuteStateMachine()
  {
   int recoveryState = (int)ReadGV("RECOVERY_STATE", STATE_R_IDLE);
   double txId = ReadGV("TRANSACTION_ID", 0);
   double recoveryAckId = ReadGV("RECOVERY_ACK_ID", 0);
   switch(m_gridsState)
     {
      case STATE_G_IDLE: HandleStateIdle(recoveryState, txId); break;
      case STATE_G_ACCUMULATING: HandleStateAccumulating(recoveryState, txId); break;
      case STATE_G_READY: HandleStateReady(recoveryState, recoveryAckId); break;
      case STATE_G_ACKNOWLEDGED: HandleStateAcknowledged(recoveryState); break;
     }
  }

void CRecoveryProfit::HandleStateIdle(int recoveryState, double txId)
  {
   if(recoveryState == STATE_R_REQUESTING && txId > m_currentTxId)
     {
      m_profitTarget = ReadGV("PROFIT_TARGET", 0);
      if(m_profitTarget > 0)
        {
         m_currentTxId = txId;
         WriteGV("GRIDS_ACK_ID", m_currentTxId);
         m_gridsState = STATE_G_ACCUMULATING;
         WriteGV("GRIDS_STATE", m_gridsState);
        }
     }
  }

void CRecoveryProfit::HandleStateAccumulating(int recoveryState, double txId)
  {
   if(txId != m_currentTxId) { ResetToIdle(); return; }
   if(recoveryState == STATE_R_IDLE) { ResetToIdle(); return; }
   if(m_accumulatedProfit >= m_profitTarget)
     {
      m_gridsState = STATE_G_READY;
      WriteGV("GRIDS_STATE", m_gridsState);
      WriteGV("ACCUMULATED_PROFIT", m_accumulatedProfit);
     }
  }

void CRecoveryProfit::HandleStateReady(int recoveryState, double recoveryAckId)
  {
   if(recoveryAckId == m_currentTxId)
     {
      m_gridsState = STATE_G_ACKNOWLEDGED;
      WriteGV("GRIDS_STATE", m_gridsState);
     }
  }

void CRecoveryProfit::HandleStateAcknowledged(int recoveryState)
  {
   if(recoveryState == STATE_R_IDLE || recoveryState == STATE_R_CONFIRMING)
      ResetToIdle();
  }

void CRecoveryProfit::ResetToIdle()
  {
   m_gridsState = STATE_G_IDLE;
   m_profitTarget = 0;
   WriteGV("GRIDS_STATE", STATE_G_IDLE);
  }

void CRecoveryProfit::AddProfit(double profit)
  {
   double oldValue = m_accumulatedProfit;
   m_accumulatedProfit += profit;
   WriteGV("ACCUMULATED_PROFIT", m_accumulatedProfit);
   Print("[RecoveryProfit] AddProfit: +", profit, " (", oldValue, " -> ", m_accumulatedProfit, ")");
  }

void CRecoveryProfit::ResetProfit()
  {
   m_accumulatedProfit = 0;
   WriteGV("ACCUMULATED_PROFIT", 0);
  }

string CRecoveryProfit::GetStateString()
  {
   switch(m_gridsState)
     {
      case STATE_G_IDLE: return "閒置";
      case STATE_G_ACCUMULATING: return "累積中";
      case STATE_G_READY: return "就緒";
      case STATE_G_ACKNOWLEDGED: return "已確認";
      default: return "未知";
     }
  }

#endif
