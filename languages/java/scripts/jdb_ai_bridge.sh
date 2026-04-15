#!/bin/bash
# ============================================================================
# JDB AI Bridge - LLM与JDB之间的桥接层
# 
# 工作流程:
# 1. 执行JDB命令
# 2. 捕获输出
# 3. 构建prompt发送给LLM
# 4. LLM返回下一步指令
# 5. 循环直到调试完成
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/jdb_session.sh"

# ============================================================================
# 配置
# ============================================================================

DEFAULT_LLM_PROVIDER="${LLM_PROVIDER:-anthropic}"
DEFAULT_LLM_MODEL="${LLM_MODEL:-claude-3-opus}"
MAX_ITERATIONS=30
CONTEXT_HISTORY_SIZE=10

# ============================================================================
# LLM 调用
# ============================================================================

# 调用LLM API (使用hermes内置的LLM能力，或curl直接调用)
call_llm() {
    local prompt="$1"
    local provider="${LLM_PROVIDER:-$DEFAULT_LLM_PROVIDER}"
    local model="${LLM_MODEL:-$DEFAULT_LLM_MODEL}"
    
    # 使用环境变量中的API配置
    local api_key=""
    local api_url=""
    
    case "$provider" in
        anthropic)
            api_key="${ANTHROPIC_API_KEY:-}"
            api_url="https://api.anthropic.com/v1/messages"
            ;;
        openai)
            api_key="${OPENAI_API_KEY:-}"
            api_url="https://api.openai.com/v1/chat/completions"
            ;;
        custom)
            api_key="${CUSTOM_API_KEY:-}"
            api_url="${CUSTOM_API_URL:-}"
            ;;
        *)
            echo "ERROR: Unsupported LLM provider: $provider" >&2
            return 1
            ;;
    esac
    
    if [ -z "$api_key" ]; then
        echo "ERROR: API key not set for provider: $provider" >&2
        return 1
    fi
    
    # 调用API (简化版，实际应该用Python或更完善的HTTP客户端)
    # 这里输出prompt，让外部调用者处理LLM响应
    echo "$prompt"
}

# 构建LLM prompt
build_llm_prompt() {
    local session_name="$1"
    local jdb_output="$2"
    local context_file="$3"
    
    # 读取上下文
    local breakpoints=""
    local call_stack=""
    local variables=""
    local history=""
    
    if [ -f "$context_file" ]; then
        source "$context_file"
    fi
    
    cat << PROMPT_EOF
你是一个Java调试专家。当前正在使用jdb调试Java程序。

## 当前调试状态

### 断点列表
$breakpoints

### 调用栈 (最近5层)
$call_stack

### 关键变量
$variables

### 最近执行历史
$history

## JDB最新输出
\`\`\`
$jdb_output
\`\`\`

## 你的任务

分析上面的输出，决定下一步操作。

响应格式（必须是有效的JSON）：
{
    "analysis": "分析当前状态，描述你看到了什么",
    "action": "下一步jdb命令",
    "reason": "为什么选择这个操作",
    "is_complete": false,
    "finding": "如果发现问题，在这里描述"
}

允许的action命令：
- "step" - 单步执行（进入方法）
- "next" - 单步执行（不进入方法）
- "cont" - 继续执行到下一个断点
- "print <表达式>" - 打印变量值
- "dump <对象>" - 打印对象详细信息
- "where" - 查看调用栈
- "locals" - 查看局部变量
- "threads" - 查看所有线程
- "stop at <类>:<行>" - 设置断点
- "stop in <类>.<方法>" - 设置方法断点
- "quit" - 结束调试

如果已经找到问题根因，设置 is_complete=true，并在 finding 中说明发现。
PROMPT_EOF
}

# 解析LLM响应
parse_llm_response() {
    local response="$1"
    
    # 提取JSON部分（假设响应包含JSON）
    local json=$(echo "$response" | grep -oE '\{[^}]*"action"[^}]*\}' | head -1)
    
    if [ -z "$json" ]; then
        echo '{"action": "where", "reason": "Failed to parse LLM response", "is_complete": false}'
        return
    fi
    
    echo "$json"
}

# ============================================================================
# 上下文管理
# ============================================================================

# 创建上下文文件
create_context() {
    local session_name="$1"
    local context_file="/tmp/jdb_context_${session_name}.sh"
    
    cat > "$context_file" << 'EOF'
# JDB Debug Context
BREAKPOINTS=""
CALL_STACK=""
VARIABLES=""
HISTORY=""
ITERATION=0
EOF
    
    echo "$context_file"
}

# 更新上下文
update_context() {
    local context_file="$1"
    local key="$2"
    local value="$3"
    
    # 追加或更新上下文变量
    sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$context_file" 2>/dev/null || \
        echo "${key}=\"${value}\"" >> "$context_file"
}

# ============================================================================
# 调试循环
# ============================================================================

# 运行AI驱动的调试会话
run_ai_debug_session() {
    local session_name="$1"
    local initial_command="${2:-cont}"
    local context_file=$(create_context "$session_name")
    
    log "Starting AI debug session: $session_name"
    log "Context file: $context_file"
    
    # 执行初始命令
    local output=$(session_exec "$session_name" "$initial_command" 2)
    log "Initial output: $output"
    
    # 主循环
    for ((i=1; i<=MAX_ITERATIONS; i++)); do
        log "=== Iteration $i ==="
        
        # 构建prompt
        local prompt=$(build_llm_prompt "$session_name" "$output" "$context_file")
        
        # 调用LLM (这里输出prompt，实际需要外部LLM处理)
        log "Calling LLM..."
        echo ""
        echo "=== LLM PROMPT ==="
        echo "$prompt"
        echo "=== END PROMPT ==="
        echo ""
        
        # 等待外部LLM响应（通过环境变量或文件）
        # 这里需要外部系统提供LLM响应
        # 简化版本：等待用户输入
        echo "Enter LLM response (JSON format):"
        read -r llm_response
        
        # 解析响应
        local decision=$(parse_llm_response "$llm_response")
        local action=$(echo "$decision" | jq -r '.action')
        local is_complete=$(echo "$decision" | jq -r '.is_complete')
        local finding=$(echo "$decision" | jq -r '.finding // empty')
        
        log "Action: $action"
        log "Is complete: $is_complete"
        
        # 检查是否完成
        if [ "$is_complete" = "true" ] || [ "$action" = "quit" ]; then
            log "Debug session completed"
            if [ -n "$finding" ]; then
                log "Finding: $finding"
            fi
            return 0
        fi
        
        # 执行动作
        output=$(session_exec "$session_name" "$action" 2)
        
        # 更新历史
        update_context "$context_file" "HISTORY" "$action\n$HISTORY"
        update_context "$context_file" "ITERATION" "$i"
        
        # 短暂暂停
        sleep 0.5
    done
    
    log "Max iterations reached"
    return 1
}

# ============================================================================
# 简化的交互模式（不需要外部LLM，直接交互）
# ============================================================================

run_interactive_session() {
    local session_name="$1"
    
    log "Starting interactive debug session: $session_name"
    log "Type 'quit' to exit, 'help' for commands"
    
    while true; do
        echo ""
        echo -n "jdb> "
        read -r command
        
        case "$command" in
            quit|exit)
                session_kill "$session_name"
                break
                ;;
            help)
                echo "Commands: step, next, cont, print <expr>, dump <expr>, where, threads, locals, quit"
                ;;
            *)
                output=$(session_exec "$session_name" "$command" 1)
                echo "$output"
                ;;
        esac
    done
}

# ============================================================================
# 主程序
# ============================================================================

show_usage() {
    cat << EOF
JDB AI Bridge - LLM与JDB之间的桥接层

用法:
    $0 <command> [arguments...]

命令:
    start-interactive <session_name>    启动交互式调试会话
    start-ai <session_name>             启动AI驱动的调试会话
    build-prompt <session> <output>     构建LLM prompt
    exec <session> <command>            执行命令并获取输出

环境变量:
    LLM_PROVIDER    - LLM提供商 (anthropic, openai, custom)
    LLM_MODEL       - 模型名称
    ANTHROPIC_API_KEY - Anthropic API密钥
    OPENAI_API_KEY  - OpenAI API密钥

示例:
    # 启动交互式会话
    $0 start-interactive my_session
    
    # 启动AI驱动会话（需要外部LLM集成）
    $0 start-ai my_session
    
    # 执行命令
    $0 exec my_session "print user.name"

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
    start-interactive)
        [ $# -lt 1 ] && error "Usage: $0 start-interactive <session_name>"
        run_interactive_session "$1"
        ;;
    start-ai)
        [ $# -lt 1 ] && error "Usage: $0 start-ai <session_name>"
        run_ai_debug_session "$1"
        ;;
    build-prompt)
        [ $# -lt 3 ] && error "Usage: $0 build-prompt <session> <output> <context_file>"
        build_llm_prompt "$1" "$2" "$3"
        ;;
    exec)
        [ $# -lt 2 ] && error "Usage: $0 exec <session> <command>"
        session_exec "$1" "$2"
        ;;
    *)
        error "Unknown command: $command"
        ;;
esac
