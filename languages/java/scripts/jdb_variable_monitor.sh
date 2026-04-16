#!/bin/bash
# ============================================================================
# JDB Variable Monitor - Real-time variable monitoring during JDB debugging
# 
# Features:
# - Monitor single or multiple variables
# - Automatic refresh at configurable intervals
# - Value change detection and alerts
# - Variable history tracking
# - Export monitored values to file
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../common/functions.sh"

# ============================================================================
# Configuration
# ============================================================================

# Default settings
readonly DEFAULT_MONITOR_INTERVAL=2  # seconds between refreshes
readonly DEFAULT_MAX_HISTORY=100      # maximum history entries per variable
readonly MAX_MONITORED_VARS=20        # maximum number of variables to monitor

# State file for persistent monitoring
MONITOR_STATE_DIR="/tmp/jdb_monitor_states"

# ============================================================================
# Initialization
# ============================================================================

# Ensure state directory exists
ensure_state_dir() {
    mkdir -p "$MONITOR_STATE_DIR"
}

# ============================================================================
# Variable Monitoring Functions
# ============================================================================

# Monitor a single variable
# Usage: monitor_variable <session> <variable_name> [class_context]
monitor_variable() {
    local session_name="$1"
    local var_name="$2"
    local class_context="${3:-}"
    
    log "Monitoring variable: $var_name"
    
    # Get current value
    local output=$(session_exec_poll "$session_name" "print $var_name" 5 0.5)
    
    # Parse the value from output
    local value=$(echo "$output" | grep -A1 "$var_name" | tail -1 | sed 's/^[[:space:]]*//' || echo "undefined")
    
    echo "VARIABLE=$var_name"
    echo "VALUE=$value"
    echo "TIMESTAMP=$(date -Iseconds)"
    
    return 0
}

# Monitor multiple variables
# Usage: monitor_multiple <session> <var1,var2,var3,...> [class_context]
monitor_multiple() {
    local session_name="$1"
    local var_list="$2"
    local class_context="${3:-}"
    
    IFS=',' read -ra vars <<< "$var_list"
    
    log "Monitoring ${#vars[@]} variables"
    
    local timestamp=$(date -Iseconds)
    echo "TIMESTAMP=$timestamp"
    echo "---"
    
    for var in "${vars[@]}"; do
        var=$(echo "$var" | xargs)  # trim whitespace
        [ -z "$var" ] && continue
        
        local output=$(session_exec_poll "$session_name" "print $var" 5 0.5)
        local value=$(echo "$output" | grep -A1 "$var" | tail -1 | sed 's/^[[:space:]]*//' || echo "undefined")
        
        echo "$var = $value"
    done
    
    return 0
}

# ============================================================================
# Continuous Monitoring
# ============================================================================

# Start continuous monitoring loop
# Usage: start_continuous_monitor <session> <var_list> [interval] [max_iterations]
start_continuous_monitor() {
    local session_name="$1"
    local var_list="$2"
    local interval="${3:-$DEFAULT_MONITOR_INTERVAL}"
    local max_iterations="${4:-0}"  # 0 = infinite
    
    IFS=',' read -ra vars <<< "$var_list"
    
    log "Starting continuous monitor for ${#vars[@]} variables (interval: ${interval}s)"
    
    local iteration=0
    local prev_values=()
    
    # Initialize previous values array
    for var in "${vars[@]}"; do
        prev_values+=("")
    done
    
    while true; do
        # Check if session still exists
        if ! session_exists "$session_name"; then
            log_warn "Session '$session_name' no longer exists"
            break
        fi
        
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "=== [$timestamp] ==="
        
        local idx=0
        for var in "${vars[@]}"; do
            var=$(echo "$var" | xargs)
            [ -z "$var" ] && continue
            
            local output=$(session_exec_poll "$session_name" "print $var" 5 0.5)
            local value=$(echo "$output" | grep -A1 "$var" | tail -1 | sed 's/^[[:space:]]*//' || echo "undefined")
            
            local prev_val="${prev_values[$idx]}"
            
            # Check for value change
            if [ -n "$prev_val" ] && [ "$value" != "$prev_val" ]; then
                echo -e "${YELLOW}>>> CHANGE DETECTED: $var${NC}"
                echo "    Old: $prev_val"
                echo "    New: $value"
            else
                echo "  $var = $value"
            fi
            
            prev_values[$idx]="$value"
            idx=$((idx + 1))
        done
        
        echo ""
        
        # Check iteration limit
        iteration=$((iteration + 1))
        if [ $max_iterations -gt 0 ] && [ $iteration -ge $max_iterations ]; then
            log "Max iterations ($max_iterations) reached"
            break
        fi
        
        sleep "$interval"
    done
    
    return 0
}

# ============================================================================
# Watch Mode with Change Detection
# ============================================================================

# Watch variables and alert on changes
# Usage: watch_for_changes <session> <var_list> [interval] [timeout]
watch_for_changes() {
    local session_name="$1"
    local var_list="$2"
    local interval="${3:-$DEFAULT_MONITOR_INTERVAL}"
    local timeout="${4:-300}"  # 5 minutes default
    
    IFS=',' read -ra vars <<< "$var_list"
    
    log "Watching for changes (timeout: ${timeout}s)"
    
    local start_time=$(date +%s)
    local prev_values=()
    
    # Initialize previous values
    for var in "${vars[@]}"; do
        local output=$(session_exec_poll "$session_name" "print $var" 5 0.5)
        local value=$(echo "$output" | grep -A1 "$var" | tail -1 | sed 's/^[[:space:]]*//' || echo "undefined")
        prev_values+=("$value")
    done
    
    echo "Initial values:"
    local idx=0
    for var in "${vars[@]}"; do
        echo "  $var = ${prev_values[$idx]}"
        idx=$((idx + 1))
    done
    echo ""
    echo "Watching for changes..."
    
    while true; do
        # Check timeout
        local current_time=$(date +%s)
        if [ $((current_time - start_time)) -ge $timeout ]; then
            log "Watch timeout reached (${timeout}s)"
            return 124
        fi
        
        # Check session
        if ! session_exists "$session_name"; then
            log_warn "Session no longer exists"
            return 1
        fi
        
        sleep "$interval"
        
        # Check for changes
        local idx=0
        for var in "${vars[@]}"; do
            local output=$(session_exec_poll "$session_name" "print $var" 5 0.5)
            local value=$(echo "$output" | grep -A1 "$var" | tail -1 | sed 's/^[[:space:]]*//' || echo "undefined")
            
            if [ "$value" != "${prev_values[$idx]}" ]; then
                local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
                echo ""
                echo -e "${GREEN}[$timestamp] CHANGE DETECTED!${NC}"
                echo "  Variable: $var"
                echo "  Previous: ${prev_values[$idx]}"
                echo "  Current:  $value"
                echo ""
                
                prev_values[$idx]="$value"
                echo "CHANGE_VAR=$var"
                echo "CHANGE_OLD=${prev_values[$idx]}"
                echo "CHANGE_NEW=$value"
                return 0
            fi
            
            idx=$((idx + 1))
        done
        
        # Progress indicator
        printf "."
    done
    
    return 0
}

# ============================================================================
# History Tracking
# ============================================================================

# Track variable history
# Usage: track_history <session> <var_name> <iterations> [interval]
track_history() {
    local session_name="$1"
    local var_name="$2"
    local iterations="${3:-10}"
    local interval="${4:-$DEFAULT_MONITOR_INTERVAL}"
    
    ensure_state_dir
    local history_file="$MONITOR_STATE_DIR/${session_name}_${var_name}_history.txt"
    
    log "Tracking history for '$var_name' ($iterations iterations)"
    
    # Clear existing history
    > "$history_file"
    
    local i=0
    while [ $i -lt $iterations ]; do
        if ! session_exists "$session_name"; then
            log_warn "Session no longer exists"
            break
        fi
        
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local output=$(session_exec_poll "$session_name" "print $var_name" 5 0.5)
        local value=$(echo "$output" | grep -A1 "$var_name" | tail -1 | sed 's/^[[:space:]]*//' || echo "undefined")
        
        echo "[$timestamp] $var_name = $value" >> "$history_file"
        echo "[$i/$iterations] $var_name = $value"
        
        i=$((i + 1))
        
        if [ $i -lt $iterations ]; then
            sleep "$interval"
        fi
    done
    
    log "History saved to: $history_file"
    echo "HISTORY_FILE=$history_file"
    
    return 0
}

# Show variable history
# Usage: show_history <session> <var_name>
show_history() {
    local session_name="$1"
    local var_name="$2"
    
    ensure_state_dir
    local history_file="$MONITOR_STATE_DIR/${session_name}_${var_name}_history.txt"
    
    if [ ! -f "$history_file" ]; then
        log_warn "No history found for '$var_name' in session '$session_name'"
        return 1
    fi
    
    log "History for '$var_name':"
    echo "---"
    cat "$history_file"
    echo "---"
    
    return 0
}

# ============================================================================
# Object Inspection
# ============================================================================

# Inspect object fields
# Usage: inspect_object <session> <object_ref> [depth]
inspect_object() {
    local session_name="$1"
    local object_ref="$2"
    local depth="${3:-1}"
    
    log "Inspecting object: $object_ref (depth: $depth)"
    
    # Use 'dump' command to get object details
    local output=$(session_exec_poll "$session_name" "dump $object_ref" 5 0.5)
    
    echo "Object: $object_ref"
    echo "---"
    
    # Parse and display fields
    echo "$output" | grep -E "^\s+[a-zA-Z_][a-zA-Z0-9_]*\s*:" | while read line; do
        local field=$(echo "$line" | awk '{print $1}' | tr -d ':')
        local value=$(echo "$line" | cut -d':' -f2- | sed 's/^[[:space:]]*//')
        echo "  $field = $value"
    done
    
    return 0
}

# Monitor object field changes
# Usage: monitor_object_fields <session> <object_ref> <field_list> [interval]
monitor_object_fields() {
    local session_name="$1"
    local object_ref="$2"
    local field_list="$3"
    local interval="${4:-$DEFAULT_MONITOR_INTERVAL}"
    
    IFS=',' read -ra fields <<< "$field_list"
    
    log "Monitoring ${#fields[@]} fields of $object_ref"
    
    while true; do
        if ! session_exists "$session_name"; then
            log_warn "Session no longer exists"
            break
        fi
        
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "=== [$timestamp] ==="
        
        for field in "${fields[@]}"; do
            field=$(echo "$field" | xargs)
            [ -z "$field" ] && continue
            
            local full_ref="${object_ref}.${field}"
            local output=$(session_exec_poll "$session_name" "print $full_ref" 5 0.5)
            local value=$(echo "$output" | grep -A1 "$full_ref" | tail -1 | sed 's/^[[:space:]]*//' || echo "undefined")
            
            echo "  $field = $value"
        done
        
        echo ""
        sleep "$interval"
    done
    
    return 0
}

# ============================================================================
# Array Monitoring
# ============================================================================

# Monitor array elements
# Usage: monitor_array <session> <array_name> [start_idx] [end_idx] [interval]
monitor_array() {
    local session_name="$1"
    local array_name="$2"
    local start_idx="${3:-0}"
    local end_idx="${4:--1}"  # -1 = all elements
    local interval="${5:-$DEFAULT_MONITOR_INTERVAL}"
    
    log "Monitoring array: $array_name"
    
    # First get array length
    local len_output=$(session_exec_poll "$session_name" "print ${array_name}.length" 5 0.5)
    local array_len=$(echo "$len_output" | grep -oE '[0-9]+' | tail -1)
    
    if [ -z "$array_len" ]; then
        log_warn "Could not determine array length"
        array_len=0
    fi
    
    echo "Array: $array_name (length: $array_len)"
    
    # Adjust end index if -1
    if [ "$end_idx" -eq -1 ] || [ "$end_idx" -ge "$array_len" ]; then
        end_idx=$((array_len - 1))
    fi
    
    echo "Monitoring indices $start_idx to $end_idx"
    echo "---"
    
    local i=$start_idx
    while [ $i -le $end_idx ]; do
        local output=$(session_exec_poll "$session_name" "print ${array_name}[$i]" 5 0.5)
        local value=$(echo "$output" | grep -A1 "\[$i\]" | tail -1 | sed 's/^[[:space:]]*//' || echo "undefined")
        
        echo "  [$i] = $value"
        i=$((i + 1))
    done
    
    return 0
}

# ============================================================================
# Export Functions
# ============================================================================

# Export monitored values to file
# Usage: export_values <session> <var_list> <output_file>
export_values() {
    local session_name="$1"
    local var_list="$2"
    local output_file="$3"
    
    ensure_state_dir
    
    IFS=',' read -ra vars <<< "$var_list"
    
    log "Exporting ${#vars[@]} variables to $output_file"
    
    # Create output with timestamp
    {
        echo "# JDB Variable Export"
        echo "# Session: $session_name"
        echo "# Timestamp: $(date -Iseconds)"
        echo ""
        
        for var in "${vars[@]}"; do
            var=$(echo "$var" | xargs)
            [ -z "$var" ] && continue
            
            local output=$(session_exec_poll "$session_name" "print $var" 5 0.5)
            local value=$(echo "$output" | grep -A1 "$var" | tail -1 | sed 's/^[[:space:]]*//' || echo "undefined")
            
            echo "$var=$value"
        done
    } > "$output_file"
    
    log "Values exported to: $output_file"
    echo "EXPORT_FILE=$output_file"
    
    return 0
}

# ============================================================================
# Monitoring Profiles
# ============================================================================

# Save monitoring profile
# Usage: save_profile <session> <profile_name> <var_list>
save_profile() {
    local session_name="$1"
    local profile_name="$2"
    local var_list="$3"
    
    ensure_state_dir
    local profile_file="$MONITOR_STATE_DIR/profile_${profile_name}.conf"
    
    log "Saving profile '$profile_name'"
    
    cat > "$profile_file" << EOF
# Monitoring Profile: $profile_name
# Created: $(date -Iseconds)
VARIABLES=$var_list
SESSION=$session_name
EOF
    
    log "Profile saved to: $profile_file"
    echo "PROFILE_FILE=$profile_file"
    
    return 0
}

# Load monitoring profile
# Usage: load_profile <session> <profile_name>
load_profile() {
    local session_name="$1"
    local profile_name="$2"
    
    ensure_state_dir
    local profile_file="$MONITOR_STATE_DIR/profile_${profile_name}.conf"
    
    if [ ! -f "$profile_file" ]; then
        log_warn "Profile '$profile_name' not found"
        return 1
    fi
    
    source "$profile_file"
    
    log "Loaded profile '$profile_name'"
    echo "VARIABLES=$VARIABLES"
    
    return 0
}

# List available profiles
# Usage: list_profiles
list_profiles() {
    ensure_state_dir
    
    log "Available monitoring profiles:"
    
    local count=0
    for profile in "$MONITOR_STATE_DIR"/profile_*.conf; do
        [ -e "$profile" ] || continue
        local name=$(basename "$profile" | sed 's/profile_//;s/\.conf$//')
        echo "  - $name"
        count=$((count + 1))
    done
    
    if [ $count -eq 0 ]; then
        echo "  (no profiles saved)"
    fi
    
    return 0
}

# ============================================================================
# Help
# ============================================================================

show_usage() {
    cat << EOF
JDB Variable Monitor - Real-time variable monitoring during JDB debugging

Usage:
  $0 <command> [arguments...]

Commands:
  # Single/Multi Variable Monitoring
  single <session> <var_name> [class]
    Monitor a single variable
    Example: $0 single mysession i
  
  multi <session> <var1,var2,...> [class]
    Monitor multiple variables (comma-separated)
    Example: $0 multi mysession "i,j,arr"
  
  # Continuous Monitoring
  continuous <session> <var_list> [interval] [max_iter]
    Continuously monitor variables with auto-refresh
    Example: $0 continuous mysession "i,j" 2 100
    Example: $0 continuous mysession "i" 1 0  # infinite
  
  # Change Detection
  watch <session> <var_list> [interval] [timeout]
    Watch for value changes with alerts
    Example: $0 watch mysession "i,j" 1 300
  
  # History Tracking
  history <session> <var_name> <iterations> [interval]
    Track variable value history
    Example: $0 history mysession i 10 1
  
  show-history <session> <var_name>
    Show recorded history for a variable
    Example: $0 show-history mysession i
  
  # Object Inspection
  inspect <session> <object_ref> [depth]
    Inspect object fields and values
    Example: $0 inspect mysession this
    Example: $0 inspect mysession arr 2
  
  object-fields <session> <object_ref> <field_list> [interval]
    Monitor specific object fields
    Example: $0 object-fields mysession this "name,value,count"
  
  # Array Monitoring
  array <session> <array_name> [start] [end]
    Monitor array elements
    Example: $0 array mysession arr 0 5
    Example: $0 array mysession arr 0 -1  # all elements
  
  # Export/Profiles
  export <session> <var_list> <output_file>
    Export current values to file
    Example: $0 export mysession "i,j" /tmp/values.txt
  
  save-profile <session> <profile_name> <var_list>
    Save a monitoring profile
    Example: $0 save-profile mysession loop_debug "i,j,k"
  
  load-profile <session> <profile_name>
    Load and display a saved profile
    Example: $0 load-profile mysession loop_debug
  
  list-profiles
    List all saved monitoring profiles

Options:
  -h, --help    Show this help message
  -v, --verbose Enable verbose output

Environment Variables:
  LOG_LEVEL      Log level (DEBUG, INFO, WARN, ERROR)

Examples:
  # Monitor loop counter
  $0 single mysession i
  
  # Continuous monitoring with 1-second interval
  $0 continuous mysession "i,j" 1 0
  
  # Watch for changes in array index
  $0 watch mysession "arr[0],arr[1]" 2 60
  
  # Track first 20 iterations of loop
  $0 history mysession i 20 1
  
  # Monitor object fields
  $0 object-fields mysession node "data,next,prev"

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
    single|var)
        [ $# -lt 2 ] && error "Usage: $0 single <session> <var_name> [class]"
        monitor_variable "$1" "$2" "${3:-}"
        ;;
    multi|vars)
        [ $# -lt 2 ] && error "Usage: $0 multi <session> <var1,var2,...> [class]"
        monitor_multiple "$1" "$2" "${3:-}"
        ;;
    continuous|cont)
        [ $# -lt 2 ] && error "Usage: $0 continuous <session> <var_list> [interval] [max_iter]"
        start_continuous_monitor "$1" "$2" "${3:-$DEFAULT_MONITOR_INTERVAL}" "${4:-0}"
        ;;
    watch)
        [ $# -lt 2 ] && error "Usage: $0 watch <session> <var_list> [interval] [timeout]"
        watch_for_changes "$1" "$2" "${3:-$DEFAULT_MONITOR_INTERVAL}" "${4:-300}"
        ;;
    history|track)
        [ $# -lt 3 ] && error "Usage: $0 history <session> <var_name> <iterations> [interval]"
        track_history "$1" "$2" "$3" "${4:-$DEFAULT_MONITOR_INTERVAL}"
        ;;
    show-history)
        [ $# -lt 2 ] && error "Usage: $0 show-history <session> <var_name>"
        show_history "$1" "$2"
        ;;
    inspect|dump)
        [ $# -lt 2 ] && error "Usage: $0 inspect <session> <object_ref> [depth]"
        inspect_object "$1" "$2" "${3:-1}"
        ;;
    object-fields|obj)
        [ $# -lt 3 ] && error "Usage: $0 object-fields <session> <object_ref> <field_list> [interval]"
        monitor_object_fields "$1" "$2" "$3" "${4:-$DEFAULT_MONITOR_INTERVAL}"
        ;;
    array|arr)
        [ $# -lt 2 ] && error "Usage: $0 array <session> <array_name> [start] [end]"
        monitor_array "$1" "$2" "${3:-0}" "${4:--1}"
        ;;
    export)
        [ $# -lt 3 ] && error "Usage: $0 export <session> <var_list> <output_file>"
        export_values "$1" "$2" "$3"
        ;;
    save-profile|save)
        [ $# -lt 3 ] && error "Usage: $0 save-profile <session> <profile_name> <var_list>"
        save_profile "$1" "$2" "$3"
        ;;
    load-profile|load)
        [ $# -lt 2 ] && error "Usage: $0 load-profile <session> <profile_name>"
        load_profile "$1" "$2"
        ;;
    list-profiles|profiles)
        list_profiles
        ;;
    -h|--help)
        show_usage
        exit 0
        ;;
    *)
        error "Unknown command: $command. Use --help for usage."
        ;;
esac
