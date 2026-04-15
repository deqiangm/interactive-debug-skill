#!/bin/bash
# ============================================================================
# JDB Advanced Breakpoint Manager - 高级断点管理
# 
# 功能:
# - 条件断点 (conditional breakpoint)
# - 临时断点 (temporary breakpoint)
# - 观察点 (watchpoint)
# - 方法断点 (method breakpoint)
# - 异常断点 (exception breakpoint)
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common/functions.sh"

# ============================================================================
# 断点类型
# ============================================================================

# 创建条件断点
# 条件断点在满足条件时才触发
create_conditional_breakpoint() {
    local session_name="$1"
    local location="$2"      # Class:line 或 Class.method
    local condition="$3"     # 条件表达式
    
    log "Creating conditional breakpoint at $location"
    log "Condition: $condition"
    
    # JDB通过在断点后手动检查条件来模拟条件断点
    # 步骤: 设置断点 -> 命中断点 -> 检查条件 -> 如果不满足则continue
    
    # 首先设置断点
    session_send "$session_name" "stop at $location"
    
    # 等待断点设置确认
    local output=$(session_poll "$session_name" 5 0.5)
    
    # 创建条件断点脚本（供后续使用）
    local bp_id=$(echo "$location" | tr ':.' '__')
    local script_file="/tmp/jdb_cond_bp_${bp_id}.sh"
    
    cat > "$script_file" << EOF
#!/bin/bash
# Conditional breakpoint script for $location
# Condition: $condition

# 当断点命中时，执行此脚本检查条件
# 返回0表示应该暂停，返回1表示应该继续

# 获取变量值
RESULT=\$(session_exec_poll "$session_name" "print $condition" 5 0.5)

# 检查结果是否为true
if echo "\$RESULT" | grep -qE "true|= 1[^0-9]"; then
    echo "Condition met: $condition = true"
    exit 0
else
    echo "Condition not met, continuing..."
    session_send "$session_name" "cont"
    exit 1
fi
EOF
    chmod +x "$script_file"
    
    log "Conditional breakpoint script created: $script_file"
    echo "BP_ID=$bp_id"
    echo "SCRIPT=$script_file"
}

# 创建临时断点（只触发一次）
create_temporary_breakpoint() {
    local session_name="$1"
    local location="$2"
    
    log "Creating temporary breakpoint at $location"
    
    # 设置断点
    session_send "$session_name" "stop at $location"
    local output=$(session_poll "$session_name" 5 0.5)
    
    # 创建自动清除脚本
    local bp_id=$(echo "$location" | tr ':.' '__')
    local cleanup_script="/tmp/jdb_temp_bp_cleanup_${bp_id}.sh"
    
    cat > "$cleanup_script" << EOF
#!/bin/bash
# Temporary breakpoint cleanup script
# This will be called after the breakpoint is hit once

session_send "$session_name" "clear $location"
echo "Temporary breakpoint at $location cleared"
EOF
    chmod +x "$cleanup_script"
    
    log "Temporary breakpoint set. Cleanup script: $cleanup_script"
    echo "CLEANUP_SCRIPT=$cleanup_script"
}

# 创建观察点（监视字段访问/修改）
# JDB通过watch命令实现
create_watchpoint() {
    local session_name="$1"
    local class="$2"
    local field="$3"
    local access_type="${4:-all}"  # all, read, write
    
    log "Creating watchpoint for $class.$field (type: $access_type)"
    
    case "$access_type" in
        read)
            session_send "$session_name" "watch access $class.$field"
            ;;
        write)
            session_send "$session_name" "watch modification $class.$field"
            ;;
        all|*)
            session_send "$session_name" "watch access $class.$field"
            session_send "$session_name" "watch modification $class.$field"
            ;;
    esac
    
    local output=$(session_poll "$session_name" 5 0.5)
    
    if echo "$output" | grep -q "Unable to watch"; then
        log_warn "Watchpoint may not be supported for this field"
    else
        log "Watchpoint created successfully"
    fi
}

# 创建方法断点
create_method_breakpoint() {
    local session_name="$1"
    local class="$2"
    local method="$3"
    
    log "Creating method breakpoint for $class.$method"
    
    session_send "$session_name" "stop in $class.$method"
    local output=$(session_poll "$session_name" 5 0.5)
    
    if echo "$output" | grep -qE "Set|Deferring"; then
        log "Method breakpoint set successfully"
    else
        log_warn "Failed to set method breakpoint"
    fi
}

# 创建异常断点
create_exception_breakpoint() {
    local session_name="$1"
    local exception_class="${2:-java.lang.Throwable}"
    local caught="${3:-both}"  # caught, uncaught, both
    
    log "Creating exception breakpoint for $exception_class"
    
    case "$caught" in
        caught)
            session_send "$session_name" "catch $exception_class"
            ;;
        uncaught)
            session_send "$session_name" "catch $exception_class"
            ;;
        both|*)
            # JDB的catch默认捕获所有
            session_send "$session_name" "catch $exception_class"
            ;;
    esac
    
    local output=$(session_poll "$session_name" 5 0.5)
    log "Exception breakpoint output: $output"
}

# ============================================================================
# 断点管理
# ============================================================================

# 列出所有断点
list_breakpoints() {
    local session_name="$1"
    
    log "Listing all breakpoints..."
    
    session_send "$session_name" "stop"
    local output=$(session_poll "$session_name" 5 0.5)
    
    echo "$output"
}

# 清除断点
clear_breakpoint() {
    local session_name="$1"
    local location="$2"
    
    log "Clearing breakpoint at $location"
    
    session_send "$session_name" "clear $location"
    local output=$(session_poll "$session_name" 5 0.5)
    
    echo "$output"
}

# 清除所有断点
clear_all_breakpoints() {
    local session_name="$1"
    
    log "Clearing all breakpoints..."
    
    # 获取所有断点
    session_send "$session_name" "stop"
    local output=$(session_poll "$session_name" 5 0.5)
    
    # 解析并清除每个断点
    echo "$output" | grep -oE '[0-9]+:' | while read bp; do
        local bp_num=$(echo "$bp" | tr -d ':')
        session_send "$session_name" "clear $bp_num"
        sleep 0.5
    done
    
    log "All breakpoints cleared"
}

# ============================================================================
# 条件断点处理
# ============================================================================

# 当断点命中时检查条件
# 需要在断点命中后手动调用
check_breakpoint_condition() {
    local session_name="$1"
    local condition="$2"
    
    log "Checking condition: $condition"
    
    # 执行条件表达式
    session_send "$session_name" "eval $condition"
    local output=$(session_poll "$session_name" 5 0.5)
    
    # 解析结果
    if echo "$output" | grep -qE "true|[^a-zA-Z]1[^0-9]"; then
        log "Condition met"
        return 0
    else
        log "Condition not met, continuing..."
        session_send "$session_name" "cont"
        return 1
    fi
}

# ============================================================================
# 高级断点脚本
# ============================================================================

# 自动条件断点检测循环
# 用于自动化调试场景
auto_conditional_loop() {
    local session_name="$1"
    local location="$2"
    local condition="$3"
    local max_iterations="${4:-100}"
    
    log "Starting auto conditional loop for $location with condition: $condition"
    
    local iteration=0
    while [ $iteration -lt $max_iterations ]; do
        # 等待断点命中
        session_send "$session_name" "cont"
        local output=$(session_poll "$session_name" 10 0.5)
        
        if echo "$output" | grep -q "Breakpoint hit"; then
            # 检查条件
            if check_breakpoint_condition "$session_name" "$condition"; then
                log "Condition met at iteration $iteration"
                echo "CONDITION_MET=$iteration"
                return 0
            fi
        elif echo "$output" | grep -qE "exited|The application exited"; then
            log "Application exited without meeting condition"
            return 1
        fi
        
        iteration=$((iteration + 1))
    done
    
    log_warn "Max iterations reached without meeting condition"
    return 2
}

# ============================================================================
# 断点模板
# ============================================================================

# 常用条件断点模板
apply_bp_template() {
    local session_name="$1"
    local template="$2"
    local params="$3"
    
    case "$template" in
        null_check)
            # 检查变量是否为null
            local var_name="$params"
            create_conditional_breakpoint "$session_name" "$location" "$var_name == null"
            ;;
        array_bounds)
            # 检查数组越界
            local arr_name=$(echo "$params" | cut -d',' -f1)
            local idx_name=$(echo "$params" | cut -d',' -f2)
            create_conditional_breakpoint "$session_name" "$location" "$idx_name >= $arr_name.length"
            ;;
        value_change)
            # 检查值变化
            local var_name="$params"
            create_watchpoint "$session_name" "$class" "$var_name" "write"
            ;;
        loop_iteration)
            # 在特定循环迭代时中断
            local iter_num="$params"
            create_conditional_breakpoint "$session_name" "$location" "i == $iter_num"
            ;;
        *)
            log_warn "Unknown template: $template"
            ;;
    esac
}

# ============================================================================
# 帮助
# ============================================================================

show_usage() {
    cat << EOF
JDB Advanced Breakpoint Manager

用法:
    $0 <command> [arguments...]

命令:
    # 条件断点
    cond <session> <Class:line> "<condition>"
        创建条件断点
        示例: $0 cond mysession BubbleSort:11 "i > 5"
    
    # 临时断点
    temp <session> <Class:line>
        创建临时断点（只触发一次）
        示例: $0 temp mysession BubbleSort:11
    
    # 观察点
    watch <session> <Class> <field> [read|write|all]
        创建观察点
        示例: $0 watch mysession BubbleSort arr write
    
    # 方法断点
    method <session> <Class> <method>
        创建方法断点
        示例: $0 method mysession BubbleSort sort
    
    # 异常断点
    exception <session> [ExceptionClass]
        创建异常断点
        示例: $0 exception mysession NullPointerException
    
    # 管理
    list <session>
        列出所有断点
    
    clear <session> <Class:line>
        清除指定断点
    
    clear-all <session>
        清除所有断点
    
    # 条件检查
    check-cond <session> "<condition>"
        检查条件（在断点命中后使用）
    
    # 自动循环
    auto-cond <session> <Class:line> "<condition>" [max_iter]
        自动循环直到条件满足

示例:
    # 创建条件断点: i > 3时中断
    $0 cond mysession BubbleSort:11 "i > 3"
    
    # 创建观察点: 监视arr字段修改
    $0 watch mysession BubbleSort arr write
    
    # 创建异常断点: NullPointerException时中断
    $0 exception mysession NullPointerException

EOF
}

# ============================================================================
# 主程序
# ============================================================================

if [ $# -lt 1 ]; then
    show_usage
    exit 1
fi

command="$1"
shift

case "$command" in
    cond|conditional)
        [ $# -lt 3 ] && error "Usage: $0 cond <session> <Class:line> \"<condition>\""
        create_conditional_breakpoint "$1" "$2" "$3"
        ;;
    temp|temporary)
        [ $# -lt 2 ] && error "Usage: $0 temp <session> <Class:line>"
        create_temporary_breakpoint "$1" "$2"
        ;;
    watch|watchpoint)
        [ $# -lt 3 ] && error "Usage: $0 watch <session> <Class> <field> [read|write|all]"
        create_watchpoint "$1" "$2" "$3" "${4:-all}"
        ;;
    method)
        [ $# -lt 3 ] && error "Usage: $0 method <session> <Class> <method>"
        create_method_breakpoint "$1" "$2" "$3"
        ;;
    exception)
        [ $# -lt 1 ] && error "Usage: $0 exception <session> [ExceptionClass]"
        create_exception_breakpoint "$1" "${2:-java.lang.Throwable}"
        ;;
    list)
        [ $# -lt 1 ] && error "Usage: $0 list <session>"
        list_breakpoints "$1"
        ;;
    clear)
        [ $# -lt 2 ] && error "Usage: $0 clear <session> <Class:line>"
        clear_breakpoint "$1" "$2"
        ;;
    clear-all)
        [ $# -lt 1 ] && error "Usage: $0 clear-all <session>"
        clear_all_breakpoints "$1"
        ;;
    check-cond)
        [ $# -lt 2 ] && error "Usage: $0 check-cond <session> \"<condition>\""
        check_breakpoint_condition "$1" "$2"
        ;;
    auto-cond)
        [ $# -lt 3 ] && error "Usage: $0 auto-cond <session> <Class:line> \"<condition>\" [max_iter]"
        auto_conditional_loop "$1" "$2" "$3" "${4:-100}"
        ;;
    -h|--help)
        show_usage
        exit 0
        ;;
    *)
        error "Unknown command: $command. Use --help for usage."
        ;;
esac
