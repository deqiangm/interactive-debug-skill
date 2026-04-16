#!/bin/bash
# ============================================================================
# JDB Expression Evaluation - Advanced expression evaluation during JDB debugging
# 
# Features:
# - Evaluate complex Java expressions
# - Support method invocation
# - Array and collection operations
# - Type casting and instanceof checks
# - Expression history and templates
# - Batch expression evaluation
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../common/functions.sh"

# ============================================================================
# Configuration
# ============================================================================

# Default settings
readonly DEFAULT_EVAL_TIMEOUT=10
readonly MAX_EXPRESSION_LENGTH=500
readonly MAX_HISTORY_SIZE=50

# State directory for expression history
EVAL_STATE_DIR="/tmp/jdb_eval_states"

# ============================================================================
# Initialization
# ============================================================================

# Ensure state directory exists
ensure_eval_state_dir() {
    mkdir -p "$EVAL_STATE_DIR"
}

# ============================================================================
# Expression Evaluation Functions
# ============================================================================

# Evaluate a simple expression
# Usage: eval_expression <session> <expression>
eval_expression() {
    local session_name="$1"
    local expression="$2"
    
    # Validate expression length
    if [ ${#expression} -gt $MAX_EXPRESSION_LENGTH ]; then
        log_error "Expression too long (max $MAX_EXPRESSION_LENGTH chars)"
        return 1
    fi
    
    log "Evaluating: $expression"
    
    # Execute eval command
    local output=$(session_exec_poll "$session_name" "eval $expression" $DEFAULT_EVAL_TIMEOUT 1)
    
    echo "$output"
    
    # Save to history
    save_expression_history "$session_name" "$expression" "$output"
    
    return 0
}

# Evaluate with formatting
# Usage: eval_formatted <session> <expression> [format]
eval_formatted() {
    local session_name="$1"
    local expression="$2"
    local format="${3:-default}"
    
    local output=$(eval_expression "$session_name" "$expression")
    local result=$(parse_eval_result "$output")
    
    case "$format" in
        json)
            echo "{\"expression\": \"$expression\", \"result\": \"$result\", \"timestamp\": \"$(date -Iseconds)\"}"
            ;;
        table)
            printf "%-40s | %s\n" "EXPRESSION" "RESULT"
            printf "%-40s | %s\n" "$expression" "$result"
            ;;
        default|*)
            echo "Expression: $expression"
            echo "Result: $result"
            ;;
    esac
    
    return 0
}

# ============================================================================
# Method Invocation
# ============================================================================

# Invoke a method and capture result
# Usage: invoke_method <session> <object_ref> <method> [args...]
invoke_method() {
    local session_name="$1"
    local object_ref="$2"
    local method="$3"
    shift 3
    local args="$*"
    
    local expression="${object_ref}.${method}()"
    [ -n "$args" ] && expression="${object_ref}.${method}($args)"
    
    log "Invoking method: $expression"
    
    # Use print for method invocation
    local output=$(session_exec_poll "$session_name" "print $expression" $DEFAULT_EVAL_TIMEOUT 1)
    
    echo "$output"
    
    # Save to history
    save_expression_history "$session_name" "$expression" "$output"
    
    return 0
}

# Invoke static method
# Usage: invoke_static <session> <class> <method> [args...]
invoke_static() {
    local session_name="$1"
    local class_name="$2"
    local method="$3"
    shift 3
    local args="$*"
    
    local expression="${class_name}.${method}()"
    [ -n "$args" ] && expression="${class_name}.${method}($args)"
    
    log "Invoking static method: $expression"
    
    local output=$(session_exec_poll "$session_name" "print $expression" $DEFAULT_EVAL_TIMEOUT 1)
    
    echo "$output"
    save_expression_history "$session_name" "$expression" "$output"
    
    return 0
}

# ============================================================================
# Array Operations
# ============================================================================

# Get array length
# Usage: eval_array_length <session> <array_ref>
eval_array_length() {
    local session_name="$1"
    local array_ref="$2"
    
    local expression="${array_ref}.length"
    
    log "Getting array length: $array_ref"
    
    local output=$(session_exec_poll "$session_name" "print $expression" $DEFAULT_EVAL_TIMEOUT 1)
    
    echo "$output"
    
    return 0
}

# Get array element
# Usage: eval_array_element <session> <array_ref> <index>
eval_array_element() {
    local session_name="$1"
    local array_ref="$2"
    local index="$3"
    
    local expression="${array_ref}[$index]"
    
    log "Getting array element: $array_ref[$index]"
    
    local output=$(session_exec_poll "$session_name" "print $expression" $DEFAULT_EVAL_TIMEOUT 1)
    
    echo "$output"
    
    return 0
}

# Dump array range
# Usage: eval_array_range <session> <array_ref> [start] [end]
eval_array_range() {
    local session_name="$1"
    local array_ref="$2"
    local start="${3:-0}"
    local end="${4:-}"
    
    log "Dumping array range: $array_ref[$start..${end:-end}]"
    
    # First get length
    local len_output=$(session_exec_poll "$session_name" "print ${array_ref}.length" $DEFAULT_EVAL_TIMEOUT 1)
    local length=$(parse_eval_result "$len_output")
    
    if [ -z "$end" ] || [ "$end" -gt "$length" ]; then
        end=$length
    fi
    
    echo "Array: $array_ref (length: $length)"
    echo "---"
    
    local i=$start
    while [ $i -lt $end ]; do
        local output=$(session_exec_poll "$session_name" "print ${array_ref}[$i]" $DEFAULT_EVAL_TIMEOUT 0.5)
        local value=$(parse_eval_result "$output")
        printf "  [%3d] = %s\n" "$i" "$value"
        i=$((i + 1))
    done
    
    return 0
}

# ============================================================================
# Object Inspection
# ============================================================================

# Check instanceof
# Usage: eval_instanceof <session> <object_ref> <class>
eval_instanceof() {
    local session_name="$1"
    local object_ref="$2"
    local class_name="$3"
    
    # JDB doesn't directly support instanceof, we need to check class
    log "Checking instanceof: $object_ref instanceof $class_name"
    
    local output=$(session_exec_poll "$session_name" "print $object_ref.getClass().getName()" $DEFAULT_EVAL_TIMEOUT 1)
    local actual_class=$(parse_eval_result "$output")
    
    # Simple check - exact match or contains
    if [[ "$actual_class" == *"$class_name"* ]]; then
        echo "true ($object_ref is instance of $class_name)"
        echo "Actual class: $actual_class"
    else
        echo "false ($object_ref is NOT instance of $class_name)"
        echo "Actual class: $actual_class"
    fi
    
    return 0
}

# Get object class
# Usage: eval_get_class <session> <object_ref>
eval_get_class() {
    local session_name="$1"
    local object_ref="$2"
    
    log "Getting class of: $object_ref"
    
    local output=$(session_exec_poll "$session_name" "print $object_ref.getClass().getName()" $DEFAULT_EVAL_TIMEOUT 1)
    
    echo "$output"
    
    return 0
}

# Get object hashCode
# Usage: eval_hashcode <session> <object_ref>
eval_hashcode() {
    local session_name="$1"
    local object_ref="$2"
    
    log "Getting hashCode of: $object_ref"
    
    local output=$(session_exec_poll "$session_name" "print $object_ref.hashCode()" $DEFAULT_EVAL_TIMEOUT 1)
    
    echo "$output"
    
    return 0
}

# Get object toString
# Usage: eval_tostring <session> <object_ref>
eval_tostring() {
    local session_name="$1"
    local object_ref="$2"
    
    log "Getting toString of: $object_ref"
    
    local output=$(session_exec_poll "$session_name" "print $object_ref.toString()" $DEFAULT_EVAL_TIMEOUT 1)
    
    echo "$output"
    
    return 0
}

# ============================================================================
# Type Casting
# ============================================================================

# Cast expression to type
# Usage: eval_cast <session> <type> <expression>
eval_cast() {
    local session_name="$1"
    local type="$2"
    local expression="$3"
    
    local cast_expr="(($type)$expression)"
    
    log "Casting: ($type)$expression"
    
    local output=$(session_exec_poll "$session_name" "print $cast_expr" $DEFAULT_EVAL_TIMEOUT 1)
    
    echo "$output"
    
    return 0
}

# ============================================================================
# Collection Operations
# ============================================================================

# Get collection size
# Usage: eval_collection_size <session> <collection_ref>
eval_collection_size() {
    local session_name="$1"
    local collection_ref="$2"
    
    log "Getting collection size: $collection_ref"
    
    local output=$(session_exec_poll "$session_name" "print $collection_ref.size()" $DEFAULT_EVAL_TIMEOUT 1)
    
    echo "$output"
    
    return 0
}

# Check if collection is empty
# Usage: eval_is_empty <session> <collection_ref>
eval_is_empty() {
    local session_name="$1"
    local collection_ref="$2"
    
    log "Checking if empty: $collection_ref"
    
    local output=$(session_exec_poll "$session_name" "print $collection_ref.isEmpty()" $DEFAULT_EVAL_TIMEOUT 1)
    
    echo "$output"
    
    return 0
}

# Get list element
# Usage: eval_list_get <session> <list_ref> <index>
eval_list_get() {
    local session_name="$1"
    local list_ref="$2"
    local index="$3"
    
    log "Getting list element: $list_ref.get($index)"
    
    local output=$(session_exec_poll "$session_name" "print $list_ref.get($index)" $DEFAULT_EVAL_TIMEOUT 1)
    
    echo "$output"
    
    return 0
}

# Check if map contains key
# Usage: eval_map_contains_key <session> <map_ref> <key>
eval_map_contains_key() {
    local session_name="$1"
    local map_ref="$2"
    local key="$3"
    
    log "Checking map contains key: $map_ref.containsKey($key)"
    
    local output=$(session_exec_poll "$session_name" "print $map_ref.containsKey($key)" $DEFAULT_EVAL_TIMEOUT 1)
    
    echo "$output"
    
    return 0
}

# Get map value
# Usage: eval_map_get <session> <map_ref> <key>
eval_map_get() {
    local session_name="$1"
    local map_ref="$2"
    local key="$3"
    
    log "Getting map value: $map_ref.get($key)"
    
    local output=$(session_exec_poll "$session_name" "print $map_ref.get($key)" $DEFAULT_EVAL_TIMEOUT 1)
    
    echo "$output"
    
    return 0
}

# ============================================================================
# String Operations
# ============================================================================

# Get string length
# Usage: eval_string_length <session> <string_ref>
eval_string_length() {
    local session_name="$1"
    local string_ref="$2"
    
    log "Getting string length: $string_ref"
    
    local output=$(session_exec_poll "$session_name" "print $string_ref.length()" $DEFAULT_EVAL_TIMEOUT 1)
    
    echo "$output"
    
    return 0
}

# Get string char at
# Usage: eval_string_char_at <session> <string_ref> <index>
eval_string_char_at() {
    local session_name="$1"
    local string_ref="$2"
    local index="$3"
    
    log "Getting string char at: $string_ref.charAt($index)"
    
    local output=$(session_exec_poll "$session_name" "print $string_ref.charAt($index)" $DEFAULT_EVAL_TIMEOUT 1)
    
    echo "$output"
    
    return 0
}

# Check string equals
# Usage: eval_string_equals <session> <string_ref> <other>
eval_string_equals() {
    local session_name="$1"
    local string_ref="$2"
    local other="$3"
    
    log "Checking string equals: $string_ref.equals($other)"
    
    local output=$(session_exec_poll "$session_name" "print $string_ref.equals($other)" $DEFAULT_EVAL_TIMEOUT 1)
    
    echo "$output"
    
    return 0
}

# ============================================================================
# Mathematical Operations
# ============================================================================

# Evaluate arithmetic expression
# Usage: eval_arithmetic <session> <expression>
eval_arithmetic() {
    local session_name="$1"
    local expression="$2"
    
    log "Evaluating arithmetic: $expression"
    
    local output=$(session_exec_poll "$session_name" "print $expression" $DEFAULT_EVAL_TIMEOUT 1)
    
    echo "$output"
    
    return 0
}

# ============================================================================
# Batch Operations
# ============================================================================

# Evaluate multiple expressions
# Usage: eval_batch <session> <expr1;expr2;expr3>
eval_batch() {
    local session_name="$1"
    local expressions="$2"
    
    IFS=';' read -ra exprs <<< "$expressions"
    
    log "Batch evaluating ${#exprs[@]} expressions"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "=== Batch Evaluation [$timestamp] ==="
    echo "Session: $session_name"
    echo "Expressions: ${#exprs[@]}"
    echo "---"
    
    local idx=1
    for expr in "${exprs[@]}"; do
        expr=$(echo "$expr" | xargs)
        [ -z "$expr" ] && continue
        
        echo "[$idx] $expr"
        
        local output=$(session_exec_poll "$session_name" "print $expr" $DEFAULT_EVAL_TIMEOUT 1)
        local result=$(parse_eval_result "$output")
        
        echo "    => $result"
        
        save_expression_history "$session_name" "$expr" "$output"
        
        idx=$((idx + 1))
    done
    
    echo "---"
    echo "Evaluated: $((idx - 1)) expressions"
    
    return 0
}

# ============================================================================
# Expression History
# ============================================================================

# Save expression to history
# Usage: save_expression_history <session> <expression> <output>
save_expression_history() {
    local session_name="$1"
    local expression="$2"
    local output="$3"
    
    ensure_eval_state_dir
    
    local history_file="$EVAL_STATE_DIR/${session_name}_eval_history.txt"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local result=$(parse_eval_result "$output")
    
    # Append to history
    echo "[$timestamp] $expression => $result" >> "$history_file"
    
    # Trim history if too large
    local lines=$(wc -l < "$history_file" 2>/dev/null || echo "0")
    if [ "$lines" -gt $MAX_HISTORY_SIZE ]; then
        tail -n $MAX_HISTORY_SIZE "$history_file" > "${history_file}.tmp"
        mv "${history_file}.tmp" "$history_file"
    fi
    
    return 0
}

# Show expression history
# Usage: show_expression_history <session> [count]
show_expression_history() {
    local session_name="$1"
    local count="${2:-20}"
    
    ensure_eval_state_dir
    
    local history_file="$EVAL_STATE_DIR/${session_name}_eval_history.txt"
    
    if [ ! -f "$history_file" ]; then
        log_info "No expression history for session: $session_name"
        return 0
    fi
    
    echo "=== Expression History (last $count) ==="
    echo "Session: $session_name"
    echo "---"
    
    tail -n "$count" "$history_file"
    
    return 0
}

# Clear expression history
# Usage: clear_expression_history <session>
clear_expression_history() {
    local session_name="$1"
    
    ensure_eval_state_dir
    
    local history_file="$EVAL_STATE_DIR/${session_name}_eval_history.txt"
    
    if [ -f "$history_file" ]; then
        rm -f "$history_file"
        log "Cleared expression history for session: $session_name"
    fi
    
    return 0
}

# ============================================================================
# Expression Templates
# ============================================================================

# Show available templates
show_expression_templates() {
    echo "=== Expression Templates ==="
    echo ""
    echo "ARRAY OPERATIONS:"
    echo "  {array}.length              - Get array length"
    echo "  {array}[i]                  - Get array element at index i"
    echo ""
    echo "STRING OPERATIONS:"
    echo "  {str}.length()              - Get string length"
    echo "  {str}.charAt(i)             - Get character at index"
    echo "  {str}.equals(obj)           - Check string equality"
    echo "  {str}.substring(start,end)  - Get substring"
    echo "  {str}.toUpperCase()         - Convert to uppercase"
    echo "  {str}.toLowerCase()         - Convert to lowercase"
    echo "  {str}.trim()                - Remove whitespace"
    echo ""
    echo "COLLECTION OPERATIONS:"
    echo "  {collection}.size()        - Get collection size"
    echo "  {collection}.isEmpty()     - Check if empty"
    echo "  {list}.get(i)              - Get list element"
    echo "  {list}.contains(obj)       - Check if contains"
    echo "  {map}.get(key)             - Get map value"
    echo "  {map}.containsKey(key)     - Check if key exists"
    echo "  {map}.keySet()             - Get all keys"
    echo ""
    echo "OBJECT OPERATIONS:"
    echo "  {obj}.getClass()           - Get object class"
    echo "  {obj}.hashCode()           - Get hash code"
    echo "  {obj}.toString()           - Get string representation"
    echo "  {obj} instanceof {Class}   - Type check (requires eval)"
    echo ""
    echo "MATHEMATICAL:"
    echo "  a + b, a - b, a * b, a / b - Basic arithmetic"
    echo "  a % b                       - Modulo"
    echo "  Math.max(a, b)              - Maximum"
    echo "  Math.min(a, b)              - Minimum"
    echo "  Math.abs(a)                 - Absolute value"
    echo ""
    echo "TYPE CASTING:"
    echo "  ((Type)object)              - Cast to type"
    echo ""
    echo "Usage Examples:"
    echo "  ./jdb_expression_eval.sh eval mysession 'arr.length'"
    echo "  ./jdb_expression_eval.sh eval mysession 'list.size()'"
    echo "  ./jdb_expression_eval.sh eval mysession 'str.toUpperCase()'"
    echo ""
    
    return 0
}

# ============================================================================
# Helper Functions
# ============================================================================

# Parse evaluation result from JDB output
parse_eval_result() {
    local output="$1"
    
    # JDB output format: "expression = value" or "value"
    local result=$(echo "$output" | grep -E "^\s*(.*=.*|null|true|false|[0-9]+)$" | tail -1)
    
    # Extract value after = if present
    if [[ "$result" == *"="* ]]; then
        result=$(echo "$result" | sed 's/^[^=]*=\s*//')
    fi
    
    echo "$result"
}

# ============================================================================
# Smart Suggestions
# ============================================================================

# Suggest expressions based on variable type
# Usage: suggest_expressions <session> <variable>
suggest_expressions() {
    local session_name="$1"
    local variable="$2"
    
    echo "=== Expression Suggestions for '$variable' ==="
    echo ""
    
    # Try to get the type
    local type_output=$(session_exec_poll "$session_name" "print $variable.getClass().getName()" $DEFAULT_EVAL_TIMEOUT 1 2>/dev/null || echo "")
    local type=$(parse_eval_result "$type_output")
    
    if [ -z "$type" ] || [[ "$type" == *"null"* ]]; then
        echo "Unable to determine type. The variable may be null."
        echo ""
        echo "Try these common expressions:"
        echo "  $variable"
        echo "  $variable == null"
        return 0
    fi
    
    echo "Detected type: $type"
    echo ""
    echo "Suggested expressions:"
    echo ""
    
    case "$type" in
        *String*)
            echo "String operations:"
            echo "  $variable.length()"
            echo "  $variable.isEmpty()"
            echo "  $variable.charAt(0)"
            echo "  $variable.toUpperCase()"
            echo "  $variable.toLowerCase()"
            echo "  $variable.trim()"
            echo "  $variable.equals(\"other\")"
            echo "  $variable.startsWith(\"prefix\")"
            echo "  $variable.endsWith(\"suffix\")"
            echo "  $variable.contains(\"sub\")"
            ;;
        *List*|*ArrayList*|*LinkedList*)
            echo "List operations:"
            echo "  $variable.size()"
            echo "  $variable.isEmpty()"
            echo "  $variable.get(0)"
            echo "  $variable.contains(obj)"
            echo "  $variable.indexOf(obj)"
            echo "  $variable.iterator()"
            ;;
        *Map*|*HashMap*|*LinkedHashMap*)
            echo "Map operations:"
            echo "  $variable.size()"
            echo "  $variable.isEmpty()"
            echo "  $variable.get(key)"
            echo "  $variable.containsKey(key)"
            echo "  $variable.containsValue(value)"
            echo "  $variable.keySet()"
            echo "  $variable.values()"
            ;;
        *Set*|*HashSet*)
            echo "Set operations:"
            echo "  $variable.size()"
            echo "  $variable.isEmpty()"
            echo "  $variable.contains(obj)"
            echo "  $variable.iterator()"
            ;;
        *Array*)
            echo "Array operations:"
            echo "  $variable.length"
            echo "  $variable[0]"
            echo "  $variable[$variable.length - 1]"
            ;;
        *Integer*|*int*)
            echo "Integer operations:"
            echo "  $variable"
            echo "  $variable + 1"
            echo "  $variable * 2"
            echo "  Math.abs($variable)"
            ;;
        *Double*|*double*|*Float*|*float*)
            echo "Numeric operations:"
            echo "  $variable"
            echo "  Math.round($variable)"
            echo "  Math.floor($variable)"
            echo "  Math.ceil($variable)"
            echo "  Math.abs($variable)"
            ;;
        *)
            echo "Object operations:"
            echo "  $variable"
            echo "  $variable.getClass()"
            echo "  $variable.hashCode()"
            echo "  $variable.toString()"
            echo "  $variable.equals(other)"
            ;;
    esac
    
    return 0
}

# ============================================================================
# Command Line Interface
# ============================================================================

show_help() {
    cat << 'EOF'
JDB Expression Evaluation - Evaluate complex expressions during debugging

USAGE:
    ./jdb_expression_eval.sh <command> [arguments]

COMMANDS:

BASIC EVALUATION:
    eval <session> <expression>              Evaluate an expression
    eval-fmt <session> <expr> [format]       Evaluate with formatting (json/table)
    batch <session> <expr1;expr2;...>        Evaluate multiple expressions

METHOD INVOCATION:
    invoke <session> <object> <method> [args]    Invoke instance method
    invoke-static <session> <class> <method> [args]  Invoke static method

ARRAY OPERATIONS:
    array-len <session> <array>              Get array length
    array-get <session> <array> <index>      Get array element
    array-range <session> <array> [start] [end]  Dump array range

OBJECT INSPECTION:
    class <session> <object>                 Get object class
    hashcode <session> <object>              Get object hashCode
    tostring <session> <object>              Get toString result
    instanceof <session> <object> <class>    Check instanceof

COLLECTION OPERATIONS:
    coll-size <session> <collection>         Get collection size
    coll-empty <session> <collection>        Check if empty
    list-get <session> <list> <index>        Get list element
    map-get <session> <map> <key>            Get map value
    map-contains <session> <map> <key>       Check if map contains key

STRING OPERATIONS:
    str-len <session> <string>               Get string length
    str-char <session> <string> <index>      Get char at index
    str-equals <session> <string> <other>    Check string equality

TYPE OPERATIONS:
    cast <session> <type> <expression>       Cast expression to type

ARITHMETIC:
    calc <session> <expression>              Evaluate arithmetic expression

HISTORY:
    history <session> [count]                Show expression history
    clear-history <session>                  Clear expression history

HELPERS:
    suggest <session> <variable>             Suggest expressions based on type
    templates                                Show expression templates

OPTIONS:
    --help                                   Show this help message

EXAMPLES:
    # Evaluate simple expression
    ./jdb_expression_eval.sh eval mysession 'x + y'
    
    # Get array length
    ./jdb_expression_eval.sh array-len mysession myArray
    
    # Invoke method
    ./jdb_expression_eval.sh invoke mysession obj getName
    
    # Batch evaluation
    ./jdb_expression_eval.sh batch mysession 'x;y;z;arr.length'
    
    # Check instanceof
    ./jdb_expression_eval.sh instanceof mysession obj String
    
    # Get suggestions for variable
    ./jdb_expression_eval.sh suggest mysession myList
    
    # Show expression templates
    ./jdb_expression_eval.sh templates

NOTES:
    - Expression length limited to 500 characters
    - History limited to last 50 expressions per session
    - Use single quotes to escape special characters
    - Complex expressions may require longer evaluation time

WORKFLOW:
    The typical workflow for expression evaluation:
    
    1. Stop at a breakpoint
    2. Evaluate variables: ./jdb_expression_eval.sh eval session 'var'
    3. Check type: ./jdb_expression_eval.sh class session var
    4. Get suggestions: ./jdb_expression_eval.sh suggest session var
    5. Use suggested expressions for deeper inspection

EOF
    return 0
}

# ============================================================================
# Main Entry Point
# ============================================================================

main() {
    ensure_eval_state_dir
    
    # Parse command
    local command="${1:-}"
    shift || true
    
    case "$command" in
        eval)
            [ $# -lt 2 ] && { log_error "Usage: eval <session> <expression>"; return 1; }
            eval_expression "$1" "$2"
            ;;
        eval-fmt)
            [ $# -lt 2 ] && { log_error "Usage: eval-fmt <session> <expression> [format]"; return 1; }
            eval_formatted "$1" "$2" "${3:-default}"
            ;;
        batch)
            [ $# -lt 2 ] && { log_error "Usage: batch <session> <expr1;expr2;...>"; return 1; }
            eval_batch "$1" "$2"
            ;;
        invoke)
            [ $# -lt 3 ] && { log_error "Usage: invoke <session> <object> <method> [args]"; return 1; }
            invoke_method "$1" "$2" "$3" "${4:-}"
            ;;
        invoke-static)
            [ $# -lt 3 ] && { log_error "Usage: invoke-static <session> <class> <method> [args]"; return 1; }
            invoke_static "$1" "$2" "$3" "${4:-}"
            ;;
        array-len)
            [ $# -lt 2 ] && { log_error "Usage: array-len <session> <array>"; return 1; }
            eval_array_length "$1" "$2"
            ;;
        array-get)
            [ $# -lt 3 ] && { log_error "Usage: array-get <session> <array> <index>"; return 1; }
            eval_array_element "$1" "$2" "$3"
            ;;
        array-range)
            [ $# -lt 2 ] && { log_error "Usage: array-range <session> <array> [start] [end]"; return 1; }
            eval_array_range "$1" "$2" "${3:-0}" "${4:-}"
            ;;
        class)
            [ $# -lt 2 ] && { log_error "Usage: class <session> <object>"; return 1; }
            eval_get_class "$1" "$2"
            ;;
        hashcode)
            [ $# -lt 2 ] && { log_error "Usage: hashcode <session> <object>"; return 1; }
            eval_hashcode "$1" "$2"
            ;;
        tostring)
            [ $# -lt 2 ] && { log_error "Usage: tostring <session> <object>"; return 1; }
            eval_tostring "$1" "$2"
            ;;
        instanceof)
            [ $# -lt 3 ] && { log_error "Usage: instanceof <session> <object> <class>"; return 1; }
            eval_instanceof "$1" "$2" "$3"
            ;;
        coll-size)
            [ $# -lt 2 ] && { log_error "Usage: coll-size <session> <collection>"; return 1; }
            eval_collection_size "$1" "$2"
            ;;
        coll-empty)
            [ $# -lt 2 ] && { log_error "Usage: coll-empty <session> <collection>"; return 1; }
            eval_is_empty "$1" "$2"
            ;;
        list-get)
            [ $# -lt 3 ] && { log_error "Usage: list-get <session> <list> <index>"; return 1; }
            eval_list_get "$1" "$2" "$3"
            ;;
        map-get)
            [ $# -lt 3 ] && { log_error "Usage: map-get <session> <map> <key>"; return 1; }
            eval_map_get "$1" "$2" "$3"
            ;;
        map-contains)
            [ $# -lt 3 ] && { log_error "Usage: map-contains <session> <map> <key>"; return 1; }
            eval_map_contains_key "$1" "$2" "$3"
            ;;
        str-len)
            [ $# -lt 2 ] && { log_error "Usage: str-len <session> <string>"; return 1; }
            eval_string_length "$1" "$2"
            ;;
        str-char)
            [ $# -lt 3 ] && { log_error "Usage: str-char <session> <string> <index>"; return 1; }
            eval_string_char_at "$1" "$2" "$3"
            ;;
        str-equals)
            [ $# -lt 3 ] && { log_error "Usage: str-equals <session> <string> <other>"; return 1; }
            eval_string_equals "$1" "$2" "$3"
            ;;
        cast)
            [ $# -lt 3 ] && { log_error "Usage: cast <session> <type> <expression>"; return 1; }
            eval_cast "$1" "$2" "$3"
            ;;
        calc)
            [ $# -lt 2 ] && { log_error "Usage: calc <session> <expression>"; return 1; }
            eval_arithmetic "$1" "$2"
            ;;
        history)
            show_expression_history "$1" "${2:-20}"
            ;;
        clear-history)
            [ $# -lt 1 ] && { log_error "Usage: clear-history <session>"; return 1; }
            clear_expression_history "$1"
            ;;
        suggest)
            [ $# -lt 2 ] && { log_error "Usage: suggest <session> <variable>"; return 1; }
            suggest_expressions "$1" "$2"
            ;;
        templates)
            show_expression_templates
            ;;
        --help|-h|"")
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            echo "Use --help for usage information"
            return 1
            ;;
    esac
    
    return 0
}

# Run main
main "$@"
