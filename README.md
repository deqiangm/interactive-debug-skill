# Interactive Debug Skill Enhancement

> 基于tmux的LLM驱动智能调试工作流增强项目

[![Status](https://img.shields.io/badge/Status-🚧%20进行中-yellow)](docs/CHECKLIST.md)
[![Languages](https://img.shields.io/badge/Languages-Java%20%7C%20Python%20%7C%20Go%20%7C%20Node.js-blue)](#支持的编程语言)

---

## 📖 概述

Interactive Debug Skill Enhancement 是一个增强调试能力的工具集，提供：

- **多语言调试支持**: Java (jdb), Python (pdb), Go (delve), Node.js (node inspect)
- **高级断点功能**: 条件断点、临时断点、观察点、方法断点、异常断点
- **LLM集成**: 智能断点建议、问题诊断分析、根因分析报告
- **Tmux会话隔离**: 每个调试会话运行在独立的tmux会话中

## 🚀 快速开始

### 前置要求

- Bash 4.0+
- tmux 3.0+
- bc (计算器)
- jq (可选，用于JSON处理)

```bash
# 检查依赖
./common/functions.sh  # 会自动检查依赖

# Ubuntu/Debian
sudo apt-get install tmux bc jq

# macOS
brew install tmux bc jq
```

### 安装

```bash
# 克隆仓库
git clone https://github.com/deqiangm/interactive-debug-skill.git
cd interactive-debug-skill

# 添加到PATH（可选）
export PATH="$PWD/languages/java/scripts:$PATH"
```

### 快速示例

#### Java调试

```bash
# 启动JDB调试会话
./languages/java/scripts/jdb_advanced_bp.sh start MyProgram

# 设置条件断点
./languages/java/scripts/jdb_advanced_bp.sh cond-bp MyClass:42 "i > 10"

# 设置观察点
./languages/java/scripts/jdb_advanced_bp.sh watch MyClass.counter
```

## 📁 项目结构

```
interactive-debug-skill-enhancement/
├── README.md                    # 本文件
├── common/                      # 公共模块
│   ├── functions.sh             # 公共函数库
│   └── config.sh                # 配置文件模板
├── languages/                   # 语言特定实现
│   ├── java/
│   │   ├── scripts/             # Java调试脚本
│   │   │   └── jdb_advanced_bp.sh
│   │   └── templates/           # Java模板文件
│   ├── python/
│   │   ├── scripts/             # Python调试脚本
│   │   │   └── pdb_session.sh
│   │   └── templates/
│   ├── go/
│   │   ├── scripts/
│   │   └── templates/
│   └── nodejs/
│       ├── scripts/
│       └── templates/
├── docs/                        # 文档
│   ├── PLAN.md                  # 项目计划
│   ├── CHECKLIST.md             # 任务清单
│   └── WORKLOG.md               # 工作日志
└── tests/                       # 测试用例
```

## 🔧 核心功能

### 1. 公共函数库 (common/functions.sh)

提供所有调试脚本共用的基础功能：

#### 日志系统

```bash
source common/functions.sh

log_info "信息消息"      # 正常输出
log_debug "调试信息"     # 仅在LOG_LEVEL=DEBUG时显示
log_warn "警告信息"      # 黄色警告
log_error "错误信息"     # 红色错误，输出到stderr
```

#### Tmux Session 管理

```bash
# 创建会话
session_create "my_debug_session" "jdb MyProgram"

# 发送命令
session_send "my_debug_session" "stop at MyClass:10"

# 读取输出
output=$(session_read "my_debug_session")

# Poll等待输出完成
session_poll "my_debug_session" 30  # 30秒超时

# 执行命令并poll
session_exec_poll "my_debug_session" "print var" 10

# 等待特定模式
session_wait_for "my_debug_session" "Breakpoint hit" 30

# 终止会话
session_kill "my_debug_session"

# 清理所有匹配前缀的会话
session_cleanup "jdb_"

# 列出所有会话
session_list "jdb_"
```

#### 网络工具

```bash
# 检查端口是否可用
check_port localhost 5005

# 等待端口可用
wait_for_port localhost 5005 30  # 30秒超时
```

#### 文件工具

```bash
# 查找项目根目录
root=$(find_project_root .)

# 检测项目类型 (maven, gradle, go, nodejs, python, rust)
type=$(detect_project_type /path/to/project)
```

### 2. Java高级断点 (languages/java/scripts/jdb_advanced_bp.sh)

#### 条件断点

当满足特定条件时才触发的断点：

```bash
# 在第42行设置条件断点，当i > 10时触发
./jdb_advanced_bp.sh cond-bp MyClass:42 "i > 10"

# 在循环中设置条件断点
./jdb_advanced_bp.sh cond-bp BubbleSort:15 "arr[j] > arr[j+1]"
```

#### 临时断点

只触发一次后自动删除：

```bash
# 设置临时断点
./jdb_advanced_bp.sh temp-bp MyClass:100

# 命中后自动清除
```

#### 观察点 (Watchpoint)

监控字段访问和修改：

```bash
# 监控字段访问
./jdb_advanced_bp.sh watch-access MyClass.counter

# 监控字段修改
./jdb_advanced_bp.sh watch-modify MyClass.balance
```

#### 方法断点

在方法入口/出口暂停：

```bash
# 方法入口断点
./jdb_advanced_bp.sh method-bp MyClass.processData

# 方法入口和出口都暂停
./jdb_advanced_bp.sh method-bp MyClass.processData --exit
```

#### 异常断点

当抛出指定异常时暂停：

```bash
# 捕获NullPointerException
./jdb_advanced_bp.sh exception-bp java.lang.NullPointerException

# 捕获所有异常
./jdb_advanced_bp.sh exception-bp all
```

### 3. Python调试 (pdb_session.sh)

```bash
# 启动pdb会话
./pdb_session.sh start script.py

# 远程attach
./pdb_session.sh remote-attach localhost 4444
```

## 📋 命名约定

| 模式 | 用途 | 示例 |
|------|------|------|
| `<debugger>_session.sh` | Session管理 | `jdb_session.sh`, `pdb_session.sh` |
| `<debugger>_remote_attach.sh` | 远程attach | `jdb_remote_attach.sh` |
| `<debugger>_quick_start.sh` | 快速启动 | `jdb_quick_start.sh` |
| `<debugger>_<feature>.sh` | 特定功能 | `jdb_advanced_bp.sh` |

## 🧪 测试

```bash
# 运行Java冒泡排序调试测试
./tests/test_java_bubble_sort.sh

# 运行条件断点功能测试
./tests/test_conditional_breakpoint.sh
```

## 📚 文档

- [PLAN.md](docs/PLAN.md) - 项目计划和技术架构
- [CHECKLIST.md](docs/CHECKLIST.md) - 任务清单和进度追踪
- [WORKLOG.md](docs/WORKLOG.md) - 工作日志和决策记录

## 🔗 相关项目

- [interactive-debug-skill](https://github.com/deqiangm/interactive-debug-skill) - 原始skill定义
- [Hermes Agent](https://github.com/nousresearch/hermes) - AI Agent框架

## 📝 开发状态

详见 [CHECKLIST.md](docs/CHECKLIST.md)

### 已完成 ✅
- Phase 1: 项目基础设施
  - 目录结构
  - 公共函数库
  - 配置文件模板

### 进行中 🚧
- Phase 2: Java高级断点功能
  - 条件断点 (已完成)
  - 临时断点 (已完成)
  - 观察点 (已完成)
  - 方法断点 (已完成)
  - 异常断点 (已完成)

### 计划中 📋
- Phase 3: Python调试支持
- Phase 4: Go调试支持
- Phase 5: Node.js调试支持
- Phase 6: LLM集成

## 🤝 贡献

欢迎贡献！请查看 [CHECKLIST.md](docs/CHECKLIST.md) 了解当前任务。

## 📄 许可证

MIT License

---

*由 Hermes Agent 自动维护*
