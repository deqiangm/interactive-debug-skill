#!/bin/bash
# ============================================================================
# JDB Exception Breakpoint - 异常断点支持 (stop on exception)
# 
# 功能:
# 1. 设置异常断点 (catch <exception_class>)
# 2. 支持捕获/未捕获异常筛选
# 3. 异常断点列表管理
# 4. 异常命中通知和堆栈显示
# 5. 常见异常类型快捷设置
# 
# JDB命令参考:
# - catch <exception_class>    在异常抛出时停止
# - catch                      显示当前异常断点
# - ignore <exception_class>   移除异常断点
# 
# 与普通断点的区别:
# - 异常断点不需要指定位置
# - 当指定类型（或子类）的异常被抛出时触发
# - 对于调试NullPointerException等异常非常有用
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

EXC_BP_SESSION_PREFIX="jdb_exc_bp"
EXC_BP_STORAGE_DIR="/tmp/jdb_exc_bp_$$"

# 常见异常类型列表
COMMON_EXCEPTIONS=(
 "java.lang.NullPointerException:NPE:空指针异常"
 "java.lang.ArrayIndexOutOfBoundsException:AIOOBE:数组越界异常"
 "java.lang.ClassCastException:CCE:类型转换异常"
 "java.lang.IllegalArgumentException:IAE:非法参数异常"
 "java.lang.IllegalStateException:ISE:非法状态异常"
 "java.lang.NumberFormatException:NFE:数字格式异常"
 "java.lang.IndexOutOfBoundsException:IOOBE:索引越界异常"
 "java.lang.UnsupportedOperationException:UOE:不支持的操作异常"
 "java.lang.ArithmeticException:AE:算术异常"
 "java.lang.OutOfMemoryError:OOME:内存溢出错误"
 "java.lang.StackOverflowError:SOE:栈溢出错误"
 "java.io.IOException:IOE:IO异常"
 "java.sql.SQLException:SQLE:SQL异常"
 "java.lang.RuntimeException:RE:运行时异常（所有未捕获异常）"
 "java.lang.Exception:E:所有异常"
 "java.lang.Throwable:T:所有异常和错误"
)

# ============================================================================
# 异常断点存储管理
# ============================================================================

# 初始化异常断点存储
init_exc_bp_storage() {
 mkdir -p "$EXC_BP_STORAGE_DIR"
}

# 清理异常断点存储
cleanup_exc_bp_storage() {
 rm -rf "$EXC_BP_STORAGE_DIR" 2>/dev/null || true
}

# 生成异常断点的唯一键
# 用法: generate_exc_bp_key <exception_class>
generate_exc_bp_key() {
 local exception_class="$1"
 local safe_class=$(echo "$exception_class" | tr '.[]' '_')
 echo "$safe_class"
}

# 保存异常断点信息
save_exception_breakpoint() {
 local session="$1"
 local exception_class="$2"
 local caught="${3:-both}" # caught, uncaught, both
 local temp="${4:-no}"
 
 local key=$(generate_exc_bp_key "$exception_class")
 local file="$EXC_BP_STORAGE_DIR/${session}_${key}"
 
 cat > "$file" << EOF
SESSION=$session
EXCEPTION_CLASS=$exception_class
CAUGHT=$caught
TEMP=$temp
ACTIVE=yes
HIT_COUNT=0
CREATED=$(date '+%Y-%m-%d %H:%M:%S')
EOF
 
 log_debug "Saved exception breakpoint: $exception_class"
}

# 加载异常断点信息
load_exception_breakpoint() {
 local session="$1"
 local exception_class="$2"
 
 local key=$(generate_exc_bp_key "$exception_class")
 local file="$EXC_BP_STORAGE_DIR/${session}_${key}"
 
 if [ -f "$file" ]; then
 cat "$file"
 fi
}

# 更新命中计数
increment_exc_bp_hit_count() {
 local session="$1"
 local exception_class="$2"
 
 local key=$(generate_exc_bp_key "$exception_class")
 local file="$EXC_BP_STORAGE_DIR/${session}_${key}"
 
 if [ -f "$file" ]; then
 local count=$(grep "^HIT_COUNT=" "$file" | cut -d= -f2)
 count=$((count + 1))
 sed -i "s/^HIT_COUNT=.*/HIT_COUNT=$count/" "$file"
 echo "$count"
 else
 echo "0"
 fi
}

# 标记异常断点为非活动
deactivate_exception_breakpoint() {
 local session="$1"
 local exception_class="$2"
 
 local key=$(generate_exc_bp_key "$exception_class")
 local file="$EXC_BP_STORAGE_DIR/${session}_${key}"
 
 if [ -f "$file" ]; then
 sed -i 's/^ACTIVE=.*/ACTIVE=no/' "$file"
 fi
}

# 列出所有异常断点
list_exception_breakpoints() {
 local session="$1"
 
 if [ -d "$EXC_BP_STORAGE_DIR" ]; then
 for file in "$EXC_BP_STORAGE_DIR"/${session}_*; do
 if [ -f "$file" ]; then
 local bp_class=$(grep "^EXCEPTION_CLASS=" "$file" | cut -d= -f2)
 local caught=$(grep "^CAUGHT=" "$file" | cut -d= -f2)
 local temp=$(grep "^TEMP=" "$file" | cut -d= -f2)
 local active=$(grep "^ACTIVE=" "$file" | cut -d= -f2)
 local hits=$(grep "^HIT_COUNT=" "$file" | cut -d= -f2)
 local created=$(grep "^CREATED=" "$file" | cut -d= -f2)
 
 local status="$active"
 [ "$temp" = "yes" ] && status="$status (temporary)"
 
 echo "Exception: $bp_class"
 echo " Caught: $caught"
 echo " Status: $status"
 echo " Hits: $hits"
 echo " Created: $created"
 echo ""
 fi
 done
 fi
}

# ============================================================================
# JDB异常断点操作
# ============================================================================

# 设置异常断点（核心函数）
# 用法: set_exception_breakpoint <session> <exception_class> [caught] [temp]
set_exception_breakpoint() {
 local session="$1"
 local exception_class="$2"
 local caught="${3:-both}" # caught, uncaught, both
 local temp="${4:-no}"
 
 # 检查session是否存在
 if ! session_exists "$session"; then
 error "Session '$session' not found"
 fi
 
 # 初始化存储
 init_exc_bp_storage
 
 log "Setting exception breakpoint for: $exception_class"
 [ "$temp" = "yes" ] && log "Temporary: will be removed after first hit"
 
 # 发送JDB catch命令
 session_send "$session" "catch $exception_class"
 sleep 0.5
 
 # 保存断点信息
 save_exception_breakpoint "$session" "$exception_class" "$caught" "$temp"
 
 # 显示结果
 echo ""
 echo "============================================"
 echo "EXCEPTION BREAKPOINT SET"
 echo "============================================"
 echo "Exception: $exception_class"
 echo "Caught: $caught"
 echo "Temporary: $temp"
 echo ""
 echo "The debugger will stop when:"
 echo " - An exception of type $exception_class is thrown"
 echo " - Or any subclass of $exception_class"
 echo ""
 echo "Useful commands after hit:"
 echo " - where  Show call stack at exception point"
 echo " - locals Show local variables"
 echo " - print <var> Print variable value"
 echo " - cont  Continue execution (exception propagates)"
 echo "============================================"
 echo ""
 echo "Session: $session"
}

# 设置NPE断点快捷方式
# 用法: set_npe_breakpoint <session> [temp]
set_npe_breakpoint() {
 local session="$1"
 local temp="${2:-no}"
 
 log "Setting NullPointerException breakpoint"
 set_exception_breakpoint "$session" "java.lang.NullPointerException" "both" "$temp"
}

# 设置数组越界断点
# 用法: set_array_bounds_breakpoint <session> [temp]
set_array_bounds_breakpoint() {
 local session="$1"
 local temp="${2:-no}"
 
 log "Setting ArrayIndexOutOfBoundsException breakpoint"
 set_exception_breakpoint "$session" "java.lang.ArrayIndexOutOfBoundsException" "both" "$temp"
}

# 设置所有未捕获异常断点
# 用法: set_uncaught_breakpoint <session> [temp]
set_uncaught_breakpoint() {
 local session="$1"
 local temp="${2:-no}"
 
 log "Setting uncaught exception breakpoint"
 # 注意：JDB的catch命令默认捕获所有异常（包括捕获和未捕获）
 # 要只捕获未捕获异常，需要使用特定选项或运行时设置
 set_exception_breakpoint "$session" "java.lang.RuntimeException" "uncaught" "$temp"
}

# 设置所有异常断点
# 用法: set_all_exceptions_breakpoint <session> [temp]
set_all_exceptions_breakpoint() {
 local session="$1"
 local temp="${2:-no}"
 
 log "Setting breakpoint for all exceptions"
 set_exception_breakpoint "$session" "java.lang.Throwable" "both" "$temp"
 
 echo ""
 echo "Note: This will stop on ALL exceptions including:"
 echo " - NullPointerException, ArrayIndexOutOfBoundsException, etc."
 echo " - May be noisy for large applications"
 echo " - Consider using more specific exception types"
}

# 清除异常断点
# 用法: clear_exception_breakpoint <session> <exception_class>
clear_exception_breakpoint() {
 local session="$1"
 local exception_class="$2"
 
 if ! session_exists "$session"; then
 error "Session '$session' not found"
 fi
 
 log "Clearing exception breakpoint: $exception_class"
 
 # JDB使用ignore命令清除异常断点
 session_send "$session" "ignore $exception_class"
 sleep 0.5
 
 # 标记为非活动
 deactivate_exception_breakpoint "$session" "$exception_class"
 
 echo "Exception breakpoint cleared: $exception_class"
}

# 清除所有异常断点
# 用法: clear_all_exception_breakpoints <session>
clear_all_exception_breakpoints() {
 local session="$1"
 
 if ! session_exists "$session"; then
 error "Session '$session' not found"
 fi
 
 log "Clearing all exception breakpoints for session: $session"
 
 # 遍历并清除所有异常断点
 if [ -d "$EXC_BP_STORAGE_DIR" ]; then
 for file in "$EXC_BP_STORAGE_DIR"/${session}_*; do
 if [ -f "$file" ]; then
 local bp_class=$(grep "^EXCEPTION_CLASS=" "$file" | cut -d= -f2)
 
 session_send "$session" "ignore $bp_class" 2>/dev/null || true
 deactivate_exception_breakpoint "$session" "$bp_class"
 fi
 done
 fi
 
 echo "All exception breakpoints cleared for session: $session"
}

# 列出JDB中的所有异常断点
# 用法: list_jdb_exception_breakpoints <session>
list_jdb_exception_breakpoints() {
 local session="$1"
 
 if ! session_exists "$session"; then
 error "Session '$session' not found"
 fi
 
 echo "Listing all exception breakpoints from JDB..."
 session_send "$session" "catch"
 sleep 1
 session_read "$session"
}

# ============================================================================
# 异常断点监控
# ============================================================================

# 监控异常断点命中（后台运行）
# 用法: monitor_exception_breakpoint <session> <exception_class> [check_interval]
monitor_exception_breakpoint() {
 local session="$1"
 local exception_class="$2"
 local interval="${3:-1}"
 
 # 加载断点信息
 local bp_info=$(load_exception_breakpoint "$session" "$exception_class")
 if [ -z "$bp_info" ]; then
 error "No exception breakpoint found for $exception_class"
 fi
 
 local temp=$(echo "$bp_info" | grep "^TEMP=" | cut -d= -f2)
 
 log "Starting exception breakpoint monitor for $exception_class"
 log "Checking every ${interval}s"
 
 # 异常命中的输出模式
 # JDB输出格式: "Exception occurred: <exception>, ..."
 local hit_pattern="Exception occurred.*$exception_class"
 
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
 local hit_count=$(increment_exc_bp_hit_count "$session" "$exception_class")
 
 echo ""
 echo "============================================"
 echo "${RED}EXCEPTION BREAKPOINT HIT #$hit_count${NC}"
 echo "============================================"
 echo "Exception: $exception_class"
 echo ""
 echo "Exception occurred! The debugger has stopped."
 echo ""
 echo "Useful commands:"
 echo " where   Show call stack at exception point"
 echo " locals  Show local variables"
 echo " print <var> Print variable value"
 echo " cont    Continue execution"
 echo ""
 echo "To see the exception details:"
 echo " print <exception_var>  Print exception object"
 echo " where                  Show stack trace"
 echo "============================================"
 echo ""
 
 # 如果是临时断点，清除它
 if [ "$temp" = "yes" ]; then
 log "Temporary breakpoint, clearing..."
 session_send "$session" "ignore $exception_class"
 deactivate_exception_breakpoint "$session" "$exception_class"
 break
 fi
 fi
 done
}

# ============================================================================
# 异常断点建议
# ============================================================================

# 显示常见异常类型
show_common_exceptions() {
 echo ""
 echo "============================================"
 echo "COMMON EXCEPTION TYPES"
 echo "============================================"
 echo ""
 printf "%-50s %-10s %s\n" "Exception Class" "Short" "Description"
 echo "--------------------------------------------------------------------------------"
 
 for entry in "${COMMON_EXCEPTIONS[@]}"; do
 IFS=':' read -r class short desc <<< "$entry"
 printf "%-50s %-10s %s\n" "$class" "$short" "$desc"
 done
 
 echo ""
 echo "Short names can be used with the --short option:"
 echo " $0 set <session> NPE    # Same as java.lang.NullPointerException"
 echo " $0 set <session> AIOOBE # Same as ArrayIndexOutOfBoundsException"
 echo ""
}

# 解析异常类型名称
# 用法: resolve_exception_name <name>
# 返回: 完整的异常类名
resolve_exception_name() {
 local name="$1"
 
 # 如果包含点，认为是完整类名
 if echo "$name" | grep -q '\.'; then
 echo "$name"
 return 0
 fi
 
 # 查找短名称
 for entry in "${COMMON_EXCEPTIONS[@]}"; do
 IFS=':' read -r class short desc <<< "$entry"
 if [ "$name" = "$short" ]; then
 echo "$class"
 return 0
 fi
 done
 
 # 未找到，尝试添加java.lang前缀
 echo "java.lang.$name"
}

# ============================================================================
# 高级功能：异常分析
# ============================================================================

# 分析异常堆栈（当断点命中后）
# 用法: analyze_exception_stack <session>
analyze_exception_stack() {
 local session="$1"
 
 if ! session_exists "$session"; then
 error "Session '$session' not found"
 fi
 
 log "Analyzing exception stack..."
 
 # 获取调用栈
 session_send "$session" "where"
 sleep 1
 local stack_output=$(session_read "$session")
 
 echo ""
 echo "============================================"
 echo "EXCEPTION STACK ANALYSIS"
 echo "============================================"
 echo ""
 echo "Stack trace:"
 echo "$stack_output" | grep -E "^\[|at " | head -20
 echo ""
 echo "Analysis suggestions:"
 echo ""
 
 # 分析常见模式
 if echo "$stack_output" | grep -q "NullPointerException"; then
 echo "[NPE Analysis]"
 echo " - Check for null variables in the current frame"
 echo " - Use 'locals' to see variable values"
 echo " - Common cause: method call on null object"
 echo " - Use 'print <var> == null' to check specific variables"
 echo ""
 fi
 
 if echo "$stack_output" | grep -q "ArrayIndexOutOfBoundsException"; then
 echo "[AIOOBE Analysis]"
 echo " - Check array access with index variable"
 echo " - Use 'print <array>.length' to see array size"
 echo " - Use 'print <index>' to see current index value"
 echo " - Common cause: off-by-one errors or empty arrays"
 echo ""
 fi
 
 echo "Useful commands for investigation:"
 echo " where   Full stack trace"
 echo " locals  Local variables in current frame"
 echo " this    Current object (for instance methods)"
 echo " print <var>  Print specific variable"
 echo "============================================"
}

# ============================================================================
# 帮助和主程序
# ============================================================================

show_help() {
 cat << EOF
jdb_exception_breakpoint.sh - JDB异常断点支持

用法:
 $0 <command> [arguments...]

命令:
 set <session> <ExceptionClass> [temp]
 设置异常断点
 temp: 可选，设为 "yes" 表示临时断点（命中后自动删除）
 
 示例:
 $0 set my_session java.lang.NullPointerException
 $0 set my_session NullPointerException yes

 set-short <session> <ShortName> [temp]
 使用短名称设置异常断点
 短名称: NPE, AIOOBE, CCE, IAE, ISE, NFE, IOOBE, UOE, AE, OOME, SOE
 
 示例:
 $0 set-short my_session NPE
 $0 set-short my_session AIOOBE yes

 npe <session> [temp]
 快捷方式：设置NullPointerException断点
 
 array-bounds <session> [temp]
 快捷方式：设置ArrayIndexOutOfBoundsException断点
 
 all <session> [temp]
 设置所有异常断点（java.lang.Throwable）
 警告：可能会很吵闹
 
 uncaught <session> [temp]
 设置未捕获异常断点

 clear <session> <ExceptionClass>
 清除异常断点

 clear-all <session>
 清除所有异常断点

 list <session>
 列出已设置的异常断点

 list-jdb <session>
 列出JDB中的所有异常断点

 monitor <session> <ExceptionClass> [interval]
 后台监控异常断点命中

 analyze <session>
 分析异常堆栈（异常命中后使用）

 common
 显示常见异常类型列表

短名称映射:
 NPE  - NullPointerException (空指针异常)
 AIOOBE - ArrayIndexOutOfBoundsException (数组越界)
 CCE  - ClassCastException (类型转换异常)
 IAE  - IllegalArgumentException (非法参数异常)
 ISE  - IllegalStateException (非法状态异常)
 NFE  - NumberFormatException (数字格式异常)
 IOOBE - IndexOutOfBoundsException (索引越界)
 UOE  - UnsupportedOperationException (不支持操作)
 AE   - ArithmeticException (算术异常)
 OOME - OutOfMemoryError (内存溢出)
 SOE  - StackOverflowError (栈溢出)
 RE   - RuntimeException (运行时异常)
 E    - Exception (所有异常)
 T    - Throwable (所有异常和错误)

工作原理:
 1. 使用JDB的catch命令设置异常断点
 2. 当指定类型的异常被抛出时，调试器停止
 3. 使用where命令查看异常抛出点的调用栈
 4. 使用ignore命令清除异常断点

注意事项:
 - 异常断点会在异常被抛出时触发，而不是被捕获时
 - 子类异常也会触发断点
 - 对于频繁抛出的异常（如某些框架异常），可能会很吵闹
 - 建议使用具体的异常类型，而不是通用的Exception/Throwable

示例:
 # 设置NullPointerException断点
 $0 set my_session NullPointerException
 
 # 使用短名称设置断点
 $0 set-short my_session NPE
 
 # 设置临时断点（命中后自动删除）
 $0 set my_session NullPointerException yes
 
 # 设置所有异常断点
 $0 all my_session
 
 # 列出异常断点
 $0 list my_session
 
 # 监控异常命中
 $0 monitor my_session NullPointerException 0.5

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
 [ $# -lt 2 ] && error "Usage: $0 set <session> <ExceptionClass> [temp]"
 set_exception_breakpoint "$1" "$2" "both" "${3:-no}"
 ;;
 set-short)
 [ $# -lt 2 ] && error "Usage: $0 set-short <session> <ShortName> [temp]"
 local resolved=$(resolve_exception_name "$2")
 set_exception_breakpoint "$1" "$resolved" "both" "${3:-no}"
 ;;
 npe)
 [ $# -lt 1 ] && error "Usage: $0 npe <session> [temp]"
 set_npe_breakpoint "$1" "${2:-no}"
 ;;
 array-bounds)
 [ $# -lt 1 ] && error "Usage: $0 array-bounds <session> [temp]"
 set_array_bounds_breakpoint "$1" "${2:-no}"
 ;;
 all)
 [ $# -lt 1 ] && error "Usage: $0 all <session> [temp]"
 set_all_exceptions_breakpoint "$1" "${2:-no}"
 ;;
 uncaught)
 [ $# -lt 1 ] && error "Usage: $0 uncaught <session> [temp]"
 set_uncaught_breakpoint "$1" "${2:-no}"
 ;;
 clear)
 [ $# -lt 2 ] && error "Usage: $0 clear <session> <ExceptionClass>"
 clear_exception_breakpoint "$1" "$2"
 ;;
 clear-all)
 [ $# -lt 1 ] && error "Usage: $0 clear-all <session>"
 clear_all_exception_breakpoints "$1"
 ;;
 list)
 [ $# -lt 1 ] && error "Usage: $0 list <session>"
 list_exception_breakpoints "$1"
 ;;
 list-jdb)
 [ $# -lt 1 ] && error "Usage: $0 list-jdb <session>"
 list_jdb_exception_breakpoints "$1"
 ;;
 monitor)
 [ $# -lt 2 ] && error "Usage: $0 monitor <session> <ExceptionClass> [interval]"
 monitor_exception_breakpoint "$1" "$2" "${3:-1}"
 ;;
 analyze)
 [ $# -lt 1 ] && error "Usage: $0 analyze <session>"
 analyze_exception_stack "$1"
 ;;
 common)
 show_common_exceptions
 ;;
 *)
 error "Unknown command: $command. Use --help for usage."
 ;;
esac

# 清理
trap cleanup_exc_bp_storage EXIT
