#!/bin/bash
# ============================================================================
# 配置文件模板
# ============================================================================

# 调试器配置
DEBUG_CONFIG="${DEBUG_CONFIG:-$HOME/.config/debug-tools/config.yaml}"

# 默认值
DEFAULT_JAVA_DEBUG_PORT=5005
DEFAULT_PYTHON_DEBUG_PORT=5678
DEFAULT_GO_DEBUG_PORT=38697
DEFAULT_NODE_DEBUG_PORT=9229

# Poll配置
DEFAULT_POLL_INTERVAL=0.5
DEFAULT_POLL_TIMEOUT=60
DEFAULT_STABLE_COUNT=2

# Session配置
DEFAULT_TMUX_WIDTH=200
DEFAULT_TMUX_HEIGHT=50

# 日志配置
DEFAULT_LOG_LEVEL="INFO"

# 断点配置
MAX_BREAKPOINTS=100
MAX_WATCHPOINTS=50

# 远程调试配置
REMOTE_CONNECT_TIMEOUT=10
REMOTE_RETRY_COUNT=3

# LLM配置（可选）
LLM_PROVIDER="${LLM_PROVIDER:-openai}"
LLM_MODEL="${LLM_MODEL:-gpt-4}"
LLM_API_KEY="${LLM_API_KEY:-}"
