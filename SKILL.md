# Interactive Debug Skill

系统化的交互式调试技能，支持多种编程语言的智能调试工作流。

## 支持的语言

| 语言 | 调试器 | 状态 |
|------|--------|------|
| Java | jdb | ✅ 已实现 |
| Python | pdb | 🚧 计划中 |
| Go | dlv | 🚧 计划中 |
| Rust | rust-gdb | 🚧 计划中 |
| Node.js | node inspect | 🚧 计划中 |

## 核心理念

1. **Session隔离** - 每个调试会话独立运行在tmux中
2. **LLM驱动** - AI分析调试输出，决策下一步操作
3. **自动化优先** - 自动解析项目配置，减少手动设置
4. **Shell为主** - 尽量使用shell脚本，减少复杂依赖

## Java/jdb 使用

### 快速开始

```bash
cd languages/java/scripts

# 列出Java进程
./jdb_quick_start.sh --list-java

# Attach到进程
./jdb_quick_start.sh /path/to/project --attach <pid>

# 从main class启动
./jdb_quick_start.sh /path/to/project --main com.example.Main --breakpoint Main:10
```

### 核心工具

| 工具 | 功能 |
|------|------|
| `jdb_session.sh` | Tmux session管理 |
| `classpath_resolver.sh` | Maven/Gradle classpath解析 |
| `jdb_ai_bridge.sh` | LLM集成桥接 |
| `jdb_quick_start.sh` | 一键启动 |

### 调试循环

```
┌──────────────────────────────────────────────┐
│                                              │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐  │
│  │  JDB    │───▶│ 解析    │───▶│  LLM    │  │
│  │ 输出    │    │ 输出    │    │ 决策    │  │
│  └─────────┘    └─────────┘    └─────────┘  │
│       ▲                               │      │
│       │                               ▼      │
│       │                        ┌──────────┐ │
│       └────────────────────────│ 执行命令 │ │
│                                └──────────┘ │
│                                              │
└──────────────────────────────────────────────┘
```

### 常用命令

```bash
# Session管理
./jdb_session.sh create my_session "jdb -attach 12345"
./jdb_session.sh list
./jdb_session.sh exec my_session "where"
./jdb_session.sh kill my_session

# JDB命令
./jdb_session.sh exec $SESSION "cont"        # 继续
./jdb_session.sh exec $SESSION "step"        # 单步进入
./jdb_session.sh exec $SESSION "next"        # 单步跳过
./jdb_session.sh exec $SESSION "where"       # 调用栈
./jdb_session.sh exec $SESSION "print x"     # 打印变量
./jdb_session.sh exec $SESSION "dump obj"    # 对象详情
./jdb_session.sh exec $SESSION "threads"     # 线程列表
```

## 扩展其他语言

添加新语言调试支持：

1. 创建 `languages/<lang>/scripts/` 目录
2. 实现核心脚本：
   - `<debugger>_session.sh` - Session管理
   - `<debugger>_quick_start.sh` - 快速启动
3. 添加README和示例

## 配置

环境变量：

```bash
# LLM配置
export LLM_PROVIDER=anthropic
export LLM_MODEL=claude-3-opus
export ANTHROPIC_API_KEY=your-key

# 调试配置
export MAX_DEBUG_ITERATIONS=30
export DEBUG_WAIT_TIMEOUT=2
```

## 相关文件

- `languages/java/` - Java/jdb实现
- `languages/java/scripts/` - Shell脚本
- `languages/java/templates/` - 调试模板（计划中）
