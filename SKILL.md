---
name: interactive-debug
description: LLM-driven intelligent debugging workflows via tmux sessions
version: 1.0.0
tags: [debug, jdb, pdb, dlv, node-inspect, tmux, breakpoint, llm]
---

# Interactive Debug Skill

LLM-driven debugging via tmux sessions with intelligent poll mechanism.

## Core Concepts

1. **Session Isolation** - Each debug session runs in isolated tmux pane
2. **Poll Mechanism** - Smart wait for debugger output completion
3. **LLM-Driven** - AI analyzes output, decides next actions
4. **Shell-First** - Minimal dependencies, shell scripts preferred

## Supported Languages

| Language | Debugger | Script |
|----------|----------|--------|
| Java | jdb | `languages/java/scripts/jdb_session.sh` |
| Python | pdb | `languages/python/scripts/pdb_session.sh` |
| Go | delve | `languages/go/scripts/dlv_session.sh` |
| Node.js | node inspect | `languages/nodejs/scripts/node_session.sh` |

## Quick Reference

### Java (jdb)

```bash
# Create session
./jdb_session.sh create mysession "jdb -classpath target/classes MyApp"

# Set breakpoint
./jdb_session.sh bp mysession MyClass 10

# Execution
./jdb_session.sh run mysession
./jdb_session.sh step mysession
./jdb_session.sh next mysession
./jdb_session.sh cont mysession

# Variables
./jdb_session.sh locals mysession
./jdb_session.sh print mysession "myVar"
./jdb_session.sh dump mysession "arr"
```

### Python (pdb)

```bash
# Quick start
./pdb_session.sh quick-start /project main.py

# Commands
./pdb_session.sh bp mysession main.py:10
./pdb_session.sh bp-cond mysession main.py:10 "i > 5"
./pdb_session.sh cont mysession
./pdb_session.sh step mysession
./pdb_session.sh print mysession "my_var"
./pdb_session.sh locals mysession
```

### Go (delve)

```bash
# Quick start
./dlv_session.sh quick-start /module

# Commands
./dlv_session.sh bp mysession main.go:20
./dlv_session.sh bp-cond mysession main.go:20 "i > 5"
./dlv_session.sh cont mysession
./dlv_session.sh step mysession
./dlv_session.sh print mysession "myVar"
./dlv_session.sh goroutines mysession
```

### Node.js

```bash
# Quick start
./node_session.sh quick-start /project

# Commands
./node_session.sh bp mysession app.js:20
./node_session.sh cont mysession
./node_session.sh step mysession
./node_session.sh print mysession "myVar"
./node_session.sh bt mysession
```

## Poll Mechanism

Smart waiting for debugger output completion:

- **Prompt Detection**: Waits for debugger prompt (e.g., `main[1]`, `(pdb)`, `(dlv)`)
- **Output Stability**: Returns when output unchanged for 2 consecutive polls
- **Timeout**: Returns current output if timeout reached

### Recommended Timeouts

| Operation | Timeout |
|-----------|---------|
| Breakpoint | 5s |
| Startup/run | 30s |
| Single step | 5s |
| Continue | 30s |
| Variable print | 5s |

## Advanced Features (Java)

```bash
# Conditional breakpoint
./jdb_advanced_bp.sh cond mysession MyClass:42 "i > 10"

# Watchpoint
./jdb_advanced_bp.sh watch mysession MyClass counter write

# Method breakpoint
./jdb_advanced_bp.sh method mysession MyClass processData

# Exception breakpoint
./jdb_advanced_bp.sh exception mysession java.lang.NullPointerException
```

## Project Location

- **Enhanced Version**: `~/.hermes/cron/interactive-debug-skill-enhancement/`
- **GitHub**: https://github.com/deqiangm/interactive-debug-skill

## Best Practices

1. **Compile with debug info**: `javac -g` for Java
2. **Set breakpoints on executable lines only**
3. **Use appropriate timeouts**: Longer for startup, shorter for simple operations
4. **Check poll output before proceeding**
5. **Clean up sessions**: Use `kill` or `cleanup` when done

## Prerequisites

- Bash 4.0+
- tmux 3.0+
- bc (calculator)
- Language-specific: jdk (Java), python3 (Python), go+dlv (Go), node (Node.js)
