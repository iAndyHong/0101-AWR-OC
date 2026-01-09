const { exec } = require('child_process');

const HOOK_CONFIG = {
    name: "Voice Completion Reminder",
    description: "在任務完成時播放語音提示",
    trigger: "task_completed",
    enabled: true
};

async function voiceReminder(context = {}) {
    if (context.status === 'completed' || context.taskType) {
        exec('say -r 220 作業完成，待命中');
    }
}

module.exports = {
    config: HOOK_CONFIG,
    execute: voiceReminder
};
