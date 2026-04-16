# Interactive Debug Skill - Claude Code Adapter

> This file provides instructions for Claude Code to use the interactive-debug skill for LLM-driven debugging workflows.

## Overview

Interactive Debug Skill enables Claude Code to debug programs through tmux sessions. It provides a poll-based mechanism to wait for debugger output, allowing Claude to analyze results and decide next steps.

## Supported Languages

| Language | Debugger | Session Script |
|----------|----------|----------------|
| Java | jdb | `languages/java/scripts/jdb_session.sh` |
| Python | pdb | `languages/python/scripts/pdb_session.sh` |
| Go | dlv | `languages/go/scripts/dlv_session.sh` |
| Node.js | node inspect | `languages/nodejs/scripts/node_session.sh` |

## Quick Reference

### Java (jdb)
```bash
# Create session
./jdb_session.sh create mysession "jdb -classpath target/classes MyApp"

# Breakpoints
./jdb_session.sh bp mysession MyClass 10
./jdb_session.sh exec-poll mysession "stop at MyClass:10" 5 0.5

# Execution
./jdb_session.sh exec-poll mysession "run" 30 0.5
./jdb_session.sh exec-poll mysession "step" 5 0.5
./jdb_session.sh exec-poll mysession "next" 5 0.5
./jdb_session.sh exec-poll mysession "cont" 30 0.5

# Variables
./jdb_session.sh exec-poll mysession "locals" 5 0.5
./jdb_session.sh exec-poll mysession "dump myVar" 5 0.5
./jdb_session.sh exec-poll mysession "print arr[0]" 5 0.5

# Call stack
./jdb_session.sh exec-poll mysession "where" 5 0.5
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
./pdb_session.sh next mysession
./pdb_session.sh print mysession "my_var"
./pdb_session.sh locals mysession
```

### Go (dlv)
```bash
# Quick start
./dlv_session.sh quick-start /module

# Commands
./dlv_session.sh bp mysession main.go:20
./dlv_session.sh bp-cond mysession main.go:20 "i > 5"
./dlv_session.sh cont mysession
./dlv_session.sh step mysession
./dlv_session.sh next mysession
./dlv_session.sh print mysession "myVar"
./dlv_session.sh locals mysession
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
./node_session.sh next mysession
./node_session.sh print mysession "myVar"
./node_session.sh bt mysession
```

## Poll Mechanism

When sending commands to a debugger, use the poll mechanism to wait for output:

1. **Prompt Detection**: Wait for debugger prompt (e.g., `main[1]`, `(pdb)`, `(dlv)`)
2. **Output Stability**: Wait until output stops changing (2 consecutive polls identical)
3. **Timeout**: Return current output if timeout reached

Recommended timeouts:
- Startup: 30s
- Breakpoint: 5s
- Single step: 5s
- Continue: 30s
- Variable print: 5s

## Remote Debugging (Java)

```bash
# Start Java with debug port
java -agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=*:5005 MyApp

# Attach with jdb
./jdb_remote_attach.sh attach localhost 5005
```

## Best Practices

1. **Always compile with debug info**: `javac -g` for Java
2. **Set breakpoints on executable lines only**
3. **Use appropriate timeouts**: Longer for startup, shorter for simple operations
4. **Check poll output before proceeding**: Ensure command executed successfully
5. **Clean up sessions**: Use `cleanup` command when done

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Breakpoint not set | Check class name (fully qualified), line number, debug compilation |
| Poll timeout | Increase timeout, check if program is waiting for input |
| Output truncated | Increase tmux pane size in session_create |

## Project Structure

```
~/.hermes/cron/interactive-debug-skill-enhancement/
├── common/
│   └── functions.sh          # Core utilities (tmux, poll, logging)
├── languages/
│   ├── java/scripts/         # jdb scripts
│   ├── python/scripts/       # pdb scripts
│   ├── go/scripts/           # dlv scripts
│   └── nodejs/scripts/       # node inspect scripts
└── docs/
    ├── PLAN.md               # Project plan
    ├── CHECKLIST.md          # Task tracking
    └── WORKLOG.md            # Work log
```

## GitHub

https://github.com/deqiangm/interactive-debug-skill
