# Task Completion Reminder Hook

## Hook Configuration

```yaml
name: "Task Completion Reminder"
description: "在所有交辦事項完成時提醒用戶，顯示待命狀態"
trigger: "task_completed"
enabled: true
```

## Hook Logic

當檢測到任務完成時，自動執行以下步驟：

1. 檢查是否所有交辦事項都已完成
2. 確認沒有待處理的錯誤或問題
3. 顯示完成狀態摘要
4. 提醒用戶進入待命狀態

## Implementation

```javascript
// Hook 實現邏輯
async function taskCompletionReminder(context) {
    const { taskType, status, details } = context;
    
    // 檢查任務完成狀態
    if (status === 'completed') {
        console.log(`✅ 任務完成: ${taskType}`);
        
        // 檢查是否還有其他待處理任務
        const pendingTasks = await checkPendingTasks();
        
        if (pendingTasks.length === 0) {
            // 所有任務都已完成
            showCompletionSummary(details);
            showStandbyMessage();
        } else {
            // 還有其他任務待處理
            showRemainingTasks(pendingTasks);
        }
    }
}

// 檢查待處理任務
async function checkPendingTasks() {
    const tasks = [];
    
    // 檢查編譯錯誤
    if (await hasCompileErrors()) {
        tasks.push({
            type: 'compile_error',
            description: '存在編譯錯誤需要修復'
        });
    }
    
    // 檢查未完成的代碼修改
    if (await hasUnfinishedModifications()) {
        tasks.push({
            type: 'code_modification',
            description: '存在未完成的代碼修改'
        });
    }
    
    // 檢查測試需求
    if (await hasTestingRequirements()) {
        tasks.push({
            type: 'testing',
            description: '需要進行測試驗證'
        });
    }
    
    return tasks;
}

// 顯示完成摘要
function showCompletionSummary(details) {
    console.log('\n' + '='.repeat(50));
    console.log('🎉 所有交辦事項已完成');
    console.log('='.repeat(50));
    
    if (details && details.summary) {
        console.log('\n📋 完成摘要:');
        details.summary.forEach((item, index) => {
            console.log(`  ${index + 1}. ✅ ${item}`);
        });
    }
    
    if (details && details.nextSteps) {
        console.log('\n💡 建議下一步:');
        details.nextSteps.forEach((step, index) => {
            console.log(`  ${index + 1}. ${step}`);
        });
    }
    
    console.log('\n' + '='.repeat(50));
}

// 顯示待命消息
function showStandbyMessage() {
    console.log('\n🤖 Agent 狀態: 待命中');
    console.log('📞 如有新的任務需求，請隨時告知');
    console.log('⏰ 準備接收下一個指令...\n');
    
    // 可選：播放提示音或發送通知
    if (process.env.ENABLE_NOTIFICATIONS === 'true') {
        sendNotification('Agent 待命中', '所有任務已完成，準備接收新指令');
    }
}

// 顯示剩餘任務
function showRemainingTasks(tasks) {
    console.log('\n⚠️  還有以下任務待處理:');
    tasks.forEach((task, index) => {
        console.log(`  ${index + 1}. 🔄 ${task.description}`);
    });
    console.log('\n📝 完成所有任務後將進入待命狀態');
}
```

## Usage Examples

### 代碼修改完成時
```
✅ 任務完成: 代碼修改
==================================================
🎉 所有交辦事項已完成
==================================================

📋 完成摘要:
  1. ✅ 修復了 UpdateCurrentBarHighLow 函數缺失問題
  2. ✅ 修復了 6 處 else if 語法錯誤
  3. ✅ 確認括號匹配正確
  4. ✅ 移除了所有進場指標限制

💡 建議下一步:
  1. 在 MetaEditor 中編譯測試
  2. 載入到 MT5 進行實際測試
  3. 觀察純網格功能運行情況

==================================================

🤖 Agent 狀態: 待命中
📞 如有新的任務需求，請隨時告知
⏰ 準備接收下一個指令...
```

### 還有待處理任務時
```
✅ 任務完成: 代碼修改

⚠️  還有以下任務待處理:
  1. 🔄 存在編譯錯誤需要修復
  2. 🔄 需要進行測試驗證

📝 完成所有任務後將進入待命狀態
```

## Configuration

可以通過環境變數配置行為：

```bash
# 啟用系統通知
export ENABLE_NOTIFICATIONS=true

# 設定檢查間隔（秒）
export TASK_CHECK_INTERVAL=30

# 設定待命提醒間隔（分鐘）
export STANDBY_REMINDER_INTERVAL=60
```

## Benefits

1. **明確狀態**：清楚告知用戶所有任務完成狀態
2. **避免等待**：防止用戶不知道是否還在處理中
3. **任務追蹤**：自動檢查是否還有未完成的工作
4. **提高效率**：用戶可以立即知道何時可以進行下一步
5. **專業體驗**：提供類似專業助理的服務體驗