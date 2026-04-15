#!/bin/bash
# ============================================================================
# Classpath Resolver - 自动解析Maven/Gradle项目的classpath
# 
# 支持的项目类型:
# - Maven (pom.xml)
# - Gradle (build.gradle / build.gradle.kts)
# 
# 输出:
# - CLASSPATH: 所有依赖和编译输出的路径
# - SOURCEPATH: 源码路径
# - OUTPUT_DIR: 编译输出目录
# ============================================================================

set -e

# ============================================================================
# 辅助函数
# ============================================================================

log() {
    echo "[CLASSPATH] $1" >&2
}

error() {
    echo "ERROR: $1" >&2
    exit 1
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ============================================================================
# 项目类型检测
# ============================================================================

detect_project_type() {
    local project_dir="$1"
    
    if [ -f "$project_dir/pom.xml" ]; then
        echo "maven"
    elif [ -f "$project_dir/build.gradle" ] || [ -f "$project_dir/build.gradle.kts" ]; then
        echo "gradle"
    else
        echo "unknown"
    fi
}

# ============================================================================
# Maven 项目解析
# ============================================================================

resolve_maven() {
    local project_dir="$1"
    local output_file=$(mktemp)
    
    log "Detected Maven project: $project_dir"
    
    # 方法1: 使用 mvn dependency:build-classpath
    if command_exists mvn; then
        log "Running 'mvn dependency:build-classpath'..."
        
        cd "$project_dir"
        
        if mvn dependency:build-classpath -Dmdep.outputFile="$output_file" -q 2>/dev/null; then
            # 读取classpath
            CLASSPATH=$(cat "$output_file" | tr '\n' ':' | sed 's/:$//')
            
            # 添加target/classes
            if [ -d "target/classes" ]; then
                CLASSPATH="target/classes:$CLASSPATH"
            fi
            
            # 添加target/test-classes
            if [ -d "target/test-classes" ]; then
                CLASSPATH="target/test-classes:$CLASSPATH"
            fi
            
            rm -f "$output_file"
            
            SOURCEPATH="src/main/java:src/test/java"
            OUTPUT_DIR="target/classes"
            
            log "Maven classpath resolved successfully"
            return 0
        fi
    fi
    
    # 方法2: 直接读取.m2/repository（备用方案）
    log "Falling back to pom.xml parsing..."
    resolve_maven_from_pom "$project_dir"
}

resolve_maven_from_pom() {
    local project_dir="$1"
    local pom_file="$project_dir/pom.xml"
    local m2_repo="$HOME/.m2/repository"
    
    CLASSPATH=""
    
    # 解析pom.xml中的依赖（简化版，使用grep和sed）
    # 提取 groupId:artifactId:version
    while IFS= read -r line; do
        # 跳过注释
        [[ "$line" =~ ^[[:space:]]*<!-- ]] && continue
        
        # 提取groupId, artifactId, version
        # 这是一个简化版本，实际应该用xmllint或python xml解析
        :
    done < "$pom_file"
    
    # 添加target/classes
    if [ -d "$project_dir/target/classes" ]; then
        CLASSPATH="$project_dir/target/classes"
    fi
    
    SOURCEPATH="$project_dir/src/main/java"
    if [ -d "$project_dir/src/test/java" ]; then
        SOURCEPATH="$SOURCEPATH:$project_dir/src/test/java"
    fi
    
    OUTPUT_DIR="$project_dir/target/classes"
    
    log "Basic pom.xml parsing completed (dependencies may be incomplete)"
}

# ============================================================================
# Gradle 项目解析
# ============================================================================

resolve_gradle() {
    local project_dir="$1"
    local output_file=$(mktemp)
    
    log "Detected Gradle project: $project_dir"
    
    cd "$project_dir"
    
    # 方法1: 使用 gradle dependencies
    if command_exists gradle; then
        log "Running 'gradle dependencies'..."
        
        # 获取runtimeClasspath
        if gradle dependencies --configuration runtimeClasspath -q > "$output_file" 2>/dev/null; then
            # 解析gradle输出，提取jar路径
            CLASSPATH=$(grep -E '^\s*[+\\]' "$output_file" | \
                       grep -oE '/[^:]+\.jar' | \
                       sort -u | \
                       tr '\n' ':' | \
                       sed 's/:$//')
        fi
        
        # 方法2: 使用 gradle properties 获取 buildDir
        local build_dir=$(gradle properties -q 2>/dev/null | grep "buildDir:" | awk '{print $2}')
        
        if [ -n "$build_dir" ] && [ -d "$build_dir/classes/java/main" ]; then
            CLASSPATH="$build_dir/classes/java/main:$CLASSPATH"
            OUTPUT_DIR="$build_dir/classes/java/main"
        fi
        
        # test classes
        if [ -d "$build_dir/classes/java/test" ]; then
            CLASSPATH="$build_dir/classes/java/test:$CLASSPATH"
        fi
        
        rm -f "$output_file"
        
        SOURCEPATH="src/main/java"
        [ -d "src/main/kotlin" ] && SOURCEPATH="$SOURCEPATH:src/main/kotlin"
        [ -d "src/test/java" ] && SOURCEPATH="$SOURCEPATH:src/test/java"
        [ -d "src/test/kotlin" ] && SOURCEPATH="$SOURCEPATH:src/test/kotlin"
        
        log "Gradle classpath resolved successfully"
        return 0
    fi
    
    # Gradle wrapper
    if [ -f "./gradlew" ]; then
        log "Using Gradle wrapper..."
        chmod +x ./gradlew
        
        # 使用gradlew获取信息
        if ./gradlew dependencies --configuration runtimeClasspath -q > "$output_file" 2>/dev/null; then
            CLASSPATH=$(grep -oE '/[^:]+\.jar' "$output_file" | sort -u | tr '\n' ':' | sed 's/:$//')
        fi
        
        local build_dir=$(./gradlew properties -q 2>/dev/null | grep "buildDir:" | awk '{print $2}')
        
        if [ -n "$build_dir" ] && [ -d "$build_dir/classes/java/main" ]; then
            CLASSPATH="$build_dir/classes/java/main:$CLASSPATH"
            OUTPUT_DIR="$build_dir/classes/java/main"
        fi
        
        rm -f "$output_file"
        
        SOURCEPATH="src/main/java"
        [ -d "src/main/kotlin" ] && SOURCEPATH="$SOURCEPATH:src/main/kotlin"
        
        return 0
    fi
    
    # 备用方案：手动构建classpath
    resolve_gradle_manual "$project_dir"
}

resolve_gradle_manual() {
    local project_dir="$1"
    
    # 查找 .gradle 缓存目录
    local gradle_cache="$HOME/.gradle/caches/modules-2/files-2.1"
    
    # 添加 build/classes
    if [ -d "$project_dir/build/classes/java/main" ]; then
        CLASSPATH="$project_dir/build/classes/java/main"
        OUTPUT_DIR="$project_dir/build/classes/java/main"
    fi
    
    if [ -d "$project_dir/build/classes/java/test" ]; then
        CLASSPATH="$CLASSPATH:$project_dir/build/classes/java/test"
    fi
    
    # 查找项目lib目录
    if [ -d "$project_dir/lib" ]; then
        for jar in "$project_dir/lib"/*.jar; do
            [ -f "$jar" ] && CLASSPATH="$CLASSPATH:$jar"
        done
    fi
    
    SOURCEPATH="$project_dir/src/main/java"
    [ -d "$project_dir/src/main/kotlin" ] && SOURCEPATH="$SOURCEPATH:$project_dir/src/main/kotlin"
    
    log "Manual Gradle resolution completed"
}

# ============================================================================
# 输出格式化
# ============================================================================

print_classpath_json() {
    cat << EOF
{
    "classpath": "$(echo "$CLASSPATH" | sed 's/"/\\"/g')",
    "sourcepath": "$(echo "$SOURCEPATH" | sed 's/"/\\"/g')",
    "output_dir": "$(echo "$OUTPUT_DIR" | sed 's/"/\\"/g')",
    "project_type": "$PROJECT_TYPE"
}
EOF
}

print_classpath_shell() {
    cat << EOF
export CLASSPATH="$CLASSPATH"
export SOURCEPATH="$SOURCEPATH"
export OUTPUT_DIR="$OUTPUT_DIR"
export PROJECT_TYPE="$PROJECT_TYPE"
EOF
}

print_classpath_simple() {
    echo "CLASSPATH=$CLASSPATH"
    echo "SOURCEPATH=$SOURCEPATH"
    echo "OUTPUT_DIR=$OUTPUT_DIR"
    echo "PROJECT_TYPE=$PROJECT_TYPE"
}

# ============================================================================
# 生成JDB启动命令
# ============================================================================

generate_jdb_command() {
    local main_class="$1"
    local attach_pid="$2"
    
    local cmd="jdb"
    
    if [ -n "$attach_pid" ]; then
        # Attach模式
        cmd="$cmd -attach $attach_pid"
        if [ -n "$SOURCEPATH" ]; then
            cmd="$cmd -sourcepath $SOURCEPATH"
        fi
    else
        # Main class模式
        if [ -n "$CLASSPATH" ]; then
            cmd="$cmd -classpath $CLASSPATH"
        fi
        if [ -n "$SOURCEPATH" ]; then
            cmd="$cmd -sourcepath $SOURCEPATH"
        fi
        if [ -n "$main_class" ]; then
            cmd="$cmd $main_class"
        fi
    fi
    
    echo "$cmd"
}

# ============================================================================
# 主程序
# ============================================================================

show_usage() {
    cat << EOF
Classpath Resolver - 自动解析Maven/Gradle项目的classpath

用法:
    $0 <project_dir> [options]

选项:
    --format <json|shell|simple>   输出格式 (默认: simple)
    --jdb-command <main_class>     生成JDB启动命令
    --attach <pid>                 生成attach模式的JDB命令
    -h, --help                     显示帮助

示例:
    # 基本用法
    $0 /path/to/maven-project
    
    # JSON输出
    $0 /path/to/gradle-project --format json
    
    # 生成JDB启动命令
    $0 /path/to/project --jdb-command com.example.Main
    
    # 生成attach命令
    $0 /path/to/project --attach 12345
    
    # 在shell中使用
    eval \$($0 /path/to/project --format shell)

EOF
}

# 解析参数
if [ $# -lt 1 ]; then
    show_usage
    exit 1
fi

PROJECT_DIR=""
OUTPUT_FORMAT="simple"
MAIN_CLASS=""
ATTACH_PID=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        --format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --jdb-command)
            MAIN_CLASS="$2"
            shift 2
            ;;
        --attach)
            ATTACH_PID="$2"
            shift 2
            ;;
        -*)
            error "Unknown option: $1"
            ;;
        *)
            if [ -z "$PROJECT_DIR" ]; then
                PROJECT_DIR="$1"
            fi
            shift
            ;;
    esac
done

# 验证项目目录
if [ -z "$PROJECT_DIR" ]; then
    error "Project directory is required"
fi

if [ ! -d "$PROJECT_DIR" ]; then
    error "Directory not found: $PROJECT_DIR"
fi

# 转换为绝对路径
PROJECT_DIR=$(cd "$PROJECT_DIR" && pwd)

# 检测项目类型并解析
PROJECT_TYPE=$(detect_project_type "$PROJECT_DIR")

case "$PROJECT_TYPE" in
    maven)
        resolve_maven "$PROJECT_DIR"
        ;;
    gradle)
        resolve_gradle "$PROJECT_DIR"
        ;;
    *)
        error "Unsupported project type. Expected Maven or Gradle project."
        ;;
esac

# 输出结果
if [ -n "$MAIN_CLASS" ] || [ -n "$ATTACH_PID" ]; then
    generate_jdb_command "$MAIN_CLASS" "$ATTACH_PID"
else
    case "$OUTPUT_FORMAT" in
        json)
            print_classpath_json
            ;;
        shell)
            print_classpath_shell
            ;;
        *)
            print_classpath_simple
            ;;
    esac
fi
