#!/bin/bash
# ============================================================================
# Configuration Template - Default settings for debugging tools
# ============================================================================

# Debugger configuration file path
DEBUG_CONFIG="${DEBUG_CONFIG:-$HOME/.config/debug-tools/config.yaml}"

# Default debug ports by language
DEFAULT_JAVA_DEBUG_PORT=5005
DEFAULT_PYTHON_DEBUG_PORT=5678
DEFAULT_GO_DEBUG_PORT=38697
DEFAULT_NODE_DEBUG_PORT=9229

# Poll configuration
DEFAULT_POLL_INTERVAL=0.5
DEFAULT_POLL_TIMEOUT=60
DEFAULT_STABLE_COUNT=2

# Session configuration
DEFAULT_TMUX_WIDTH=200
DEFAULT_TMUX_HEIGHT=50

# Logging configuration
DEFAULT_LOG_LEVEL="INFO"

# Breakpoint limits
MAX_BREAKPOINTS=100
MAX_WATCHPOINTS=50

# Remote debug configuration
REMOTE_CONNECT_TIMEOUT=10
REMOTE_RETRY_COUNT=3

# LLM configuration (optional)
LLM_PROVIDER="${LLM_PROVIDER:-openai}"
LLM_MODEL="${LLM_MODEL:-gpt-4}"
LLM_API_KEY="${LLM_API_KEY:-}"
