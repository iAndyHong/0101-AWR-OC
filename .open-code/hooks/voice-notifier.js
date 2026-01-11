const { exec } = require('child_process');
const path = require('path');

const HOOK_CONFIG = {
    name: "Voice Notifier",
    description: "負責任務開始與結束的語音提示",
    trigger: ["task_started", "task_completed"],
    enabled: false
};

async function execute(context = {}) {
    try {
        const text = (context.event === 'task_started') ? "開始作業" : "作業完成，待命中";
        const scriptPath = path.join(process.cwd(), 'speech.sh');
        exec(`"${scriptPath}" "${text}"`);
    } catch (e) {
    }
}

module.exports = {
    config: HOOK_CONFIG,
    execute: execute
};
