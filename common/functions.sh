#!/bin/bash
# ============================================================================
# Common Functions Library - Shared utilities for debugging tools
# 
# Provides:
#   - Logging system (log, log_debug, log_info, log_warn, log_error)
#   - Tmux session management (create, send, read, poll, kill)
#   - Network utilities (check_port, wait_for_port)
#   - File utilities (find_project_root, detect_project_type)
# ============================================================================

# Prevent duplicate sourcing
if [ -n "$_DEBUG_COMMON_LOADED" ]; then
    return 0
fi
_DEBUG_COMMON_LOADED=1

# ============================================================================
# Configuration Constants
# ============================================================================

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default configuration
readonly DEFAULT_POLL_INTERVAL=0.5
readonly DEFAULT_TIMEOUT=60
readonly DEFAULT_WAIT_TIME=5
readonly DEFAULT_DEBUG_PORT=5005
readonly MAX_STABLE_COUNT=2

# ============================================================================
# Logging System
# ============================================================================

# Log level (DEBUG, INFO, WARN, ERROR)
LOG_LEVEL="${LOG_LEVEL:-INFO}"

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

# Simplified log function (backward compatible)
log() { log_info "$*"; }

# Log error and exit
error() {
    log_error "$*"
    exit 1
}

# ============================================================================
# Tmux Session Management
# ============================================================================

# Generate unique session name
# Usage: generate_session_name <prefix> <target>
generate_session_name() {
    local prefix="$1"
    local target="$2"
    local timestamp=$(date +%s)
    local sanitized=$(echo "$target" | tr '/:.@' '_' | head -20)
    echo "${prefix}_${sanitized}_${timestamp}"
}

# Check if session exists
# Usage: session_exists <session_name>
session_exists() {
    local session_name="$1"
    tmux has-session -t "$session_name" 2>/dev/null
}

# Create tmux session
# Usage: session_create <session_name> <command> [width] [height]
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

# Send command to session
# Usage: session_send <session_name> <command>
session_send() {
    local session_name="$1"
    local command="$2"
    
    if ! session_exists "$session_name"; then
        error "Session '$session_name' not found"
    fi
    
    tmux send-keys -t "$session_name" "$command" Enter
    log_debug "Sent to '$session_name': $command"
}

# Read session output
# Usage: session_read <session_name>
session_read() {
    local session_name="$1"
    
    if ! session_exists "$session_name"; then
        error "Session '$session_name' not found"
    fi
    
    tmux capture-pane -t "$session_name" -p -S - 2>/dev/null
}

# Poll for output completion
# Usage: session_poll <session_name> [timeout] [poll_interval] [prompt_pattern]
# Returns: 0 on success, 124 on timeout
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
        
        # Check for prompt
        if echo "$current_output" | grep -qE "$prompt_pattern"; then
            log_debug "Prompt detected after ${poll_count} polls"
            echo "$current_output"
            return 0
        fi
        
        # Check for output stability
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

# Execute command and poll for result
# Usage: session_exec_poll <session_name> <command> [timeout] [poll_interval]
session_exec_poll() {
    local session_name="$1"
    local command="$2"
    local timeout="${3:-$DEFAULT_TIMEOUT}"
    local poll_interval="${4:-$DEFAULT_POLL_INTERVAL}"
    
    session_send "$session_name" "$command"
    session_poll "$session_name" "$timeout" "$poll_interval"
}

# Wait for specific pattern in output
# Usage: session_wait_for <session_name> <pattern> [timeout] [poll_interval]
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

# Terminate session
# Usage: session_kill <session_name>
session_kill() {
    local session_name="$1"
    
    if session_exists "$session_name"; then
        tmux kill-session -t "$session_name" 2>/dev/null
        log "Session '$session_name' killed"
    else
        log_warn "Session '$session_name' not found"
    fi
}

# Cleanup all sessions matching prefix
# Usage: session_cleanup [prefix]
session_cleanup() {
    local prefix="${1:-.*}"
    
    log "Cleaning up sessions matching: $prefix"
    tmux list-sessions 2>/dev/null | grep -E "^$prefix" | cut -d: -f1 | while read session; do
        session_kill "$session"
    done
}

# List all sessions
# Usage: session_list [prefix]
session_list() {
    local prefix="${1:-.*}"
    
    tmux list-sessions 2>/dev/null | grep -E "^$prefix" | cut -d: -f1
}

# ============================================================================
# Network Utilities
# ============================================================================

# Check if port is available
# Usage: check_port <host> <port>
check_port() {
    local host="${1:-localhost}"
    local port="$2"
    
    if [ -z "$port" ]; then
        error "Port is required"
    fi
    
    nc -z "$host" "$port" 2>/dev/null
}

# Wait for port to become available
# Usage: wait_for_port <host> <port> [timeout]
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
# File Utilities
# ============================================================================

# Find project root directory
# Usage: find_project_root [start_dir]
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

# Detect project type
# Usage: detect_project_type <project_dir>
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
# String Utilities
# ============================================================================

# Safely quote string for command line
# Usage: shell_quote <string>
shell_quote() {
    local str="$1"
    printf '%q' "$str"
}

# Extract JSON field value
# Usage: json_get <json_string> <field_path>
json_get() {
    local json="$1"
    local field="$2"
    
    echo "$json" | jq -r "$field" 2>/dev/null
}

# ============================================================================
# Validation Utilities
# ============================================================================

# Verify required commands exist
# Usage: require_commands <cmd1> [cmd2] ...
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

# Verify environment variables are set
# Usage: require_env <var1> [var2] ...
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
# Help System
# ============================================================================

# Display usage help
# Usage: show_help <script_name> <description> <commands>
show_help() {
    local script_name="$1"
    local description="$2"
    local commands="$3"
    
    cat << EOF
$script_name - $description

Usage:
    $script_name <command> [arguments...]

Commands:
$commands

Options:
    -h, --help      Show this help message
    -v, --verbose   Enable verbose output

Environment Variables:
    LOG_LEVEL       Log level (DEBUG, INFO, WARN, ERROR)

Examples:
    $script_name --help

EOF
}

# ============================================================================
# Initialization Checks
# ============================================================================

# Check base dependencies
check_dependencies() {
    require_commands tmux bc
    
    # jq is optional but recommended
    if ! command -v jq &>/dev/null; then
        log_warn "jq not found, JSON parsing will be limited"
    fi
}

# Run initialization checks
check_dependencies
