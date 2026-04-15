#!/bin/bash
# ============================================================================
# JDB Session Manager - 基于tmux的交互式JDB调试会话管理
# 
# 核心功能:
# 1. 创建隔离的tmux session运行jdb
# 2. 发送指令到jdb并获取输出
# 3. 支持多个独立debug session
# ============================================================================

set -e

# 配置
JDB_SESSION_PREFIX="jdb_debug"
DEFAULT_SHELL="/bin/bash"

# ============================================================================
# 辅助函数
# ============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "ERROR: $1" >&2
    exit 1
}

# 生成唯一session名称
generate_session_name() {
    local target="$1"
    local timestamp=$(date +%s)
    echo "${JDB_SESSION_PREFIX}_${target}_${timestamp}"
}

# ============================================================================
# Session 生命周期管理
# ============================================================================

# 创建新的jdb debug session
# 用法: jdb_session_create <session_name> <jdb_command...>
session_create() {
    local session_name="$1"
    shift
    local jdb_cmd="$@"
    
    # 检查session是否已存在
    if tmux has-session -t "$session_name" 2>/dev/null; then
        error "Session '$session_name' already exists"
    fi
    
    # 创建新session，运行jdb
    tmux new-session -d -s "$session_name" -x 200 -y 50 "$jdb_cmd"
    
    # 等待jdb初始化
    sleep 1
    
    # 验证session已创建
    if tmux has-session -t "$session_name" 2>/dev/null; then
        log "Session '$session_name' created successfully"
        echo "$session_name"
    else
        error "Failed to create session '$session_name'"
    fi
}

# 列出所有jdb debug sessions
session_list() {
    tmux list-sessions 2>/dev/null | grep "^${JDB_SESSION_PREFIX}" || true
}

# 检查session是否存在
session_exists() {
    local session_name="$1"
    tmux has-session -t "$session_name" 2>/dev/null
}

# 终止session
session_kill() {
    local session_name="$1"
    
    if session_exists "$session_name"; then
        tmux kill-session -t "$session_name"
        log "Session '$session_name' killed"
    else
        log "Session '$session_name' not found"
    fi
}

# 清理所有jdb sessions
session_cleanup() {
    local sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^${JDB_SESSION_PREFIX}" || true)
    
    for session in $sessions; do
        session_kill "$session"
    done
    
    log "All jdb sessions cleaned up"
}

# ============================================================================
# 输入输出交互
# ============================================================================

# 向session发送命令
# 用法: session_send <session_name> <command>
session_send() {
    local session_name="$1"
    local command="$2"
    
    if ! session_exists "$session_name"; then
        error "Session '$session_name' not found"
    fi
    
    # 发送命令（加Enter）
    tmux send-keys -t "$session_name" "$command" Enter
    
    log "Sent command to '$session_name': $command"
}

# 从session读取当前输出（无等待）
# 用法: session_read <session_name>
session_read() {
    local session_name="$1"
    
    if ! session_exists "$session_name"; then
        error "Session '$session_name' not found"
    fi
    
    # 捕获pane内容
    tmux capture-pane -t "$session_name" -p -S - 2>/dev/null
}

# Poll等待输出完成（智能等待）
# 用法: session_poll <session_name> [timeout_seconds] [poll_interval_seconds]
# 
# 工作原理:
# 1. 每隔poll_interval检查一次输出
# 2. 检测JDB提示符 "> " 或 ">]" 表示输出完成
# 3. 输出稳定（连续2次相同）则认为完成
# 4. 超过timeout则返回当前内容
#
# 返回:
#   - 读取到的完整输出
#   - 退出码: 0=正常完成, 124=超时
session_poll() {
    local session_name="$1"
    local timeout="${2:-60}"
    local poll_interval="${3:-0.5}"
    
    if ! session_exists "$session_name"; then
        error "Session '$session_name' not found"
    fi
    
    # 计算最大poll次数
    local max_polls=$(echo "$timeout / $poll_interval" | bc)
    local poll_count=0
    local prev_output=""
    local stable_count=0
    local max_stable=2  # 连续稳定次数
    
    # JDB提示符模式（表示可以输入新命令）
    local prompt_pattern='(^|\n)[[:space:]]*>[[:space:]]*$|^[[:space:]]*>[[[:space:]]'
    
    while [ $poll_count -lt $max_polls ]; do
        sleep "$poll_interval"
        poll_count=$((poll_count + 1))
        
        # 读取当前输出
        local current_output=$(session_read "$session_name")
        
        # 检查是否出现提示符（输出完成）
        if echo "$current_output" | grep -qE "$prompt_pattern"; then
            log "Output complete (prompt detected after ${poll_count} polls)"
            echo "$current_output"
            return 0
        fi
        
        # 检查输出是否稳定（连续相同）
        if [ "$current_output" = "$prev_output" ]; then
            stable_count=$((stable_count + 1))
            if [ $stable_count -ge $max_stable ]; then
                log "Output stable after ${poll_count} polls"
                echo "$current_output"
                return 0
            fi
        else
            stable_count=0
        fi
        
        prev_output="$current_output"
    done
    
    # 超时返回当前内容
    log "Poll timeout after ${timeout}s (${poll_count} polls)"
    session_read "$session_name"
    return 124
}

# 执行命令并poll等待结果
# 用法: session_exec_poll <session_name> <command> [timeout] [poll_interval]
session_exec_poll() {
    local session_name="$1"
    local command="$2"
    local timeout="${3:-60}"
    local poll_interval="${4:-0.5}"
    
    # 清空之前的输出缓冲（发送空命令获取干净状态）
    session_send "$session_name" "" 2>/dev/null || true
    
    # 发送命令
    session_send "$session_name" "$command"
    
    # Poll等待结果
    session_poll "$session_name" "$timeout" "$poll_interval"
}

# 执行命令并获取结果（固定等待，兼容旧接口）
# 用法: session_exec <session_name> <command> [wait_seconds]
session_exec() {
    local session_name="$1"
    local command="$2"
    local wait="${3:-1}"
    
    session_send "$session_name" "$command"
    sleep "$wait"
    session_read "$session_name"
}

# 等待特定输出模式出现
# 用法: session_wait_for <session_name> <pattern> [timeout_seconds]
# 例如: session_wait_for my_session "Breakpoint hit" 30
session_wait_for() {
    local session_name="$1"
    local pattern="$2"
    local timeout="${3:-60}"
    local poll_interval="${4:-0.5}"
    
    if ! session_exists "$session_name"; then
        error "Session '$session_name' not found"
    fi
    
    local max_polls=$(echo "$timeout / $poll_interval" | bc)
    local poll_count=0
    
    while [ $poll_count -lt $max_polls ]; do
        sleep "$poll_interval"
        poll_count=$((poll_count + 1))
        
        local output=$(session_read "$session_name")
        
        if echo "$output" | grep -qE "$pattern"; then
            log "Pattern '$pattern' found after ${poll_count} polls"
            echo "$output"
            return 0
        fi
    done
    
    log "Pattern '$pattern' not found after ${timeout}s"
    return 124
}

# 等待断点命中
# 用法: session_wait_breakpoint <session_name> [timeout_seconds]
session_wait_breakpoint() {
    local session_name="$1"
    local timeout="${2:-60}"
    
    # 断点命中的典型输出模式
    # "Breakpoint hit: "thread=main", com.example.Test.main(), line=42 bci=0"
    session_wait_for "$session_name" "Breakpoint hit|Step completed" "$timeout"
}

# 等待程序终止
# 用法: session_wait_exit <session_name> [timeout_seconds]
session_wait_exit() {
    local session_name="$1"
    local timeout="${2:-60}"
    
    session_wait_for "$session_name" "The application exited|The VM has been disconnected" "$timeout"
}

# ============================================================================
# JDB 特定操作
# ============================================================================

# 设置断点
jdb_set_breakpoint() {
    local session_name="$1"
    local class="$2"
    local line="$3"
    
    session_exec "$session_name" "stop at ${class}:${line}" 1
}

# 设置方法断点
jdb_set_method_breakpoint() {
    local session_name="$1"
    local class="$2"
    local method="$3"
    
    session_exec "$session_name" "stop in ${class}.${method}" 1
}

# 继续执行
jdb_continue() {
    local session_name="$1"
    session_exec "$session_name" "cont" 1
}

# 单步执行
jdb_step() {
    local session_name="$1"
    session_exec "$session_name" "step" 1
}

# 下一步（不进入方法）
jdb_next() {
    local session_name="$1"
    session_exec "$session_name" "next" 1
}

# 打印变量
jdb_print() {
    local session_name="$1"
    local expr="$2"
    session_exec "$session_name" "print $expr" 1
}

# 打印对象详情
jdb_dump() {
    local session_name="$1"
    local expr="$2"
    session_exec "$session_name" "dump $expr" 1
}

# 查看调用栈
jdb_where() {
    local session_name="$1"
    session_exec "$session_name" "where" 1
}

# 查看线程
jdb_threads() {
    local session_name="$1"
    session_exec "$session_name" "threads" 2
}

# 查看类
jdb_classes() {
    local session_name="$1"
    session_exec "$session_name" "classes" 2
}

# 查看局部变量
jdb_locals() {
    local session_name="$1"
    session_exec "$session_name" "locals" 1
}

# ============================================================================
# 主程序
# ============================================================================

show_usage() {
    cat << EOF
JDB Session Manager - 基于tmux的交互式JDB调试会话管理

用法:
    $0 <command> [arguments...]

Session管理:
    create <session_name> <jdb_command...>   创建新的debug session
    list                                     列出所有jdb sessions
    kill <session_name>                      终止指定session
    cleanup                                  清理所有jdb sessions
    exists <session_name>                    检查session是否存在

输入输出:
    send <session_name> <command>            发送命令到session
    read <session_name>                      读取session当前输出
    poll <session_name> [timeout] [interval] Poll等待输出完成（智能）
    exec <session_name> <command> [wait]     执行命令并获取结果（固定等待）
    exec-poll <session> <cmd> [timeout] [interval] 执行命令并poll等待
    wait-for <session> <pattern> [timeout]   等待特定输出模式
    wait-breakpoint <session> [timeout]      等待断点命中
    wait-exit <session> [timeout]            等待程序终止

JDB操作:
    bp <session_name> <class> <line>         设置断点
    bp-method <session> <class> <method>     设置方法断点
    cont <session_name>                      继续执行
    step <session_name>                      单步执行
    next <session_name>                      下一步
    print <session_name> <expr>              打印变量
    dump <session_name> <expr>               打印对象详情
    where <session_name>                     查看调用栈
    threads <session_name>                   查看线程
    classes <session_name>                   查看类
    locals <session_name>                    查看局部变量

示例:
    # 创建session (attach到进程)
    $0 create my_session "jdb -attach 12345"
    
    # 创建session (从main class启动)
    $0 create my_session "jdb -classpath /path/to/classes MyApp"
    
    # 设置断点并继续
    $0 bp my_session com.example.UserService 42
    $0 cont my_session
    
    # 查看变量
    $0 print my_session user.name
    $0 dump my_session user
    
    # === 智能Poll等待（推荐） ===
    # 执行命令并智能等待（0.5s poll, 60s超时）
    $0 exec-poll my_session "where" 30 0.5
    
    # 等待断点命中
    $0 wait-breakpoint my_session 60
    
    # 等待程序结束
    $0 wait-exit my_session 120
    
    # 等待特定输出
    $0 wait-for my_session "NullPointerException" 30

EOF
}

# 入口
if [ $# -lt 1 ]; then
    show_usage
    exit 1
fi

command="$1"
shift

case "$command" in
    create)
        [ $# -lt 2 ] && error "Usage: $0 create <session_name> <jdb_command...>"
        session_create "$@"
        ;;
    list)
        session_list
        ;;
    kill)
        [ $# -lt 1 ] && error "Usage: $0 kill <session_name>"
        session_kill "$1"
        ;;
    cleanup)
        session_cleanup
        ;;
    exists)
        [ $# -lt 1 ] && error "Usage: $0 exists <session_name>"
        session_exists "$1" && echo "exists" || echo "not found"
        ;;
    send)
        [ $# -lt 2 ] && error "Usage: $0 send <session_name> <command>"
        session_send "$1" "$2"
        ;;
    read)
        [ $# -lt 1 ] && error "Usage: $0 read <session_name>"
        session_read "$1"
        ;;
    exec)
        [ $# -lt 2 ] && error "Usage: $0 exec <session_name> <command> [wait]"
        session_exec "$1" "$2" "${3:-1}"
        ;;
    poll)
        [ $# -lt 1 ] && error "Usage: $0 poll <session_name> [timeout] [interval]"
        session_poll "$1" "${2:-60}" "${3:-0.5}"
        ;;
    exec-poll)
        [ $# -lt 2 ] && error "Usage: $0 exec-poll <session_name> <command> [timeout] [interval]"
        session_exec_poll "$1" "$2" "${3:-60}" "${4:-0.5}"
        ;;
    wait-for)
        [ $# -lt 2 ] && error "Usage: $0 wait-for <session_name> <pattern> [timeout]"
        session_wait_for "$1" "$2" "${3:-60}"
        ;;
    wait-breakpoint)
        [ $# -lt 1 ] && error "Usage: $0 wait-breakpoint <session_name> [timeout]"
        session_wait_breakpoint "$1" "${2:-60}"
        ;;
    wait-exit)
        [ $# -lt 1 ] && error "Usage: $0 wait-exit <session_name> [timeout]"
        session_wait_exit "$1" "${2:-60}"
        ;;
    bp)
        [ $# -lt 3 ] && error "Usage: $0 bp <session_name> <class> <line>"
        jdb_set_breakpoint "$1" "$2" "$3"
        ;;
    bp-method)
        [ $# -lt 3 ] && error "Usage: $0 bp-method <session_name> <class> <method>"
        jdb_set_method_breakpoint "$1" "$2" "$3"
        ;;
    cont)
        [ $# -lt 1 ] && error "Usage: $0 cont <session_name>"
        jdb_continue "$1"
        ;;
    step)
        [ $# -lt 1 ] && error "Usage: $0 step <session_name>"
        jdb_step "$1"
        ;;
    next)
        [ $# -lt 1 ] && error "Usage: $0 next <session_name>"
        jdb_next "$1"
        ;;
    print)
        [ $# -lt 2 ] && error "Usage: $0 print <session_name> <expr>"
        jdb_print "$1" "$2"
        ;;
    dump)
        [ $# -lt 2 ] && error "Usage: $0 dump <session_name> <expr>"
        jdb_dump "$1" "$2"
        ;;
    where)
        [ $# -lt 1 ] && error "Usage: $0 where <session_name>"
        jdb_where "$1"
        ;;
    threads)
        [ $# -lt 1 ] && error "Usage: $0 threads <session_name>"
        jdb_threads "$1"
        ;;
    classes)
        [ $# -lt 1 ] && error "Usage: $0 classes <session_name>"
        jdb_classes "$1"
        ;;
    locals)
        [ $# -lt 1 ] && error "Usage: $0 locals <session_name>"
        jdb_locals "$1"
        ;;
    *)
        error "Unknown command: $command"
        ;;
esac
