const { exec } = require('child_process');

const HOOK_CONFIG = {
    name: "MQL4 Compile Notifier",
    description: "針對 MQ4/MQH 的編譯成功與失敗事件處理",
    trigger: "file_saved",
    filePattern: ["*.mq4", "*.mqh"],
    enabled: true
};

async function execute(context) {
    const { fileName } = context;
    
    if (!fileName.endsWith('.mq4') && !fileName.endsWith('.mqh')) {
        return;
    }

    let targetToCompile = fileName;
    if (fileName.endsWith('.mqh')) {
        targetToCompile = "Grids 2.3/Grids 2.3.mq4";
    }

    const command = `./compile.sh "${targetToCompile}"`;

    exec(command, (error, stdout) => {
        if (!error) {
            exec('say -r 220 "編譯成功， ex4 檔案已更新"');
        } else {
            exec('say -r 220 "編譯失敗，請檢查代碼錯誤"');
            const errors = stdout.split('\n').filter(line => line.toLowerCase().includes('error')).join('\n');
            if (errors) console.log("\n--- 編譯錯誤摘要 ---\n" + errors);
        }
    });
}

module.exports = {
    config: HOOK_CONFIG,
    execute
};
