# MQL4 Compile Notifier Hook

## Hook Configuration

```yaml
name: "MQL4 Compile Notifier"
description: "針對 MQ4/MQH 的編譯成功與失敗事件處理"
trigger: "file_saved"
patterns: ["*.mq4", "*.mqh"]
enabled: true
```

## Hook Logic

當檢測到 MQ4 或 MQH 檔案儲存時，自動觸發以下行為：

1.  **自動辨識目標**：若修改的是 `.mqh`，自動指向 `Grids 2.3.mq4` 進行編譯。
2.  **執行編譯**：調用 `./compile.sh` 進行虛擬機端編譯。
3.  **語音回饋**：
    *   **編譯成功**：播放「編譯成功，ex4 檔案已更新」。
    *   **編譯失敗**：播放「編譯失敗，請檢查代碼錯誤」。
4.  **錯誤摘要**：在終端機列出所有 `error` 關鍵字行，方便快速定位。

## Implementation

實作於 `.open-code/hooks/mql4-compile-notifier.js`。
