#!/bin/bash
# ============================================================================
# JDB Remote Attach - 远程进程调试支持
# 
# 支持两种模式:
# 1. Attach到已运行的远程调试端口
# 2. 启动Java程序并开启远程调试端口，然后attach
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# 配置
# ============================================================================

DEFAULT_DEBUG_PORT=5005
DEFAULT_HOST="localhost"

# ============================================================================
# 工具函数
# ============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "ERROR: $*" >&2
    exit 1
}

# 检查端口是否被占用
check_port_available() {
    local host="$1"
    local port="$2"
    
    if nc -z "$host" "$port" 2>/dev/null; then
        return 0  # 端口被占用（调试端口已打开）
    else
        return 1  # 端口可用
    fi
}

# 等待端口可用
wait_for_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-30}"
    
    log "Waiting for debug port $host:$port (timeout: ${timeout}s)..."
    
    local start=$(date +%s)
    while true; do
        if nc -z "$host" "$port" 2>/dev/null; then
            log "Port $port is now available"
            return 0
        fi
        
        local now=$(date +%s)
        if [ $((now - start)) -ge $timeout ]; then
            error "Timeout waiting for port $port"
        fi
        
        sleep 0.5
    done
}

# ============================================================================
# 核心功能
# ============================================================================

# 启动带调试端口的Java程序
start_java_with_debug() {
    local project_dir="$1"
    local main_class="$2"
    local port="${3:-$DEFAULT_DEBUG_PORT}"
    local suspend="${4:-y}"  # y=等待调试器连接, n=不等待
    
    log "Resolving classpath for: $project_dir"
    
    # 简单的classpath解析
    local classpath=""
    if [ -d "$project_dir/target/classes" ]; then
        classpath="$project_dir/target/classes"
    fi
    
    # 构建Java调试参数
    local debug_opts="-agentlib:jdwp=transport=dt_socket,server=y,suspend=$suspend,address=*:$port"
    
    log "Starting Java with debug options: $debug_opts"
    
    # 构建启动命令
    local java_cmd="java $debug_opts"
    [ -n "$classpath" ] && java_cmd="$java_cmd -classpath $classpath"
    java_cmd="$java_cmd $main_class"
    
    log "Java command: $java_cmd"
    
    # 在tmux session中启动Java程序
    local session_name="java_debug_${main_class##*.}_$$"
    
    tmux new-session -d -s "$session_name" -x 200 -y 50 "$java_cmd"
    
    log "Java process started in session: $session_name"
    echo "$session_name"
}

# Attach到远程调试端口
attach_remote() {
    local host="$1"
    local port="$2"
    local session_name="$3"
    
    # 生成session名称
    if [ -z "$session_name" ]; then
        session_name="jdb_remote_${host}_${port}_$$"
    fi
    
    # 构建jdb命令
    local jdb_cmd="jdb -connect com.sun.jdi.SocketAttach:hostname=$host,port=$port"
    
    log "Attaching to $host:$port..."
    log "JDB command: $jdb_cmd"
    
    # 创建tmux session
    tmux new-session -d -s "$session_name" -x 200 -y 50 "$jdb_cmd"
    
    # 等待连接建立
    sleep 2
    
    # 检查连接状态
    local output=$(tmux capture-pane -t "$session_name" -p 2>/dev/null)
    
    if echo "$output" | grep -q "Unable to connect\|Connection refused"; then
        tmux kill-session -t "$session_name" 2>/dev/null
        error "Failed to connect to $host:$port"
    fi
    
    log "Successfully attached to remote process"
    echo "$session_name"
}

# 一键启动并attach
start_and_attach() {
    local project_dir="$1"
    local main_class="$2"
    local port="${3:-$DEFAULT_DEBUG_PORT}"
    
    # 启动Java程序（等待调试器）
    log "Starting Java program with debug port $port..."
    local java_session=$(start_java_with_debug "$project_dir" "$main_class" "$port" "y")
    
    # 等待端口就绪
    wait_for_port "localhost" "$port" 30
    
    # Attach到端口
    log "Attaching JDB to debug port..."
    local jdb_session=$(attach_remote "localhost" "$port" "jdb_${main_class##*.}_$$")
    
    # 返回session信息
    echo ""
    echo "========================================"
    echo "Debug Environment Ready"
    echo "========================================"
    echo "Java session: $java_session"
    echo "JDB session:  $jdb_session"
    echo "Debug port:   $port"
    echo ""
    echo "Commands:"
    echo "  tmux attach -t $jdb_session"
    echo "  $SCRIPT_DIR/jdb_session.sh exec-poll $jdb_session \"where\" 10 0.5"
    echo "========================================"
}

# ============================================================================
# 主程序
# ============================================================================

show_usage() {
    cat << EOF
JDB Remote Attach - 远程进程调试支持

用法:
    $0 <command> [arguments...]

命令:
    start_attach <project_dir> <main_class> [port]
        启动Java程序（等待调试器），然后attach
        
    start_java <project_dir> <main_class> [port] [suspend]
        只启动Java程序，不启动JDB
        
    attach <host> <port> [session_name]
        Attach到指定主机和端口的调试端口
        
    check_port <host> <port>
        检查调试端口是否可用
        
    wait_port <host> <port> [timeout]
        等待调试端口可用

示例:
    # 启动并attach（推荐）
    $0 start_attach /path/to/project com.example.Main
    
    # Attach到已存在的调试端口
    $0 attach localhost 5005
    
    # 只启动Java程序
    $0 start_java /path/to/project com.example.Main 5005 y

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
    start_attach)
        [ $# -lt 2 ] && error "Usage: $0 start_attach <project_dir> <main_class> [port]"
        start_and_attach "$1" "$2" "${3:-$DEFAULT_DEBUG_PORT}"
        ;;
    start_java)
        [ $# -lt 2 ] && error "Usage: $0 start_java <project_dir> <main_class> [port] [suspend]"
        start_java_with_debug "$1" "$2" "${3:-$DEFAULT_DEBUG_PORT}" "${4:-y}"
        ;;
    attach)
        [ $# -lt 2 ] && error "Usage: $0 attach <host> <port> [session_name]"
        attach_remote "$1" "$2" "${3:-}"
        ;;
    check_port)
        [ $# -lt 2 ] && error "Usage: $0 check_port <host> <port>"
        if check_port_available "$1" "$2"; then
            echo "Port $1:$2 is available (debug port is open)"
            exit 0
        else
            echo "Port $1:$2 is not available"
            exit 1
        fi
        ;;
    wait_port)
        [ $# -lt 2 ] && error "Usage: $0 wait_port <host> <port> [timeout]"
        wait_for_port "$1" "$2" "${3:-30}"
        ;;
    -h|--help)
        show_usage
        exit 0
        ;;
    *)
        error "Unknown command: $command. Use -h for help."
        ;;
esac
