#!/bin/bash
# ============================================================================
# PDB Session Manager - Python调试器Session管理
# 
# 基于tmux的pdb session隔离和通信
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../common/functions.sh"

# ============================================================================
# Python特定配置
# ============================================================================

DEFAULT_PDB_PORT=5678

# ============================================================================
# Session管理
# ============================================================================

# 创建pdb session
create_pdb_session() {
    local session_name="$1"
    local python_script="$2"
    local python_args="${3:-}"
    
    # 检查Python是否存在
    if ! command -v python3 &>/dev/null; then
        error "python3 not found"
    fi
    
    # 构建pdb命令
    local pdb_cmd="python3 -m pdb $python_script"
    [ -n "$python_args" ] && pdb_cmd="$pdb_cmd $python_args"
    
    log "Creating PDB session: $session_name"
    log "Script: $python_script"
    
    # 创建tmux session
    session_create "$session_name" "$pdb_cmd"
    
    # 等待pdb初始化
    sleep 1
    
    echo "SESSION_NAME=$session_name"
}

# 创建pdb session（带virtualenv）
create_pdb_session_venv() {
    local session_name="$1"
    local python_script="$2"
    local venv_path="$3"
    local python_args="${4:-}"
    
    # 验证virtualenv
    if [ ! -f "$venv_path/bin/activate" ]; then
        error "Virtualenv not found: $venv_path"
    fi
    
    # 构建命令（先激活virtualenv）
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
# 断点管理
# ============================================================================

# 设置断点
pdb_set_breakpoint() {
    local session_name="$1"
    local location="$2"  # filename:lineno 或 function_name
    
    session_send "$session_name" "b $location"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# 设置条件断点
pdb_set_conditional_breakpoint() {
    local session_name="$1"
    local location="$2"
    local condition="$3"
    
    session_send "$session_name" "b $location, $condition"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# 清除断点
pdb_clear_breakpoint() {
    local session_name="$1"
    local bp_num="${2:-}"  # 可选，不指定则清除所有
    
    if [ -n "$bp_num" ]; then
        session_send "$session_name" "cl $bp_num"
    else
        session_send "$session_name" "cl"
    fi
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# 列出断点
pdb_list_breakpoints() {
    local session_name="$1"
    
    session_send "$session_name" "b"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# ============================================================================
# 执行控制
# ============================================================================

# 运行程序
pdb_run() {
    local session_name="$1"
    
    session_send "$session_name" "c"
    session_poll "$session_name" 30 0.5 "[(]pdb[)]|->"
}

# 单步执行（进入函数）
pdb_step() {
    local session_name="$1"
    
    session_send "$session_name" "s"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# 单步执行（不进入函数）
pdb_next() {
    local session_name="$1"
    
    session_send "$session_name" "n"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# 继续执行
pdb_continue() {
    local session_name="$1"
    
    session_send "$session_name" "c"
    session_poll "$session_name" 30 0.5 "[(]pdb[)]"
}

# 返回上一级
pdb_return() {
    local session_name="$1"
    
    session_send "$session_name" "r"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# 退出
pdb_quit() {
    local session_name="$1"
    
    session_send "$session_name" "q"
    sleep 0.5
    session_send "$session_name" "y"  # 确认退出
}

# ============================================================================
# 变量查看
# ============================================================================

# 打印变量
pdb_print() {
    local session_name="$1"
    local expression="$2"
    
    session_send "$session_name" "p $expression"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# 打印变量（完整）
pdb_pretty_print() {
    local session_name="$1"
    local expression="$2"
    
    session_send "$session_name" "pp $expression"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# 列出局部变量
pdb_locals() {
    local session_name="$1"
    
    session_send "$session_name" "a"  # args
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# 列出源代码
pdb_list() {
    local session_name="$1"
    local lines="${2:-11}"  # 显示行数
    
    session_send "$session_name" "l $lines"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# ============================================================================
# 调用栈
# ============================================================================

# 打印调用栈
pdb_where() {
    local session_name="$1"
    
    session_send "$session_name" "w"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# 向上移动调用栈
pdb_up() {
    local session_name="$1"
    
    session_send "$session_name" "u"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# 向下移动调用栈
pdb_down() {
    local session_name="$1"
    
    session_send "$session_name" "d"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# ============================================================================
# 高级功能
# ============================================================================

# 执行Python语句
pdb_exec() {
    local session_name="$1"
    local statement="$2"
    
    session_send "$session_name" "! $statement"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# 设置变量值
pdb_set_var() {
    local session_name="$1"
    local var_name="$2"
    local var_value="$3"
    
    pdb_exec "$session_name" "$var_name = $var_value"
}

# 导入模块
pdb_import() {
    local session_name="$1"
    local module="$2"
    
    pdb_exec "$session_name" "import $module"
}

# 监视表达式（每次暂停时自动打印）
pdb_watch() {
    local session_name="$1"
    local expression="$2"
    
    # PDB没有内置的watch命令，使用display模拟
    session_send "$session_name" "display $expression"
    session_poll "$session_name" 5 0.5 "[(]pdb[)]"
}

# ============================================================================
# 快速启动
# ============================================================================

# 快速启动Python调试
pdb_quick_start() {
    local project_dir="$1"
    local script_name="$2"
    local args="${3:-}"
    
    # 查找脚本
    local script_path="$project_dir/$script_name"
    if [ ! -f "$script_path" ]; then
        # 尝试在子目录查找
        script_path=$(find "$project_dir" -name "$script_name" -type f 2>/dev/null | head -1)
        [ -z "$script_path" ] && error "Script not found: $script_name"
    fi
    
    # 检测virtualenv
    local venv_path=""
    if [ -f "$project_dir/venv/bin/activate" ]; then
        venv_path="$project_dir/venv"
    elif [ -f "$project_dir/.venv/bin/activate" ]; then
        venv_path="$project_dir/.venv"
    fi
    
    # 生成session名称
    local session_name="pdb_$(basename "$script_name" .py)_$$"
    
    # 创建session
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
# 主程序
# ============================================================================

show_usage() {
    cat << EOF
PDB Session Manager - Python调试器Session管理

用法:
    $0 <command> [arguments...]

命令:
    # Session管理
    create <session> <script.py> [args]
        创建pdb session
        示例: $0 create mysession test.py --arg1 value1
    
    create-venv <session> <script.py> <venv_path> [args]
        创建pdb session（带virtualenv）
        示例: $0 create-venv mysession test.py ./venv
    
    quick-start <project_dir> <script.py> [args]
        快速启动（自动检测virtualenv）
    
    # 断点
    bp <session> <file:line>
        设置断点
        示例: $0 bp mysession main.py:10
    
    bp-cond <session> <file:line> <condition>
        设置条件断点
        示例: $0 bp-cond mysession main.py:10 "i > 5"
    
    bp-list <session>
        列出所有断点
    
    bp-clear <session> [bp_num]
        清除断点
    
    # 执行控制
    run <session>
        运行程序
    
    step <session>
        单步执行（进入函数）
    
    next <session>
        单步执行（不进入函数）
    
    cont <session>
        继续执行
    
    # 变量
    print <session> <expression>
        打印表达式
        示例: $0 print mysession "my_var"
    
    locals <session>
        列出局部变量
    
    list <session> [lines]
        列出源代码
    
    # 调用栈
    where <session>
        打印调用栈
    
    up <session>
        向上移动调用栈
    
    down <session>
        向下移动调用栈
    
    # 高级
    exec <session> <statement>
        执行Python语句
    
    watch <session> <expression>
        监视表达式
    
    # Session管理
    kill <session>
        终止session
    
    cleanup
        清理所有pdb session

EOF
}

# 入口
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
