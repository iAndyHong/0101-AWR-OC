/**
 * Task Completion Reminder Hook
 * 在所有交辦事項完成時提醒用戶，顯示待命狀態
 */

const fs = require('fs').promises;
const path = require('path');

// Hook 配置
const HOOK_CONFIG = {
    name: "Task Completion Reminder",
    description: "在所有交辦事項完成時提醒用戶，顯示待命狀態",
    trigger: "task_completed",
    enabled: true
};

// 主要 Hook 函數
async function taskCompletionReminder(context = {}) {
    const { taskType = "未指定任務", status = "completed", details = {} } = context;
    
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

// 檢查待處理任務
async function checkPendingTasks() {
    const tasks = [];
    
    try {
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
        
    } catch (error) {
        console.log(`⚠️  檢查待處理任務時發生錯誤: ${error.message}`);
    }
    
    return tasks;
}

// 檢查是否有編譯錯誤
async function hasCompileErrors() {
    try {
        // 檢查編譯日誌文件
        const logFile = './compile.log';
        if (await fileExists(logFile)) {
            const logContent = await fs.readFile(logFile, 'utf8');
            
            // 檢查是否有錯誤信息
            const hasErrors = logContent.includes('error') || 
                            logContent.includes('錯誤') ||
                            logContent.includes('failed') ||
                            logContent.includes('失敗');
            
            return hasErrors;
        }
        
        return false;
    } catch (error) {
        return false;
    }
}

// 檢查是否有未完成的代碼修改
async function hasUnfinishedModifications() {
    try {
        // 檢查是否有 .tmp 或 .backup 文件
        const files = await fs.readdir('.');
        const hasBackupFiles = files.some(file => 
            file.endsWith('.tmp') || 
            file.endsWith('.backup') ||
            file.includes('.backup.')
        );
        
        return hasBackupFiles;
    } catch (error) {
        return false;
    }
}

// 檢查是否有測試需求
async function hasTestingRequirements() {
    try {
        // 檢查是否有新修改的 MQL5 文件需要測試
        const files = await fs.readdir('.');
        const mql5Files = files.filter(file => file.endsWith('.mq5'));
        
        for (const file of mql5Files) {
            const stats = await fs.stat(file);
            const modifiedTime = stats.mtime;
            const now = new Date();
            const timeDiff = (now - modifiedTime) / (1000 * 60); // 分鐘
            
            // 如果文件在最近 30 分鐘內修改過，認為需要測試
            if (timeDiff < 30) {
                return true;
            }
        }
        
        return false;
    } catch (error) {
        return false;
    }
}

// 檢查文件是否存在
async function fileExists(filePath) {
    try {
        await fs.access(filePath);
        return true;
    } catch {
        return false;
    }
}

// 顯示完成摘要
function showCompletionSummary(details) {
    console.log('\n' + '='.repeat(50));
    console.log('🎉 所有交辦事項已完成');
    console.log('='.repeat(50));
    
    if (details && details.summary && details.summary.length > 0) {
        console.log('\n📋 完成摘要:');
        details.summary.forEach((item, index) => {
            console.log(`  ${index + 1}. ✅ ${item}`);
        });
    }
    
    if (details && details.nextSteps && details.nextSteps.length > 0) {
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
    
    // 記錄待命狀態到日誌
    logStandbyStatus();
}

// 顯示剩餘任務
function showRemainingTasks(tasks) {
    console.log('\n⚠️  還有以下任務待處理:');
    tasks.forEach((task, index) => {
        console.log(`  ${index + 1}. 🔄 ${task.description}`);
    });
    console.log('\n📝 完成所有任務後將進入待命狀態');
}

// 記錄待命狀態
async function logStandbyStatus() {
    try {
        const timestamp = new Date().toISOString();
        const logEntry = `[${timestamp}] AGENT STATUS: 待命中 - 所有任務已完成\n`;
        await fs.appendFile('./agent-status.log', logEntry);
    } catch (error) {
        // 忽略日誌錯誤
    }
}

// 創建預設的完成上下文
function createCompletionContext(taskType, summary = [], nextSteps = []) {
    return {
        taskType,
        status: 'completed',
        details: {
            summary,
            nextSteps
        }
    };
}

// 導出 Hook 函數和工具函數
module.exports = {
    config: HOOK_CONFIG,
    execute: taskCompletionReminder,
    createCompletionContext,
    
    // 便利函數
    codeModificationCompleted: (summary, nextSteps) => {
        return taskCompletionReminder(
            createCompletionContext('代碼修改', summary, nextSteps)
        );
    },
    
    compileCheckCompleted: (summary, nextSteps) => {
        return taskCompletionReminder(
            createCompletionContext('編譯檢查', summary, nextSteps)
        );
    },
    
    testingCompleted: (summary, nextSteps) => {
        return taskCompletionReminder(
            createCompletionContext('測試驗證', summary, nextSteps)
        );
    },
    
    generalTaskCompleted: (taskType, summary, nextSteps) => {
        return taskCompletionReminder(
            createCompletionContext(taskType, summary, nextSteps)
        );
    }
};

// 如果直接運行此腳本，執行測試
if (require.main === module) {
    console.log('🧪 測試 Task Completion Reminder Hook...');
    
    // 測試代碼修改完成
    const testSummary = [
        '修復了 UpdateCurrentBarHighLow 函數缺失問題',
        '修復了 6 處 else if 語法錯誤',
        '確認括號匹配正確',
        '移除了所有進場指標限制'
    ];
    
    const testNextSteps = [
        '在 MetaEditor 中編譯測試',
        '載入到 MT5 進行實際測試',
        '觀察純網格功能運行情況'
    ];
    
    taskCompletionReminder(
        createCompletionContext('代碼修改', testSummary, testNextSteps)
    ).then(() => {
        console.log('✅ Hook 測試完成');
    }).catch(error => {
        console.error('❌ Hook 測試失敗:', error);
    });
}