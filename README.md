# Interactive Debug Skill

[![Status](https://img.shields.io/badge/Status-In%20Development-yellow)](https://github.com/deqiangm/interactive-debug-skill)
[![Languages](https://img.shields.io/badge/Languages-Java%20%7C%20Python%20%7C%20Go%20%7C%20Node.js-blue)](https://github.com/deqiangm/interactive-debug-skill)

AI-powered interactive debugging toolkit with tmux-based session isolation. Supports multi-language debugging with intelligent breakpoint management and LLM integration.

[中文文档](README_CN.md)

## Features

- 🔄 **Tmux Session Isolation** - Each debug session runs in isolated tmux session
- 🎯 **Advanced Breakpoints** - Conditional, temporary, watchpoints, method, and exception breakpoints
- 🔌 **Remote Attach** - Attach to running processes via JDWP/debug ports
- 🤖 **LLM Integration** - AI-assisted debugging with intelligent diagnosis
- 📦 **Multi-Language** - Java (jdb), Python (pdb), Go (delve), Node.js (inspect)

## Quick Start

### Prerequisites

```bash
# Required
sudo apt install tmux openjdk-21-jdk-headless

# Optional (for other languages)
sudo apt install python3 golang nodejs
```

### Installation

```bash
git clone https://github.com/deqiangm/interactive-debug-skill.git
cd interactive-debug-skill
```

### Java Debugging Example

```bash
# Quick start - debug a Java program
./languages/java/scripts/jdb_quick_start.sh /path/to/project MainClass

# Create a debug session
./languages/java/scripts/jdb_session.sh create mysession MainClass

# Set breakpoint
./languages/java/scripts/jdb_session.sh bp mysession MainClass:10

# Run and debug
./languages/java/scripts/jdb_session.sh run mysession
```

### Python Debugging Example

```bash
# Quick start - debug a Python script
./languages/python/scripts/pdb_session.sh quick-start /path/to/project script.py

# Set conditional breakpoint (stops when i > 5)
./languages/python/scripts/pdb_session.sh bp-cond mysession main.py:10 "i > 5"

# View variables
./languages/python/scripts/pdb_session.sh print mysession "my_var"
```

### Advanced Breakpoints (Java)

```bash
# Conditional breakpoint
./languages/java/scripts/jdb_advanced_bp.sh cond mysession BubbleSort:11 "i > 5"

# Watchpoint (stop when field is modified)
./languages/java/scripts/jdb_advanced_bp.sh watch mysession BubbleSort arr write

# Exception breakpoint
./languages/java/scripts/jdb_advanced_bp.sh exception mysession NullPointerException

# Temporary breakpoint (hit once)
./languages/java/scripts/jdb_advanced_bp.sh temp mysession BubbleSort:11
```

## Project Structure

```
interactive-debug-skill/
├── common/
│   ├── functions.sh          # Common functions library
│   └── config.sh             # Configuration constants
├── languages/
│   ├── java/
│   │   └── scripts/
│   │       ├── jdb_session.sh         # JDB session manager
│   │       ├── jdb_remote_attach.sh   # Remote process attach
│   │       ├── jdb_advanced_bp.sh     # Advanced breakpoints
│   │       └── jdb_quick_start.sh     # Quick start helper
│   ├── python/
│   │   └── scripts/
│   │       └── pdb_session.sh         # PDB session manager
│   ├── go/
│   │   └── scripts/
│   │       └── dlv_session.sh         # Delve session manager
│   └── nodejs/
│       └── scripts/
│           └── node_session.sh        # Node inspect session manager
├── docs/
│   ├── PLAN.md               # Technical architecture
│   ├── CHECKLIST.md          # Task tracking
│   └── WORKLOG.md            # Work log
├── README.md                 # English documentation
├── README_CN.md              # Chinese documentation
└── SKILL.md                  # Skill definition
```

## Core Features

### Common Functions Library

The `common/functions.sh` provides shared utilities:

```bash
source common/functions.sh

# Logging
log_info "Starting debug session"
log_error "Failed to connect"

# Session management
session_create "my_session" "jdb -classpath . Main"
session_send "my_session" "stop at Main:10"
output=$(session_poll "my_session" 30 0.5)
session_kill "my_session"

# Network utilities
check_port "localhost" 5005
wait_for_port "localhost" 5005 30
```

### Advanced Breakpoints

| Type | Description | Command |
|------|-------------|---------|
| Conditional | Stop when condition is true | `cond <session> <loc> "<expr>"` |
| Temporary | Stop once, then auto-remove | `temp <session> <loc>` |
| Watchpoint | Stop on field access/modify | `watch <session> <class> <field>` |
| Method | Stop on method entry/exit | `method <session> <class> <method>` |
| Exception | Stop on exception throw | `exception <session> [ExceptionClass]` |

### Naming Conventions

| Pattern | Purpose | Example |
|---------|---------|---------|
| `<debugger>_session.sh` | Session management | `jdb_session.sh` |
| `<debugger>_remote_attach.sh` | Remote attach | `jdb_remote_attach.sh` |
| `<debugger>_quick_start.sh` | Quick start | `jdb_quick_start.sh` |
| `<debugger>_<feature>.sh` | Specific feature | `jdb_advanced_bp.sh` |

## Development Status

| Phase | Feature | Status |
|-------|---------|--------|
| 1 | Common functions library | ✅ Done |
| 1 | Configuration templates | ✅ Done |
| 2 | Java advanced breakpoints | ✅ Done |
| 2 | Java remote attach | ✅ Done |
| 3 | Python pdb support | ✅ Done |
| 4 | Go delve support | 🚧 In Progress |
| 5 | Node.js support | 📋 Planned |
| 6 | LLM integration | 📋 Planned |

## Documentation

- [PLAN.md](docs/PLAN.md) - Technical architecture and design
- [CHECKLIST.md](docs/CHECKLIST.md) - Task tracking
- [WORKLOG.md](docs/WORKLOG.md) - Development log
- [README_CN.md](README_CN.md) - Chinese documentation

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

MIT License - see LICENSE file for details.
