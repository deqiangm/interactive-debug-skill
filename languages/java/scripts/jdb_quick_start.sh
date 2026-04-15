#!/bin/bash
# ============================================================================
# JDB Quick Start - 一键启动JDB调试会话
# 
# 自动化:
# 1. 检测项目类型 (Maven/Gradle)
# 2. 解析classpath
# 3. 启动jdb (tmux session)
# 4. 可选: 设置初始断点
# 5. 进入交互模式
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/jdb_session.sh"

# ============================================================================
# 配置
# ============================================================================

DEFAULT_WAIT_TIMEOUT=5

# ============================================================================
# 查找Java进程
# ============================================================================

find_java_processes() {
    echo "Running Java processes:"
    echo "PID      | User     | Command"
    echo "---------|----------|------------------------------------------------"
    
    jps -l | while read pid name; do
        local user=$(ps -o user= -p "$pid" 2>/dev/null | tr -d ' ')
        printf "%-8s | %-8s | %s\n" "$pid" "$user" "$name"
    done
}

# 按名称查找Java进程PID
find_pid_by_name() {
    local name="$1"
    jps -l | grep "$name" | awk '{print $1}' | head -1
}

# ============================================================================
# 主启动逻辑
# ============================================================================

start_debug_session() {
    local project_dir="$1"
    local mode="$2"  # attach 或 main
    local target="$3"  # pid 或 main class
    local initial_breakpoint="$4"
    
    # 解析classpath
    log "Resolving classpath for: $project_dir"
    local classpath_info=$("$SCRIPT_DIR/classpath_resolver.sh" "$project_dir" --format shell)
    eval "$classpath_info"
    
    log "Project type: $PROJECT_TYPE"
    log "Classpath entries: $(echo "$CLASSPATH" | tr ':' '\n' | wc -l)"
    log "Sourcepath: $SOURCEPATH"
    
    # 生成session名称
    local session_name=$(generate_session_name "$target")
    
    # 构建jdb命令
    local jdb_cmd
    if [ "$mode" = "attach" ]; then
        jdb_cmd="jdb -attach $target"
        [ -n "$SOURCEPATH" ] && jdb_cmd="$jdb_cmd -sourcepath $SOURCEPATH"
    else
        jdb_cmd="jdb"
        [ -n "$CLASSPATH" ] && jdb_cmd="$jdb_cmd -classpath $CLASSPATH"
        [ -n "$SOURCEPATH" ] && jdb_cmd="$jdb_cmd -sourcepath $SOURCEPATH"
        jdb_cmd="$jdb_cmd $target"
    fi
    
    log "JDB command: $jdb_cmd"
    
    # 创建tmux session
    session_create "$session_name" "$jdb_cmd"
    
    # 等待jdb初始化
    sleep 2
    
    # 设置初始断点
    if [ -n "$initial_breakpoint" ]; then
        log "Setting initial breakpoint: $initial_breakpoint"
        session_exec "$session_name" "stop at $initial_breakpoint" 1
    fi
    
    echo ""
    echo "========================================"
    echo "JDB Debug Session Started"
    echo "========================================"
    echo "Session name: $session_name"
    echo "Mode: $mode"
    echo "Target: $target"
    echo ""
    echo "Available commands:"
    echo "  $SCRIPT_DIR/jdb_session.sh exec $session_name \"<command>\""
    echo "  $SCRIPT_DIR/jdb_ai_bridge.sh start-interactive $session_name"
    echo ""
    echo "Useful jdb commands:"
    echo "  cont                    - Continue execution"
    echo "  step                    - Step into method"
    echo "  next                    - Step over method"
    echo "  where                   - Show call stack"
    echo "  print <expr>            - Print variable"
    echo "  dump <obj>              - Dump object details"
    echo "  threads                 - List threads"
    echo "  quit                    - Exit"
    echo "========================================"
    echo ""
    
    # 输出session名称供后续使用
    echo "SESSION_NAME=$session_name"
}

# ============================================================================
# 主程序
# ============================================================================

show_usage() {
    cat << EOF
JDB Quick Start - 一键启动JDB调试会话

用法:
    $0 <project_dir> [options]

模式选择:
    --attach <pid|name>     Attach到运行中的Java进程
    --main <class>          从main class启动
    
选项:
    --breakpoint <class:line>   设置初始断点
    --list-java                 列出运行中的Java进程
    -h, --help                  显示帮助

示例:
    # 列出Java进程
    $0 --list-java
    
    # Attach到指定PID
    $0 /path/to/project --attach 12345
    
    # Attach到进程名匹配
    $0 /path/to/project --attach MyApplication
    
    # 从main class启动
    $0 /path/to/project --main com.example.Main --breakpoint UserService:42
    
    # 纯交互模式（不指定项目）
    $0 /path/to/project --attach 12345

EOF
}

# 解析参数
if [ $# -lt 1 ]; then
    show_usage
    exit 1
fi

PROJECT_DIR=""
MODE=""
TARGET=""
INITIAL_BP=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        --attach)
            MODE="attach"
            TARGET="$2"
            shift 2
            ;;
        --main)
            MODE="main"
            TARGET="$2"
            shift 2
            ;;
        --breakpoint)
            INITIAL_BP="$2"
            shift 2
            ;;
        --list-java)
            find_java_processes
            exit 0
            ;;
        -*)
            error "Unknown option: $1"
            ;;
        *)
            if [ -z "$PROJECT_DIR" ]; then
                PROJECT_DIR="$1"
            fi
            shift
            ;;
    esac
done

# 验证参数
if [ -z "$PROJECT_DIR" ]; then
    error "Project directory is required"
fi

if [ ! -d "$PROJECT_DIR" ]; then
    error "Directory not found: $PROJECT_DIR"
fi

if [ -z "$MODE" ]; then
    error "Mode is required (--attach or --main)"
fi

# 如果attach目标是进程名，查找PID
if [ "$MODE" = "attach" ]; then
    if ! [[ "$TARGET" =~ ^[0-9]+$ ]]; then
        log "Looking up PID for: $TARGET"
        local found_pid=$(find_pid_by_name "$TARGET")
        if [ -z "$found_pid" ]; then
            error "Java process not found: $TARGET"
        fi
        log "Found PID: $found_pid"
        TARGET="$found_pid"
    fi
fi

# 启动调试会话
start_debug_session "$PROJECT_DIR" "$MODE" "$TARGET" "$INITIAL_BP"
