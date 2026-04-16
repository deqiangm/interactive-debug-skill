# Interactive Debug Skill Enhancement - Checklist

> 最后更新: 2026-04-15
> 状态: 🚧 进行中

---

## Phase 1: 项目基础设施

- [x] 创建项目目录结构
- [x] 创建公共函数库 (common/functions.sh)
- [x] 标准化错误处理和日志系统
- [x] 创建配置文件模板
- [x] 编写完整的README.md
- [x] 创建SKILL.md skill定义文件

---

## Phase 2: Java调试增强

### 2.1 高级断点功能
- [x] 条件断点 (stop at Class:line if condition)
- [x] 临时断点 (hit once then remove)
- [x] 观察点 (watch field access/modification)
- [x] 方法断点 (stop in Class.method)
- [x] 异常断点 (stop on exception)

### 2.2 调试辅助功能
- [x] 变量监视脚本
- [ ] 表达式求值脚本
- [ ] 线程分析脚本
- [ ] NPE自动定位脚本

---

## Phase 3: Python调试支持

- [x] pdb_session.sh
- [x] pdb quick start测试通过
- [ ] pdb_remote_attach.sh (remotepdb支持)
- [ ] virtualenv自动检测
- [ ] Django/Flask调试支持

---

## Phase 4: Go调试支持

- [ ] dlv_session.sh
- [ ] dlv_remote_attach.sh
- [ ] dlv_quick_start.sh
- [ ] Go module自动解析
- [ ] goroutine调试支持

---

## Phase 5: Node.js调试支持

- [ ] node_session.sh
- [ ] node_remote_attach.sh
- [ ] node_quick_start.sh
- [ ] TypeScript source map支持

---

## Phase 6: Node.js调试支持（续）

- [ ] npm/yarn/pnpm自动检测
- [ ] Jest/Mocha测试调试支持

---

## Phase 7: 多Agent适配与一键安装 (Week 7)

> **优先级**: 基础功能优先，保持轻量级

### 7.1 Core Config Files (优先)
- [ ] CLAUDE.md — Claude Code适配
- [ ] SKILL.md — Hermes适配 (精简至<5KB)
- [ ] .cursorrules — Cursor/Windsurf适配

### 7.2 One-Click Install (优先)
- [ ] 精简SKILL.md内容
- [ ] 发布到Hermes Skills Hub
- [ ] 创建install.sh脚本

### 7.3 Multi-Agent Support (暂缓)
- [ ] Codex adaptation
- [ ] OpenCode adaptation
- [ ] Universal MCP protocol support

---

## 测试清单

- [ ] Java冒泡排序调试测试
- [ ] Java远程attach测试
- [ ] Python基础调试测试
- [ ] Go基础调试测试
- [ ] Node.js基础调试测试
- [ ] 条件断点功能测试

---

## 文档清单

- [ ] README.md
- [ ] JAVA_DEBUG_GUIDE.md
- [ ] PYTHON_DEBUG_GUIDE.md
- [ ] GO_DEBUG_GUIDE.md
- [ ] NODEJS_DEBUG_GUIDE.md
- [ ] ADVANCED_FEATURES.md
