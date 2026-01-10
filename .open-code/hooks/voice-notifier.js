const { execSync } = require('child_process');

const HOOK_CONFIG = {
    name: "Voice Notifier",
    description: "負責任務開始與結束的語音提示",
    trigger: ["task_started", "task_completed"],
    enabled: true
};

async function execute(context = {}) {
    try {
        if (context.event === 'task_started') {
            execSync('say -r 220 "開始作業"');
        } else {
            execSync('say -r 220 "作業完成，待命中"');
        }
    } catch (e) {
    }
}

module.exports = {
    config: HOOK_CONFIG,
    execute: execute
};
