#!/bin/bash
# ============================================================================
# JDB Tools Demo - 演示如何使用JDB调试工具集
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "JDB Interactive Debug Tools Demo"
echo "========================================"
echo ""

# 1. 检查依赖
echo "1. Checking dependencies..."
echo ""

if ! command -v tmux &>/dev/null; then
    echo "ERROR: tmux not installed"
    exit 1
fi
echo "  ✓ tmux: $(tmux -V)"

if ! command -v jdb &>/dev/null; then
    echo "ERROR: jdb not installed (part of JDK)"
    exit 1
fi
echo "  ✓ jdb: available"

if ! command -v jps &>/dev/null; then
    echo "ERROR: jps not installed (part of JDK)"
    exit 1
fi
echo "  ✓ jps: available"

echo ""

# 2. 列出可用的Java进程
echo "2. Available Java processes:"
echo ""
"$SCRIPT_DIR/jdb_quick_start.sh" --list-java
echo ""

# 3. 演示classpath解析
echo "3. Classpath Resolution Demo:"
echo ""

# 创建临时Maven项目用于演示
TEMP_PROJECT=$(mktemp -d)
mkdir -p "$TEMP_PROJECT/src/main/java/com/example"
mkdir -p "$TEMP_PROJECT/src/test/java"

# 创建简单pom.xml
cat > "$TEMP_PROJECT/pom.xml" << 'POM_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project>
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>demo-app</artifactId>
    <version>1.0.0</version>
    
    <dependencies>
        <dependency>
            <groupId>org.apache.commons</groupId>
            <artifactId>commons-lang3</artifactId>
            <version>3.12.0</version>
        </dependency>
    </dependencies>
</project>
POM_EOF

# 创建简单Java类
cat > "$TEMP_PROJECT/src/main/java/com/example/Demo.java" << 'JAVA_EOF'
package com.example;

public class Demo {
    private String name;
    private int value;
    
    public Demo(String name, int value) {
        this.name = name;
        this.value = value;
    }
    
    public void process() {
        System.out.println("Processing: " + name);
        if (value > 100) {
            System.out.println("High value detected");
        }
    }
    
    public static void main(String[] args) {
        Demo demo = new Demo("Test", 150);
        demo.process();
    }
}
JAVA_EOF

echo "Created demo project at: $TEMP_PROJECT"
echo ""

# 解析classpath
echo "Resolving classpath..."
classpath_output=$("$SCRIPT_DIR/classpath_resolver.sh" "$TEMP_PROJECT" 2>&1) || true
echo "$classpath_output"
echo ""

# 4. 演示tmux session管理
echo "4. Tmux Session Management Demo:"
echo ""

# 创建一个测试session
TEST_SESSION="jdb_test_demo_$$"

echo "Creating test tmux session: $TEST_SESSION"
tmux new-session -d -s "$TEST_SESSION" -x 200 -y 50 "sleep 10"
sleep 1

echo "Session created. Listing all jdb sessions:"
tmux list-sessions 2>/dev/null | grep "jdb" || echo "  (no jdb sessions found)"

echo ""
echo "Killing test session..."
tmux kill-session -t "$TEST_SESSION"

echo "  ✓ Session cleanup complete"
echo ""

# 5. 显示使用示例
echo "5. Usage Examples:"
echo ""
cat << 'EXAMPLES'
# Example 1: Attach to running Java process
# -----------------------------------------
# Step 1: Find the PID
jps -l
# Output: 12345 com.example.MyApplication

# Step 2: Start debug session
./jdb_quick_start.sh /path/to/project --attach 12345

# Step 3: Interact with the session
./jdb_session.sh exec jdb_debug_12345_xxx "where"
./jdb_session.sh exec jdb_debug_12345_xxx "print user.name"
./jdb_session.sh exec jdb_debug_12345_xxx "cont"

# Example 2: Debug from main class
# ---------------------------------
./jdb_quick_start.sh /path/to/project --main com.example.Main --breakpoint Main:10

# Example 3: AI-assisted debugging
# ---------------------------------
# Start interactive session
./jdb_ai_bridge.sh start-interactive jdb_debug_xxx

# Example 4: Direct session management
# ------------------------------------
# Create session
./jdb_session.sh create my_session "jdb -attach 12345"

# Send command
./jdb_session.sh send my_session "stop at UserService:42"

# Read output
./jdb_session.sh read my_session

# Execute and get result
./jdb_session.sh exec my_session "print user.name"

# Cleanup
./jdb_session.sh kill my_session

# Or cleanup all
./jdb_session.sh cleanup

EXAMPLES

# 6. 清理
echo "6. Cleanup:"
echo ""
rm -rf "$TEMP_PROJECT"
echo "  ✓ Temporary project removed"
echo ""

echo "========================================"
echo "Demo completed!"
echo "========================================"
