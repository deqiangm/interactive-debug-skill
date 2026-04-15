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

# 从session读取输出
# 用法: session_read <session_name> [timeout_seconds]
session_read() {
    local session_name="$1"
    local timeout="${2:-2}"
    
    if ! session_exists "$session_name"; then
        error "Session '$session_name' not found"
    fi
    
    # 捕获pane内容
    tmux capture-pane -t "$session_name" -p | head -n -1  # 排除最后一行（可能是光标行）
}

# 执行命令并获取结果（组合send + read）
# 用法: session_exec <session_name> <command> [wait_seconds]
session_exec() {
    local session_name="$1"
    local command="$2"
    local wait="${3:-1}"
    
    session_send "$session_name" "$command"
    sleep "$wait"
    session_read "$session_name"
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
    read <session_name>                      读取session输出
    exec <session_name> <command> [wait]     执行命令并获取结果

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
