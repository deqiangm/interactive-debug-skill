# Interactive Debug Skill Enhancement Plan

## 项目目标

增强interactive-debug-skill，支持多语言调试和高级调试功能。

---

## Phase 1: 项目基础设施 (Week 1)

### 1.1 项目结构重组
- [ ] 创建统一的项目目录结构
- [ ] 建立公共函数库 (common/functions.sh)
- [ ] 标准化错误处理和日志系统
- [ ] 创建配置文件模板

### 1.2 文档完善
- [ ] 编写完整的README.md
- [ ] 创建SKILL.md skill定义文件
- [ ] 编写各语言的调试指南

---

## Phase 2: Java调试增强 (Week 2)

### 2.1 高级断点功能
- [ ] 条件断点 (condition breakpoint)
- [ ] 临时断点 (temporary breakpoint, hit once)
- [ ] 观察点 (watchpoint, field access/modification)
- [ ] 方法断点 (method entry/exit)
- [ ] 异常断点 (exception breakpoint)

### 2.2 调试辅助功能
- [ ] 变量监视 (watch expression)
- [ ] 表达式求值 (evaluate expression)
- [ ] 内存/堆分析 (memory analysis)
- [ ] 线程分析 (thread analysis)

### 2.3 自动化调试脚本
- [ ] NPE自动定位脚本
- [ ] 死锁检测脚本
- [ ] 性能热点分析脚本

---

## Phase 3: Python调试支持 (Week 3)

### 3.1 pdb基础封装
- [ ] pdb_session.sh - tmux session管理
- [ ] pdb_remote_attach.sh - remote debug支持
- [ ] pdb_quick_start.sh - 快速启动

### 3.2 Python特性
- [ ] 支持virtualenv自动激活
- [ ] 支持pip依赖解析
- [ ] 支持Django/Flask调试
- [ ] 支持pytest调试

---

## Phase 4: Go调试支持 (Week 4)

### 4.1 delve基础封装
- [ ] dlv_session.sh - tmux session管理
- [ ] dlv_remote_attach.sh - remote debug支持
- [ ] dlv_quick_start.sh - 快速启动

### 4.2 Go特性
- [ ] 支持Go module自动解析
- [ ] 支持goroutine调试
- [ ] 支持channel监视

---

## Phase 5: Node.js调试支持 (Week 5)

### 5.1 node inspect基础封装
- [ ] node_session.sh - tmux session管理
- [ ] node_remote_attach.sh - remote debug支持
- [ ] node_quick_start.sh - 快速启动

### 5.2 Node.js特性
- [ ] 支持npm/yarn依赖解析
- [ ] 支持TypeScript source map
- [ ] 支持async/await调试

---

## Phase 6: 高级调试模板 (Week 6)

### 6.1 调试模板
- [ ] 常见问题调试模板 (NPE, deadlock, race condition)
- [ ] 框架特定调试模板 (Spring, Django, Express)

### 6.2 自动化调试脚本
- [ ] NPE自动定位脚本
- [ ] 死锁检测脚本
- [ ] 性能热点分析脚本

---

## 技术架构

```
interactive-debug-skill/
├── common/
│   ├── functions.sh          # Common functions library
│   ├── config.sh             # Configuration management
│   └── logger.sh             # Logging system
├── languages/
│   ├── java/
│   │   ├── scripts/
│   │   │   ├── jdb_session.sh
│   │   │   ├── jdb_remote_attach.sh
│   │   │   ├── jdb_advanced_bp.sh  # Advanced breakpoints
│   │   │   ├── jdb_thread.sh       # Thread analysis
│   │   │   └── jdb_auto_npe.sh     # NPE auto-detection
│   │   └── templates/
│   │       ├── npe_debug.yaml
│   │       └── deadlock_debug.yaml
│   ├── python/
│   │   ├── scripts/
│   │   │   ├── pdb_session.sh
│   │   │   ├── pdb_remote_attach.sh
│   │   │   └── pdb_quick_start.sh
│   │   └── templates/
│   ├── go/
│   │   ├── scripts/
│   │   └── templates/
│   └── nodejs/
│       ├── scripts/
│       └── templates/
├── docs/
│   ├── JAVA_DEBUG_GUIDE.md
│   ├── PYTHON_DEBUG_GUIDE.md
│   └── ADVANCED_FEATURES.md
├── tests/
│   ├── java_test.sh
│   ├── python_test.sh
│   └── integration_test.sh
├── SKILL.md
└── README.md
```

> Note: This skill is designed for LLM agents to use. No additional LLM integration is needed.

---

## Phase 7: Multi-Agent Adaptation & One-Click Install (Week 7)

### 7.1 Multi-Agent Adaptation
- [ ] Claude Code adaptation (CLAUDE.md format)
- [ ] OpenAI Codex adaptation (CODEX.md format)
- [ ] OpenCode adaptation
- [ ] Cursor/Windsurf adaptation (.cursorrules format)
- [ ] Universal MCP protocol support

### 7.2 One-Click Install Support
- [ ] Publish to Hermes Skills Hub
- [ ] Create install script (install.sh)
- [ ] Support `hermes skills install`
- [ ] Version management and update mechanism

### 7.3 Agent-Specific Optimizations
- [ ] Claude Code: Leverage --dangerously-skip-permissions
- [ ] Codex: Leverage git worktree isolation
- [ ] Hermes: Leverage tmux session management
- [ ] Cross-agent compatibility testing

---

## Dependencies

- tmux >= 3.0
- JDK >= 11 (Java调试)
- Python >= 3.8 (Python调试)
- Go >= 1.19 (Go调试)
- Node.js >= 16 (Node.js调试)
- jq (JSON解析)
- nc (网络工具)

---

## 成功标准

1. 所有语言的基础调试功能正常工作
2. 高级断点功能在Java上验证通过
3. 至少3个自动化调试脚本可用
4. 完整的文档和测试覆盖
