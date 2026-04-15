#!/bin/bash
# ============================================================================
# PDB Session Manager - Python debugger session management with tmux
# 
# Features:
#   - Create isolated pdb sessions in tmux
#   - Support for virtualenv
#   - Breakpoint management (set, conditional, clear)
#   - Execution control (run, step, next, continue, return)
#   - Variable inspection (print, pretty-print, locals, list)
#   - Call stack navigation (where, up, down)
#   - Advanced features (exec, watch)
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../common/functions.sh"

# ============================================================================
# Python-specific Configuration
# ============================================================================

DEFAULT_PDB_PORT=5678

# ============================================================================
# Session Management
# ============================================================================

# Create pdb session
# Usage: create_pdb_session <session_name> <python_script> [args]
create_pdb_session() {
    local session_name="$1"
    local python_script="$2"
    local python_args="${3:-}"
    
    # Check if Python exists
    if ! command -v python3 &>/dev/null; then
        error "python3 not found"
    fi
    
    # Build pdb command
    local pdb_cmd="python3 -m pdb $python_script"
    [ -n "$python_args" ] && pdb_cmd="$pdb_cmd $python_args"
    
    log "Creating PDB session: $session_name"
    log "Script: $python_script"
    
    # Create tmux session
    session_create "$session_name" "$pdb_cmd"
    
    # Wait for pdb initialization
    sleep 1
    
    echo "SESSION_NAME=$session_name"
}

# Create pdb session with virtualenv
# Usage: create_pdb_session_venv <session_name> <python_script> <venv_path> [args]
create_pdb_session_venv() {
    local session_name="$1"
    local python_script="$2"
    local venv_path="$3"
    local python_args="${4:-}"
    
    # Verify virtualenv
    if [ ! -f "$venv_path/bin/activate" ]; then
        error "Virtualenv not found: $venv_path"
    fi
    
    # Build command (activate virtualenv first)
    local pdb_cmd="source $venv_path/bin/activate && python -m pdb $python_script"
    [ -n "$python_args" ] && pdb_cmd="$pdb_cmd $python_args"
    
    log "Creating PDB session with virtualenv: $session_name"
    log "Virtualenv: $venv_path"
    log "Script: $python_script"
    
    session_create "$session_name" "$pdb_cmd"
    sleep 1
    
    echo "SESSION_NAME=$session_name"
}

# ============================================================================
# Breakpoint Management
# ============================================================================

# Set breakpoint
# Usage: pdb_set_breakpoint <session> <location>
# location: filename:lineno or function_name
pdb_set_breakpoint() {
    local session_name="$1"
    local location="$2"  # filename:lineno or function_name
    
    session_send "$session_name" "b $location"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# Set conditional breakpoint
# Usage: pdb_set_conditional_breakpoint <session> <location> <condition>
pdb_set_conditional_breakpoint() {
    local session_name="$1"
    local location="$2"
    local condition="$3"
    
    session_send "$session_name" "b $location, $condition"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# Clear breakpoint
# Usage: pdb_clear_breakpoint <session> [bp_num]
pdb_clear_breakpoint() {
    local session_name="$1"
    local bp_num="${2:-}"  # Optional, clear all if not specified
    
    if [ -n "$bp_num" ]; then
        session_send "$session_name" "cl $bp_num"
    else
        session_send "$session_name" "cl"
    fi
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# List breakpoints
# Usage: pdb_list_breakpoints <session>
pdb_list_breakpoints() {
    local session_name="$1"
    
    session_send "$session_name" "b"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# ============================================================================
# Execution Control
# ============================================================================

# Run program
# Usage: pdb_run <session>
pdb_run() {
    local session_name="$1"
    
    session_send "$session_name" "c"
    session_poll "$session_name" 30 0.5 "[(]pdb[)]|->"
}

# Step into function
# Usage: pdb_step <session>
pdb_step() {
    local session_name="$1"
    
    session_send "$session_name" "s"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# Step over (don't enter function)
# Usage: pdb_next <session>
pdb_next() {
    local session_name="$1"
    
    session_send "$session_name" "n"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# Continue execution
# Usage: pdb_continue <session>
pdb_continue() {
    local session_name="$1"
    
    session_send "$session_name" "c"
    session_poll "$session_name" 30 0.5 "[(]pdb[)]"
}

# Return from current function
# Usage: pdb_return <session>
pdb_return() {
    local session_name="$1"
    
    session_send "$session_name" "r"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# Quit debugging
# Usage: pdb_quit <session>
pdb_quit() {
    local session_name="$1"
    
    session_send "$session_name" "q"
    sleep 0.5
    session_send "$session_name" "y"  # Confirm quit
}

# ============================================================================
# Variable Inspection
# ============================================================================

# Print expression
# Usage: pdb_print <session> <expression>
pdb_print() {
    local session_name="$1"
    local expression="$2"
    
    session_send "$session_name" "p $expression"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# Pretty print expression
# Usage: pdb_pretty_print <session> <expression>
pdb_pretty_print() {
    local session_name="$1"
    local expression="$2"
    
    session_send "$session_name" "pp $expression"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# List local variables (arguments)
# Usage: pdb_locals <session>
pdb_locals() {
    local session_name="$1"
    
    session_send "$session_name" "a"  # args
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# List source code
# Usage: pdb_list <session> [lines]
pdb_list() {
    local session_name="$1"
    local lines="${2:-11}"  # Number of lines to display
    
    session_send "$session_name" "l $lines"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# ============================================================================
# Call Stack
# ============================================================================

# Print call stack (where)
# Usage: pdb_where <session>
pdb_where() {
    local session_name="$1"
    
    session_send "$session_name" "w"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# Move up call stack
# Usage: pdb_up <session>
pdb_up() {
    local session_name="$1"
    
    session_send "$session_name" "u"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# Move down call stack
# Usage: pdb_down <session>
pdb_down() {
    local session_name="$1"
    
    session_send "$session_name" "d"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# ============================================================================
# Advanced Features
# ============================================================================

# Execute Python statement
# Usage: pdb_exec <session> <statement>
pdb_exec() {
    local session_name="$1"
    local statement="$2"
    
    session_send "$session_name" "! $statement"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# Set variable value
# Usage: pdb_set_var <session> <var_name> <var_value>
pdb_set_var() {
    local session_name="$1"
    local var_name="$2"
    local var_value="$3"
    
    pdb_exec "$session_name" "$var_name = $var_value"
}

# Import module
# Usage: pdb_import <session> <module>
pdb_import() {
    local session_name="$1"
    local module="$2"
    
    pdb_exec "$session_name" "import $module"
}

# Watch expression (auto-print on each stop)
# Usage: pdb_watch <session> <expression>
pdb_watch() {
    local session_name="$1"
    local expression="$2"
    
    # PDB uses 'display' for watch-like behavior
    session_send "$session_name" "display $expression"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# ============================================================================
# Quick Start
# ============================================================================

# Quick start Python debugging
# Usage: pdb_quick_start <project_dir> <script_name> [args]
pdb_quick_start() {
    local project_dir="$1"
    local script_name="$2"
    local args="${3:-}"
    
    # Find script
    local script_path="$project_dir/$script_name"
    if [ ! -f "$script_path" ]; then
        # Try to find in subdirectories
        script_path=$(find "$project_dir" -name "$script_name" -type f 2>/dev/null | head -1)
        [ -z "$script_path" ] && error "Script not found: $script_name"
    fi
    
    # Detect virtualenv
    local venv_path=""
    if [ -f "$project_dir/venv/bin/activate" ]; then
        venv_path="$project_dir/venv"
    elif [ -f "$project_dir/.venv/bin/activate" ]; then
        venv_path="$project_dir/.venv"
    fi
    
    # Generate session name
    local session_name="pdb_$(basename "$script_name" .py)_$$"
    
    # Create session
    if [ -n "$venv_path" ]; then
        create_pdb_session_venv "$session_name" "$script_path" "$venv_path" "$args"
    else
        create_pdb_session "$session_name" "$script_path" "$args"
    fi
    
    echo ""
    echo "========================================"
    echo "PDB Session Ready"
    echo "========================================"
    echo "Session: $session_name"
    echo "Script:  $script_path"
    [ -n "$venv_path" ] && echo "Venv:    $venv_path"
    echo ""
    echo "Commands:"
    echo "  $SCRIPT_DIR/pdb_session.sh exec-poll $session_name \"b main.py:10\" 5 0.5"
    echo "  $SCRIPT_DIR/pdb_session.sh exec-poll $session_name \"c\" 30 0.5"
    echo "========================================"
}

# ============================================================================
# Main Entry Point
# ============================================================================

show_usage() {
    cat << EOF
PDB Session Manager - Python debugger session management

Usage:
    $0 <command> [arguments...]

Commands:
    # Session management
    create <session> <script.py> [args]
        Create pdb session
        Example: $0 create mysession test.py --arg1 value1
    
    create-venv <session> <script.py> <venv_path> [args]
        Create pdb session with virtualenv
        Example: $0 create-venv mysession test.py ./venv
    
    quick-start <project_dir> <script.py> [args]
        Quick start (auto-detect virtualenv)
    
    # Breakpoints
    bp <session> <file:line>
        Set breakpoint
        Example: $0 bp mysession main.py:10
    
    bp-cond <session> <file:line> <condition>
        Set conditional breakpoint
        Example: $0 bp-cond mysession main.py:10 "i > 5"
    
    bp-list <session>
        List all breakpoints
    
    bp-clear <session> [bp_num]
        Clear breakpoint(s)
    
    # Execution control
    run <session>
        Run program
    
    step <session>
        Step into function
    
    next <session>
        Step over (don't enter function)
    
    cont <session>
        Continue execution
    
    # Variables
    print <session> <expression>
        Print expression
        Example: $0 print mysession "my_var"
    
    locals <session>
        List local variables
    
    list <session> [lines]
        List source code
    
    # Call stack
    where <session>
        Print call stack
    
    up <session>
        Move up call stack
    
    down <session>
        Move down call stack
    
    # Advanced
    exec <session> <statement>
        Execute Python statement
    
    watch <session> <expression>
        Watch expression (auto-print on stop)
    
    # Session management
    kill <session>
        Terminate session
    
    cleanup
        Clean up all pdb sessions

EOF
}

# Entry point
if [ $# -lt 1 ]; then
    show_usage
    exit 1
fi

command="$1"
shift

case "$command" in
    create)
        [ $# -lt 2 ] && error "Usage: $0 create <session> <script.py> [args]"
        create_pdb_session "$1" "$2" "${3:-}"
        ;;
    create-venv)
        [ $# -lt 3 ] && error "Usage: $0 create-venv <session> <script.py> <venv_path> [args]"
        create_pdb_session_venv "$1" "$2" "$3" "${4:-}"
        ;;
    quick-start)
        [ $# -lt 2 ] && error "Usage: $0 quick-start <project_dir> <script.py> [args]"
        pdb_quick_start "$1" "$2" "${3:-}"
        ;;
    bp)
        [ $# -lt 2 ] && error "Usage: $0 bp <session> <file:line>"
        pdb_set_breakpoint "$1" "$2"
        ;;
    bp-cond)
        [ $# -lt 3 ] && error "Usage: $0 bp-cond <session> <file:line> <condition>"
        pdb_set_conditional_breakpoint "$1" "$2" "$3"
        ;;
    bp-list)
        [ $# -lt 1 ] && error "Usage: $0 bp-list <session>"
        pdb_list_breakpoints "$1"
        ;;
    bp-clear)
        [ $# -lt 1 ] && error "Usage: $0 bp-clear <session> [bp_num]"
        pdb_clear_breakpoint "$1" "${2:-}"
        ;;
    run)
        [ $# -lt 1 ] && error "Usage: $0 run <session>"
        pdb_run "$1"
        ;;
    step)
        [ $# -lt 1 ] && error "Usage: $0 step <session>"
        pdb_step "$1"
        ;;
    next)
        [ $# -lt 1 ] && error "Usage: $0 next <session>"
        pdb_next "$1"
        ;;
    cont)
        [ $# -lt 1 ] && error "Usage: $0 cont <session>"
        pdb_continue "$1"
        ;;
    print)
        [ $# -lt 2 ] && error "Usage: $0 print <session> <expression>"
        pdb_print "$1" "$2"
        ;;
    locals)
        [ $# -lt 1 ] && error "Usage: $0 locals <session>"
        pdb_locals "$1"
        ;;
    list)
        [ $# -lt 1 ] && error "Usage: $0 list <session> [lines]"
        pdb_list "$1" "${2:-11}"
        ;;
    where)
        [ $# -lt 1 ] && error "Usage: $0 where <session>"
        pdb_where "$1"
        ;;
    up)
        [ $# -lt 1 ] && error "Usage: $0 up <session>"
        pdb_up "$1"
        ;;
    down)
        [ $# -lt 1 ] && error "Usage: $0 down <session>"
        pdb_down "$1"
        ;;
    exec)
        [ $# -lt 2 ] && error "Usage: $0 exec <session> <statement>"
        pdb_exec "$1" "$2"
        ;;
    watch)
        [ $# -lt 2 ] && error "Usage: $0 watch <session> <expression>"
        pdb_watch "$1" "$2"
        ;;
    kill)
        [ $# -lt 1 ] && error "Usage: $0 kill <session>"
        session_kill "$1"
        ;;
    cleanup)
        session_cleanup "pdb_"
        ;;
    -h|--help)
        show_usage
        exit 0
        ;;
    *)
        error "Unknown command: $command. Use --help for usage."
        ;;
esac
