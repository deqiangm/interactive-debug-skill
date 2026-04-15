#!/bin/bash
# ============================================================================
# JDB Watchpoint - 观察点支持（Watch Field Access/Modification）
# 
# 功能:
# 1. 设置字段访问观察点 (watch access Class.field)
# 2. 设置字段修改观察点 (watch modification Class.field)
# 3. 观察点列表管理
# 4. 观察点命中通知
# 
# JDB命令参考:
# - watch access <class>.<field>    在字段被读取时停止
# - watch modification <class>.<field> 在字段被修改时停止
# - watch all <class>.<field>       读取和修改都停止
# - unwatch <class>.<field>         移除观察点
# - watch                           列出所有观察点
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

WATCHPOINT_SESSION_PREFIX="jdb_wp"
WATCHPOINT_STORAGE_DIR="/tmp/jdb_watchpoints_$$"

# ============================================================================
# 观察点存储管理
# ============================================================================

# 初始化观察点存储
init_wp_storage() {
    mkdir -p "$WATCHPOINT_STORAGE_DIR"
}

# 清理观察点存储
cleanup_wp_storage() {
    rm -rf "$WATCHPOINT_STORAGE_DIR" 2>/dev/null || true
}

# 保存观察点信息
# 格式文件: session_class_field
save_watchpoint() {
    local session="$1"
    local class="$2"
    local field="$3"
    local type="$4"  # access, modification, all
    
    local key="${session}_${class}_${field}"
    local file="$WATCHPOINT_STORAGE_DIR/$key"
    
    cat > "$file" << EOF
SESSION=$session
CLASS=$class
FIELD=$field
TYPE=$type
ACTIVE=yes
HIT_COUNT=0
CREATED=$(date '+%Y-%m-%d %H:%M:%S')
EOF
    
    log_debug "Saved watchpoint: $class.$field ($type)"
}

# 加载观察点信息
load_watchpoint() {
    local session="$1"
    local class="$2"
    local field="$3"
    
    local key="${session}_${class}_${field}"
    local file="$WATCHPOINT_STORAGE_DIR/$key"
    
    if [ -f "$file" ]; then
        cat "$file"
    fi
}

# 更新命中计数
increment_wp_hit_count() {
    local session="$1"
    local class="$2"
    local field="$3"
    
    local key="${session}_${class}_${field}"
    local file="$WATCHPOINT_STORAGE_DIR/$key"
    
    if [ -f "$file" ]; then
        local count=$(grep "^HIT_COUNT=" "$file" | cut -d= -f2)
        count=$((count + 1))
        sed -i "s/^HIT_COUNT=.*/HIT_COUNT=$count/" "$file"
        echo "$count"
    else
        echo "0"
    fi
}

# 标记观察点为非活动
deactivate_watchpoint() {
    local session="$1"
    local class="$2"
    local field="$3"
    
    local key="${session}_${class}_${field}"
    local file="$WATCHPOINT_STORAGE_DIR/$key"
    
    if [ -f "$file" ]; then
        sed -i 's/^ACTIVE=.*/ACTIVE=no/' "$file"
    fi
}

# 列出所有观察点
list_all_watchpoints() {
    local session="$1"
    
    if [ -d "$WATCHPOINT_STORAGE_DIR" ]; then
        for file in "$WATCHPOINT_STORAGE_DIR"/${session}_*; do
            if [ -f "$file" ]; then
                local wp_class=$(grep "^CLASS=" "$file" | cut -d= -f2)
                local wp_field=$(grep "^FIELD=" "$file" | cut -d= -f2)
                local wp_type=$(grep "^TYPE=" "$file" | cut -d= -f2)
                local active=$(grep "^ACTIVE=" "$file" | cut -d= -f2)
                local hits=$(grep "^HIT_COUNT=" "$file" | cut -d= -f2)
                local created=$(grep "^CREATED=" "$file" | cut -d= -f2)
                
                echo "Watchpoint: ${wp_class}.${wp_field}"
                echo "  Type: $wp_type"
                echo "  Status: $active"
                echo "  Hits: $hits"
                echo "  Created: $created"
                echo ""
            fi
        done
    fi
}

# ============================================================================
# JDB观察点操作
# ============================================================================

# 设置访问观察点
# 用法: set_access_watchpoint <session> <class> <field>
set_access_watchpoint() {
    local session="$1"
    local class="$2"
    local field="$3"
    
    # 检查session是否存在
    if ! session_exists "$session"; then
        error "Session '$session' not found"
    fi
    
    # 初始化存储
    init_wp_storage
    
    log "Setting access watchpoint on $class.$field"
    
    # 发送JDB命令
    session_send "$session" "watch access ${class}.${field}"
    sleep 0.5
    
    # 保存观察点信息
    save_watchpoint "$session" "$class" "$field" "access"
    
    echo ""
    echo "============================================"
    echo "ACCESS WATCHPOINT SET"
    echo "============================================"
    echo "Class: $class"
    echo "Field: $field"
    echo "Type: access (stops when field is read)"
    echo ""
    echo "The debugger will stop when:"
    echo "  - Any code reads the value of $class.$field"
    echo "  - Includes getter method calls"
    echo "============================================"
    echo ""
    echo "Session: $session"
    echo "Use 'cont' to continue after hit"
    echo ""
}

# 设置修改观察点
# 用法: set_modification_watchpoint <session> <class> <field>
set_modification_watchpoint() {
    local session="$1"
    local class="$2"
    local field="$3"
    
    # 检查session是否存在
    if ! session_exists "$session"; then
        error "Session '$session' not found"
    fi
    
    # 初始化存储
    init_wp_storage
    
    log "Setting modification watchpoint on $class.$field"
    
    # 发送JDB命令
    session_send "$session" "watch modification ${class}.${field}"
    sleep 0.5
    
    # 保存观察点信息
    save_watchpoint "$session" "$class" "$field" "modification"
    
    echo ""
    echo "============================================"
    echo "MODIFICATION WATCHPOINT SET"
    echo "============================================"
    echo "Class: $class"
    echo "Field: $field"
    echo "Type: modification (stops when field is changed)"
    echo ""
    echo "The debugger will stop when:"
    echo "  - Any code modifies the value of $class.$field"
    echo "  - Includes setter method calls"
    echo "  - Includes direct field assignments"
    echo "============================================"
    echo ""
    echo "Session: $session"
    echo "Use 'cont' to continue after hit"
    echo ""
}

# 设置完全观察点（访问和修改）
# 用法: set_all_watchpoint <session> <class> <field>
set_all_watchpoint() {
    local session="$1"
    local class="$2"
    local field="$3"
    
    # 检查session是否存在
    if ! session_exists "$session"; then
        error "Session '$session' not found"
    fi
    
    # 初始化存储
    init_wp_storage
    
    log "Setting full watchpoint (access + modification) on $class.$field"
    
    # 发送JDB命令
    session_send "$session" "watch all ${class}.${field}"
    sleep 0.5
    
    # 保存观察点信息
    save_watchpoint "$session" "$class" "$field" "all"
    
    echo ""
    echo "============================================"
    echo "FULL WATCHPOINT SET"
    echo "============================================"
    echo "Class: $class"
    echo "Field: $field"
    echo "Type: all (stops on read AND write)"
    echo ""
    echo "The debugger will stop when:"
    echo "  - Any code reads the value of $class.$field"
    echo "  - Any code modifies the value of $class.$field"
    echo "============================================"
    echo ""
    echo "Session: $session"
    echo "Use 'cont' to continue after hit"
    echo ""
}

# 清除观察点
# 用法: clear_watchpoint <session> <class> <field>
clear_watchpoint() {
    local session="$1"
    local class="$2"
    local field="$3"
    
    if ! session_exists "$session"; then
        error "Session '$session' not found"
    fi
    
    log "Clearing watchpoint on $class.$field"
    
    # 发送JDB命令
    session_send "$session" "unwatch ${class}.${field}"
    sleep 0.5
    
    # 标记为非活动
    deactivate_watchpoint "$session" "$class" "$field"
    
    echo "Watchpoint cleared: $class.$field"
}

# 清除所有观察点
# 用法: clear_all_watchpoints <session>
clear_all_watchpoints() {
    local session="$1"
    
    if ! session_exists "$session"; then
        error "Session '$session' not found"
    fi
    
    log "Clearing all watchpoints for session: $session"
    
    # 发送JDB命令清除所有
    session_send "$session" "watch"
    sleep 0.5
    
    # 获取所有观察点并清除
    if [ -d "$WATCHPOINT_STORAGE_DIR" ]; then
        for file in "$WATCHPOINT_STORAGE_DIR"/${session}_*; do
            if [ -f "$file" ]; then
                local wp_class=$(grep "^CLASS=" "$file" | cut -d= -f2)
                local wp_field=$(grep "^FIELD=" "$file" | cut -d= -f2)
                session_send "$session" "unwatch ${wp_class}.${wp_field}" 2>/dev/null || true
                deactivate_watchpoint "$session" "$wp_class" "$wp_field"
            fi
        done
    fi
    
    echo "All watchpoints cleared for session: $session"
}

# 列出JDB中的观察点
# 用法: list_jdb_watchpoints <session>
list_jdb_watchpoints() {
    local session="$1"
    
    if ! session_exists "$session"; then
        error "Session '$session' not found"
    fi
    
    echo "Listing watchpoints from JDB..."
    session_send "$session" "watch"
    sleep 1
    session_read "$session"
}

# ============================================================================
# 监控观察点命中
# ============================================================================

# 监控观察点命中（后台运行）
# 用法: monitor_watchpoint <session> <class> <field> [check_interval]
monitor_watchpoint() {
    local session="$1"
    local class="$2"
    local field="$3"
    local interval="${4:-1}"
    
    # 加载观察点信息
    local wp_info=$(load_watchpoint "$session" "$class" "$field")
    if [ -z "$wp_info" ]; then
        error "No watchpoint found on $class.$field"
    fi
    
    local wp_type=$(echo "$wp_info" | grep "^TYPE=" | cut -d= -f2)
    
    log "Starting watchpoint monitor for $class.$field"
    log "Type: $wp_type, Interval: ${interval}s"
    
    # 观察点命中的输出模式
    # JDB输出格式: "Field access/update: ..."
    local hit_pattern="Field (access|modification|update).*${class}"
    
    while true; do
        sleep "$interval"
        
        # 检查观察点是否仍然活动
        local active=$(echo "$wp_info" | grep "^ACTIVE=" | cut -d= -f2 2>/dev/null || echo "no")
        if [ "$active" = "no" ]; then
            log "Watchpoint deactivated, stopping monitor"
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
            local hit_count=$(increment_wp_hit_count "$session" "$class" "$field")
            
            echo ""
            echo "============================================"
            echo "${GREEN}WATCHPOINT HIT #$hit_count${NC}"
            echo "============================================"
            echo "Class: $class"
            echo "Field: $field"
            echo "Type: $wp_type"
            echo "============================================"
            echo ""
            echo "Useful commands:"
            echo "  dump ${class}.this  - Dump current object"
            echo "  locals              - Show local variables"
            echo "  where               - Show call stack"
            echo "  cont                - Continue execution"
            echo ""
        fi
    done
}

# ============================================================================
# 高级功能：智能观察点建议
# ============================================================================

# 分析类字段并建议观察点
# 用法: suggest_watchpoints <session> <class>
suggest_watchpoints() {
    local session="$1"
    local class="$2"
    
    if ! session_exists "$session"; then
        error "Session '$session' not found"
    fi
    
    log "Analyzing class $class for watchpoint suggestions..."
    
    # 获取类的字段信息
    session_send "$session" "fields $class"
    sleep 1
    
    local output=$(session_read "$session")
    
    echo ""
    echo "============================================"
    echo "WATCHPOINT SUGGESTIONS FOR $class"
    echo "============================================"
    echo ""
    echo "Available fields (from JDB output):"
    echo "$output" | grep -E "^[[:space:]]*(private|public|protected)" || echo "  (Could not parse fields)"
    echo ""
    echo "Suggested watchpoints:"
    echo ""
    echo "For debugging state changes:"
    echo "  $0 mod $session $class <field>"
    echo ""
    echo "For debugging unexpected reads:"
    echo "  $0 access $session $class <field>"
    echo ""
    echo "For full monitoring:"
    echo "  $0 all $session $class <field>"
    echo "============================================"
}

# ============================================================================
# 帮助和主程序
# ============================================================================

show_help() {
    cat << EOF
jdb_watchpoint.sh - JDB观察点支持（监控字段访问和修改）

用法:
    $0 <command> [arguments...]

命令:
    access <session> <class> <field>
        设置访问观察点（字段被读取时停止）
        
    mod <session> <class> <field>
        设置修改观察点（字段被修改时停止）
        
    all <session> <class> <field>
        设置完全观察点（读取和修改都停止）
        
    clear <session> <class> <field>
        清除指定观察点
        
    clear-all <session>
        清除所有观察点
        
    list <session>
        列出所有观察点（本地存储）
        
    list-jdb <session>
        列出JDB中的活动观察点
        
    monitor <session> <class> <field> [interval]
        后台监控观察点命中
        
    suggest <session> <class>
        分析类并建议观察点

观察点类型说明:
    access      - 调试器在以下情况停止:
                  * 任何代码读取该字段值
                  * getter方法访问该字段
                  
    modification - 调试器在以下情况停止:
                  * 任何代码修改该字段值
                  * setter方法修改该字段
                  * 直接字段赋值
                  
    all         - 以上两种情况都触发

示例:
    # 设置修改观察点（监控字段变化）
    $0 mod my_session com.example.User name
    
    # 设置访问观察点（监控谁在读取字段）
    $0 access my_session com.example.UserService users
    
    # 设置完全观察点
    $0 all my_session com.example.Counter count
    
    # 列出所有观察点
    $0 list my_session
    
    # 清除观察点
    $0 clear my_session com.example.User name
    
    # 清除所有观察点
    $0 clear-all my_session
    
    # 监控观察点命中
    $0 monitor my_session com.example.User name 0.5
    
    # 获取观察点建议
    $0 suggest my_session com.example.User

注意事项:
    1. 观察点可能显著降低程序执行速度
    2. 建议仅在必要时设置观察点
    3. 调试完成后及时清除观察点
    4. 类名需使用全限定名（如 com.example.ClassName）

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
    access)
        [ $# -lt 3 ] && error "Usage: $0 access <session> <class> <field>"
        set_access_watchpoint "$1" "$2" "$3"
        ;;
    mod|modification)
        [ $# -lt 3 ] && error "Usage: $0 mod <session> <class> <field>"
        set_modification_watchpoint "$1" "$2" "$3"
        ;;
    all)
        [ $# -lt 3 ] && error "Usage: $0 all <session> <class> <field>"
        set_all_watchpoint "$1" "$2" "$3"
        ;;
    clear)
        [ $# -lt 3 ] && error "Usage: $0 clear <session> <class> <field>"
        clear_watchpoint "$1" "$2" "$3"
        ;;
    clear-all)
        [ $# -lt 1 ] && error "Usage: $0 clear-all <session>"
        clear_all_watchpoints "$1"
        ;;
    list)
        [ $# -lt 1 ] && error "Usage: $0 list <session>"
        list_all_watchpoints "$1"
        ;;
    list-jdb)
        [ $# -lt 1 ] && error "Usage: $0 list-jdb <session>"
        list_jdb_watchpoints "$1"
        ;;
    monitor)
        [ $# -lt 3 ] && error "Usage: $0 monitor <session> <class> <field> [interval]"
        monitor_watchpoint "$1" "$2" "$3" "${4:-1}"
        ;;
    suggest)
        [ $# -lt 2 ] && error "Usage: $0 suggest <session> <class>"
        suggest_watchpoints "$1" "$2"
        ;;
    *)
        error "Unknown command: $command. Use --help for usage."
        ;;
esac

# 清理
trap cleanup_wp_storage EXIT
