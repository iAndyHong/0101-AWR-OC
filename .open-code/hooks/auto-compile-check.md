# Auto Compile Check Hook

## Hook Configuration

```yaml
name: "Auto Compile Check"
description: "每次修改 MQL4 代碼後自動執行編譯檢查"
trigger: "file_saved"
filePattern: "*.mq4"
enabled: true
```

## Hook Logic

當保存 MQL4 文件時，自動執行以下步驟：

1. 執行 `./compile.sh <filename>` 進行編譯
2. 如果編譯失敗，自動查看編譯日誌
3. 分析錯誤並提供修正建議
4. 如果需要，自動修正常見的編譯錯誤

## Implementation

```javascript
// Hook 實現邏輯
async function autoCompileCheck(context) {
    const { filePath, fileName } = context;
    
    // 只處理 MQL4 文件
    if (!fileName.endsWith('.mq4')) {
        return;
    }
    
    console.log(`檢測到 MQL4 文件修改: ${fileName}`);
    
    try {
        // 執行編譯
        const compileResult = await executeCommand(`./compile.sh "${fileName}"`);
        
        if (compileResult.exitCode === 0) {
            console.log(`✅ ${fileName} 編譯成功`);
            showNotification(`${fileName} 編譯成功`, 'success');
        } else {
            console.log(`❌ ${fileName} 編譯失敗`);
            
            // 讀取編譯日誌
            const logContent = await readFile('./compile.log');
            
            // 分析錯誤並提供修正建議
            const errorAnalysis = analyzeCompileErrors(logContent);
            
            // 顯示錯誤信息和修正建議
            showCompileErrorDialog({
                fileName,
                errors: errorAnalysis.errors,
                suggestions: errorAnalysis.suggestions,
                logContent
            });
            
            // 如果是常見錯誤，提供自動修正選項
            if (errorAnalysis.autoFixable) {
                offerAutoFix(filePath, errorAnalysis.fixes);
            }
        }
    } catch (error) {
        console.error(`編譯檢查失敗: ${error.message}`);
        showNotification(`編譯檢查失敗: ${error.message}`, 'error');
    }
}

// 分析編譯錯誤
function analyzeCompileErrors(logContent) {
    const errors = [];
    const suggestions = [];
    const fixes = [];
    let autoFixable = false;
    
    // 常見錯誤模式
    const errorPatterns = [
        {
            pattern: /version '([^']+)' is incompatible with MQL4 Market/,
            message: "版本號格式不符合 MQL4 Market 要求",
            suggestion: "版本號必須是 xxx.yyy 格式（如 1.00, 2.15）",
            autoFix: true,
            fixFunction: fixVersionFormat
        },
        {
            pattern: /event handling function not found/,
            message: "缺少必要的事件處理函數",
            suggestion: "請確保包含 OnInit(), OnDeinit(), OnTick() 等必要函數",
            autoFix: false
        },
        {
            pattern: /undeclared identifier '([^']+)'/,
            message: "未聲明的標識符",
            suggestion: "請檢查變數或函數名稱是否正確，或是否缺少包含文件",
            autoFix: false
        },
        {
            pattern: /syntax error/,
            message: "語法錯誤",
            suggestion: "請檢查代碼語法，特別注意括號、分號等符號",
            autoFix: false
        }
    ];
    
    // 分析日誌內容
    const lines = logContent.split('\n');
    
    for (const line of lines) {
        for (const pattern of errorPatterns) {
            const match = line.match(pattern.pattern);
            if (match) {
                errors.push({
                    line: line.trim(),
                    message: pattern.message,
                    match: match[1] || null
                });
                
                suggestions.push(pattern.suggestion);
                
                if (pattern.autoFix) {
                    autoFixable = true;
                    fixes.push({
                        type: pattern.fixFunction.name,
                        data: match[1] || null
                    });
                }
            }
        }
    }
    
    return { errors, suggestions, fixes, autoFixable };
}

// 自動修正版本號格式
function fixVersionFormat(filePath, invalidVersion) {
    // 將版本號轉換為符合要求的格式
    const versionParts = invalidVersion.split(/[-._]/);
    const majorMinor = versionParts.slice(0, 2);
    
    // 確保有兩個數字部分
    if (majorMinor.length < 2) {
        majorMinor.push('00');
    }
    
    const newVersion = `${majorMinor[0]}.${majorMinor[1].padStart(2, '0')}`;
    
    return {
        search: `#property version     "${invalidVersion}"`,
        replace: `#property version     "${newVersion}"`,
        description: `將版本號從 "${invalidVersion}" 修正為 "${newVersion}"`
    };
}

// 提供自動修正選項
async function offerAutoFix(filePath, fixes) {
    const response = await showConfirmDialog({
        title: "自動修正編譯錯誤",
        message: "發現可以自動修正的錯誤，是否要自動修正？",
        details: fixes.map(fix => fix.description).join('\n'),
        confirmText: "自動修正",
        cancelText: "手動修正"
    });
    
    if (response.confirmed) {
        await applyAutoFixes(filePath, fixes);
    }
}

// 應用自動修正
async function applyAutoFixes(filePath, fixes) {
    try {
        let fileContent = await readFile(filePath);
        
        for (const fix of fixes) {
            if (fix.type === 'fixVersionFormat') {
                const fixData = fixVersionFormat(filePath, fix.data);
                fileContent = fileContent.replace(fixData.search, fixData.replace);
                console.log(`✅ ${fixData.description}`);
            }
        }
        
        await writeFile(filePath, fileContent);
        showNotification("自動修正完成，請重新編譯", 'success');
        
        // 自動重新編譯
        setTimeout(() => {
            executeCommand(`./compile.sh "${path.basename(filePath)}"`);
        }, 1000);
        
    } catch (error) {
        console.error(`自動修正失敗: ${error.message}`);
        showNotification(`自動修正失敗: ${error.message}`, 'error');
    }
}
```

## Usage

這個 Hook 會在以下情況自動觸發：

1. 保存任何 `.mq4` 文件時
2. 自動執行 `./compile.sh` 進行編譯檢查
3. 如果編譯失敗，會：
   - 顯示錯誤信息
   - 分析常見錯誤類型
   - 提供修正建議
   - 對於可自動修正的錯誤（如版本號格式），提供一鍵修正功能

## Error Types Handled

- ✅ 版本號格式錯誤（自動修正）
- ✅ 缺少事件處理函數（提示）
- ✅ 未聲明標識符（提示）
- ✅ 語法錯誤（提示）
- ✅ 其他編譯錯誤（通用處理）

## Benefits

1. **即時反饋**：保存文件後立即知道編譯結果
2. **錯誤分析**：自動分析常見錯誤並提供解決建議
3. **自動修正**：對於格式類錯誤可以一鍵修正
4. **提高效率**：減少手動編譯和錯誤排查時間
5. **學習輔助**：通過錯誤分析幫助理解 MQL4 編程規範