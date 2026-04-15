#!/bin/bash
# ============================================================================
# Common Functions Library - 调试工具公共函数库
# 
# 提供所有调试脚本共用的基础功能
# ============================================================================

# 防止重复source
if [ -n "$_DEBUG_COMMON_LOADED" ]; then
    return 0
fi
_DEBUG_COMMON_LOADED=1

# ============================================================================
# 配置常量
# ============================================================================

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# 默认配置
readonly DEFAULT_POLL_INTERVAL=0.5
readonly DEFAULT_TIMEOUT=60
readonly DEFAULT_WAIT_TIME=5
readonly DEFAULT_DEBUG_PORT=5005
readonly MAX_STABLE_COUNT=2

# ============================================================================
# 日志系统
# ============================================================================

# 日志级别
LOG_LEVEL="${LOG_LEVEL:-INFO}"  # DEBUG, INFO, WARN, ERROR

_log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        DEBUG)
            [ "$LOG_LEVEL" = "DEBUG" ] && echo -e "${BLUE}[$timestamp] [DEBUG] $message${NC}"
            ;;
        INFO)
            echo -e "[$timestamp] $message"
            ;;
        WARN)
            echo -e "${YELLOW}[$timestamp] [WARN] $message${NC}"
            ;;
        ERROR)
            echo -e "${RED}[$timestamp] [ERROR] $message${NC}" >&2
            ;;
    esac
}

log_debug() { _log DEBUG "$*"; }
log_info() { _log INFO "$*"; }
log_warn() { _log WARN "$*"; }
log_error() { _log ERROR "$*"; }

# 简化的log函数（向后兼容）
log() { log_info "$*"; }

# 错误并退出
error() {
    log_error "$*"
    exit 1
}

# ============================================================================
# Tmux Session 管理
# ============================================================================

# 生成唯一的session名称
generate_session_name() {
    local prefix="$1"
    local target="$2"
    local timestamp=$(date +%s)
    local sanitized=$(echo "$target" | tr '/:.@' '_' | head -20)
    echo "${prefix}_${sanitized}_${timestamp}"
}

# 检查session是否存在
session_exists() {
    local session_name="$1"
    tmux has-session -t "$session_name" 2>/dev/null
}

# 创建tmux session
session_create() {
    local session_name="$1"
    local command="$2"
    local width="${3:-200}"
    local height="${4:-50}"
    
    if session_exists "$session_name"; then
        log_warn "Session '$session_name' already exists"
        return 1
    fi
    
    tmux new-session -d -s "$session_name" -x "$width" -y "$height" "$command"
    log "Session '$session_name' created"
    return 0
}

# 发送命令到session
session_send() {
    local session_name="$1"
    local command="$2"
    
    if ! session_exists "$session_name"; then
        error "Session '$session_name' not found"
    fi
    
    tmux send-keys -t "$session_name" "$command" Enter
    log_debug "Sent to '$session_name': $command"
}

# 读取session输出
session_read() {
    local session_name="$1"
    
    if ! session_exists "$session_name"; then
        error "Session '$session_name' not found"
    fi
    
    tmux capture-pane -t "$session_name" -p -S - 2>/dev/null
}

# Poll等待输出完成
session_poll() {
    local session_name="$1"
    local timeout="${2:-$DEFAULT_TIMEOUT}"
    local poll_interval="${3:-$DEFAULT_POLL_INTERVAL}"
    local prompt_pattern="${4:-'$|main\[[0-9]+\]'}"
    
    if ! session_exists "$session_name"; then
        error "Session '$session_name' not found"
    fi
    
    local max_polls=$(echo "$timeout / $poll_interval" | bc 2>/dev/null || echo "$((timeout * 2))")
    local poll_count=0
    local prev_output=""
    local stable_count=0
    
    while [ $poll_count -lt $max_polls ]; do
        sleep "$poll_interval"
        poll_count=$((poll_count + 1))
        
        local current_output=$(session_read "$session_name")
        
        # 检查提示符
        if echo "$current_output" | grep -qE "$prompt_pattern"; then
            log_debug "Prompt detected after ${poll_count} polls"
            echo "$current_output"
            return 0
        fi
        
        # 检查输出稳定
        if [ "$current_output" = "$prev_output" ]; then
            stable_count=$((stable_count + 1))
            if [ $stable_count -ge $MAX_STABLE_COUNT ]; then
                log_debug "Output stable after ${poll_count} polls"
                echo "$current_output"
                return 0
            fi
        else
            stable_count=0
        fi
        
        prev_output="$current_output"
    done
    
    log_warn "Poll timeout after ${timeout}s"
    session_read "$session_name"
    return 124
}

# 执行命令并poll
session_exec_poll() {
    local session_name="$1"
    local command="$2"
    local timeout="${3:-$DEFAULT_TIMEOUT}"
    local poll_interval="${4:-$DEFAULT_POLL_INTERVAL}"
    
    session_send "$session_name" "$command"
    session_poll "$session_name" "$timeout" "$poll_interval"
}

# 等待特定模式
session_wait_for() {
    local session_name="$1"
    local pattern="$2"
    local timeout="${3:-$DEFAULT_TIMEOUT}"
    local poll_interval="${4:-$DEFAULT_POLL_INTERVAL}"
    
    if ! session_exists "$session_name"; then
        error "Session '$session_name' not found"
    fi
    
    local max_polls=$(echo "$timeout / $poll_interval" | bc 2>/dev/null || echo "$((timeout * 2))")
    local poll_count=0
    
    while [ $poll_count -lt $max_polls ]; do
        sleep "$poll_interval"
        poll_count=$((poll_count + 1))
        
        local output=$(session_read "$session_name")
        
        if echo "$output" | grep -qE "$pattern"; then
            log_debug "Pattern '$pattern' found after ${poll_count} polls"
            echo "$output"
            return 0
        fi
    done
    
    log_warn "Pattern '$pattern' not found after ${timeout}s"
    return 124
}

# 终止session
session_kill() {
    local session_name="$1"
    
    if session_exists "$session_name"; then
        tmux kill-session -t "$session_name" 2>/dev/null
        log "Session '$session_name' killed"
    else
        log_warn "Session '$session_name' not found"
    fi
}

# 清理所有匹配前缀的session
session_cleanup() {
    local prefix="${1:-.*}"
    
    log "Cleaning up sessions matching: $prefix"
    tmux list-sessions 2>/dev/null | grep -E "^$prefix" | cut -d: -f1 | while read session; do
        session_kill "$session"
    done
}

# 列出所有session
session_list() {
    local prefix="${1:-.*}"
    
    tmux list-sessions 2>/dev/null | grep -E "^$prefix" | cut -d: -f1
}

# ============================================================================
# 网络工具
# ============================================================================

# 检查端口是否可用
check_port() {
    local host="${1:-localhost}"
    local port="$2"
    
    if [ -z "$port" ]; then
        error "Port is required"
    fi
    
    nc -z "$host" "$port" 2>/dev/null
}

# 等待端口可用
wait_for_port() {
    local host="${1:-localhost}"
    local port="$2"
    local timeout="${3:-30}"
    
    log "Waiting for $host:$port (timeout: ${timeout}s)..."
    
    local start=$(date +%s)
    while true; do
        if check_port "$host" "$port"; then
            log "Port $port is available"
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
# 文件工具
# ============================================================================

# 查找项目根目录
find_project_root() {
    local start_dir="${1:-.}"
    local markers=("pom.xml" "build.gradle" "go.mod" "package.json" "requirements.txt" "Cargo.toml")
    
    local current_dir=$(cd "$start_dir" && pwd)
    
    while [ "$current_dir" != "/" ]; do
        for marker in "${markers[@]}"; do
            if [ -f "$current_dir/$marker" ]; then
                echo "$current_dir"
                return 0
            fi
        done
        current_dir=$(dirname "$current_dir")
    done
    
    echo "$start_dir"
    return 1
}

# 检测项目类型
detect_project_type() {
    local project_dir="$1"
    
    if [ -f "$project_dir/pom.xml" ]; then
        echo "maven"
    elif [ -f "$project_dir/build.gradle" ] || [ -f "$project_dir/build.gradle.kts" ]; then
        echo "gradle"
    elif [ -f "$project_dir/go.mod" ]; then
        echo "go"
    elif [ -f "$project_dir/package.json" ]; then
        echo "nodejs"
    elif [ -f "$project_dir/requirements.txt" ] || [ -f "$project_dir/setup.py" ]; then
        echo "python"
    elif [ -f "$project_dir/Cargo.toml" ]; then
        echo "rust"
    else
        echo "unknown"
    fi
}

# ============================================================================
# 字符串工具
# ============================================================================

# 安全引用字符串（用于命令行）
shell_quote() {
    local str="$1"
    printf '%q' "$str"
}

# 提取JSON字段
json_get() {
    local json="$1"
    local field="$2"
    
    echo "$json" | jq -r "$field" 2>/dev/null
}

# ============================================================================
# 验证工具
# ============================================================================

# 验证必需命令存在
require_commands() {
    local missing=()
    
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing required commands: ${missing[*]}"
    fi
}

# 验证环境变量
require_env() {
    local missing=()
    
    for var in "$@"; do
        if [ -z "${!var}" ]; then
            missing+=("$var")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing required environment variables: ${missing[*]}"
    fi
}

# ============================================================================
# 帮助系统
# ============================================================================

# 显示使用帮助
show_help() {
    local script_name="$1"
    local description="$2"
    local commands="$3"
    
    cat << EOF
$script_name - $description

用法:
    $script_name <command> [arguments...]

命令:
$commands

选项:
    -h, --help      显示此帮助信息
    -v, --verbose   启用详细输出

环境变量:
    LOG_LEVEL       日志级别 (DEBUG, INFO, WARN, ERROR)

示例:
    $script_name --help

EOF
}

# ============================================================================
# 初始化检查
# ============================================================================

# 检查基础依赖
check_dependencies() {
    require_commands tmux bc
    
    # jq是可选的，但推荐
    if ! command -v jq &>/dev/null; then
        log_warn "jq not found, JSON parsing will be limited"
    fi
}

# 运行初始化检查
check_dependencies
