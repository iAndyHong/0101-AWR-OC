/**
 * Auto Compile Check Hook
 * 每次修改 MQL5 代碼後自動執行編譯檢查
 */

const fs = require('fs').promises;
const path = require('path');
const { exec } = require('child_process');
const { promisify } = require('util');

const execAsync = promisify(exec);

// Hook 配置
const HOOK_CONFIG = {
    name: "Auto Compile Check",
    description: "每次修改 MQL5 代碼後自動執行編譯檢查",
    trigger: "file_saved",
    filePattern: "*.mq5",
    enabled: true
};

// 主要 Hook 函數
async function autoCompileCheck(context) {
    const { filePath, fileName } = context;
    
    // 只處理 MQL5 文件
    if (!fileName.endsWith('.mq5')) {
        return;
    }
    
    console.log(`🔍 檢測到 MQL5 文件修改: ${fileName}`);
    
    try {
        // 執行編譯
        console.log(`📦 開始編譯 ${fileName}...`);
        const compileResult = await executeCompile(fileName);
        
        if (compileResult.success) {
            console.log(`✅ ${fileName} 編譯成功`);
            await logMessage(`SUCCESS: ${fileName} 編譯成功`);
        } else {
            console.log(`❌ ${fileName} 編譯失敗`);
            await logMessage(`ERROR: ${fileName} 編譯失敗`);
            
            // 讀取並分析編譯日誌
            await analyzeAndReportErrors(fileName);
        }
    } catch (error) {
        console.error(`💥 編譯檢查失敗: ${error.message}`);
        await logMessage(`FATAL ERROR: 編譯檢查失敗 - ${error.message}`);
    }
}

// 執行編譯
async function executeCompile(fileName) {
    try {
        const { stdout, stderr } = await execAsync(`./compile.sh "${fileName}"`);
        
        return {
            success: true,
            stdout,
            stderr
        };
    } catch (error) {
        return {
            success: false,
            stdout: error.stdout || '',
            stderr: error.stderr || '',
            error: error.message
        };
    }
}

// 分析並報告錯誤
async function analyzeAndReportErrors(fileName) {
    try {
        // 讀取編譯日誌
        const logContent = await fs.readFile('./compile.log', 'utf8');
        
        // 分析錯誤
        const errorAnalysis = analyzeCompileErrors(logContent);
        
        // 輸出錯誤分析結果
        console.log(`\n📋 ${fileName} 編譯錯誤分析:`);
        console.log('=' .repeat(50));
        
        if (errorAnalysis.errors.length > 0) {
            console.log('🚨 發現的錯誤:');
            errorAnalysis.errors.forEach((error, index) => {
                console.log(`  ${index + 1}. ${error.message}`);
                if (error.line) {
                    console.log(`     詳情: ${error.line}`);
                }
            });
        }
        
        if (errorAnalysis.suggestions.length > 0) {
            console.log('\n💡 修正建議:');
            errorAnalysis.suggestions.forEach((suggestion, index) => {
                console.log(`  ${index + 1}. ${suggestion}`);
            });
        }
        
        // 如果有可自動修正的錯誤，提供修正選項
        if (errorAnalysis.autoFixable) {
            console.log('\n🔧 可自動修正的錯誤:');
            for (const fix of errorAnalysis.fixes) {
                if (fix.type === 'fixVersionFormat') {
                    await handleVersionFormatFix(fileName, fix.data);
                }
            }
        }
        
        console.log('\n📄 完整錯誤日誌請查看: ./compile.log');
        console.log('=' .repeat(50));
        
        // 記錄到日誌
        await logMessage(`ERROR ANALYSIS for ${fileName}:`);
        await logMessage(`Errors found: ${errorAnalysis.errors.length}`);
        await logMessage(`Auto-fixable: ${errorAnalysis.autoFixable}`);
        
    } catch (error) {
        console.error(`❌ 無法分析編譯錯誤: ${error.message}`);
        await logMessage(`ERROR: 無法分析編譯錯誤 - ${error.message}`);
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
            pattern: /version '([^']+)' is incompatible with MQL5 Market/,
            message: "版本號格式不符合 MQL5 Market 要求",
            suggestion: "版本號必須是 xxx.yyy 格式（如 1.00, 2.15）",
            autoFix: true,
            fixType: 'fixVersionFormat'
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
        },
        {
            pattern: /(\d+) errors?, (\d+) warnings?/,
            message: "編譯發現錯誤和警告",
            suggestion: "請檢查具體的錯誤和警告信息",
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
                        type: pattern.fixType,
                        data: match[1] || null
                    });
                }
            }
        }
    }
    
    return { errors, suggestions, fixes, autoFixable };
}

// 處理版本號格式修正
async function handleVersionFormatFix(fileName, invalidVersion) {
    try {
        console.log(`\n🔧 發現版本號格式錯誤: "${invalidVersion}"`);
        
        // 生成修正後的版本號
        const newVersion = generateValidVersion(invalidVersion);
        console.log(`💡 建議修正為: "${newVersion}"`);
        
        // 詢問是否自動修正（在實際環境中，這裡可以是用戶交互）
        console.log(`❓ 是否自動修正版本號？ (建議: 是)`);
        
        // 自動修正（在生產環境中可以添加用戶確認）
        const autoFix = true; // 可以改為用戶輸入或配置
        
        if (autoFix) {
            await applyVersionFix(fileName, invalidVersion, newVersion);
        }
        
    } catch (error) {
        console.error(`❌ 處理版本號修正失敗: ${error.message}`);
        await logMessage(`ERROR: 處理版本號修正失敗 - ${error.message}`);
    }
}

// 生成有效的版本號
function generateValidVersion(invalidVersion) {
    // 移除非數字字符，保留點號
    const cleaned = invalidVersion.replace(/[^0-9.]/g, '');
    const parts = cleaned.split('.');
    
    // 確保至少有兩個部分
    const major = parts[0] || '1';
    const minor = parts[1] || '00';
    
    // 格式化為 xx.yy
    return `${major.padStart(1, '0')}.${minor.padStart(2, '0')}`;
}

// 應用版本號修正
async function applyVersionFix(fileName, oldVersion, newVersion) {
    try {
        // 讀取文件內容
        const fileContent = await fs.readFile(fileName, 'utf8');
        
        // 替換版本號
        const searchPattern = `#property version     "${oldVersion}"`;
        const replacement = `#property version     "${newVersion}"`;
        
        if (fileContent.includes(searchPattern)) {
            const newContent = fileContent.replace(searchPattern, replacement);
            
            // 寫回文件
            await fs.writeFile(fileName, newContent, 'utf8');
            
            console.log(`✅ 版本號已自動修正: "${oldVersion}" → "${newVersion}"`);
            await logMessage(`AUTO-FIX: 版本號已修正 ${oldVersion} → ${newVersion} in ${fileName}`);
            
            // 自動重新編譯
            console.log(`🔄 重新編譯 ${fileName}...`);
            setTimeout(async () => {
                const recompileResult = await executeCompile(fileName);
                if (recompileResult.success) {
                    console.log(`✅ 修正後重新編譯成功!`);
                    await logMessage(`SUCCESS: 修正後重新編譯成功 - ${fileName}`);
                } else {
                    console.log(`❌ 修正後重新編譯仍有錯誤，請檢查其他問題`);
                    await logMessage(`WARNING: 修正後重新編譯仍有錯誤 - ${fileName}`);
                }
            }, 2000);
            
        } else {
            console.log(`⚠️  未找到版本號聲明，請手動檢查文件`);
            await logMessage(`WARNING: 未找到版本號聲明 in ${fileName}`);
        }
        
    } catch (error) {
        console.error(`❌ 應用版本號修正失敗: ${error.message}`);
        await logMessage(`ERROR: 應用版本號修正失敗 - ${error.message}`);
    }
}

// 記錄消息到日誌文件
async function logMessage(message) {
    try {
        const timestamp = new Date().toISOString();
        const logEntry = `[${timestamp}] HOOK: ${message}\n`;
        await fs.appendFile('./auto-compile-hook.log', logEntry);
    } catch (error) {
        console.error(`無法寫入日誌: ${error.message}`);
    }
}

// 導出 Hook 函數
module.exports = {
    config: HOOK_CONFIG,
    execute: autoCompileCheck
};

// 如果直接運行此腳本，執行測試
if (require.main === module) {
    // 測試用例
    const testContext = {
        filePath: './Grids Zero - 1.01.mq5',
        fileName: 'Grids Zero - 1.01.mq5'
    };
    
    console.log('🧪 測試 Auto Compile Check Hook...');
    autoCompileCheck(testContext).then(() => {
        console.log('✅ Hook 測試完成');
    }).catch(error => {
        console.error('❌ Hook 測試失敗:', error);
    });
}