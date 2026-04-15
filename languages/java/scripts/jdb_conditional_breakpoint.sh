#!/bin/bash
# ============================================================================
# JDB Conditional Breakpoint - 条件断点支持
# 
# 功能:
# 1. 设置条件断点 (基于JDB的stop命令)
# 2. 自动监控断点命中并检查条件
# 3. 条件不满足时自动继续执行
# 4. 支持临时断点（命中一次后自动删除）
# 
# JDB限制说明:
# 标准JDB不支持原生条件断点语法。本脚本通过以下方式模拟：
# - 设置普通断点
# - 在断点命中时自动检查条件
# - 条件不满足时自动继续执行
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 尝试加载公共函数库
COMMON_LIB="/home/deqiangm/.hermes/cron/interactive-debug-skill-enhancement/common/functions.sh"
if [ -f "$COMMON_LIB" ]; then
    source "$COMMON_LIB"
else
    # 回退到旧的jdb_session.sh
    if [ -f "$SCRIPT_DIR/jdb_session.sh" ]; then
        source "$SCRIPT_DIR/jdb_session.sh"
    fi
fi

# 如果没有加载公共函数，定义基本函数
if ! type log &>/dev/null; then
    log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
    log_error() { echo "ERROR: $1" >&2; }
    error() { log_error "$1"; exit 1; }
fi

# ============================================================================
# 配置
# ============================================================================

JDB_SESSION_PREFIX="jdb_cond_bp"
# 不重复定义DEFAULT_POLL_INTERVAL和DEFAULT_TIMEOUT（已在functions.sh中定义）
COND_BP_POLL_INTERVAL=${DEFAULT_POLL_INTERVAL:-0.5}
COND_BP_TIMEOUT=${DEFAULT_TIMEOUT:-60}

# ============================================================================
# 条件断点数据结构
# ============================================================================

# 存储条件断点的临时文件目录
CONDITION_BP_DIR="/tmp/jdb_cond_bp_$$"

# 初始化条件断点存储
init_cond_bp_storage() {
    mkdir -p "$CONDITION_BP_DIR"
}

# 清理条件断点存储
cleanup_cond_bp_storage() {
    rm -rf "$CONDITION_BP_DIR" 2>/dev/null || true
}

# 保存条件断点信息
# 格式: <session>:<class>:<line> -> <condition>
save_cond_bp() {
    local session="$1"
    local class="$2"
    local line="$3"
    local condition="$4"
    local temp="$5"  # yes/no
    
    local key="${session}_${class}_${line}"
    local file="$CONDITION_BP_DIR/$key"
    
    cat > "$file" << EOF
SESSION=$session
CLASS=$class
LINE=$line
CONDITION=$condition
TEMP=$temp
ACTIVE=yes
HIT_COUNT=0
EOF
    
    log_debug "Saved conditional breakpoint: $class:$line"
}

# 加载条件断点信息
load_cond_bp() {
    local session="$1"
    local class="$2"
    local line="$3"
    
    local key="${session}_${class}_${line}"
    local file="$CONDITION_BP_DIR/$key"
    
    if [ -f "$file" ]; then
        cat "$file"
    fi
}

# 更新命中计数
increment_hit_count() {
    local session="$1"
    local class="$2"
    local line="$3"
    
    local key="${session}_${class}_${line}"
    local file="$CONDITION_BP_DIR/$key"
    
    if [ -f "$file" ]; then
        local count=$(grep "^HIT_COUNT=" "$file" | cut -d= -f2)
        count=$((count + 1))
        sed -i "s/^HIT_COUNT=.*/HIT_COUNT=$count/" "$file"
        echo "$count"
    else
        echo "0"
    fi
}

# 标记断点为非活动
deactivate_cond_bp() {
    local session="$1"
    local class="$2"
    local line="$3"
    
    local key="${session}_${class}_${line}"
    local file="$CONDITION_BP_DIR/$key"
    
    if [ -f "$file" ]; then
        sed -i 's/^ACTIVE=.*/ACTIVE=no/' "$file"
    fi
}

# ============================================================================
# 条件断点操作
# ============================================================================

# 设置条件断点
# 用法: set_conditional_breakpoint <session> <class> <line> <condition> [temp]
set_conditional_breakpoint() {
    local session="$1"
    local class="$2"
    local line="$3"
    local condition="$4"
    local temp="${5:-no}"
    
    # 检查session是否存在
    if ! session_exists "$session"; then
        error "Session '$session' not found"
    fi
    
    # 初始化存储
    init_cond_bp_storage
    
    log "Setting conditional breakpoint at $class:$line"
    log "Condition: $condition"
    [ "$temp" = "yes" ] && log "Temporary: will be removed after first hit"
    
    # 先设置普通断点
    session_send "$session" "stop at ${class}:${line}"
    sleep 0.5
    
    # 保存条件信息
    save_cond_bp "$session" "$class" "$line" "$condition" "$temp"
    
    echo ""
    echo "Conditional breakpoint set:"
    echo "  Location: $class:$line"
    echo "  Condition: $condition"
    echo "  Temporary: $temp"
    echo ""
    echo "Use 'monitor_conditional_breakpoint' to enable automatic condition checking"
}

# 监控条件断点（后台运行）
# 用法: monitor_conditional_breakpoint <session> <class> <line> [check_interval]
monitor_conditional_breakpoint() {
    local session="$1"
    local class="$2"
    local line="$3"
    local interval="${4:-1}"
    
    # 加载条件断点信息
    local bp_info=$(load_cond_bp "$session" "$class" "$line")
    if [ -z "$bp_info" ]; then
        error "No conditional breakpoint found at $class:$line"
    fi
    
    local condition=$(echo "$bp_info" | grep "^CONDITION=" | cut -d= -f2)
    local temp=$(echo "$bp_info" | grep "^TEMP=" | cut -d= -f2)
    
    log "Starting condition monitor for $class:$line"
    log "Checking every ${interval}s"
    
    while true; do
        sleep "$interval"
        
        # 检查断点是否仍然活动
        local active=$(echo "$bp_info" | grep "^ACTIVE=" | cut -d= -f2 2>/dev/null || echo "no")
        if [ "$active" = "no" ]; then
            log "Breakpoint deactivated, stopping monitor"
            break
        fi
        
        # 检查session是否还存在
        if ! session_exists "$session"; then
            log "Session ended, stopping monitor"
            break
        fi
        
        # 读取当前输出，检查是否命中断点
        local output=$(session_read "$session")
        
        if echo "$output" | grep -q "Breakpoint hit.*$class.*line=$line"; then
            log "Breakpoint hit at $class:$line"
            
            # 增加命中计数
            local hit_count=$(increment_hit_count "$session" "$class" "$line")
            log "Hit count: $hit_count"
            
            # 求值条件
            local condition_met=$(evaluate_condition "$session" "$condition")
            
            if [ "$condition_met" = "true" ]; then
                log "${GREEN}Condition met: $condition${NC}"
                echo ""
                echo "============================================"
                echo "CONDITIONAL BREAKPOINT HIT"
                echo "Location: $class:$line"
                echo "Condition: $condition => TRUE"
                echo "============================================"
                echo ""
                
                # 如果是临时断点，清除它
                if [ "$temp" = "yes" ]; then
                    log "Temporary breakpoint, clearing..."
                    session_send "$session" "clear ${class}:${line}"
                    deactivate_cond_bp "$session" "$class" "$line"
                    break
                fi
            else
                log "${YELLOW}Condition not met: $condition => $condition_met${NC}"
                log "Auto-continuing..."
                
                # 自动继续执行
                session_send "$session" "cont"
                
                # 如果是临时断点，清除并退出
                if [ "$temp" = "yes" ]; then
                    session_send "$session" "clear ${class}:${line}"
                    deactivate_cond_bp "$session" "$class" "$line"
                    break
                fi
            fi
        fi
    done
}

# 求值条件表达式
# 用法: evaluate_condition <session> <condition>
# 返回: "true" 或 "false" 或具体的求值结果
evaluate_condition() {
    local session="$1"
    local condition="$2"
    
    # 使用JDB的eval命令求值
    session_send "$session" "eval $condition"
    sleep 0.5
    
    local output=$(session_read "$session")
    
    # 解析求值结果
    # JDB输出格式: "expression = value" 或 "(expression) = value"
    local result=$(echo "$output" | grep -E " = " | tail -1 | sed 's/.* = //')
    
    # 检查是否为布尔值
    case "$result" in
        true|TRUE|True) echo "true" ;;
        false|FALSE|False) echo "false" ;;
        null|NULL|Null) echo "null" ;;
        *) echo "$result" ;;
    esac
}

# 设置临时断点（命中一次后自动删除）
# 用法: set_temporary_breakpoint <session> <class> <line>
set_temporary_breakpoint() {
    local session="$1"
    local class="$2"
    local line="$3"
    
    log "Setting temporary breakpoint at $class:$line"
    
    # 使用条件断点机制，标记为临时
    set_conditional_breakpoint "$session" "$class" "$line" "true" "yes"
}

# 清除断点
# 用法: clear_conditional_breakpoint <session> <class> <line>
clear_conditional_breakpoint() {
    local session="$1"
    local class="$2"
    local line="$3"
    
    log "Clearing conditional breakpoint at $class:$line"
    
    # 发送clear命令
    session_send "$session" "clear ${class}:${line}"
    sleep 0.5
    
    # 标记为非活动
    deactivate_cond_bp "$session" "$class" "$line"
    
    log "Breakpoint cleared"
}

# 列出所有条件断点
list_conditional_breakpoints() {
    local session="$1"
    
    echo "Conditional breakpoints for session: $session"
    echo "----------------------------------------"
    
    if [ -d "$CONDITION_BP_DIR" ]; then
        for file in "$CONDITION_BP_DIR/${session}"_*; do
            if [ -f "$file" ]; then
                local class=$(grep "^CLASS=" "$file" | cut -d= -f2)
                local line=$(grep "^LINE=" "$file" | cut -d= -f2)
                local condition=$(grep "^CONDITION=" "$file" | cut -d= -f2)
                local temp=$(grep "^TEMP=" "$file" | cut -d= -f2)
                local active=$(grep "^ACTIVE=" "$file" | cut -d= -f2)
                local hits=$(grep "^HIT_COUNT=" "$file" | cut -d= -f2)
                
                local status="$active"
                [ "$temp" = "yes" ] && status="$status (temporary)"
                
                printf "  %s:%d\n" "$class" "$line"
                printf "    Condition: %s\n" "$condition"
                printf "    Status: %s, Hits: %s\n" "$status" "$hits"
            fi
        done
    fi
}

# ============================================================================
# 交互式条件断点设置
# ============================================================================

# 在断点命中时手动检查条件
# 用法: check_condition <session> <condition>
check_condition() {
    local session="$1"
    local condition="$2"
    
    log "Checking condition: $condition"
    
    local result=$(evaluate_condition "$session" "$condition")
    
    echo ""
    echo "Condition evaluation result:"
    echo "  $condition = $result"
    echo ""
    
    if [ "$result" = "true" ]; then
        echo "Condition is TRUE - you may want to inspect the state"
        return 0
    else
        echo "Condition is $result - you may want to continue with 'cont'"
        return 1
    fi
}

# ============================================================================
# 帮助和主程序
# ============================================================================

show_help() {
    cat << EOF
jdb_conditional_breakpoint.sh - JDB条件断点支持

用法:
    $0 <command> [arguments...]

命令:
    set <session> <class> <line> "<condition>" [temp]
        设置条件断点
        condition: 布尔表达式，如 "i > 10" 或 "name != null"
        temp: 可选，设为 "yes" 表示临时断点

    set-temp <session> <class> <line>
        设置临时断点（命中一次后自动删除）

    clear <session> <class> <line>
        清除条件断点

    list <session>
        列出所有条件断点

    check <session> "<condition>"
        手动检查条件（在断点命中时使用）

    monitor <session> <class> <line> [interval]
        后台监控条件断点（自动处理条件检查）

    eval <session> "<expression>"
        求值表达式

条件表达式示例:
    i > 10                    变量i大于10时触发
    name != null              name不为null时触发
    count == 5                count等于5时触发
    str.equals("test")        字符串等于"test"时触发
    index >= 0 && index < 10  复合条件

工作原理:
    1. 设置普通JDB断点
    2. 当断点命中时，使用JDB的eval命令检查条件
    3. 条件为false时自动发送cont继续执行
    4. 条件为true时停止，等待用户操作

限制:
    - JDB不支持原生条件断点语法
    - 本脚本通过模拟实现，需要手动启动monitor或手动检查条件
    - 复杂条件可能需要简化

示例:
    # 设置条件断点
    $0 set my_session com.example.UserService 42 "userId > 100"
    
    # 设置临时断点
    $0 set-temp my_session com.example.UserService 50
    
    # 在断点命中时检查条件
    $0 check my_session "i > 10"
    
    # 启动后台监控
    $0 monitor my_session com.example.UserService 42 0.5

EOF
}

# 入口
if [ $# -lt 1 ]; then
    show_help
    exit 1
fi

command="$1"
shift

case "$command" in
    -h|--help)
        show_help
        exit 0
        ;;
    set)
        [ $# -lt 4 ] && error "Usage: $0 set <session> <class> <line> \"<condition>\" [temp]"
        set_conditional_breakpoint "$1" "$2" "$3" "$4" "${5:-no}"
        ;;
    set-temp)
        [ $# -lt 3 ] && error "Usage: $0 set-temp <session> <class> <line>"
        set_temporary_breakpoint "$1" "$2" "$3"
        ;;
    clear)
        [ $# -lt 3 ] && error "Usage: $0 clear <session> <class> <line>"
        clear_conditional_breakpoint "$1" "$2" "$3"
        ;;
    list)
        [ $# -lt 1 ] && error "Usage: $0 list <session>"
        list_conditional_breakpoints "$1"
        ;;
    check)
        [ $# -lt 2 ] && error "Usage: $0 check <session> \"<condition>\""
        check_condition "$1" "$2"
        ;;
    monitor)
        [ $# -lt 3 ] && error "Usage: $0 monitor <session> <class> <line> [interval]"
        monitor_conditional_breakpoint "$1" "$2" "$3" "${4:-1}"
        ;;
    eval)
        [ $# -lt 2 ] && error "Usage: $0 eval <session> \"<expression>\""
        evaluate_condition "$1" "$2"
        ;;
    *)
        error "Unknown command: $command. Use --help for usage."
        ;;
esac

# 清理
trap cleanup_cond_bp_storage EXIT
