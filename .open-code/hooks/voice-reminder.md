# Voice Completion Reminder Hook

## Hook Configuration

```yaml
name: "Voice Completion Reminder"
description: "在任務完成時播放語音提示"
trigger: "task_completed"
enabled: true
```

## Hook Logic

當檢測到任務完成時，自動執行系統語音指令提醒用戶。

## Implementation

```javascript
const { exec } = require('child_process');

async function voiceReminder(context) {
    if (context.status === 'completed') {
        exec('say -r 220 作業完成，待命中', (error) => {
            if (error) {
                console.error(`語音提示失敗: ${error.message}`);
            }
        });
    }
}
```
