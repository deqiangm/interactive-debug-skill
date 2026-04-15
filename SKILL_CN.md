---
name: interactive-debug-skill-enhancement
description: 基于tmux的LLM驱动智能调试工作流增强版，支持多语言调试和高级断点功能
version: 1.0.0
tags: [debug, jdb, pdb, dlv, node-inspect, tmux, poll, breakpoint, llm]
---

# Interactive Debug Skill Enhancement

基于tmux的LLM驱动智能调试工作流增强版。

## 核心理念

1. **Session隔离** - 每个调试会话独立运行在tmux中
2. **Poll等待** - 智能等待调试器输出完成
3. **LLM驱动** - AI分析输出，决策下一步操作
4. **Shell优先** - 尽量使用shell脚本，减少复杂依赖
5. **多语言支持** - 统一接口，语言特定实现

## 项目位置

**增强版项目**: `~/.hermes/cron/interactive-debug-skill-enhancement/`

**GitHub**: https://github.com/deqiangm/interactive-debug-skill

## 支持的语言

| 语言 | 调试器 | 状态 | 核心脚本 |
|------|--------|------|---------|
| Java | jdb | ✅ 已实现 | `jdb_advanced_bp.sh` |
| Python | pdb | ✅ 已实现 | `pdb_session.sh` |
| Go | delve | 🚧 计划中 | `dlv_session.sh` |
| Node.js | node inspect | 🚧 计划中 | `node_session.sh` |

## 项目结构

```
interactive-debug-skill-enhancement/
├── SKILL.md                    # 本文件 - skill定义
├── README.md                   # 项目文档
├── common/                     # 公共模块
│   ├── functions.sh            # 公共函数库
│   └── config.sh               # 配置模板
├── languages/                  # 语言特定实现
│   ├── java/
│   │   ├── scripts/
│   │   │   └── jdb_advanced_bp.sh
│   │   └── templates/
│   ├── python/
│   │   ├── scripts/
│   │   │   └── pdb_session.sh
│   │   └── templates/
│   ├── go/
│   │   ├── scripts/
│   │   └── templates/
│   └── nodejs/
│       ├── scripts/
│       └── templates/
├── docs/
│   ├── PLAN.md                 # 项目计划
│   ├── CHECKLIST.md            # 任务追踪
│   └── WORKLOG.md              # 工作日志
└── tests/                      # 测试用例
```

---

## 快速开始

### 前置要求

- Bash 4.0+
- tmux 3.0+
- bc (计算器)
- jq (可选，用于JSON处理)

```bash
# 检查依赖
source ~/.hermes/cron/interactive-debug-skill-enhancement/common/functions.sh

# Ubuntu/Debian
sudo apt-get install tmux bc jq

# macOS
brew install tmux bc jq
```

### Java调试示例

```bash
cd ~/.hermes/cron/interactive-debug-skill-enhancement

# 1. 编译（带调试信息）
javac -g -d target/classes src/main/java/demo/BubbleSort.java

# 2. 创建调试session
source common/functions.sh
session_create "bubble" "jdb -classpath target/classes demo.BubbleSort"

# 3. 设置断点
session_exec_poll "bubble" "stop at demo.BubbleSort:11" 10

# 4. 运行
session_exec_poll "bubble" "run" 30

# 5. 查看变量
session_exec_poll "bubble" "locals" 5
session_exec_poll "bubble" "dump arr" 5

# 6. 清理
session_kill "bubble"
```

### Python调试示例

```bash
cd ~/.hermes/cron/interactive-debug-skill-enhancement

# 启动pdb会话
./languages/python/scripts/pdb_session.sh quick-start /path/to/project main.py

# 设置断点
./languages/python/scripts/pdb_session.sh bp mysession main.py:10

# 运行
./languages/python/scripts/pdb_session.sh run mysession

# 查看变量
./languages/python/scripts/pdb_session.sh print mysession "arr"
```

---

## 公共函数库 (common/functions.sh)

### 日志系统

```bash
source common/functions.sh

log_info "信息消息"      # 正常输出
log_debug "调试信息"     # 仅在LOG_LEVEL=DEBUG时显示
log_warn "警告信息"      # 黄色警告
log_error "错误信息"     # 红色错误，输出到stderr
```

### Tmux Session 管理

```bash
# 创建session
session_create "my_session" "jdb MyProgram"

# 发送命令
session_send "my_session" "stop at MyClass:10"

# 读取输出
output=$(session_read "my_session")

# Poll等待输出完成（智能等待）
session_poll "my_session" 30 0.5  # timeout=30s, interval=0.5s

# 执行命令并poll
session_exec_poll "my_session" "print var" 10

# 等待特定模式
session_wait_for "my_session" "Breakpoint hit" 30

# 终止session
session_kill "my_session"

# 清理所有匹配前缀的session
session_cleanup "jdb_"

# 列出所有session
session_list "jdb_"
```

### 网络工具

```bash
# 检查端口是否可用
check_port localhost 5005

# 等待端口可用
wait_for_port localhost 5005 30  # 30秒超时
```

### 文件工具

```bash
# 查找项目根目录
root=$(find_project_root .)

# 检测项目类型 (maven, gradle, go, nodejs, python, rust)
type=$(detect_project_type /path/to/project)
```

---

## Poll机制详解

### 核心问题

发送命令后如何等待调试器输出完成？

### 解决方案

Poll机制 - 智能等待输出完成：

```
┌─────────────────────────────────────────────────────┐
│                  Poll机制                           │
├─────────────────────────────────────────────────────┤
│ 默认参数:                                          │
│   - poll间隔: 0.5秒                                │
│   - 超时: 60秒 (120次poll)                        │
│                                                    │
│ 完成条件 (满足任一即返回):                         │
│   1. 检测到提示符 (如 "main[1]" 或 ">")           │
│   2. 输出稳定 (连续2次poll相同)                   │
│   3. 超时返回当前内容 (退出码124)                 │
└─────────────────────────────────────────────────────┘
```

### Poll实现原理

```bash
session_poll() {
  local timeout="${2:-60}"
  local poll_interval="${3:-0.5}"
  
  while [ $poll_count -lt $max_polls ]; do
    sleep "$poll_interval"
    current_output=$(session_read "$session_name")
    
    # 条件1：检测到提示符
    if echo "$current_output" | grep -qE "$prompt_pattern"; then
      return 0  # 正常完成
    fi
    
    # 条件2：输出稳定（连续2次相同）
    if [ "$current_output" = "$prev_output" ]; then
      stable_count++
      if [ $stable_count -ge 2 ]; then
        return 0
      fi
    fi
  done
  
  return 124  # 超时
}
```

### 等待时间建议

| 操作类型 | 推荐timeout | 说明 |
|---------|------------|------|
| 断点设置 | 5秒 | 调试器处理断点 |
| 程序启动/run | 30秒 | 类加载、初始化 |
| 单步执行 | 5秒 | 通常很快 |
| 继续执行(cont) | 30秒 | 等待下一个断点 |
| 变量查看 | 5秒 | 快速返回 |

---

## Java高级断点 (jdb_advanced_bp.sh)

### 条件断点

当满足特定条件时才触发的断点：

```bash
# 在第42行设置条件断点，当i > 10时触发
./jdb_advanced_bp.sh cond mysession MyClass:42 "i > 10"

# 在循环中设置条件断点
./jdb_advanced_bp.sh cond mysession BubbleSort:15 "arr[j] > arr[j+1]"

# 自动循环直到条件满足
./jdb_advanced_bp.sh auto-cond mysession BubbleSort:11 "i > 3" 100
```

**实现原理**：
1. 设置普通断点
2. 断点命中时执行: `eval <condition>`
3. 解析结果，若不满足则执行: `cont`

### 临时断点

只触发一次后自动删除：

```bash
./jdb_advanced_bp.sh temp mysession MyClass:100
# 命中后自动清除
```

### 观察点 (Watchpoint)

监控字段访问和修改：

```bash
# 监控字段访问
./jdb_advanced_bp.sh watch mysession MyClass counter read

# 监控字段修改
./jdb_advanced_bp.sh watch mysession MyClass balance write

# 两者都监视
./jdb_advanced_bp.sh watch mysession MyClass data all
```

### 方法断点

在方法入口/出口暂停：

```bash
# 方法入口断点
./jdb_advanced_bp.sh method mysession MyClass processData
```

### 异常断点

当抛出指定异常时暂停：

```bash
# 捕获NullPointerException
./jdb_advanced_bp.sh exception mysession java.lang.NullPointerException

# 捕获所有异常
./jdb_advanced_bp.sh exception mysession java.lang.Throwable
```

### 断点管理

```bash
# 列出所有断点
./jdb_advanced_bp.sh list mysession

# 清除指定断点
./jdb_advanced_bp.sh clear mysession MyClass:42

# 清除所有断点
./jdb_advanced_bp.sh clear-all mysession
```

---

## Python调试 (pdb_session.sh)

### 快速启动

```bash
# 自动检测virtualenv并启动pdb
./pdb_session.sh quick-start /path/to/project main.py
```

### Session管理

```bash
# 创建session
./pdb_session.sh create mysession /path/to/script.py

# 终止session
./pdb_session.sh kill mysession

# 列出所有session
./pdb_session.sh list
```

### 断点管理

```bash
# 设置断点
./pdb_session.sh bp mysession main.py:10

# 设置条件断点（PDB原生支持）
./pdb_session.sh bp-cond mysession main.py:10 "i > 5"

# 列出断点
./pdb_session.sh bp-list mysession

# 清除断点
./pdb_session.sh bp-clear mysession 1
```

### 执行控制

```bash
./pdb_session.sh run mysession      # 运行
./pdb_session.sh step mysession     # 单步（进入函数）
./pdb_session.sh next mysession     # 单步（不进入函数）
./pdb_session.sh cont mysession     # 继续
./pdb_session.sh return mysession   # 执行到函数返回
```

### 变量查看

```bash
./pdb_session.sh print mysession "arr"          # 打印变量
./pdb_session.sh print mysession "arr[i]"       # 打印表达式
./pdb_session.sh pretty-print mysession "data"  # 美化输出
./pdb_session.sh locals mysession               # 列出局部变量
```

### 调用栈

```bash
./pdb_session.sh where mysession   # 显示调用栈
./pdb_session.sh up mysession      # 向上移动栈帧
./pdb_session.sh down mysession    # 向下移动栈帧
```

---

## 命名约定

| 模式 | 用途 | 示例 |
|------|------|------|
| `<debugger>_session.sh` | Session管理 | `jdb_session.sh`, `pdb_session.sh` |
| `<debugger>_remote_attach.sh` | 远程attach | `jdb_remote_attach.sh` |
| `<debugger>_quick_start.sh` | 快速启动 | `jdb_quick_start.sh` |
| `<debugger>_<feature>.sh` | 特定功能 | `jdb_advanced_bp.sh` |

---

## 典型调试流程

### Java冒泡排序调试

```
# 步骤1：初始化
输入: jdb -classpath target/classes demo.BubbleSort
输出: Initializing jdb ...
      >

# 步骤2：设置断点
输入: stop at demo.BubbleSort:11
输出: Deferring breakpoint demo.BubbleSort:11.
      >

# 步骤3：运行程序
输入: run
输出: run demo.BubbleSort
      VM Started: Set deferred breakpoint demo.BubbleSort:11
      原始数组:
      [64, 34, 25, 12, 22, 11, 90
      Breakpoint hit: "thread=main", demo.BubbleSort.sort(), line=11
      main[1]

# 步骤4：查看局部变量
输入: locals
输出: Method arguments:
      arr = instance of int[7] (id=456)
      Local variables:
      n = 7
      i = 0
      j = 0
      main[1]

# 步骤5：查看数组内容
输入: dump arr
输出: arr = {
        64, 34, 25, 12, 22, 11, 90
      }
      main[1]

# 步骤6：单步执行
输入: step
输出: Step completed: "thread=main", demo.BubbleSort.sort(), line=12
      main[1]

# 步骤7：继续执行
输入: cont
输出: Breakpoint hit: "thread=main", demo.BubbleSort.sort(), line=11
      main[1]

# 步骤8：查看交换后的数组
输入: dump arr
输出: arr = {
        34, 64, 25, 12, 22, 11, 90
      }
      # 观察：64和34已交换位置
```

### 提示符模式

不同调试器的提示符：

| 调试器 | 提示符 | 说明 |
|--------|--------|------|
| JDB | `>` | 初始化状态 |
| JDB | `main[1]` | 程序暂停（断点命中） |
| PDB | `(Pdb)` | 等待命令 |
| Delve | `(dlv)` | 等待命令 |

---

## 实践经验

### 1. 编译必须带调试信息

```bash
# 正确：带 -g 参数
javac -g -d target/classes src/main/java/demo/BubbleSort.java
javac -g -cp . MyClass.java

# 错误：不带 -g，断点可能设置失败
javac -d target/classes src/main/java/demo/BubbleSort.java
```

### 2. 断点设置的行号必须是可执行行

```bash
# 使用 javap -l 查看实际的行号表
javap -l target/classes/demo/BubbleSort.class | head -40
```

### 3. 常见问题排查

**问题：断点设置失败 "Unable to set breakpoint"**
- 检查：类名是否正确（全限定名）
- 检查：行号是否在 `javap -l` 输出的行号表中
- 检查：是否用 `-g` 编译

**问题：poll超时**
- 检查：程序是否卡在输入等待
- 检查：timeout是否足够长
- 解决：增加timeout或检查程序逻辑

**问题：dump/print 显示不完整**
- 原因：输出较长时capture-pane可能截断
- 解决：增加tmux pane高度 `session_create name "cmd" 200 100`

---

## Cron Job项目管理

本项目使用PLAN/CHECKLIST/WORKLOG + cron job模式管理：

```
~/.hermes/cron/interactive-debug-skill-enhancement/
├── docs/
│   ├── PLAN.md      # 项目计划和架构
│   ├── CHECKLIST.md # 任务追踪
│   └── WORKLOG.md   # 工作日志
```

Cron job配置：

```bash
# 每30分钟运行，自动推进项目
hermes cronjob create --name interactive-debug-skill-builder \
  --schedule "every 30m" \
  --prompt "读取CHECKLIST，完成下一个任务，更新文档"
```

---

## 开发状态

详见 [CHECKLIST.md](docs/CHECKLIST.md)

### 已完成 ✅
- Phase 1: 项目基础设施
  - 目录结构
  - 公共函数库
  - 配置文件模板
  - README.md

### 进行中 🚧
- Phase 2: Java高级断点功能
  - 条件断点 ✅
  - 临时断点 ✅
  - 观察点 ✅
  - 方法断点 ✅
  - 异常断点 ✅

- Phase 3: Python调试支持
  - pdb_session.sh ✅
  - pdb quick start测试通过 ✅

### 计划中 📋
- Phase 3: Python调试（远程attach、virtualenv）
- Phase 4: Go调试支持
- Phase 5: Node.js调试支持
- Phase 6: LLM集成

---

## 相关链接

- [GitHub仓库](https://github.com/deqiangm/interactive-debug-skill)
- [PLAN.md](docs/PLAN.md) - 项目计划和架构
- [CHECKLIST.md](docs/CHECKLIST.md) - 任务追踪
- [WORKLOG.md](docs/WORKLOG.md) - 工作日志

---

*由 Hermes Agent 自动维护*
