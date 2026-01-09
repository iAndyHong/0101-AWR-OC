#!/bin/bash

# MQL4 編譯腳本
# 適用於 macOS + Parallels Desktop + Windows 11 虛擬機環境
# 使用獨立的 metaeditor2.exe 避免與常駐 MetaEditor 衝突

# 設定變數
VM_NAME="Windows 11"
MAC_MT4_PATH="${MAC_MT4_PATH:-/Users/andy/MetaTrader 4}"
VM_MT4_PATH="${VM_MT4_PATH:-C:\\MetaTrader4}"
INCLUDE_PATH="${INCLUDE_PATH:-${VM_MT4_PATH}\\MQL4}"
METAEDITOR_PATH="${VM_MT4_PATH}\\metaeditor2.exe"
LOG_FILE="./compile.log"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 函數：顯示使用說明
show_usage() {
    echo -e "${BLUE}使用方法:${NC}"
    echo "  ./compile.sh <檔案名稱.mq4>"
    echo ""
    echo -e "${BLUE}範例:${NC}"
    echo "  ./compile.sh MyEA.mq4"
    echo "  ./compile.sh \"Grids 1.7/Grids 1.17.mq4\""
}

# 函數：記錄訊息
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$LOG_FILE"
}

# 函數：檢查虛擬機狀態
check_vm_status() {
    echo -e "${BLUE}檢查虛擬機狀態...${NC}"
    
    if ! prlctl list -a | grep -q "$VM_NAME"; then
        echo -e "${RED}錯誤: 找不到虛擬機 '$VM_NAME'${NC}"
        return 1
    fi
    
    if ! prlctl list | grep -q "$VM_NAME"; then
        echo -e "${YELLOW}虛擬機未運行，正在啟動...${NC}"
        prlctl start "$VM_NAME"
        sleep 10
    fi
    
    echo -e "${GREEN}虛擬機狀態正常${NC}"
    return 0
}

# 函數：尋找 MQL4 檔案
find_MQL4_file() {
    local input_file="$1"
    local found_file=""
    
    if [ -f "./${input_file}" ]; then
        found_file="$(pwd)/${input_file}"
    elif [[ "$input_file" == /* ]] && [ -f "$input_file" ]; then
        found_file="$input_file"
    elif [ -f "${MAC_MT4_PATH}/${input_file}" ]; then
        found_file="${MAC_MT4_PATH}/${input_file}"
    elif [[ "$input_file" == *.mq4 ]] || [[ "$input_file" == *.MQ4 ]]; then
        local search_dirs=("MQL4/Experts" "MQL4/Indicators" "MQL4/Scripts" "MQL4/Libraries" "MQL4/Include")
        for dir in "${search_dirs[@]}"; do
            if [ -f "${MAC_MT4_PATH}/${dir}/${input_file}" ]; then
                found_file="${MAC_MT4_PATH}/${dir}/${input_file}"
                break
            fi
        done
        
        if [ -z "$found_file" ]; then
            found_file=$(find "${MAC_MT4_PATH}" -name "${input_file}" -type f 2>/dev/null | head -1)
        fi
    fi
    
    echo "$found_file"
}

# 函數：編譯 MQL4 檔案
compile_MQL4() {
    local input_file="$1"
    
    local mac_file_path=$(find_MQL4_file "$input_file")
    
    if [ -z "$mac_file_path" ] || [ ! -f "$mac_file_path" ]; then
        echo -e "${RED}錯誤: 找不到檔案 '$input_file'${NC}"
        return 1
    fi
    
    local relative_path=${mac_file_path#${MAC_MT4_PATH}/}
    local vm_relative_path=$(echo "$relative_path" | sed 's|/|\\|g')
    local vm_file_path="${VM_MT4_PATH}\\${vm_relative_path}"
    
    local auto_log_file="${mac_file_path%.mq4}.log"
    local ex4_file="${mac_file_path%.mq4}.ex4"
    
    echo -e "${BLUE}找到檔案: $mac_file_path${NC}"
    echo -e "${BLUE}開始編譯: $relative_path${NC}"
    log_message "INFO: 開始編譯 $relative_path"
    
    # 記錄編譯前的 ex4 時間戳
    local ex4_time_before=0
    if [ -f "$ex4_file" ]; then
        ex4_time_before=$(stat -f %m "$ex4_file" 2>/dev/null || echo 0)
    fi
    
    # 刪除舊的編譯日誌
    rm -f "$auto_log_file"
    
    echo -e "${YELLOW}正在編譯...${NC}"
    
    # 使用 metaeditor2.exe 編譯（獨立進程，編譯完會自動結束）
    prlctl exec "$VM_NAME" cmd /c "\"${METAEDITOR_PATH}\" /compile:\"${vm_file_path}\" /inc:\"${INCLUDE_PATH}\" /log" 2>&1
    
    # 等待日誌檔生成
    sleep 2
    
    # 分析編譯結果
    local has_errors=0
    local error_details=""
    
    if [ -f "$auto_log_file" ]; then
        local log_content=$(cat "$auto_log_file")
        log_message "COMPILE LOG: $log_content"
        
        local result_line=$(grep "Result:" "$auto_log_file")
        if [ -n "$result_line" ]; then
            echo -e "${BLUE}$result_line${NC}"
            
            local error_count=$(echo "$result_line" | sed -n 's/.*Result: \([0-9]*\) error.*/\1/p')
            if [ -n "$error_count" ] && [ "$error_count" -gt 0 ]; then
                has_errors=1
                error_details=$(grep -i "error\[" "$auto_log_file" | head -20)
            fi
        fi
        
        if echo "$log_content" | grep -v "Result: 0 error" | grep -i "^.*error\[" > /dev/null 2>&1; then
            has_errors=1
            error_details=$(grep -i "error\[" "$auto_log_file" | head -20)
        fi
    else
        echo -e "${YELLOW}警告: 未找到編譯日誌檔${NC}"
    fi
    
    # 檢查 ex4 檔案是否更新
    if [ -f "$ex4_file" ]; then
        local ex4_time_after=$(stat -f %m "$ex4_file" 2>/dev/null || echo 0)
        if [ "$ex4_time_after" -gt "$ex4_time_before" ] && [ "$has_errors" -eq 0 ]; then
            echo -e "${GREEN}編譯成功! ex4 檔案已更新${NC}"
            log_message "SUCCESS: 編譯成功"
            return 0
        fi
    fi
    
    if [ "$has_errors" -eq 1 ]; then
        echo -e "${RED}編譯失敗!${NC}"
        if [ -n "$error_details" ]; then
            echo -e "${RED}錯誤詳情:${NC}"
            echo "$error_details"
        fi
        log_message "ERROR: 編譯失敗"
        return 1
    fi
    
    # 如果沒有錯誤但也沒更新 ex4，可能是警告
    if [ -f "$ex4_file" ]; then
        echo -e "${GREEN}編譯完成${NC}"
        return 0
    fi
    
    echo -e "${RED}編譯失敗: 未生成 ex4 檔案${NC}"
    return 1
}

# 主程式
main() {
    if [ $# -ne 1 ]; then
        echo -e "${RED}錯誤: 請提供 MQL4 檔案${NC}"
        show_usage
        exit 1
    fi
    
    local input_file="$1"
    
    echo "========================================" > "$LOG_FILE"
    log_message "開始編譯: $input_file"
    say  -r 220 開始編譯
    
    if ! check_vm_status; then
        exit 1
    fi
    
    if compile_MQL4 "$input_file"; then
        echo -e "${GREEN}編譯工作完成${NC}"
        say  -r 220 }編譯工作完成
        echo ""
        # 編譯成功後等待 3 秒讓用戶看到結果，然後自動結束
        sleep 3
        exit 0
    else
        echo -e "${RED}編譯工作失敗${NC}"
        say  -r 220 編譯工作失敗
        echo ""
        # 編譯失敗保持終端機開啟，讓用戶查看錯誤
        echo -e "${YELLOW}按 Enter 關閉此終端機...${NC}"
        read -r
        exit 1
    fi
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_usage
    exit 0
fi

main "$@"
