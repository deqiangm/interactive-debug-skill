#!/bin/bash
# ============================================================================
# Node Session Manager - Node.js debugger session management with tmux
# 
# Features:
# - Create isolated node inspect sessions in tmux
# - Package.json auto-detection
# - Breakpoint management (set, conditional, clear)
# - Execution control (run, step, next, continue)
# - Variable inspection (print, repl)
# - Call stack navigation (backtrace, up, down)
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../common/functions.sh"

# ============================================================================
# Node.js-specific Configuration
# ============================================================================

DEFAULT_NODE_PORT=9229
NODE_PROMPT='debug>|[(]node[)]|>'

# ============================================================================
# Session Management
# ============================================================================

# Create node inspect session
# Usage: create_node_session <session_name> <script_path> [args]
create_node_session() {
	local session_name="$1"
	local script_path="$2"
	local script_args="${3:-}"
	
	# Check if node exists
	if ! command -v node &>/dev/null; then
		error "node not found"
	fi
	
	# Build node inspect command
	local node_cmd="node inspect $script_path"
	[ -n "$script_args" ] && node_cmd="$node_cmd $script_args"
	
	log "Creating Node inspect session: $session_name"
	log "Script: $script_path"
	
	# Create tmux session
	session_create "$session_name" "$node_cmd"
	
	# Wait for debugger initialization
	sleep 1
	
	echo "SESSION_NAME=$session_name"
}

# Create node inspect session from project directory
# Usage: create_node_session_project <session_name> <project_dir> [args]
create_node_session_project() {
	local session_name="$1"
	local project_dir="$2"
	local script_args="${3:-}"
	
	# Verify Node project
	if [ ! -f "$project_dir/package.json" ]; then
		error "Node project not found: $project_dir/package.json"
	fi
	
	# Find main script
	local main_script=$(cd "$project_dir" && node -e "
		const pkg = require('./package.json');
		console.log(pkg.main || 'index.js');
	" 2>/dev/null || echo "index.js")
	
	if [ ! -f "$project_dir/$main_script" ]; then
		# Try common entry points
		for f in "index.js" "main.js" "app.js" "server.js" "src/index.js" "src/main.js"; do
			if [ -f "$project_dir/$f" ]; then
				main_script="$f"
				break
			fi
		done
	fi
	
	local script_path="$project_dir/$main_script"
	if [ ! -f "$script_path" ]; then
		error "No entry point found in $project_dir"
	fi
	
	log "Creating Node inspect session: $session_name"
	log "Project: $project_dir"
	log "Entry: $main_script"
	
	# Build command
	local node_cmd="cd $project_dir && node inspect $main_script"
	[ -n "$script_args" ] && node_cmd="$node_cmd $script_args"
	
	session_create "$session_name" "$node_cmd"
	sleep 1
	
	echo "SESSION_NAME=$session_name"
	echo "SCRIPT_PATH=$script_path"
}

# ============================================================================
# Breakpoint Management
# ============================================================================

# Set breakpoint
# Usage: node_set_breakpoint <session> <location>
# location: filename:lineno or function_name
node_set_breakpoint() {
	local session_name="$1"
	local location="$2"
	
	session_send "$session_name" "sb($location)"
	session_poll "$session_name" 5 0.5 "$NODE_PROMPT"
}

# Set conditional breakpoint
# Usage: node_set_conditional_breakpoint <session> <location> <condition>
node_set_conditional_breakpoint() {
	local session_name="$1"
	local location="$2"
	local condition="$3"
	
	# Node's inspect supports conditions in sb() with condition as second arg
	session_send "$session_name" "sb('$location', $condition)"
	session_poll "$session_name" 5 0.5 "$NODE_PROMPT"
}

# Clear breakpoint
# Usage: node_clear_breakpoint <session> [bp_id]
node_clear_breakpoint() {
	local session_name="$1"
	local bp_id="${2:-}"
	
	if [ -n "$bp_id" ]; then
		session_send "$session_name" "cb($bp_id)"
	else
		session_send "$session_name" "clearBreakpoints()"
	fi
	session_poll "$session_name" 5 0.5 "$NODE_PROMPT"
}

# List breakpoints
# Usage: node_list_breakpoints <session>
node_list_breakpoints() {
	local session_name="$1"
	
	session_send "$session_name" "breakpoints"
	session_poll "$session_name" 5 0.5 "$NODE_PROMPT"
}

# ============================================================================
# Execution Control
# ============================================================================

# Run program
# Usage: node_run <session>
node_run() {
	local session_name="$1"
	
	session_send "$session_name" "c"
	session_poll "$session_name" 30 0.5 "$NODE_PROMPT"
}

# Step into function
# Usage: node_step <session>
node_step() {
	local session_name="$1"
	
	session_send "$session_name" "step"
	session_poll "$session_name" 5 0.5 "$NODE_PROMPT"
}

# Step over (don't enter function)
# Usage: node_next <session>
node_next() {
	local session_name="$1"
	
	session_send "$session_name" "n"
	session_poll "$session_name" 5 0.5 "$NODE_PROMPT"
}

# Continue execution
# Usage: node_continue <session>
node_continue() {
	local session_name="$1"
	
	session_send "$session_name" "c"
	session_poll "$session_name" 30 0.5 "$NODE_PROMPT"
}

# Step out of current function
# Usage: node_stepout <session>
node_stepout() {
	local session_name="$1"
	
	session_send "$session_name" "out"
	session_poll "$session_name" 10 0.5 "$NODE_PROMPT"
}

# Pause execution
# Usage: node_pause <session>
node_pause() {
	local session_name="$1"
	
	session_send "$session_name" "pause"
	session_poll "$session_name" 5 0.5 "$NODE_PROMPT"
}

# Quit debugging
# Usage: node_quit <session>
node_quit() {
	local session_name="$1"
	
	session_send "$session_name" "exit"
	sleep 0.5
}

# ============================================================================
# Variable Inspection
# ============================================================================

# Print expression
# Usage: node_print <session> <expression>
node_print() {
	local session_name="$1"
	local expression="$2"
	
	# Use repl to evaluate expression
	session_send "$session_name" "repl"
	sleep 0.3
	session_send "$session_name" "$expression"
	sleep 0.5
	session_send "$session_name" ""  # Empty line to exit repl
	session_poll "$session_name" 5 0.5 "$NODE_PROMPT"
}

# List local variables
# Usage: node_locals <session>
node_locals() {
	local session_name="$1"
	
	# Use repl to get local variables
	session_send "$session_name" "repl"
	sleep 0.3
	session_send "$session_name" "this"
	sleep 0.5
	session_send "$session_name" ""  # Exit repl
	session_poll "$session_name" 5 0.5 "$NODE_PROMPT"
}

# Watch expression
# Usage: node_watch <session> <expression>
node_watch() {
	local session_name="$1"
	local expression="$2"
	
	session_send "$session_name" "watch('$expression')"
	session_poll "$session_name" 5 0.5 "$NODE_PROMPT"
}

# List watchers
# Usage: node_watchers <session>
node_watchers() {
	local session_name="$1"
	
	session_send "$session_name" "watchers"
	session_poll "$session_name" 5 0.5 "$NODE_PROMPT"
}

# ============================================================================
# Call Stack
# ============================================================================

# Print call stack (backtrace)
# Usage: node_backtrace <session>
node_backtrace() {
	local session_name="$1"
	
	session_send "$session_name" "bt"
	session_poll "$session_name" 5 0.5 "$NODE_PROMPT"
}

# Move up call stack
# Usage: node_up <session>
node_up() {
	local session_name="$1"
	
	session_send "$session_name" "up"
	session_poll "$session_name" 5 0.5 "$NODE_PROMPT"
}

# Move down call stack
# Usage: node_down <session>
node_down() {
	local session_name="$1"
	
	session_send "$session_name" "down"
	session_poll "$session_name" 5 0.5 "$NODE_PROMPT"
}

# Set frame
# Usage: node_set_frame <session> <frame_num>
node_set_frame() {
	local session_name="$1"
	local frame_num="$2"
	
	session_send "$session_name" "frame $frame_num"
	session_poll "$session_name" 5 0.5 "$NODE_PROMPT"
}

# ============================================================================
# Source Code
# ============================================================================

# List source code
# Usage: node_list <session> [lines]
node_list() {
	local session_name="$1"
	local lines="${2:-5}"
	
	session_send "$session_name" "list($lines)"
	session_poll "$session_name" 5 0.5 "$NODE_PROMPT"
}

# ============================================================================
# Quick Start
# ============================================================================

# Quick start Node.js debugging
# Usage: node_quick_start <project_dir> [script]
node_quick_start() {
	local project_dir="$1"
	local script="${2:-}"
	
	# Verify Node project
	if [ ! -f "$project_dir/package.json" ]; then
		error "Node project not found: $project_dir/package.json"
	fi
	
	# Generate session name
	local session_name="node_$(basename "$project_dir")_$$"
	
	# Find entry point if not specified
	if [ -n "$script" ]; then
		local script_path="$project_dir/$script"
	else
		local main_script=$(cd "$project_dir" && node -e "
			const pkg = require('./package.json');
			console.log(pkg.main || 'index.js');
		" 2>/dev/null || echo "index.js")
		
		local script_path="$project_dir/$main_script"
		script="$main_script"
	fi
	
	if [ ! -f "$script_path" ]; then
		error "Script not found: $script_path"
	fi
	
	# Create session
	create_node_session_project "$session_name" "$project_dir"
	
	echo ""
	echo "========================================"
	echo "Node Session Ready"
	echo "========================================"
	echo "Session: $session_name"
	echo "Project: $project_dir"
	echo "Entry: $script"
	echo ""
	echo "Commands:"
	echo "  $SCRIPT_DIR/node_session.sh bp $session_name app.js:10"
	echo "  $SCRIPT_DIR/node_session.sh cont $session_name"
	echo "  $SCRIPT_DIR/node_session.sh next $session_name"
	echo "  $SCRIPT_DIR/node_session.sh print $session_name \"myVar\""
	echo "========================================"
}

# ============================================================================
# Main Entry Point
# ============================================================================

show_usage() {
	cat << EOF
Node Session Manager - Node.js debugger session management

Usage:
 $0 <command> [arguments...]

Commands:
 # Session management
 create <session> <script.js> [args]
 Create node inspect session
 Example: $0 create mysession app.js
 
 create-project <session> <project_dir> [args]
 Create node inspect session from project
 Example: $0 create-project mysession /path/to/project
 
 quick-start <project_dir> [script]
 Quick start (auto-detect entry point)
 
 # Breakpoints
 bp <session> <file:line|func>
 Set breakpoint
 Example: $0 bp mysession app.js:20
 Example: $0 bp mysession myFunction
 
 bp-cond <session> <location> <condition>
 Set conditional breakpoint
 Example: $0 bp-cond mysession app.js:20 "i > 5"
 
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
 
 pause <session>
 Pause execution
 
 # Variables
 print <session> <expression>
 Print expression
 Example: $0 print mysession myVar
 Example: $0 print mysession myArray[0]
 
 locals <session>
 List local variables (shows 'this')
 
 watch <session> <expression>
 Watch expression (auto-eval on each stop)
 
 watchers <session>
 List all watchers
 
 # Call stack
 bt <session>
 Print call stack (backtrace)
 
 up <session>
 Move up call stack
 
 down <session>
 Move down call stack
 
 frame <session> <num>
 Set current frame
 
 # Source
 list <session> [lines]
 List source code around current line
 
 # Session management
 kill <session>
 Terminate session
 
 cleanup
 Clean up all node sessions

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
		[ $# -lt 2 ] && error "Usage: $0 create <session> <script.js> [args]"
		create_node_session "$1" "$2" "${3:-}"
		;;
	create-project)
		[ $# -lt 2 ] && error "Usage: $0 create-project <session> <project_dir> [args]"
		create_node_session_project "$1" "$2" "${3:-}"
		;;
	quick-start)
		[ $# -lt 1 ] && error "Usage: $0 quick-start <project_dir> [script]"
		node_quick_start "$1" "${2:-}"
		;;
	bp)
		[ $# -lt 2 ] && error "Usage: $0 bp <session> <location>"
		node_set_breakpoint "$1" "$2"
		;;
	bp-cond)
		[ $# -lt 3 ] && error "Usage: $0 bp-cond <session> <location> <condition>"
		node_set_conditional_breakpoint "$1" "$2" "$3"
		;;
	bp-list)
		[ $# -lt 1 ] && error "Usage: $0 bp-list <session>"
		node_list_breakpoints "$1"
		;;
	bp-clear)
		[ $# -lt 1 ] && error "Usage: $0 bp-clear <session> [bp_id]"
		node_clear_breakpoint "$1" "${2:-}"
		;;
	run)
		[ $# -lt 1 ] && error "Usage: $0 run <session>"
		node_run "$1"
		;;
	step)
		[ $# -lt 1 ] && error "Usage: $0 step <session>"
		node_step "$1"
		;;
	next)
		[ $# -lt 1 ] && error "Usage: $0 next <session>"
		node_next "$1"
		;;
	cont|continue)
		[ $# -lt 1 ] && error "Usage: $0 cont <session>"
		node_continue "$1"
		;;
	stepout)
		[ $# -lt 1 ] && error "Usage: $0 stepout <session>"
		node_stepout "$1"
		;;
	pause)
		[ $# -lt 1 ] && error "Usage: $0 pause <session>"
		node_pause "$1"
		;;
	print)
		[ $# -lt 2 ] && error "Usage: $0 print <session> <expression>"
		node_print "$1" "$2"
		;;
	locals)
		[ $# -lt 1 ] && error "Usage: $0 locals <session>"
		node_locals "$1"
		;;
	watch)
		[ $# -lt 2 ] && error "Usage: $0 watch <session> <expression>"
		node_watch "$1" "$2"
		;;
	watchers)
		[ $# -lt 1 ] && error "Usage: $0 watchers <session>"
		node_watchers "$1"
		;;
	bt|backtrace)
		[ $# -lt 1 ] && error "Usage: $0 bt <session>"
		node_backtrace "$1"
		;;
	up)
		[ $# -lt 1 ] && error "Usage: $0 up <session>"
		node_up "$1"
		;;
	down)
		[ $# -lt 1 ] && error "Usage: $0 down <session>"
		node_down "$1"
		;;
	frame)
		[ $# -lt 2 ] && error "Usage: $0 frame <session> <num>"
		node_set_frame "$1" "$2"
		;;
	list)
		[ $# -lt 1 ] && error "Usage: $0 list <session> [lines]"
		node_list "$1" "${2:-}"
		;;
	kill)
		[ $# -lt 1 ] && error "Usage: $0 kill <session>"
		session_kill "$1"
		;;
	cleanup)
		session_cleanup "node_"
		;;
	*)
		error "Unknown command: $command"
		;;
esac
