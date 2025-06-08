#!/bin/bash

# Nanobrowser MCP Native Messaging Host Installer
# This script installs the Native Messaging Host for macOS and Linux

# Exit on any error
set -e

# Define colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Print a colored message
print_message() {
  local color=$1
  local message=$2
  echo -e "${color}${message}${NC}"
}

# Print an error message and exit
error_exit() {
  print_message "${RED}${BOLD}ERROR:${NC} $1"
  exit 1
}

# Function to find MCP Host processes
find_mcp_processes() {
  local pids=()
  
  # Method 1: Check PID file (most reliable method)
  local pid_file="$HOME/.nanobrowser/mcp-host.pid"
  if [ -f "$pid_file" ]; then
    local pid_from_file=$(cat "$pid_file" 2>/dev/null | tr -d '\n' | tr -d ' ')
    if [ -n "$pid_from_file" ] && [[ "$pid_from_file" =~ ^[0-9]+$ ]]; then
      # Verify the process is actually running
      if kill -0 "$pid_from_file" 2>/dev/null; then
        pids="$pids $pid_from_file"
      fi
    fi
  fi
  
  # Method 2: Find by port usage (port 9666 is default for MCP Host)
  if command -v lsof &> /dev/null; then
    local port_pids=$(lsof -ti:9666 2>/dev/null || true)
    pids="$pids $port_pids"
  fi
  
  # Remove duplicates and empty entries, then return
  echo $pids | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' '
}

# Function to check if a process is healthy (responding)
check_process_health() {
  local pid=$1
  
  # Check if process exists
  if ! kill -0 "$pid" 2>/dev/null; then
    return 2  # Process doesn't exist
  fi
  
  # Try to check if MCP Host is responding (if curl is available)
  if command -v curl &> /dev/null; then
    if curl -s --max-time 2 --connect-timeout 1 http://127.0.0.1:9666/health >/dev/null 2>&1; then
      return 0  # Process is healthy
    fi
  fi
  
  # Process exists but might not be responding
  return 1  # Potentially zombie process
}

# Function to terminate a process gracefully
terminate_process_gracefully() {
  local pid=$1
  local process_name=$(ps -p $pid -o comm= 2>/dev/null || echo "unknown")
  
  print_message "${BLUE}Terminating $process_name (PID: $pid)...${NC}"
  
  # Step 1: Try SIGTERM (graceful termination)
  if kill -TERM "$pid" 2>/dev/null; then
    # Wait up to 5 seconds for graceful termination
    for i in {1..5}; do
      if ! kill -0 "$pid" 2>/dev/null; then
        print_message "${GREEN}Process terminated gracefully${NC}"
        return 0
      fi
      sleep 1
    done
  fi
  
  # Step 2: Force termination with SIGKILL
  print_message "${YELLOW}Process not responding, force terminating...${NC}"
  if kill -KILL "$pid" 2>/dev/null; then
    sleep 1
    if ! kill -0 "$pid" 2>/dev/null; then
      print_message "${GREEN}Process force terminated${NC}"
      return 0
    fi
  fi
  
  print_message "${RED}Warning: Failed to terminate process $pid${NC}"
  return 1
}

# Function to cleanup zombie processes
cleanup_zombie_processes() {
  local force_mode=${1:-false}
  local mcp_pids=$(find_mcp_processes)
  
  if [ -z "$mcp_pids" ]; then
    print_message "${GREEN}No existing MCP Host processes found${NC}"
    return 0
  fi
  
  print_message "${YELLOW}Found existing MCP Host processes: $mcp_pids${NC}"
  
  for pid in $mcp_pids; do
    # Skip empty PIDs
    [ -z "$pid" ] && continue
    
    case $(check_process_health $pid) in
      0) 
        print_message "${GREEN}Found healthy MCP Host process ($pid)${NC}"
        if [ "$force_mode" = true ]; then
          terminate_process_gracefully $pid
        else
          print_message "${YELLOW}A healthy MCP Host is already running.${NC}"
          read -p "Terminate existing process to continue installation? (y/n): " response
          if [[ "$response" =~ ^[Yy]$ ]]; then
            terminate_process_gracefully $pid
          else
            print_message "${BLUE}Installation aborted by user. Options:${NC}"
            print_message "${BLUE}1. Manually stop the MCP Host process${NC}"
            print_message "${BLUE}2. Run with --force to automatically terminate processes${NC}"
            print_message "${BLUE}3. Use --cleanup to only clean up processes${NC}"
            exit 1
          fi
        fi
        ;;
      1)
        print_message "${YELLOW}Found zombie MCP Host process ($pid), cleaning up...${NC}"
        terminate_process_gracefully $pid
        ;;
      2)
        # Process doesn't exist anymore, skip
        ;;
    esac
  done
}

# Function to check and cleanup orphaned ports
cleanup_orphaned_ports() {
  if command -v lsof &> /dev/null; then
    local port_processes=$(lsof -ti:9666 2>/dev/null || true)
    if [ -n "$port_processes" ]; then
      print_message "${YELLOW}Port 9666 is still in use by processes: $port_processes${NC}"
      # These should have been cleaned up by process cleanup, but just in case
      for pid in $port_processes; do
        if kill -0 "$pid" 2>/dev/null; then
          print_message "${YELLOW}Cleaning up process $pid using port 9666${NC}"
          terminate_process_gracefully $pid
        fi
      done
    fi
  fi
}

# Function to cleanup temporary files
cleanup_temp_files() {
  local temp_dirs=(
    "/tmp/mcp-host*"
    "/tmp/nanobrowser*"
    "$HOME/.nanobrowser/tmp"
  )
  
  for pattern in "${temp_dirs[@]}"; do
    if ls $pattern >/dev/null 2>&1; then
      print_message "${BLUE}Cleaning up temporary files: $pattern${NC}"
      rm -rf $pattern
    fi
  done
}

# Function for comprehensive pre-installation cleanup
pre_install_cleanup() {
  local force_mode=${1:-false}
  
  print_message "${BLUE}${BOLD}Performing pre-installation cleanup...${NC}"
  
  # Step 1: Check and cleanup processes
  cleanup_zombie_processes $force_mode
  
  # Step 2: Check and cleanup orphaned ports
  cleanup_orphaned_ports
  
  # Step 3: Cleanup temporary files
  cleanup_temp_files
  
  print_message "${GREEN}Pre-installation cleanup completed${NC}"
}

# Function to verify installation success
verify_installation() {
  local host_script="$1"
  local manifest_path="$2"
  local extension_id="$3"
  
  print_message "${BLUE}${BOLD}Verifying installation...${NC}"
  
  # Check 1: Host script exists and is executable
  if [ ! -f "$host_script" ]; then
    print_message "${RED}❌ Host script not found: $host_script${NC}"
    return 1
  fi
  
  if [ ! -x "$host_script" ]; then
    print_message "${RED}❌ Host script is not executable: $host_script${NC}"
    return 1
  fi
  print_message "${GREEN}✅ Host script exists and is executable${NC}"
  
  # Check 2: Manifest files exist
  if [ ! -f "$manifest_path" ]; then
    print_message "${RED}❌ Manifest file not found: $manifest_path${NC}"
    return 1
  fi
  print_message "${GREEN}✅ Manifest file exists${NC}"
  
  # Check 3: Manifest content is valid JSON
  if ! python3 -m json.tool "$manifest_path" >/dev/null 2>&1 && ! node -e "JSON.parse(require('fs').readFileSync('$manifest_path', 'utf8'))" >/dev/null 2>&1; then
    print_message "${RED}❌ Manifest file contains invalid JSON${NC}"
    return 1
  fi
  print_message "${GREEN}✅ Manifest file contains valid JSON${NC}"
  
  # Check 4: Extension ID in manifest matches provided ID
  if command -v node &> /dev/null; then
    local manifest_extension_id=$(node -e "
      const fs = require('fs');
      const manifest = JSON.parse(fs.readFileSync('$manifest_path', 'utf8'));
      const origins = manifest.allowed_origins || [];
      const match = origins[0] && origins[0].match(/chrome-extension:\/\/([a-z]{32})\//);
      console.log(match ? match[1] : '');
    " 2>/dev/null || echo "")
    
    if [ "$manifest_extension_id" != "$extension_id" ]; then
      print_message "${RED}❌ Extension ID mismatch in manifest${NC}"
      print_message "${RED}   Expected: $extension_id${NC}"
      print_message "${RED}   Found: $manifest_extension_id${NC}"
      return 1
    fi
    print_message "${GREEN}✅ Extension ID matches in manifest${NC}"
  fi
  
  print_message "${GREEN}${BOLD}Installation verification completed successfully!${NC}"
  return 0
}

# Function for diagnostic mode
diagnose_system() {
  print_message "${BLUE}${BOLD}=== MCP Host System Diagnosis ===${NC}"
  
  # System information
  print_message "${BLUE}System Information:${NC}"
  print_message "  OS: $OSTYPE"
  print_message "  Platform: $PLATFORM"
  print_message "  Shell: $SHELL"
  print_message "  User: $USER"
  print_message "  Home: $HOME"
  
  # Process check
  print_message "${BLUE}Process Check:${NC}"
  
  # Check PID file first
  local pid_file="$HOME/.nanobrowser/mcp-host.pid"
  if [ -f "$pid_file" ]; then
    local pid_from_file=$(cat "$pid_file" 2>/dev/null | tr -d '\n' | tr -d ' ')
    print_message "  PID file exists: $pid_file"
    print_message "    PID from file: $pid_from_file"
    if [ -n "$pid_from_file" ] && [[ "$pid_from_file" =~ ^[0-9]+$ ]]; then
      if kill -0 "$pid_from_file" 2>/dev/null; then
        print_message "    Process $pid_from_file is running"
      else
        print_message "    Process $pid_from_file is NOT running (stale PID file)"
      fi
    else
      print_message "    Invalid PID in file"
    fi
  else
    print_message "  No PID file found"
  fi
  
  local mcp_pids=$(find_mcp_processes)
  if [ -n "$mcp_pids" ]; then
    print_message "  Found MCP processes: $mcp_pids"
    for pid in $mcp_pids; do
      [ -z "$pid" ] && continue
      local health=$(check_process_health $pid && echo "healthy" || echo "unhealthy")
      local cmd=$(ps -p $pid -o args= 2>/dev/null || echo "unknown")
      print_message "    PID $pid: $health - $cmd"
    done
  else
    print_message "  No MCP Host processes found"
  fi
  
  # Port check
  print_message "${BLUE}Port Check:${NC}"
  if command -v lsof &> /dev/null; then
    local port_usage=$(lsof -i:9666 2>/dev/null || echo "")
    if [ -n "$port_usage" ]; then
      print_message "  Port 9666 usage:"
      echo "$port_usage" | while read line; do
        print_message "    $line"
      done
    else
      print_message "  Port 9666 is available"
    fi
  else
    print_message "  lsof not available, cannot check port usage"
  fi
  
  # File system check
  print_message "${BLUE}Installation Files Check:${NC}"
  local nanobrowser_dir="$HOME/.nanobrowser"
  if [ -d "$nanobrowser_dir" ]; then
    print_message "  Nanobrowser directory exists: $nanobrowser_dir"
    ls -la "$nanobrowser_dir" | while read line; do
      print_message "    $line"
    done
  else
    print_message "  Nanobrowser directory not found"
  fi
  
  # Chrome integration check
  print_message "${BLUE}Chrome Integration Check:${NC}"
  local manifest_dirs=("$CHROME_NM_DIR" "$CHROME_CANARY_NM_DIR" "$CHROME_DEV_NM_DIR" "$CHROMIUM_NM_DIR")
  for dir in "${manifest_dirs[@]}"; do
    if [ -d "$dir" ]; then
      print_message "  $dir exists"
      if ls "$dir"/*.json >/dev/null 2>&1; then
        ls "$dir"/*.json | while read manifest; do
          print_message "    Found manifest: $(basename "$manifest")"
        done
      else
        print_message "    No manifest files found"
      fi
    else
      print_message "  $dir does not exist"
    fi
  done
  
  print_message "${GREEN}${BOLD}Diagnosis completed${NC}"
}

# Native messaging host name (must follow Chrome's naming rules)
HOST_NAME="ai.nanobrowser.mcp.host"

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  PLATFORM="linux"
  # User-level directories
  CHROME_NM_DIR="$HOME/.config/google-chrome/NativeMessagingHosts"
  CHROME_CANARY_NM_DIR="$HOME/.config/google-chrome-unstable/NativeMessagingHosts"
  CHROME_DEV_NM_DIR="$HOME/.config/google-chrome-unstable/NativeMessagingHosts"
  CHROMIUM_NM_DIR="$HOME/.config/chromium/NativeMessagingHosts"
  # System-level directories (would require sudo)
  # CHROME_NM_SYS_DIR="/etc/opt/chrome/native-messaging-hosts"
  # CHROMIUM_NM_SYS_DIR="/etc/chromium/native-messaging-hosts"
elif [[ "$OSTYPE" == "darwin"* ]]; then
  PLATFORM="macos"
  # User-level directories
  CHROME_NM_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
  CHROME_CANARY_NM_DIR="$HOME/Library/Application Support/Google/Chrome Canary/NativeMessagingHosts"
  CHROME_DEV_NM_DIR="$HOME/Library/Application Support/Google/Chrome Dev/NativeMessagingHosts"
  CHROMIUM_NM_DIR="$HOME/Library/Application Support/Chromium/NativeMessagingHosts"
  # System-level directories (would require sudo)
  # CHROME_NM_SYS_DIR="/Library/Google/Chrome/NativeMessagingHosts"
  # CHROMIUM_NM_SYS_DIR="/Library/Application Support/Chromium/NativeMessagingHosts"
else
  error_exit "Unsupported platform: $OSTYPE. This script only supports Linux and macOS."
fi

print_message "${BLUE}${BOLD}Nanobrowser MCP Native Messaging Host Installer${NC}"
print_message "${BLUE}Platform detected: ${BOLD}$PLATFORM${NC}"

# Get the directory of the script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
print_message "${BLUE}Installation directory: ${BOLD}$SCRIPT_DIR${NC}"

# Function to show help
show_help() {
  cat << EOF
${BLUE}${BOLD}Nanobrowser MCP Native Messaging Host Installer${NC}

${BOLD}USAGE:${NC}
  ./install.sh [OPTIONS]

${BOLD}OPTIONS:${NC}
  --dev, -d         Enable development mode
                    • Runs directly from source dist/ directory
                    • No file copying - changes reflected immediately after rebuild
                    • Ideal for debugging and development

  --force, -f       Force mode - automatically terminate existing processes
                    • Skips user prompts for process termination
                    • Useful for automated installations

  --cleanup, -c     Cleanup mode - only clean up processes and files
                    • Terminates existing MCP Host processes
                    • Cleans up temporary files and orphaned ports
                    • Does not perform installation

  --diagnose        Diagnostic mode - check system status
                    • Shows detailed system information
                    • Lists running processes and port usage
                    • Checks installation files and Chrome integration
                    • Useful for troubleshooting

  --help, -h        Show this help message and exit

${BOLD}EXAMPLES:${NC}
  ./install.sh                    # Production installation (default)
  ./install.sh --dev              # Development installation
  ./install.sh --force            # Force installation (auto-terminate processes)
  ./install.sh --cleanup          # Clean up existing processes only
  ./install.sh --diagnose         # Show system diagnostic information
  ./install.sh --help             # Show this help

${BOLD}MODES:${NC}
  ${BOLD}Production Mode (default):${NC}
    • Uses Bun compiled binary (standalone executable)
    • Self-contained, no Node.js dependencies required
    • Requires rebuild and reinstallation for updates

  ${BOLD}Development Mode (--dev):${NC}
    • Runs directly from source directory
    • No file copying required
    • Immediate reflection of changes after 'npm run build'
    • Easier debugging and iteration

${BOLD}REQUIREMENTS:${NC}
  • Node.js installed
  • Project built with 'npm run build'
  • For dev mode: node_modules installed with 'npm install'

${BOLD}SUPPORT:${NC}
  • Platforms: macOS, Linux
  • Browsers: Chrome, Chromium, Chrome Canary, Chrome Dev
EOF
}

# Check command line arguments
DEV_MODE=false
FORCE_MODE=false
CLEANUP_ONLY=false
DIAGNOSE_MODE=false

case "$1" in
  --help|-h)
    show_help
    exit 0
    ;;
  --dev|-d)
    DEV_MODE=true
    print_message "${YELLOW}${BOLD}Development mode enabled${NC}"
    print_message "${YELLOW}Host will run directly from source directory for easier debugging${NC}"
    ;;
  --force|-f)
    FORCE_MODE=true
    print_message "${YELLOW}${BOLD}Force mode enabled${NC}"
    print_message "${YELLOW}Will automatically terminate existing processes${NC}"
    ;;
  --cleanup|-c)
    CLEANUP_ONLY=true
    print_message "${YELLOW}${BOLD}Cleanup mode enabled${NC}"
    print_message "${YELLOW}Will clean up processes and files only (no installation)${NC}"
    ;;
  --diagnose)
    DIAGNOSE_MODE=true
    print_message "${BLUE}${BOLD}Diagnostic mode enabled${NC}"
    print_message "${BLUE}Will show detailed system information${NC}"
    ;;
  "")
    # No arguments - default production mode
    ;;
  *)
    print_message "${RED}${BOLD}Unknown option: $1${NC}"
    print_message "${YELLOW}Use --help for available options${NC}"
    exit 1
    ;;
esac

# Handle special modes first
if [ "$DIAGNOSE_MODE" = true ]; then
  diagnose_system
  exit 0
fi

if [ "$CLEANUP_ONLY" = true ]; then
  print_message "${BLUE}${BOLD}=== MCP Host Cleanup Mode ===${NC}"
  
  if [ "$FORCE_MODE" = true ]; then
    print_message "${YELLOW}Force mode: Will terminate all MCP Host processes${NC}"
    cleanup_zombie_processes true
  else
    print_message "${BLUE}Interactive cleanup mode${NC}"
    cleanup_zombie_processes false
  fi
  
  cleanup_orphaned_ports
  cleanup_temp_files
  
  print_message "${GREEN}${BOLD}Cleanup completed${NC}"
  exit 0
fi

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
  error_exit "Node.js is not installed. Please install Node.js and try again."
fi

# Perform pre-installation cleanup
pre_install_cleanup $FORCE_MODE

# Check if Bun binary exists
BUN_BINARY="$SCRIPT_DIR/bin/nanobrowser-mcp-host-bun"
if [ ! -f "$BUN_BINARY" ]; then
  error_exit "Bun binary not found at $BUN_BINARY. Please run 'npm run build:bun' first."
fi

print_message "${GREEN}Using Bun compiled binary for Nanobrowser MCP Native Messaging Host...${NC}"
cd "$SCRIPT_DIR"

# Create required directories
NANOBROWSER_DIR="$HOME/.nanobrowser"
LOGS_DIR="$NANOBROWSER_DIR/logs"
BIN_DIR="$NANOBROWSER_DIR/bin"

mkdir -p "$LOGS_DIR"
mkdir -p "$BIN_DIR"

print_message "${BLUE}Directories created:${NC}"
print_message "${BLUE}  - Log directory: ${BOLD}$LOGS_DIR${NC}"
print_message "${BLUE}  - Binary directory: ${BOLD}$BIN_DIR${NC}"

# Copy the Bun binary
print_message "${BLUE}Installing Bun binary...${NC}"
cp "$BUN_BINARY" "$BIN_DIR/nanobrowser-mcp-host"
chmod +x "$BIN_DIR/nanobrowser-mcp-host"
print_message "${GREEN}Bun binary installed successfully.${NC}"

# Create the host script
HOST_SCRIPT="$BIN_DIR/mcp-host.sh"
print_message "${BLUE}Creating host script: ${BOLD}$HOST_SCRIPT${NC}"

if [ "$DEV_MODE" = true ]; then
  # Development mode: run directly from source using Node.js
  if [ ! -d "$SCRIPT_DIR/dist" ]; then
    error_exit "Build directory 'dist' not found. Please build the project first with 'npm run build'."
  fi
  if [ ! -d "$SCRIPT_DIR/node_modules" ]; then
    error_exit "node_modules directory not found. Please run 'npm install' first."
  fi
  
  cat > "$HOST_SCRIPT" << EOF
#!/bin/bash

# Set log level (can be overridden by install.sh)
export LOG_LEVEL=INFO

# Set log directory and file
export LOG_DIR="$HOME/.nanobrowser/logs"
export LOG_FILE="mcp-host.log"

# Create logs directory if it doesn't exist
mkdir -p "\$LOG_DIR"

# Development mode: run directly from source dist directory
cd "$SCRIPT_DIR/dist"

# Run MCP host using Node.js - logs are handled internally by the Logger class
node index.js
EOF
else
  # Production mode: use the Bun compiled binary
  cat > "$HOST_SCRIPT" << EOF
#!/bin/bash

# Set log level (can be overridden by install.sh)
export LOG_LEVEL=INFO

# Set log directory and file
export LOG_DIR="$HOME/.nanobrowser/logs"
export LOG_FILE="mcp-host.log"

# Create logs directory if it doesn't exist
mkdir -p "\$LOG_DIR"

# Production mode: use the Bun compiled binary
# The binary is self-contained and doesn't need Node.js
"$BIN_DIR/nanobrowser-mcp-host"
EOF
fi

chmod +x "$HOST_SCRIPT"

# Create/update the manifest with the correct values - using proper naming convention
MANIFEST_FILENAME="$HOST_NAME.json"
MANIFEST_PATH="$SCRIPT_DIR/$MANIFEST_FILENAME"
print_message "${BLUE}Creating Native Messaging Host manifest: ${BOLD}$MANIFEST_PATH${NC}"

# Get the extension ID from the user
print_message "${YELLOW}The extension ID is required to connect Chrome with the native messaging host.${NC}"
read -p "Enter your Chrome extension ID: " EXTENSION_ID
if [[ -z "$EXTENSION_ID" ]]; then
  error_exit "Extension ID cannot be empty."
fi

# Check if extension ID matches the expected format (32 character string)
if ! [[ $EXTENSION_ID =~ ^[a-z]{32}$ ]]; then
  print_message "${YELLOW}Warning: Extension ID format looks unusual. Standard Chrome extension IDs are 32 lowercase letters.${NC}"
  read -p "Continue anyway? (y/n): " CONFIRM
  if [[ "$CONFIRM" != "y" ]]; then
    error_exit "Installation aborted by user."
  fi
fi

# Create the manifest JSON directly
cat > "$MANIFEST_PATH" << EOF
{
  "name": "$HOST_NAME",
  "description": "Nanobrowser MCP Native Messaging Host",
  "path": "$HOST_SCRIPT",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$EXTENSION_ID/"]
}
EOF

# Set log level for the host
LOG_LEVELS=("ERROR" "WARN" "INFO" "DEBUG")
DEFAULT_LOG_LEVEL="INFO"

print_message "${BLUE}Available log levels: ${BOLD}${LOG_LEVELS[*]}${NC}"
read -p "Enter log level for MCP Host [default: $DEFAULT_LOG_LEVEL]: " LOG_LEVEL

# Validate and set log level
LOG_LEVEL=${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}
LOG_LEVEL=$(echo "$LOG_LEVEL" | tr '[:lower:]' '[:upper:]')
VALID_LEVEL=false

for level in "${LOG_LEVELS[@]}"; do
  if [ "$LOG_LEVEL" = "$level" ]; then
    VALID_LEVEL=true
    break
  fi
done

if [ "$VALID_LEVEL" = false ]; then
  print_message "${YELLOW}Invalid log level: $LOG_LEVEL. Using default: $DEFAULT_LOG_LEVEL${NC}"
  LOG_LEVEL=$DEFAULT_LOG_LEVEL
fi

# Update host script with log level
sed -i.bak "s|export LOG_LEVEL=INFO|export LOG_LEVEL=$LOG_LEVEL|g" "$HOST_SCRIPT"
rm "$HOST_SCRIPT.bak"

print_message "${GREEN}Logs will be written to $HOME/.nanobrowser/logs/mcp-host.log${NC}"

# Create Native Messaging directories if they don't exist
print_message "${BLUE}Creating Native Messaging Host directories...${NC}"
mkdir -p "$CHROME_NM_DIR"
mkdir -p "$CHROME_CANARY_NM_DIR"
mkdir -p "$CHROME_DEV_NM_DIR"
mkdir -p "$CHROMIUM_NM_DIR"

# Install the manifest with proper name
print_message "${BLUE}Installing Native Messaging Host manifest...${NC}"
cp "$MANIFEST_PATH" "$CHROME_NM_DIR/$MANIFEST_FILENAME"
cp "$MANIFEST_PATH" "$CHROME_CANARY_NM_DIR/$MANIFEST_FILENAME"
cp "$MANIFEST_PATH" "$CHROME_DEV_NM_DIR/$MANIFEST_FILENAME"
cp "$MANIFEST_PATH" "$CHROMIUM_NM_DIR/$MANIFEST_FILENAME"

# Perform comprehensive installation verification
if verify_installation "$HOST_SCRIPT" "$MANIFEST_PATH" "$EXTENSION_ID"; then
  print_message "${GREEN}${BOLD}Nanobrowser MCP Native Messaging Host has been installed successfully!${NC}"
  print_message "${GREEN}Host path: ${BOLD}$HOST_SCRIPT${NC}"
  print_message "${GREEN}${BOLD}Manifest installed in:${NC}"
  print_message "${GREEN}  - $CHROME_NM_DIR${NC}"
  print_message "${GREEN}  - $CHROME_CANARY_NM_DIR${NC}"
  print_message "${GREEN}  - $CHROME_DEV_NM_DIR${NC}"
  print_message "${GREEN}  - $CHROMIUM_NM_DIR${NC}"
else
  error_exit "Installation verification failed. Please check the errors above and try again."
fi

print_message "${YELLOW}${BOLD}Important:${NC} If you are using Chrome, you may need to restart it for the changes to take effect."
print_message "${YELLOW}If you still receive 'Native host not found' errors, please verify:${NC}"
print_message "${YELLOW}1. The extension ID is correct ($EXTENSION_ID)${NC}"
print_message "${YELLOW}2. The Chrome process can access $HOST_SCRIPT${NC}"
print_message "${YELLOW}3. Check the logs at $HOME/.nanobrowser/logs/mcp-host.log for any errors${NC}"

if [ "$DEV_MODE" = true ]; then
  print_message "${BLUE}${BOLD}Development Mode Notes:${NC}"
  print_message "${BLUE}• Host runs directly from $SCRIPT_DIR/dist${NC}"
  print_message "${BLUE}• No file copying - changes to source are reflected immediately after rebuild${NC}"
  print_message "${BLUE}• To rebuild: npm run build${NC}"
  print_message "${BLUE}• To switch to production mode: ./install.sh (without --dev flag)${NC}"
else
  print_message "${BLUE}${BOLD}Production Mode Notes:${NC}"
  print_message "${BLUE}• Host runs from Bun compiled binary${NC}"
  print_message "${BLUE}• To update: rebuild with 'npm run build:bun' and run ./install.sh again${NC}"
  print_message "${BLUE}• For development mode: ./install.sh --dev${NC}"
fi
