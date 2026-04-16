#!/bin/bash
# ============================================================================
# JDB Thread Analyzer - Comprehensive thread analysis and debugging support
# 
# Features:
# - List all threads with status information
# - Thread stack trace analysis
# - Thread state statistics
# - Deadlock detection
# - Thread filtering and search
# - Thread transition monitoring
# - Thread comparison (before/after)
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../common/functions.sh"

# ============================================================================
# Configuration
# ============================================================================

readonly DEFAULT_THREAD_POLL_INTERVAL=3
readonly THREAD_STATE_DIR="/tmp/jdb_thread_states"

# Thread states in JVM
declare -A THREAD_STATES=(
    ["NEW"]="Thread created but not started"
    ["RUNNABLE"]="Thread executing in JVM"
    ["BLOCKED"]="Thread blocked waiting for monitor lock"
    ["WAITING"]="Thread waiting indefinitely"
    ["TIMED_WAITING"]="Thread waiting with timeout"
    ["TERMINATED"]="Thread has exited"
)

# ============================================================================
# Initialization
# ============================================================================

ensure_state_dir() {
    mkdir -p "$THREAD_STATE_DIR"
}

# ============================================================================
# Core Thread Functions
# ============================================================================

# List all threads in the debugged JVM
# Usage: list_threads <session>
list_threads() {
    local session_name="$1"
    
    log_info "Listing all threads in session: $session_name"
    
    # Use JDB's threads command
    local output=$(session_exec_poll "$session_name" "threads" 10 1)
    
    echo "$output"
    return 0
}

# Get detailed info about a specific thread
# Usage: thread_info <session> <thread_name_or_id>
thread_info() {
    local session_name="$1"
    local thread_id="$2"
    
    log_info "Getting info for thread: $thread_id"
    
    # Use JDB's thread command
    local output=$(session_exec_poll "$session_name" "thread $thread_id" 10 1)
    
    echo "$output"
    return 0
}

# Get thread stack trace
# Usage: thread_stack <session> <thread_name_or_id> [depth]
thread_stack() {
    local session_name="$1"
    local thread_id="$2"
    local depth="${3:-50}"
    
    log_info "Getting stack trace for thread: $thread_id (depth: $depth)"
    
    # First select the thread, then get stack
    session_send "$session_name" "thread $thread_id"
    sleep 0.5
    
    local output=$(session_exec_poll "$session_name" "where" 10 1)
    
    echo "$output"
    return 0
}

# Get stack trace for all threads
# Usage: all_stacks <session> [max_depth]
all_stacks() {
    local session_name="$1"
    local max_depth="${2:-20}"
    
    log_info "Getting stack traces for all threads"
    
    # Use JDB's where all command
    local output=$(session_exec_poll "$session_name" "where all" 30 2)
    
    echo "$output"
    return 0
}

# ============================================================================
# Thread Analysis Functions
# ============================================================================

# Count threads by state
# Usage: thread_stats <session>
thread_stats() {
    local session_name="$1"
    
    log_info "Analyzing thread states"
    
    local output=$(session_exec_poll "$session_name" "threads" 10 1)
    
    # Parse and count states
    local total=0
    local runnable=0
    local blocked=0
    local waiting=0
    local timed_waiting=0
    
    while IFS= read -r line; do
        if [[ "$line" =~ "Thread-"[0-9]+.*\(.*\) ]]; then
            ((total++))
            if [[ "$line" =~ "runnable" ]]; then
                ((runnable++))
            elif [[ "$line" =~ "blocked" ]]; then
                ((blocked++))
            elif [[ "$line" =~ "waiting" ]] && [[ ! "$line" =~ "timed" ]]; then
                ((waiting++))
            elif [[ "$line" =~ "timed_waiting" ]]; then
                ((timed_waiting++))
            fi
        fi
    done <<< "$output"
    
    echo "╔══════════════════════════════════════╗"
    echo "║       THREAD STATE STATISTICS        ║"
    echo "╠══════════════════════════════════════╣"
    printf "║ %-25s %8d ║\n" "Total Threads:" "$total"
    printf "║ %-25s %8d ║\n" "RUNNABLE:" "$runnable"
    printf "║ %-25s %8d ║\n" "BLOCKED:" "$blocked"
    printf "║ %-25s %8d ║\n" "WAITING:" "$waiting"
    printf "║ %-25s %8d ║\n" "TIMED_WAITING:" "$timed_waiting"
    echo "╚══════════════════════════════════════╝"
    
    # Health assessment
    if [ "$blocked" -gt 5 ] || [ "$waiting" -gt 10 ]; then
        log_warn "High number of blocked/waiting threads detected"
    fi
    
    return 0
}

# Find threads in a specific state
# Usage: find_by_state <session> <state>
find_by_state() {
    local session_name="$1"
    local state="$2"
    
    state=$(echo "$state" | tr '[:upper:]' '[:lower:]')
    
    log_info "Finding threads in state: $state"
    
    local output=$(session_exec_poll "$session_name" "threads" 10 1)
    
    echo "Threads in state: $state"
    echo "================================"
    
    while IFS= read -r line; do
        local line_lower=$(echo "$line" | tr '[:upper:]' '[:lower:]')
        if [[ "$line_lower" =~ "$state" ]]; then
            echo "$line"
        fi
    done <<< "$output"
    
    return 0
}

# Search threads by name pattern
# Usage: search_threads <session> <pattern>
search_threads() {
    local session_name="$1"
    local pattern="$2"
    
    log_info "Searching threads matching: $pattern"
    
    local output=$(session_exec_poll "$session_name" "threads" 10 1)
    
    echo "Threads matching: $pattern"
    echo "=============================="
    
    grep -i "$pattern" <<< "$output" || echo "No threads found matching pattern"
    
    return 0
}

# ============================================================================
# Deadlock Detection
# ============================================================================

# Check for potential deadlocks
# Usage: detect_deadlock <session>
detect_deadlock() {
    local session_name="$1"
    
    log_info "Checking for potential deadlocks"
    
    local output=$(session_exec_poll "$session_name" "threads" 10 1)
    
    local blocked_threads=()
    local deadlock_suspects=()
    
    # Find all BLOCKED threads
    while IFS= read -r line; do
        if [[ "$line" =~ blocked ]]; then
            blocked_threads+=("$line")
        fi
    done <<< "$output"
    
    # Get stack traces for blocked threads
    if [ ${#blocked_threads[@]} -gt 1 ]; then
        echo "╔══════════════════════════════════════╗"
        echo "║         DEADLOCK ANALYSIS            ║"
        echo "╠══════════════════════════════════════╣"
        printf "║ %-36s ║\n" "Blocked threads found: ${#blocked_threads[@]}"
        echo "╚══════════════════════════════════════╝"
        echo ""
        
        echo "Blocked Threads:"
        echo "----------------"
        for thread in "${blocked_threads[@]}"; do
            echo "  $thread"
        done
        echo ""
        
        # Get detailed info for each blocked thread
        local stacks_output=$(session_exec_poll "$session_name" "where all" 30 2)
        
        echo "Stack Trace Analysis:"
        echo "---------------------"
        
        # Look for common deadlock patterns
        local sync_wait_count=$(grep -c "waiting to lock" <<< "$stacks_output" 2>/dev/null || echo 0)
        local lock_held_count=$(grep -c "locked" <<< "$stacks_output" 2>/dev/null || echo 0)
        
        echo "  Synchronization wait count: $sync_wait_count"
        echo "  Lock held count: $lock_held_count"
        
        if [ "$sync_wait_count" -gt 1 ] && [ "$lock_held_count" -gt 1 ]; then
            echo ""
            log_warn "POTENTIAL DEADLOCK DETECTED!"
            echo "  Multiple threads waiting for locks while holding other locks"
            echo "  This is a classic deadlock pattern"
            echo ""
            echo "  Recommended actions:"
            echo "    1. Review stack traces above"
            echo "    2. Identify circular lock dependencies"
            echo "    3. Check lock acquisition order"
        fi
        
        return 1
    else
        echo "No obvious deadlock detected (${#blocked_threads[@]} blocked thread(s))"
        return 0
    fi
}

# ============================================================================
# Thread Comparison
# ============================================================================

# Save current thread state for later comparison
# Usage: save_state <session> [label]
save_state() {
    local session_name="$1"
    local label="${2:-snapshot_$(date +%Y%m%d_%H%M%S)}"
    
    ensure_state_dir
    
    local state_file="$THREAD_STATE_DIR/${session_name}_${label}.txt"
    
    log_info "Saving thread state to: $state_file"
    
    session_exec_poll "$session_name" "threads" 10 1 > "$state_file"
    
    echo "Thread state saved to: $state_file"
    return 0
}

# Compare current state with saved state
# Usage: compare_state <session> [label]
compare_state() {
    local session_name="$1"
    local label="${2:-}"
    
    ensure_state_dir
    
    # Find the most recent state file if no label provided
    if [ -z "$label" ]; then
        label=$(ls -t "$THREAD_STATE_DIR"/${session_name}_*.txt 2>/dev/null | head -1 | xargs -I{} basename {} .txt | sed "s/${session_name}_//")
        if [ -z "$label" ]; then
            log_error "No saved state found for session: $session_name"
            return 1
        fi
    fi
    
    local saved_file="$THREAD_STATE_DIR/${session_name}_${label}.txt"
    
    if [ ! -f "$saved_file" ]; then
        log_error "Saved state not found: $saved_file"
        return 1
    fi
    
    log_info "Comparing current state with: $label"
    
    local current_state=$(session_exec_poll "$session_name" "threads" 10 1)
    local saved_state=$(cat "$saved_file")
    
    echo "╔══════════════════════════════════════╗"
    echo "║       THREAD STATE COMPARISON        ║"
    echo "╠══════════════════════════════════════╣"
    printf "║ %-36s ║\n" "Comparing with: $label"
    echo "╚══════════════════════════════════════╝"
    echo ""
    
    # Count threads in each state
    local current_count=$(grep -c "Thread-" <<< "$current_state" || echo 0)
    local saved_count=$(grep -c "Thread-" <<< "$saved_state" || echo 0)
    
    echo "Thread Count Changes:"
    echo "---------------------"
    echo "  Previous: $saved_count threads"
    echo "  Current:  $current_count threads"
    echo "  Change:   $((current_count - saved_count)) threads"
    echo ""
    
    # Find new threads
    echo "New Threads (not in saved state):"
    echo "---------------------------------"
    while IFS= read -r line; do
        if [[ "$line" =~ "Thread-" ]]; then
            local thread_name=$(echo "$line" | grep -oP "Thread-[0-9]+" | head -1)
            if ! grep -q "$thread_name" <<< "$saved_state" 2>/dev/null; then
                echo "  + $line"
            fi
        fi
    done <<< "$current_state"
    echo ""
    
    # Find terminated threads
    echo "Terminated Threads (in saved state but not current):"
    echo "----------------------------------------------------"
    while IFS= read -r line; do
        if [[ "$line" =~ "Thread-" ]]; then
            local thread_name=$(echo "$line" | grep -oP "Thread-[0-9]+" | head -1)
            if ! grep -q "$thread_name" <<< "$current_state" 2>/dev/null; then
                echo "  - $line"
            fi
        fi
    done <<< "$saved_state"
    
    return 0
}

# List saved states
# Usage: list_saved_states <session>
list_saved_states() {
    local session_name="$1"
    
    ensure_state_dir
    
    echo "Saved Thread States:"
    echo "===================="
    
    ls -la "$THREAD_STATE_DIR"/${session_name}_*.txt 2>/dev/null || echo "No saved states found"
    
    return 0
}

# ============================================================================
# Thread Monitoring
# ============================================================================

# Monitor thread count changes
# Usage: monitor_threads <session> [interval] [max_iterations]
monitor_threads() {
    local session_name="$1"
    local interval="${2:-$DEFAULT_THREAD_POLL_INTERVAL}"
    local max_iterations="${3:-100}"
    
    log_info "Starting thread monitor (interval: ${interval}s, max: ${max_iterations})"
    
    local iteration=0
    local prev_count=0
    local prev_blocked=0
    
    echo "╔══════════════════════════════════════╗"
    echo "║        THREAD MONITOR ACTIVE         ║"
    echo "╠══════════════════════════════════════╣"
    printf "║ %-36s ║\n" "Session: $session_name"
    printf "║ %-36s ║\n" "Interval: ${interval}s"
    printf "║ %-36s ║\n" "Max iterations: $max_iterations"
    echo "╚══════════════════════════════════════╝"
    echo ""
    echo "Press Ctrl+C to stop monitoring"
    echo ""
    
    while [ $iteration -lt $max_iterations ]; do
        local output=$(session_exec_poll "$session_name" "threads" 10 1)
        
        local current_count=$(grep -c "Thread-" <<< "$output" || echo 0)
        local current_blocked=$(grep -c "blocked" <<< "$output" || echo 0)
        
        local timestamp=$(date +"%H:%M:%S")
        local change_marker=""
        local blocked_marker=""
        
        if [ "$current_count" -ne "$prev_count" ]; then
            change_marker=" [CHANGED: $((current_count - prev_count))]"
        fi
        
        if [ "$current_blocked" -ne "$prev_blocked" ]; then
            blocked_marker=" [BLOCKED CHANGE: $((current_blocked - prev_blocked))]"
        fi
        
        echo "[$timestamp] Threads: $current_count${change_marker}, Blocked: $current_blocked${blocked_marker}"
        
        prev_count=$current_count
        prev_blocked=$current_blocked
        ((iteration++))
        
        sleep "$interval"
    done
    
    return 0
}

# ============================================================================
# Thread Name/ID Utilities
# ============================================================================

# Extract thread IDs from output
# Usage: extract_thread_ids <session>
extract_thread_ids() {
    local session_name="$1"
    
    local output=$(session_exec_poll "$session_name" "threads" 10 1)
    
    echo "Thread IDs:"
    echo "==========="
    
    grep -oP "Thread-[0-9]+" <<< "$output" | sort -u
    
    return 0
}

# Get main thread info
# Usage: main_thread <session>
main_thread() {
    local session_name="$1"
    
    log_info "Finding main thread"
    
    local output=$(session_exec_poll "$session_name" "threads" 10 1)
    
    echo "Main Thread Info:"
    echo "================="
    
    grep -i "main" <<< "$output" || echo "Main thread not found in output"
    
    return 0
}

# ============================================================================
# Special Thread Analysis
# ============================================================================

# Analyze system threads (GC, Finalizer, etc.)
# Usage: system_threads <session>
system_threads() {
    local session_name="$1"
    
    log_info "Analyzing system threads"
    
    local output=$(session_exec_poll "$session_name" "threads" 10 1)
    
    echo "╔══════════════════════════════════════╗"
    echo "║         SYSTEM THREADS               ║"
    echo "╠══════════════════════════════════════╣"
    
    local system_found=0
    
    # Common JVM system threads
    for pattern in "Finalizer" "Reference Handler" "Signal Dispatcher" "GC" "Attach Listener" "Common-Cleaner" "JavaFX"; do
        if grep -qi "$pattern" <<< "$output"; then
            printf "║ %-36s ║\n" "$pattern: Found"
            grep -i "$pattern" <<< "$output" | head -1
            ((system_found++))
        fi
    done
    
    if [ "$system_found" -eq 0 ]; then
        printf "║ %-36s ║\n" "No system threads identified"
    fi
    
    echo "╚══════════════════════════════════════╝"
    
    return 0
}

# Analyze thread pools (ExecutorService threads)
# Usage: thread_pools <session>
thread_pools() {
    local session_name="$1"
    
    log_info "Analyzing thread pool threads"
    
    local output=$(session_exec_poll "$session_name" "threads" 10 1)
    
    echo "Thread Pool Analysis:"
    echo "====================="
    
    # Common thread pool patterns
    local pool_patterns=("pool-" "ForkJoinPool" "worker" "ExecutorService" "Scheduled")
    local pool_count=0
    
    for pattern in "${pool_patterns[@]}"; do
        local count=$(grep -ic "$pattern" <<< "$output" || echo 0)
        if [ "$count" -gt 0 ]; then
            echo ""
            echo "Pattern '$pattern': $count thread(s)"
            grep -i "$pattern" <<< "$output"
            ((pool_count += count))
        fi
    done
    
    echo ""
    echo "Total thread pool threads: $pool_count"
    
    return 0
}

# ============================================================================
# Help and Usage
# ============================================================================

show_help() {
    cat << 'EOF'
JDB Thread Analyzer - Comprehensive thread analysis and debugging

USAGE:
    ./jdb_thread_analyzer.sh <command> [arguments]

COMMANDS:

  Basic Commands:
    list <session>                     List all threads
    info <session> <thread_id>         Get detailed info for a thread
    stack <session> <thread_id> [d]    Get stack trace (optional depth)
    stacks <session> [max_depth]       Get all thread stack traces

  Analysis Commands:
    stats <session>                    Show thread state statistics
    find <session> <state>             Find threads in specific state
    search <session> <pattern>         Search threads by name pattern

  Deadlock Detection:
    deadlock <session>                 Analyze potential deadlocks

  State Comparison:
    save <session> [label]             Save current thread state
    compare <session> [label]          Compare with saved state
    saved <session>                    List saved states

  Monitoring:
    monitor <session> [interval] [max] Monitor thread changes

  Utilities:
    ids <session>                      Extract all thread IDs
    main <session>                     Find main thread
    system <session>                   Analyze system threads
    pools <session>                    Analyze thread pools

THREAD STATES:
    NEW           - Thread created but not started
    RUNNABLE      - Thread executing in JVM
    BLOCKED       - Waiting for monitor lock
    WAITING       - Waiting indefinitely
    TIMED_WAITING - Waiting with timeout
    TERMINATED    - Thread has exited

EXAMPLES:
    # List all threads
    ./jdb_thread_analyzer.sh list my_session

    # Get stack trace for Thread-1
    ./jdb_thread_analyzer.sh stack my_session "Thread-1"

    # Check for deadlocks
    ./jdb_thread_analyzer.sh deadlock my_session

    # Find all blocked threads
    ./jdb_thread_analyzer.sh find my_session blocked

    # Monitor thread changes every 5 seconds
    ./jdb_thread_analyzer.sh monitor my_session 5

    # Save state for comparison
    ./jdb_thread_analyzer.sh save my_session before_test

    # Compare current state with saved
    ./jdb_thread_analyzer.sh compare my_session before_test

NOTES:
    - Session must be an active JDB tmux session
    - Thread ID can be thread name or number
    - State comparison helps track thread lifecycle

EOF
    return 0
}

# ============================================================================
# Main Entry Point
# ============================================================================

main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        # Basic Commands
        list|threads)
            list_threads "$@"
            ;;
        info)
            thread_info "$@"
            ;;
        stack)
            thread_stack "$@"
            ;;
        stacks|where)
            all_stacks "$@"
            ;;
        
        # Analysis Commands
        stats|statistics)
            thread_stats "$@"
            ;;
        find)
            find_by_state "$@"
            ;;
        search)
            search_threads "$@"
            ;;
        
        # Deadlock Detection
        deadlock|dead)
            detect_deadlock "$@"
            ;;
        
        # State Comparison
        save)
            save_state "$@"
            ;;
        compare|diff)
            compare_state "$@"
            ;;
        saved|states)
            list_saved_states "$@"
            ;;
        
        # Monitoring
        monitor|watch)
            monitor_threads "$@"
            ;;
        
        # Utilities
        ids)
            extract_thread_ids "$@"
            ;;
        main)
            main_thread "$@"
            ;;
        system)
            system_threads "$@"
            ;;
        pools)
            thread_pools "$@"
            ;;
        
        # Help
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
