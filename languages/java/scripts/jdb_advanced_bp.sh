#!/bin/bash
# ============================================================================
# JDB Advanced Breakpoint Manager - Advanced breakpoint management for JDB
# 
# Features:
#   - Conditional breakpoints (stop when condition is true)
#   - Temporary breakpoints (hit once, then auto-remove)
#   - Watchpoints (stop on field access/modification)
#   - Method breakpoints (stop on method entry/exit)
#   - Exception breakpoints (stop on exception throw)
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../common/functions.sh"

# ============================================================================
# Breakpoint Types
# ============================================================================

# Create conditional breakpoint
# Stops only when condition evaluates to true
# Usage: create_conditional_breakpoint <session> <location> <condition>
create_conditional_breakpoint() {
    local session_name="$1"
    local location="$2"      # Class:line or Class.method
    local condition="$3"     # Condition expression
    
    log "Creating conditional breakpoint at $location"
    log "Condition: $condition"
    
    # JDB simulates conditional breakpoints by:
    # 1. Set breakpoint
    # 2. When hit, check condition
    # 3. If condition not met, continue
    
    # First set the breakpoint
    session_send "$session_name" "stop at $location"
    
    # Wait for confirmation
    local output=$(session_poll "$session_name" 5 0.5)
    
    # Create condition check script (for later use)
    local bp_id=$(echo "$location" | tr ':.' '__')
    local script_file="/tmp/jdb_cond_bp_${bp_id}.sh"
    
    cat > "$script_file" << EOF
#!/bin/bash
# Conditional breakpoint script for $location
# Condition: $condition

# This script is called when breakpoint is hit
# Returns 0 if should stop, 1 if should continue

# Get variable value
RESULT=\$(session_exec_poll "$session_name" "print $condition" 5 0.5)

# Check if result is true
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

# Create temporary breakpoint (triggers once, then removed)
# Usage: create_temporary_breakpoint <session> <location>
create_temporary_breakpoint() {
    local session_name="$1"
    local location="$2"
    
    log "Creating temporary breakpoint at $location"
    
    # Set breakpoint
    session_send "$session_name" "stop at $location"
    local output=$(session_poll "$session_name" 5 0.5)
    
    # Create auto-cleanup script
    local bp_id=$(echo "$location" | tr ':.' '__')
    local cleanup_script="/tmp/jdb_temp_bp_cleanup_${bp_id}.sh"
    
    cat > "$cleanup_script" << EOF
#!/bin/bash
# Temporary breakpoint cleanup script
# Called after breakpoint is hit once

session_send "$session_name" "clear $location"
echo "Temporary breakpoint at $location cleared"
EOF
    chmod +x "$cleanup_script"
    
    log "Temporary breakpoint set. Cleanup script: $cleanup_script"
    echo "CLEANUP_SCRIPT=$cleanup_script"
}

# Create watchpoint (monitor field access/modification)
# Usage: create_watchpoint <session> <class> <field> [access_type]
# access_type: all, read, write
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

# Create method breakpoint
# Usage: create_method_breakpoint <session> <class> <method>
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

# Create exception breakpoint
# Usage: create_exception_breakpoint <session> [exception_class] [caught]
# caught: caught, uncaught, both
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
            # JDB catch catches all by default
            session_send "$session_name" "catch $exception_class"
            ;;
    esac
    
    local output=$(session_poll "$session_name" 5 0.5)
    log "Exception breakpoint output: $output"
}

# ============================================================================
# Breakpoint Management
# ============================================================================

# List all breakpoints
# Usage: list_breakpoints <session>
list_breakpoints() {
    local session_name="$1"
    
    log "Listing all breakpoints..."
    
    session_send "$session_name" "stop"
    local output=$(session_poll "$session_name" 5 0.5)
    
    echo "$output"
}

# Clear a specific breakpoint
# Usage: clear_breakpoint <session> <location>
clear_breakpoint() {
    local session_name="$1"
    local location="$2"
    
    log "Clearing breakpoint at $location"
    
    session_send "$session_name" "clear $location"
    local output=$(session_poll "$session_name" 5 0.5)
    
    echo "$output"
}

# Clear all breakpoints
# Usage: clear_all_breakpoints <session>
clear_all_breakpoints() {
    local session_name="$1"
    
    log "Clearing all breakpoints..."
    
    # Get all breakpoints
    session_send "$session_name" "stop"
    local output=$(session_poll "$session_name" 5 0.5)
    
    # Parse and clear each breakpoint
    echo "$output" | grep -oE '[0-9]+:' | while read bp; do
        local bp_num=$(echo "$bp" | tr -d ':')
        session_send "$session_name" "clear $bp_num"
        sleep 0.5
    done
    
    log "All breakpoints cleared"
}

# ============================================================================
# Conditional Breakpoint Handling
# ============================================================================

# Check condition when breakpoint is hit
# Must be called after breakpoint is hit
# Usage: check_breakpoint_condition <session> <condition>
check_breakpoint_condition() {
    local session_name="$1"
    local condition="$2"
    
    log "Checking condition: $condition"
    
    # Evaluate condition expression
    session_send "$session_name" "eval $condition"
    local output=$(session_poll "$session_name" 5 0.5)
    
    # Parse result
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
# Advanced Breakpoint Scripts
# ============================================================================

# Auto conditional loop - automatically continues until condition is met
# Usage: auto_conditional_loop <session> <location> <condition> [max_iterations]
auto_conditional_loop() {
    local session_name="$1"
    local location="$2"
    local condition="$3"
    local max_iterations="${4:-100}"
    
    log "Starting auto conditional loop for $location with condition: $condition"
    
    local iteration=0
    while [ $iteration -lt $max_iterations ]; do
        # Continue and wait for breakpoint
        session_send "$session_name" "cont"
        local output=$(session_poll "$session_name" 10 0.5)
        
        if echo "$output" | grep -q "Breakpoint hit"; then
            # Check condition
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
# Breakpoint Templates
# ============================================================================

# Apply common breakpoint templates
# Usage: apply_bp_template <session> <template> <params>
apply_bp_template() {
    local session_name="$1"
    local template="$2"
    local params="$3"
    
    case "$template" in
        null_check)
            # Check if variable is null
            local var_name="$params"
            create_conditional_breakpoint "$session_name" "$location" "$var_name == null"
            ;;
        array_bounds)
            # Check for array index out of bounds
            local arr_name=$(echo "$params" | cut -d',' -f1)
            local idx_name=$(echo "$params" | cut -d',' -f2)
            create_conditional_breakpoint "$session_name" "$location" "$idx_name >= $arr_name.length"
            ;;
        value_change)
            # Watch for value changes
            local var_name="$params"
            create_watchpoint "$session_name" "$class" "$var_name" "write"
            ;;
        loop_iteration)
            # Break at specific loop iteration
            local iter_num="$params"
            create_conditional_breakpoint "$session_name" "$location" "i == $iter_num"
            ;;
        *)
            log_warn "Unknown template: $template"
            ;;
    esac
}

# ============================================================================
# Help
# ============================================================================

show_usage() {
    cat << EOF
JDB Advanced Breakpoint Manager

Usage:
    $0 <command> [arguments...]

Commands:
    # Conditional breakpoints
    cond <session> <Class:line> "<condition>"
        Create conditional breakpoint
        Example: $0 cond mysession BubbleSort:11 "i > 5"
    
    # Temporary breakpoints
    temp <session> <Class:line>
        Create temporary breakpoint (triggers once)
        Example: $0 temp mysession BubbleSort:11
    
    # Watchpoints
    watch <session> <Class> <field> [read|write|all]
        Create watchpoint
        Example: $0 watch mysession BubbleSort arr write
    
    # Method breakpoints
    method <session> <Class> <method>
        Create method breakpoint
        Example: $0 method mysession BubbleSort sort
    
    # Exception breakpoints
    exception <session> [ExceptionClass]
        Create exception breakpoint
        Example: $0 exception mysession NullPointerException
    
    # Management
    list <session>
        List all breakpoints
    
    clear <session> <Class:line>
        Clear specific breakpoint
    
    clear-all <session>
        Clear all breakpoints
    
    # Condition checking
    check-cond <session> "<condition>"
        Check condition (use after breakpoint hit)
    
    # Auto loop
    auto-cond <session> <Class:line> "<condition>" [max_iter]
        Auto loop until condition met

Examples:
    # Conditional breakpoint: stop when i > 3
    $0 cond mysession BubbleSort:11 "i > 3"
    
    # Watchpoint: monitor arr field modifications
    $0 watch mysession BubbleSort arr write
    
    # Exception breakpoint: stop on NullPointerException
    $0 exception mysession NullPointerException

EOF
}

# ============================================================================
# Main Entry Point
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
