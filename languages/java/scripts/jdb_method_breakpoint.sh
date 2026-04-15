#!/bin/bash
# ============================================================================
# JDB Method Breakpoint - 方法断点支持 (stop in Class.method)
# 
# 功能:
# 1. 设置方法断点 (stop in Class.method)
# 2. 支持方法重载（指定参数类型）
# 3. 方法断点列表管理
# 4. 方法断点命中通知和调用栈显示
# 
# JDB命令参考:
# - stop in <class>.<method>         在方法入口处停止（无参数重载版本）
# - stop in <class>.<method>(params) 在指定参数类型的方法入口处停止
# - clear <class>.<method>           清除方法断点
# - clear                            列出所有断点
# 
# 与行断点的区别:
# - 方法断点在方法入口处停止，不需要知道具体行号
# - 对于追踪方法调用流程非常有用
# - 支持追踪构造函数: stop in <class>.<init>
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载公共函数库
COMMON_LIB="/home/deqiangm/.hermes/cron/interactive-debug-skill-enhancement/common/functions.sh"
if [ -f "$COMMON_LIB" ]; then
 source "$COMMON_LIB"
else
 # 回退到jdb_session.sh
 if [ -f "$SCRIPT_DIR/jdb_session.sh" ]; then
 source "$SCRIPT_DIR/jdb_session.sh"
 fi
fi

# 如果没有加载公共函数，定义基本函数
if ! type log &>/dev/null; then
 log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
 log_error() { echo "ERROR: $1" >&2; }
 error() { log_error "$1"; exit 1; }
fi

# ============================================================================
# 配置
# ============================================================================

METHOD_BP_SESSION_PREFIX="jdb_method_bp"
METHOD_BP_STORAGE_DIR="/tmp/jdb_method_bp_$$"

# ============================================================================
# 方法断点存储管理
# ============================================================================

# 初始化方法断点存储
init_method_bp_storage() {
 mkdir -p "$METHOD_BP_STORAGE_DIR"
}

# 清理方法断点存储
cleanup_method_bp_storage() {
 rm -rf "$METHOD_BP_STORAGE_DIR" 2>/dev/null || true
}

# 生成方法断点的唯一键
# 用法: generate_method_bp_key <class> <method> [params]
generate_method_bp_key() {
 local class="$1"
 local method="$2"
 local params="${3:-}"
 
 local safe_class=$(echo "$class" | tr '.[]' '_')
 local safe_method=$(echo "$method" | tr '[]<>' '_')
 
 if [ -n "$params" ]; then
 local safe_params=$(echo "$params" | tr ',;:' '_')
 echo "${safe_class}_${safe_method}_${safe_params}"
 else
 echo "${safe_class}_${safe_method}"
 fi
}

# 保存方法断点信息
save_method_breakpoint() {
 local session="$1"
 local class="$2"
 local method="$3"
 local params="${4:-}"
 local temp="${5:-no}"
 
 local key=$(generate_method_bp_key "$class" "$method" "$params")
 local file="$METHOD_BP_STORAGE_DIR/${session}_${key}"
 
 cat > "$file" << EOF
SESSION=$session
CLASS=$class
METHOD=$method
PARAMS=$params
TEMP=$temp
ACTIVE=yes
HIT_COUNT=0
CREATED=$(date '+%Y-%m-%d %H:%M:%S')
FULL_NAME=${class}.${method}$( [ -n "$params" ] && echo "($params)" || echo "" )
EOF
 
 log_debug "Saved method breakpoint: $class.$method"
}

# 加载方法断点信息
load_method_breakpoint() {
 local session="$1"
 local class="$2"
 local method="$3"
 local params="${4:-}"
 
 local key=$(generate_method_bp_key "$class" "$method" "$params")
 local file="$METHOD_BP_STORAGE_DIR/${session}_${key}"
 
 if [ -f "$file" ]; then
 cat "$file"
 fi
}

# 更新命中计数
increment_method_bp_hit_count() {
 local session="$1"
 local class="$2"
 local method="$3"
 local params="${4:-}"
 
 local key=$(generate_method_bp_key "$class" "$method" "$params")
 local file="$METHOD_BP_STORAGE_DIR/${session}_${key}"
 
 if [ -f "$file" ]; then
 local count=$(grep "^HIT_COUNT=" "$file" | cut -d= -f2)
 count=$((count + 1))
 sed -i "s/^HIT_COUNT=.*/HIT_COUNT=$count/" "$file"
 echo "$count"
 else
 echo "0"
 fi
}

# 标记方法断点为非活动
deactivate_method_breakpoint() {
 local session="$1"
 local class="$2"
 local method="$3"
 local params="${4:-}"
 
 local key=$(generate_method_bp_key "$class" "$method" "$params")
 local file="$METHOD_BP_STORAGE_DIR/${session}_${key}"
 
 if [ -f "$file" ]; then
 sed -i 's/^ACTIVE=.*/ACTIVE=no/' "$file"
 fi
}

# 列出所有方法断点
list_method_breakpoints() {
 local session="$1"
 
 if [ -d "$METHOD_BP_STORAGE_DIR" ]; then
 for file in "$METHOD_BP_STORAGE_DIR"/${session}_*; do
 if [ -f "$file" ]; then
 local bp_class=$(grep "^CLASS=" "$file" | cut -d= -f2)
 local bp_method=$(grep "^METHOD=" "$file" | cut -d= -f2)
 local bp_params=$(grep "^PARAMS=" "$file" | cut -d= -f2)
 local temp=$(grep "^TEMP=" "$file" | cut -d= -f2)
 local active=$(grep "^ACTIVE=" "$file" | cut -d= -f2)
 local hits=$(grep "^HIT_COUNT=" "$file" | cut -d= -f2)
 local created=$(grep "^CREATED=" "$file" | cut -d= -f2)
 
 local status="$active"
 [ "$temp" = "yes" ] && status="$status (temporary)"
 
 local full_name="${bp_class}.${bp_method}"
 [ -n "$bp_params" ] && full_name="$full_name($bp_params)"
 
 echo "Method: $full_name"
 echo " Status: $status"
 echo " Hits: $hits"
 echo " Created: $created"
 echo ""
 fi
 done
 fi
}

# ============================================================================
# JDB方法断点操作
# ============================================================================

# 设置方法断点（核心函数）
# 用法: set_method_breakpoint <session> <class> <method> [params] [temp]
set_method_breakpoint() {
 local session="$1"
 local class="$2"
 local method="$3"
 local params="${4:-}"
 local temp="${5:-no}"
 
 # 检查session是否存在
 if ! session_exists "$session"; then
 error "Session '$session' not found"
 fi
 
 # 初始化存储
 init_method_bp_storage
 
 # 构建JDB命令
 local jdb_cmd="stop in ${class}.${method}"
 if [ -n "$params" ]; then
 jdb_cmd="stop in ${class}.${method}($params)"
 fi
 
 log "Setting method breakpoint: $jdb_cmd"
 [ "$temp" = "yes" ] && log "Temporary: will be removed after first hit"
 
 # 发送JDB命令
 session_send "$session" "$jdb_cmd"
 sleep 0.5
 
 # 保存断点信息
 save_method_breakpoint "$session" "$class" "$method" "$params" "$temp"
 
 # 显示结果
 local full_name="${class}.${method}"
 [ -n "$params" ] && full_name="$full_name($params)"
 
 echo ""
 echo "============================================"
 echo "METHOD BREAKPOINT SET"
 echo "============================================"
 echo "Class: $class"
 echo "Method: $method"
 [ -n "$params" ] && echo "Params: $params"
 echo "Full: $full_name"
 echo "Temporary: $temp"
 echo ""
 echo "The debugger will stop when:"
 echo " - The method $method is called"
 echo " - Before any code in the method executes"
 echo ""
 echo "Useful commands after hit:"
 echo " - where    Show call stack"
 echo " - locals   Show local variables"
 echo " - step     Step into method"
 echo " - next     Step over current line"
 echo " - cont     Continue execution"
 echo "============================================"
 echo ""
 echo "Session: $session"
}

# 设置构造函数断点
# 用法: set_constructor_breakpoint <session> <class> [params]
set_constructor_breakpoint() {
 local session="$1"
 local class="$2"
 local params="${3:-}"
 
 log "Setting constructor breakpoint for class: $class"
 
 # 构造函数在JDB中使用 <init> 表示
 set_method_breakpoint "$session" "$class" "<init>" "$params" "${4:-no}"
 
 echo ""
 echo "Note: Constructor breakpoint uses <init> method name"
 echo "This will break when new $class() is called"
}

# 设置静态初始化块断点
# 用法: set_static_init_breakpoint <session> <class>
set_static_init_breakpoint() {
 local session="$1"
 local class="$2"
 
 log "Setting static initializer breakpoint for class: $class"
 
 # 静态初始化块使用 <clinit> 表示
 set_method_breakpoint "$session" "$class" "<clinit>" "" "${3:-no}"
 
 echo ""
 echo "Note: Static initializer breakpoint uses <clinit> method name"
 echo "This will break when the class is first loaded"
}

# 清除方法断点
# 用法: clear_method_breakpoint <session> <class> <method> [params]
clear_method_breakpoint() {
 local session="$1"
 local class="$2"
 local method="$3"
 local params="${4:-}"
 
 if ! session_exists "$session"; then
 error "Session '$session' not found"
 fi
 
 # 构建JDB命令
 local jdb_cmd="clear ${class}.${method}"
 if [ -n "$params" ]; then
 jdb_cmd="clear ${class}.${method}($params)"
 fi
 
 log "Clearing method breakpoint: $jdb_cmd"
 
 # 发送JDB命令
 session_send "$session" "$jdb_cmd"
 sleep 0.5
 
 # 标记为非活动
 deactivate_method_breakpoint "$session" "$class" "$method" "$params"
 
 local full_name="${class}.${method}"
 [ -n "$params" ] && full_name="$full_name($params)"
 
 echo "Method breakpoint cleared: $full_name"
}

# 清除所有方法断点
# 用法: clear_all_method_breakpoints <session>
clear_all_method_breakpoints() {
 local session="$1"
 
 if ! session_exists "$session"; then
 error "Session '$session' not found"
 fi
 
 log "Clearing all method breakpoints for session: $session"
 
 # 列出并清除所有方法断点
 if [ -d "$METHOD_BP_STORAGE_DIR" ]; then
 for file in "$METHOD_BP_STORAGE_DIR"/${session}_*; do
 if [ -f "$file" ]; then
 local bp_class=$(grep "^CLASS=" "$file" | cut -d= -f2)
 local bp_method=$(grep "^METHOD=" "$file" | cut -d= -f2)
 local bp_params=$(grep "^PARAMS=" "$file" | cut -d= -f2)
 
 local jdb_cmd="clear ${bp_class}.${bp_method}"
 [ -n "$bp_params" ] && jdb_cmd="clear ${bp_class}.${bp_method}($bp_params)"
 
 session_send "$session" "$jdb_cmd" 2>/dev/null || true
 deactivate_method_breakpoint "$session" "$bp_class" "$bp_method" "$bp_params"
 fi
 done
 fi
 
 echo "All method breakpoints cleared for session: $session"
}

# 列出JDB中的所有断点
# 用法: list_jdb_breakpoints <session>
list_jdb_breakpoints() {
 local session="$1"
 
 if ! session_exists "$session"; then
 error "Session '$session' not found"
 fi
 
 echo "Listing all breakpoints from JDB..."
 session_send "$session" "clear"
 sleep 1
 session_read "$session"
}

# ============================================================================
# 方法断点监控
# ============================================================================

# 监控方法断点命中（后台运行）
# 用法: monitor_method_breakpoint <session> <class> <method> [params] [check_interval]
monitor_method_breakpoint() {
 local session="$1"
 local class="$2"
 local method="$3"
 local params="${4:-}"
 local interval="${5:-1}"
 
 # 加载断点信息
 local bp_info=$(load_method_breakpoint "$session" "$class" "$method" "$params")
 if [ -z "$bp_info" ]; then
 error "No method breakpoint found at $class.$method"
 fi
 
 local temp=$(echo "$bp_info" | grep "^TEMP=" | cut -d= -f2)
 local full_name=$(echo "$bp_info" | grep "^FULL_NAME=" | cut -d= -f2)
 
 log "Starting method breakpoint monitor for $full_name"
 log "Checking every ${interval}s"
 
 # 方法断点命中的输出模式
 # JDB输出格式: "Breakpoint hit: ..., thread=..., class=..., method=..."
 local hit_pattern="Breakpoint hit.*${class}.*${method}"
 
 while true; do
 sleep "$interval"
 
 # 检查断点是否仍然活动
 local active=$(echo "$bp_info" | grep "^ACTIVE=" | cut -d= -f2 2>/dev/null || echo "no")
 if [ "$active" = "no" ]; then
 log "Breakpoint deactivated, stopping monitor"
 break
 fi
 
 # 检查session是否还存在
 if ! session_exists "$session"; then
 log "Session ended, stopping monitor"
 break
 fi
 
 # 读取当前输出
 local output=$(session_read "$session")
 
 if echo "$output" | grep -qiE "$hit_pattern"; then
 # 增加命中计数
 local hit_count=$(increment_method_bp_hit_count "$session" "$class" "$method" "$params")
 
 echo ""
 echo "============================================"
 echo "${GREEN}METHOD BREAKPOINT HIT #$hit_count${NC}"
 echo "============================================"
 echo "Method: $full_name"
 echo "Class: $class"
 echo ""
 echo "Method entry point reached!"
 echo ""
 echo "Useful commands:"
 echo " where     Show call stack (who called this method)"
 echo " locals    Show local variables (method parameters)"
 echo " this      Show current object (for instance methods)"
 echo " step      Step into the method"
 echo " next      Step over current line"
 echo " cont      Continue execution"
 echo "============================================"
 echo ""
 
 # 如果是临时断点，清除它
 if [ "$temp" = "yes" ]; then
 log "Temporary breakpoint, clearing..."
 local jdb_cmd="clear ${class}.${method}"
 [ -n "$params" ] && jdb_cmd="clear ${class}.${method}($params)"
 session_send "$session" "$jdb_cmd"
 deactivate_method_breakpoint "$session" "$class" "$method" "$params"
 break
 fi
 fi
 done
}

# ============================================================================
# 高级功能：方法断点建议
# ============================================================================

# 分析类方法并建议断点
# 用法: suggest_method_breakpoints <session> <class>
suggest_method_breakpoints() {
 local session="$1"
 local class="$2"
 
 if ! session_exists "$session"; then
 error "Session '$session' not found"
 fi
 
 log "Analyzing class $class for method breakpoint suggestions..."
 
 # 使用methods命令获取类的方法列表
 session_send "$session" "methods $class"
 sleep 1
 
 local output=$(session_read "$session")
 
 echo ""
 echo "============================================"
 echo "METHOD BREAKPOINT SUGGESTIONS FOR $class"
 echo "============================================"
 echo ""
 echo "Available methods (from JDB output):"
 echo "$output" | grep -E "^[[:space:]]*(private|public|protected|static).*" || echo " (Could not parse methods)"
 echo ""
 echo "Suggested breakpoints:"
 echo ""
 echo "For tracing method entry:"
 echo " $0 set $session $class <methodName>"
 echo ""
 echo "For specific overload:"
 echo " $0 set $session $class <methodName> \"<paramTypes>\""
 echo ""
 echo "For constructor:"
 echo " $0 constructor $session $class"
 echo ""
 echo "For static initializer:"
 echo " $0 clinit $session $class"
 echo ""
 echo "============================================"
}

# ============================================================================
# 高级功能：批量设置方法断点
# ============================================================================

# 批量设置多个方法断点
# 用法: batch_set_method_breakpoints <session> <class> <method1,method2,...>
batch_set_method_breakpoints() {
 local session="$1"
 local class="$2"
 local methods="$3"
 local temp="${4:-no}"
 
 if ! session_exists "$session"; then
 error "Session '$session' not found"
 fi
 
 log "Batch setting method breakpoints for class: $class"
 
 # 分割方法列表
 IFS=',' read -ra method_array <<< "$methods"
 
 for method in "${method_array[@]}"; do
 # 去除空格
 method=$(echo "$method" | xargs)
 
 if [ -n "$method" ]; then
 log "Setting breakpoint for: $method"
 set_method_breakpoint "$session" "$class" "$method" "" "$temp"
 sleep 0.3
 fi
 done
 
 echo ""
 echo "Batch operation completed"
}

# 设置getter/setter方法断点
# 用法: set_getter_setter_breakpoints <session> <class> [fieldName]
set_getter_setter_breakpoints() {
 local session="$1"
 local class="$2"
 local field="${3:-}"
 
 if ! session_exists "$session"; then
 error "Session '$session' not found"
 fi
 
 log "Setting getter/setter breakpoints for class: $class"
 
 if [ -n "$field" ]; then
 # 首字母大写
 local field_cap="$(echo ${field:0:1} | tr '[:lower:]' '[:upper:]')${field:1}"
 
 # 设置特定字段的getter和setter
 batch_set_method_breakpoints "$session" "$class" "get${field_cap},set${field_cap}"
 else
 # 设置所有getter和setter
 # 需要先获取方法列表
 session_send "$session" "methods $class"
 sleep 1
 local output=$(session_read "$session")
 
 local getters=$(echo "$output" | grep -oE "get[A-Z][a-zA-Z]*" | sort -u | tr '\n' ',')
 local setters=$(echo "$output" | grep -oE "set[A-Z][a-zA-Z]*" | sort -u | tr '\n' ',')
 
 if [ -n "$getters" ]; then
 log "Found getters: $getters"
 batch_set_method_breakpoints "$session" "$class" "$getters"
 fi
 
 if [ -n "$setters" ]; then
 log "Found setters: $setters"
 batch_set_method_breakpoints "$session" "$class" "$setters"
 fi
 fi
}

# ============================================================================
# 帮助和主程序
# ============================================================================

show_help() {
 cat << EOF
jdb_method_breakpoint.sh - JDB方法断点支持（在方法入口处停止）

用法:
 $0 <command> [arguments...]

命令:
 set <session> <class> <method> [params] [temp]
 设置方法断点
 params: 可选，方法参数类型，用于重载方法
 temp: 可选，设为 "yes" 表示临时断点

 constructor <session> <class> [params]
 设置构造函数断点

 clinit <session> <class>
 设置静态初始化块断点

 clear <session> <class> <method> [params]
 清除方法断点

 clear-all <session>
 清除所有方法断点

 list <session>
 列出所有方法断点（本地存储）

 list-jdb <session>
 列出JDB中的所有断点

 monitor <session> <class> <method> [params] [interval]
 监控方法断点命中

 suggest <session> <class>
 分析类并建议方法断点

 batch <session> <class> <methods>
 批量设置方法断点
 methods: 逗号分隔的方法名列表

 getters-setters <session> <class> [field]
 设置getter/setter方法断点
 field: 可选，只设置特定字段的getter/setter

方法断点语法:
 Class.method               无参数的方法
 Class.method(params)      指定参数类型的方法
 Class.<init>              构造函数
 Class.<clinit>            静态初始化块

参数类型示例:
 "int,String"              接受int和String参数的方法
 "String"                  只接受String参数
 ""                        无参数（显式指定）

工作原理:
 1. 发送JDB的 "stop in Class.method" 命令
 2. 当方法被调用时，JDB在方法入口处停止
 3. 可以查看调用栈、参数和局部变量

与行断点的区别:
 - 不需要知道具体行号
 - 在方法入口处停止，可以追踪调用来源
 - 对追踪构造函数和静态初始化特别有用

示例:
 # 设置普通方法断点
 $0 set my_session com.example.UserService getUserById
 
 # 设置重载方法断点
 $0 set my_session com.example.Calculator add "int,int"
 
 # 设置构造函数断点
 $0 constructor my_session com.example.User
 
 # 设置静态初始化断点
 $0 clinit my_session com.example.Constants
 
 # 临时断点（命中一次后自动删除）
 $0 set my_session com.example.UserService processRequest "" yes
 
 # 批量设置多个方法断点
 $0 batch my_session com.example.Service "init,start,stop"
 
 # 设置所有getter/setter断点
 $0 getters-setters my_session com.example.User

EOF
}

# 入口
if [ $# -lt 1 ]; then
 show_help
 exit 1
fi

command="$1"
shift

case "$command" in
 -h|--help)
 show_help
 exit 0
 ;;
 set)
 [ $# -lt 3 ] && error "Usage: $0 set <session> <class> <method> [params] [temp]"
 set_method_breakpoint "$1" "$2" "$3" "${4:-}" "${5:-no}"
 ;;
 constructor)
 [ $# -lt 2 ] && error "Usage: $0 constructor <session> <class> [params]"
 set_constructor_breakpoint "$1" "$2" "${3:-}" "${4:-no}"
 ;;
 clinit)
 [ $# -lt 2 ] && error "Usage: $0 clinit <session> <class>"
 set_static_init_breakpoint "$1" "$2" "${3:-no}"
 ;;
 clear)
 [ $# -lt 3 ] && error "Usage: $0 clear <session> <class> <method> [params]"
 clear_method_breakpoint "$1" "$2" "$3" "${4:-}"
 ;;
 clear-all)
 [ $# -lt 1 ] && error "Usage: $0 clear-all <session>"
 clear_all_method_breakpoints "$1"
 ;;
 list)
 [ $# -lt 1 ] && error "Usage: $0 list <session>"
 list_method_breakpoints "$1"
 ;;
 list-jdb)
 [ $# -lt 1 ] && error "Usage: $0 list-jdb <session>"
 list_jdb_breakpoints "$1"
 ;;
 monitor)
 [ $# -lt 3 ] && error "Usage: $0 monitor <session> <class> <method> [params] [interval]"
 monitor_method_breakpoint "$1" "$2" "$3" "${4:-}" "${5:-1}"
 ;;
 suggest)
 [ $# -lt 2 ] && error "Usage: $0 suggest <session> <class>"
 suggest_method_breakpoints "$1" "$2"
 ;;
 batch)
 [ $# -lt 3 ] && error "Usage: $0 batch <session> <class> <methods>"
 batch_set_method_breakpoints "$1" "$2" "$3" "${4:-no}"
 ;;
 getters-setters)
 [ $# -lt 2 ] && error "Usage: $0 getters-setters <session> <class> [field]"
 set_getter_setter_breakpoints "$1" "$2" "${3:-}"
 ;;
 *)
 error "Unknown command: $command. Use --help for usage."
 ;;
esac

# 清理
trap cleanup_method_bp_storage EXIT
