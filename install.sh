#!/bin/bash
# ============================================================================
# Interactive Debug Skill - One-Click Installation Script
# 
# Installs the interactive-debug skill for Hermes, Claude Code, Cursor, etc.
# ============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
REPO_URL="https://github.com/deqiangm/interactive-debug-skill.git"
INSTALL_DIR="${HOME}/.hermes/cron/interactive-debug-skill-enhancement"
SKILL_DIR="${HOME}/.hermes/skills/devops/interactive-debug"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Interactive Debug Skill Installer${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check dependencies
echo -e "${YELLOW}Checking dependencies...${NC}"

check_command() {
	if ! command -v "$1" &>/dev/null; then
		echo -e "${RED}✗ $1 not found${NC}"
		return 1
	fi
	echo -e "${GREEN}✓ $1 found${NC}"
	return 0
}

# Required commands
REQUIRED_CMDS=("tmux" "git" "bash")
OPTIONAL_CMDS=("java" "python3" "go" "node")

missing_required=()

for cmd in "${REQUIRED_CMDS[@]}"; do
	if ! check_command "$cmd"; then
		missing_required+=("$cmd")
	fi
done

if [ ${#missing_required[@]} -gt 0 ]; then
	echo -e "${RED}Error: Missing required commands: ${missing_required[*]}${NC}"
	echo "Please install them and run this script again."
	exit 1
fi

echo ""

# Check optional language runtimes
echo -e "${YELLOW}Checking language support...${NC}"
for cmd in "${OPTIONAL_CMDS[@]}"; do
	if check_command "$cmd"; then
		case "$cmd" in
			java)
				# Check for jdb
				if command -v jdb &>/dev/null; then
					echo -e "  ${GREEN}→ Java debugging available (jdb)${NC}"
				else
					echo -e "  ${YELLOW}→ Java found but jdb missing (install JDK)${NC}"
				fi
				;;
			python3)
				echo -e "  ${GREEN}→ Python debugging available (pdb)${NC}"
				;;
			go)
				# Check for dlv
				if command -v dlv &>/dev/null; then
					echo -e "  ${GREEN}→ Go debugging available (dlv)${NC}"
				else
					echo -e "  ${YELLOW}→ Go found but dlv missing (install: go install github.com/go-delve/delve/cmd/dlv@latest)${NC}"
				fi
				;;
			node)
				echo -e "  ${GREEN}→ Node.js debugging available (node inspect)${NC}"
				;;
		esac
	fi
done

echo ""

# Clone or update repository
echo -e "${YELLOW}Installing skill...${NC}"

if [ -d "$INSTALL_DIR" ]; then
	echo -e "${YELLOW}Updating existing installation...${NC}"
	cd "$INSTALL_DIR"
	git pull origin main || {
		echo -e "${RED}Failed to update. Trying fresh install...${NC}"
		rm -rf "$INSTALL_DIR"
		git clone "$REPO_URL" "$INSTALL_DIR"
	}
else
	echo -e "${YELLOW}Cloning repository...${NC}"
	git clone "$REPO_URL" "$INSTALL_DIR"
fi

echo ""

# Make scripts executable
echo -e "${YELLOW}Setting up scripts...${NC}"
find "$INSTALL_DIR/languages" -name "*.sh" -exec chmod +x {} \;
echo -e "${GREEN}✓ Scripts are executable${NC}"

echo ""

# Install Hermes skill
echo -e "${YELLOW}Installing Hermes skill...${NC}"
mkdir -p "$(dirname "$SKILL_DIR")"

if [ -d "$SKILL_DIR" ]; then
	echo -e "${YELLOW}Updating existing skill...${NC}"
else
	mkdir -p "$SKILL_DIR"
fi

# Copy SKILL.md to Hermes skills directory
cp "$INSTALL_DIR/SKILL.md" "$SKILL_DIR/SKILL.md" 2>/dev/null || {
	# SKILL.md might be in parent directory
	if [ -f "$(dirname "$INSTALL_DIR")/SKILL.md" ]; then
		cp "$(dirname "$INSTALL_DIR")/SKILL.md" "$SKILL_DIR/SKILL.md"
	fi
}

# Create skill directory structure link
if [ ! -f "$SKILL_DIR/scripts" ]; then
	# Create a wrapper that points to the enhancement directory
	cat > "$SKILL_DIR/scripts" << 'WRAPPER'
#!/bin/bash
# Wrapper script to run debugger scripts
SCRIPTS_DIR="${HOME}/.hermes/cron/interactive-debug-skill-enhancement"
exec "$@"
WRAPPER
	chmod +x "$SKILL_DIR/scripts"
fi

echo -e "${GREEN}✓ Hermes skill installed${NC}"

echo ""

# Verify installation
echo -e "${YELLOW}Verifying installation...${NC}"

verify_script() {
	local script="$1"
	if [ -f "$script" ]; then
		if [ -x "$script" ]; then
			echo -e "${GREEN}✓ $script${NC}"
			return 0
		else
			echo -e "${RED}✗ $script (not executable)${NC}"
			return 1
		fi
	else
		echo -e "${YELLOW}○ $script (not found)${NC}"
		return 0
	fi
}

verify_script "$INSTALL_DIR/common/functions.sh"
verify_script "$INSTALL_DIR/languages/java/scripts/jdb_session.sh"
verify_script "$INSTALL_DIR/languages/python/scripts/pdb_session.sh"
verify_script "$INSTALL_DIR/languages/go/scripts/dlv_session.sh"
verify_script "$INSTALL_DIR/languages/nodejs/scripts/node_session.sh"

echo ""

# Success message
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Installation directory: $INSTALL_DIR"
echo ""
echo -e "${BLUE}Quick Start:${NC}"
echo ""
echo "  Java:"
echo "    cd \$PROJECT_DIR"
echo "    javac -g -d target/classes src/main/java/**/*.java"
echo "    $INSTALL_DIR/languages/java/scripts/jdb_session.sh create myapp \"jdb -classpath target/classes Main\""
echo ""
echo "  Python:"
echo "    $INSTALL_DIR/languages/python/scripts/pdb_session.sh quick-start /path/to/project main.py"
echo ""
echo "  Go:"
echo "    $INSTALL_DIR/languages/go/scripts/dlv_session.sh quick-start /path/to/module"
echo ""
echo "  Node.js:"
echo "    $INSTALL_DIR/languages/nodejs/scripts/node_session.sh quick-start /path/to/project"
echo ""
echo -e "${BLUE}Documentation:${NC}"
echo "  README: $INSTALL_DIR/README.md"
echo "  CLAUDE.md: $INSTALL_DIR/CLAUDE.md"
echo "  .cursorrules: $INSTALL_DIR/.cursorrules"
echo ""
