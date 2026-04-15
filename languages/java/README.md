# Interactive Debug Skill - Java/JDB

基于tmux的交互式Java调试工具集，支持AI驱动的智能调试。

## 核心特性

1. **Tmux Session隔离** - 每个debug会话独立运行在tmux中
2. **自动化Classpath解析** - 支持Maven/Gradle项目
3. **LLM驱动决策** - 可集成AI进行智能调试决策
4. **简单Shell实现** - 尽量使用shell，减少Python依赖

## 快速开始

```bash
# 1. 列出Java进程
./scripts/jdb_quick_start.sh --list-java

# 2. Attach到进程
./scripts/jdb_quick_start.sh /path/to/project --attach 12345

# 3. 或从main class启动
./scripts/jdb_quick_start.sh /path/to/project --main com.example.Main

# 4. 与session交互
./scripts/jdb_session.sh exec <session_name> "where"
```

## 工具脚本

| 脚本 | 功能 |
|------|------|
| `jdb_session.sh` | Tmux session管理（创建/发送/读取/销毁） |
| `classpath_resolver.sh` | Maven/Gradle classpath自动解析 |
| `jdb_ai_bridge.sh` | LLM集成桥接层 |
| `jdb_quick_start.sh` | 一键启动调试会话 |
| `demo.sh` | 功能演示 |

## 架构

```
┌─────────────────────────────────────────┐
│           JDB AI Controller             │
│  (未来: Python LLM循环控制)              │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│         jdb_ai_bridge.sh                │
│  (构建prompt + 解析LLM响应)              │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│         jdb_session.sh                  │
│  (tmux session: send/read/exec)         │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│         tmux session (jdb进程)           │
│  ┌────────────────────────────────────┐ │
│  │ jdb> _                             │ │
│  │                                    │ │
│  └────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

## 使用场景

### 场景1: Attach到运行进程

```bash
# 查找进程
jps -l
# 12345 com.example.MyApp

# 启动调试
./jdb_quick_start.sh ~/projects/myapp --attach 12345

# 获取session名称
SESSION="jdb_debug_12345_xxx"

# 设置断点
./jdb_session.sh exec $SESSION "stop at UserService:42"

# 继续执行
./jdb_session.sh exec $SESSION "cont"

# 查看调用栈
./jdb_session.sh exec $SESSION "where"

# 打印变量
./jdb_session.sh exec $SESSION "print user.name"
```

### 场景2: AI辅助调试

```bash
# 启动session
./jdb_quick_start.sh ~/projects/myapp --attach 12345

# 启动AI交互模式
./jdb_ai_bridge.sh start-interactive $SESSION_NAME
```

## Classpath解析

支持自动解析：
- Maven项目（pom.xml）
- Gradle项目（build.gradle）

```bash
# 查看classpath
./classpath_resolver.sh /path/to/project

# JSON格式
./classpath_resolver.sh /path/to/project --format json

# 生成JDB命令
./classpath_resolver.sh /path/to/project --jdb-command com.example.Main
```

## 下一步

- [ ] 添加Python LLM控制器（完整AI驱动循环）
- [ ] 添加预设调试模板（NPE、死锁、性能）
- [ ] 支持其他语言（Python/pdb, Go/dlv）
