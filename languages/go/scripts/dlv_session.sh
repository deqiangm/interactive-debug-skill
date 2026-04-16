#!/bin/bash
# ============================================================================
# DLV Session Manager - Go debugger (Delve) session management with tmux
# 
# Features:
# - Create isolated dlv sessions in tmux
# - Go module auto-detection
# - Breakpoint management (set, conditional, clear)
# - Execution control (run, step, next, continue)
# - Variable inspection (print, locals, args)
# - Goroutine support (list, switch)
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../common/functions.sh"

# ============================================================================
# Go-specific Configuration
# ============================================================================

DEFAULT_DLV_PORT=4040
DLV_PROMPT='[(]dlv[)]|>'

# ============================================================================
# Session Management
# ============================================================================

# Create dlv session for debugging a Go program
# Usage: create_dlv_session <session_name> <program_path> [args]
create_dlv_session() {
	local session_name="$1"
	local program_path="$2"
	local program_args="${3:-}"
	
	# Check if dlv exists
	if ! command -v dlv &>/dev/null; then
		error "dlv (Delve) not found. Install: go install github.com/go-delve/delve/cmd/dlv@latest"
	fi
	
	# Build dlv command
	local dlv_cmd="dlv debug $program_path"
	[ -n "$program_args" ] && dlv_cmd="$dlv_cmd -- $program_args"
	
	log "Creating DLV session: $session_name"
	log "Program: $program_path"
	
	# Create tmux session
	session_create "$session_name" "$dlv_cmd"
	
	# Wait for dlv initialization
	sleep 1
	
	echo "SESSION_NAME=$session_name"
}

# Create dlv session from Go module
# Usage: create_dlv_session_module <session_name> <module_dir> [args]
create_dlv_session_module() {
	local session_name="$1"
	local module_dir="$2"
	local program_args="${3:-}"
	
	# Verify Go module
	if [ ! -f "$module_dir/go.mod" ]; then
		error "Go module not found: $module_dir/go.mod"
	fi
	
	# Find main package
	local main_pkg=""
	if [ -f "$module_dir/main.go" ]; then
		main_pkg="."
	elif [ -d "$module_dir/cmd" ]; then
		main_pkg="./cmd/..."
	fi
	
	if ! command -v dlv &>/dev/null; then
		error "dlv (Delve) not found"
	fi
	
	local dlv_cmd="cd $module_dir && dlv debug $main_pkg"
	[ -n "$program_args" ] && dlv_cmd="$dlv_cmd -- $program_args"
	
	log "Creating DLV session: $session_name"
	log "Module: $module_dir"
	
	session_create "$session_name" "$dlv_cmd"
	sleep 1
	
	echo "SESSION_NAME=$session_name"
}

# ============================================================================
# Breakpoint Management
# ============================================================================

# Set breakpoint
# Usage: dlv_set_breakpoint <session> <location>
# location: filename:lineno or function_name
dlv_set_breakpoint() {
	local session_name="$1"
	local location="$2"
	
	session_send "$session_name" "break $location"
	session_poll "$session_name" 5 0.5 "$DLV_PROMPT"
}

# Set conditional breakpoint
# Usage: dlv_set_conditional_breakpoint <session> <location> <condition>
dlv_set_conditional_breakpoint() {
	local session_name="$1"
	local location="$2"
	local condition="$3"
	
	session_send "$session_name" "break $location"
	session_poll "$session_name" 5 0.5 "$DLV_PROMPT"
	
	# Get breakpoint ID and add condition
	session_send "$session_name" "condition $(dlv_get_last_bp_id "$session_name") $condition"
	session_poll "$session_name" 5 0.5 "$DLV_PROMPT"
}

# Clear breakpoint
# Usage: dlv_clear_breakpoint <session> [bp_id]
dlv_clear_breakpoint() {
	local session_name="$1"
	local bp_id="${2:-}"
	
	if [ -n "$bp_id" ]; then
		session_send "$session_name" "clear $bp_id"
	else
		session_send "$session_name" "clearall"
	fi
	session_poll "$session_name" 5 0.5 "$DLV_PROMPT"
}

# List breakpoints
# Usage: dlv_list_breakpoints <session>
dlv_list_breakpoints() {
	local session_name="$1"
	
	session_send "$session_name" "breakpoints"
	session_poll "$session_name" 5 0.5 "$DLV_PROMPT"
}

# Get last breakpoint ID from output (helper)
dlv_get_last_bp_id() {
	local session_name="$1"
	local output=$(session_read "$session_name")
	echo "$output" | grep -oP 'Breakpoint \K[0-9]+' | tail -1
}

# ============================================================================
# Execution Control
# ============================================================================

# Run program
# Usage: dlv_run <session>
dlv_run() {
	local session_name="$1"
	
	session_send "$session_name" "continue"
	session_poll "$session_name" 30 0.5 "$DLV_PROMPT"
}

# Step into function
# Usage: dlv_step <session>
dlv_step() {
	local session_name="$1"
	
	session_send "$session_name" "step"
	session_poll "$session_name" 5 0.5 "$DLV_PROMPT"
}

# Step over (don't enter function)
# Usage: dlv_next <session>
dlv_next() {
	local session_name="$1"
	
	session_send "$session_name" "next"
	session_poll "$session_name" 5 0.5 "$DLV_PROMPT"
}

# Continue execution
# Usage: dlv_continue <session>
dlv_continue() {
	local session_name="$1"
	
	session_send "$session_name" "continue"
	session_poll "$session_name" 30 0.5 "$DLV_PROMPT"
}

# Step out of current function
# Usage: dlv_stepout <session>
dlv_stepout() {
	local session_name="$1"
	
	session_send "$session_name" "stepout"
	session_poll "$session_name" 10 0.5 "$DLV_PROMPT"
}

# Restart program
# Usage: dlv_restart <session>
dlv_restart() {
	local session_name="$1"
	
	session_send "$session_name" "restart"
	session_poll "$session_name" 10 0.5 "$DLV_PROMPT"
}

# Quit debugging
# Usage: dlv_quit <session>
dlv_quit() {
	local session_name="$1"
	
	session_send "$session_name" "exit"
	sleep 0.5
	session_send "$session_name" "y" 2>/dev/null || true
}

# ============================================================================
# Variable Inspection
# ============================================================================

# Print expression
# Usage: dlv_print <session> <expression>
dlv_print() {
	local session_name="$1"
	local expression="$2"
	
	session_send "$session_name" "print $expression"
	session_poll "$session_name" 5 0.5 "$DLV_PROMPT"
}

# List local variables
# Usage: dlv_locals <session>
dlv_locals() {
	local session_name="$1"
	
	session_send "$session_name" "locals"
	session_poll "$session_name" 5 0.5 "$DLV_PROMPT"
}

# List function arguments
# Usage: dlv_args <session>
dlv_args() {
	local session_name="$1"
	
	session_send "$session_name" "args"
	session_poll "$session_name" 5 0.5 "$DLV_PROMPT"
}

# Set variable value
# Usage: dlv_set_var <session> <var_name> <var_value>
dlv_set_var() {
	local session_name="$1"
	local var_name="$2"
	local var_value="$3"
	
	session_send "$session_name" "set $var_name = $var_value"
	session_poll "$session_name" 5 0.5 "$DLV_PROMPT"
}

# ============================================================================
# Call Stack
# ============================================================================

# Print call stack
# Usage: dlv_stack <session>
dlv_stack() {
	local session_name="$1"
	
	session_send "$session_name" "stack"
	session_poll "$session_name" 5 0.5 "$DLV_PROMPT"
}

# Move up call stack
# Usage: dlv_up <session>
dlv_up() {
	local session_name="$1"
	
	session_send "$session_name" "up"
	session_poll "$session_name" 5 0.5 "$DLV_PROMPT"
}

# Move down call stack
# Usage: dlv_down <session>
dlv_down() {
	local session_name="$1"
	
	session_send "$session_name" "down"
	session_poll "$session_name" 5 0.5 "$DLV_PROMPT"
}

# ============================================================================
# Goroutine Support
# ============================================================================

# List goroutines
# Usage: dlv_goroutines <session>
dlv_goroutines() {
	local session_name="$1"
	
	session_send "$session_name" "goroutines"
	session_poll "$session_name" 5 0.5 "$DLV_PROMPT"
}

# Switch to specific goroutine
# Usage: dlv_switch_goroutine <session> <goroutine_id>
dlv_switch_goroutine() {
	local session_name="$1"
	local goroutine_id="$2"
	
	session_send "$session_name" "goroutine $goroutine_id"
	session_poll "$session_name" 5 0.5 "$DLV_PROMPT"
}

# Show current goroutine info
# Usage: dlv_goroutine_info <session>
dlv_goroutine_info() {
	local session_name="$1"
	
	session_send "$session_name" "goroutine"
	session_poll "$session_name" 5 0.5 "$DLV_PROMPT"
}

# ============================================================================
# Source Code
# ============================================================================

# List source code
# Usage: dlv_list <session> [lines]
dlv_list() {
	local session_name="$1"
	local lines="${2:-10}"
	
	session_send "$session_name" "list"
	session_poll "$session_name" 5 0.5 "$DLV_PROMPT"
}

# ============================================================================
# Quick Start
# ============================================================================

# Quick start Go debugging
# Usage: dlv_quick_start <project_dir> [main_file]
dlv_quick_start() {
	local project_dir="$1"
	local main_file="${2:-}"
	
	# Verify Go module
	if [ ! -f "$project_dir/go.mod" ]; then
		error "Go module not found: $project_dir/go.mod"
	fi
	
	# Generate session name
	local session_name="dlv_$(basename "$project_dir")_$$"
	
	# Find main package if not specified
	if [ -z "$main_file" ]; then
		if [ -f "$project_dir/main.go" ]; then
			main_pkg="."
		elif [ -d "$project_dir/cmd" ]; then
			# Find first cmd subdirectory with main.go
			main_pkg=$(find "$project_dir/cmd" -name "main.go" -type f 2>/dev/null | head -1 | xargs dirname)
			[ -z "$main_pkg" ] && error "No main package found in $project_dir"
		else
			error "No main.go found in $project_dir"
		fi
	else
		main_pkg="$main_file"
	fi
	
	# Create session
	create_dlv_session_module "$session_name" "$project_dir"
	
	echo ""
	echo "========================================"
	echo "DLV Session Ready"
	echo "========================================"
	echo "Session: $session_name"
	echo "Project: $project_dir"
	echo ""
	echo "Commands:"
	echo "  $SCRIPT_DIR/dlv_session.sh bp $session_name main.go:10"
	echo "  $SCRIPT_DIR/dlv_session.sh continue $session_name"
	echo "  $SCRIPT_DIR/dlv_session.sh next $session_name"
	echo "  $SCRIPT_DIR/dlv_session.sh print $session_name \"myVar\""
	echo "========================================"
}

# ============================================================================
# Main Entry Point
# ============================================================================

show_usage() {
	cat << EOF
DLV Session Manager - Go debugger (Delve) session management

Usage:
 $0 <command> [arguments...]

Commands:
 # Session management
 create <session> <program> [args]
 Create dlv session
 Example: $0 create mysession ./myprogram
 
 create-module <session> <module_dir> [args]
 Create dlv session from Go module
 Example: $0 create-module mysession /path/to/module
 
 quick-start <project_dir> [main_file]
 Quick start (auto-detect module)
 
 # Breakpoints
 bp <session> <file:line|func>
 Set breakpoint
 Example: $0 bp mysession main.go:20
 Example: $0 bp mysession main.myFunction
 
 bp-cond <session> <location> <condition>
 Set conditional breakpoint
 Example: $0 bp-cond mysession main.go:20 "i > 5"
 
 bp-list <session>
 List all breakpoints
 
 bp-clear <session> [bp_id]
 Clear breakpoint(s)
 
 # Execution control
 run <session>
 Run program (continue from start)
 
 step <session>
 Step into function
 
 next <session>
 Step over (don't enter function)
 
 cont <session>
 Continue execution
 
 stepout <session>
 Step out of current function
 
 restart <session>
 Restart program
 
 # Variables
 print <session> <expression>
 Print expression
 Example: $0 print mysession "myVar"
 Example: $0 print mysession "mySlice[0]"
 
 locals <session>
 List local variables
 
 args <session>
 List function arguments
 
 set <session> <var> <value>
 Set variable value
 Example: $0 set mysession myVar 10
 
 # Call stack
 stack <session>
 Print call stack
 
 up <session>
 Move up call stack
 
 down <session>
 Move down call stack
 
 # Goroutines
 goroutines <session>
 List all goroutines
 
 goroutine <session> [id]
 Show current goroutine or switch to id
 
 # Source
 list <session>
 List source code around current line
 
 # Session management
 kill <session>
 Terminate session
 
 cleanup
 Clean up all dlv sessions

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
		[ $# -lt 2 ] && error "Usage: $0 create <session> <program> [args]"
		create_dlv_session "$1" "$2" "${3:-}"
		;;
	create-module)
		[ $# -lt 2 ] && error "Usage: $0 create-module <session> <module_dir> [args]"
		create_dlv_session_module "$1" "$2" "${3:-}"
		;;
	quick-start)
		[ $# -lt 1 ] && error "Usage: $0 quick-start <project_dir> [main_file]"
		dlv_quick_start "$1" "${2:-}"
		;;
	bp)
		[ $# -lt 2 ] && error "Usage: $0 bp <session> <location>"
		dlv_set_breakpoint "$1" "$2"
		;;
	bp-cond)
		[ $# -lt 3 ] && error "Usage: $0 bp-cond <session> <location> <condition>"
		dlv_set_conditional_breakpoint "$1" "$2" "$3"
		;;
	bp-list)
		[ $# -lt 1 ] && error "Usage: $0 bp-list <session>"
		dlv_list_breakpoints "$1"
		;;
	bp-clear)
		[ $# -lt 1 ] && error "Usage: $0 bp-clear <session> [bp_id]"
		dlv_clear_breakpoint "$1" "${2:-}"
		;;
	run)
		[ $# -lt 1 ] && error "Usage: $0 run <session>"
		dlv_run "$1"
		;;
	step)
		[ $# -lt 1 ] && error "Usage: $0 step <session>"
		dlv_step "$1"
		;;
	next)
		[ $# -lt 1 ] && error "Usage: $0 next <session>"
		dlv_next "$1"
		;;
	cont|continue)
		[ $# -lt 1 ] && error "Usage: $0 cont <session>"
		dlv_continue "$1"
		;;
	stepout)
		[ $# -lt 1 ] && error "Usage: $0 stepout <session>"
		dlv_stepout "$1"
		;;
	restart)
		[ $# -lt 1 ] && error "Usage: $0 restart <session>"
		dlv_restart "$1"
		;;
	print)
		[ $# -lt 2 ] && error "Usage: $0 print <session> <expression>"
		dlv_print "$1" "$2"
		;;
	locals)
		[ $# -lt 1 ] && error "Usage: $0 locals <session>"
		dlv_locals "$1"
		;;
	args)
		[ $# -lt 1 ] && error "Usage: $0 args <session>"
		dlv_args "$1"
		;;
	set)
		[ $# -lt 3 ] && error "Usage: $0 set <session> <var> <value>"
		dlv_set_var "$1" "$2" "$3"
		;;
	stack)
		[ $# -lt 1 ] && error "Usage: $0 stack <session>"
		dlv_stack "$1"
		;;
	up)
		[ $# -lt 1 ] && error "Usage: $0 up <session>"
		dlv_up "$1"
		;;
	down)
		[ $# -lt 1 ] && error "Usage: $0 down <session>"
		dlv_down "$1"
		;;
	goroutines)
		[ $# -lt 1 ] && error "Usage: $0 goroutines <session>"
		dlv_goroutines "$1"
		;;
	goroutine)
		[ $# -lt 1 ] && error "Usage: $0 goroutine <session> [id]"
		if [ -n "$2" ]; then
			dlv_switch_goroutine "$1" "$2"
		else
			dlv_goroutine_info "$1"
		fi
		;;
	list)
		[ $# -lt 1 ] && error "Usage: $0 list <session>"
		dlv_list "$1" "${2:-}"
		;;
	kill)
		[ $# -lt 1 ] && error "Usage: $0 kill <session>"
		session_kill "$1"
		;;
	cleanup)
		session_cleanup "dlv_"
		;;
	*)
		error "Unknown command: $command"
		;;
esac
