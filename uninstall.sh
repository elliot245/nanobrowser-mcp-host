#!/bin/bash

# Nanobrowser MCP Native Messaging Host Uninstaller
# This script uninstalls the Native Messaging Host for macOS and Linux
# and kills any running mcp-host processes

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
elif [[ "$OSTYPE" == "darwin"* ]]; then
  PLATFORM="macos"
  # User-level directories
  CHROME_NM_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
  CHROME_CANARY_NM_DIR="$HOME/Library/Application Support/Google/Chrome Canary/NativeMessagingHosts"
  CHROME_DEV_NM_DIR="$HOME/Library/Application Support/Google/Chrome Dev/NativeMessagingHosts"
  CHROMIUM_NM_DIR="$HOME/Library/Application Support/Chromium/NativeMessagingHosts"
else
  error_exit "Unsupported platform: $OSTYPE. This script only supports Linux and macOS."
fi

print_message "${BLUE}${BOLD}Nanobrowser MCP Native Messaging Host Uninstaller${NC}"
print_message "${BLUE}Platform detected: ${BOLD}$PLATFORM${NC}"

# Get the directory of the script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Define paths
NANOBROWSER_DIR="$HOME/.nanobrowser"
LOGS_DIR="$NANOBROWSER_DIR/logs"
BIN_DIR="$NANOBROWSER_DIR/bin"
APP_DIR="$NANOBROWSER_DIR/app"
HOST_SCRIPT="$BIN_DIR/mcp-host.sh"
MANIFEST_FILENAME="$HOST_NAME.json"

# Step 1: Kill any running mcp-host processes
print_message "${BLUE}Looking for and terminating running mcp-host processes...${NC}"

# Find and kill Node.js processes that are running the mcp-host
if pgrep -f "node.*mcp-host" > /dev/null; then
  print_message "${YELLOW}Found running mcp-host processes. Terminating...${NC}"
  
  # Get the PIDs
  HOST_PIDS=$(pgrep -f "node.*mcp-host")
  
  # Kill each process
  for pid in $HOST_PIDS; do
    if kill -15 "$pid" 2>/dev/null; then
      print_message "${GREEN}Successfully terminated process with PID: $pid${NC}"
    else
      print_message "${YELLOW}Process with PID: $pid already terminated or permission denied${NC}"
    fi
  done
  
  # Double-check if any processes are still running after a short delay
  sleep 1
  if pgrep -f "node.*mcp-host" > /dev/null; then
    print_message "${YELLOW}Some processes still running. Attempting to force kill...${NC}"
    pkill -9 -f "node.*mcp-host" 2>/dev/null || true
  fi
  
  print_message "${GREEN}All mcp-host processes have been terminated.${NC}"
else
  print_message "${GREEN}No running mcp-host processes found.${NC}"
fi

# Step 1B: Find and kill processes listening on port 7890 (MCP server)
print_message "${BLUE}Looking for and terminating processes listening on port 7890 (MCP server)...${NC}"

# Function to get PID of process using port 7890
get_pid_on_port() {
  if command -v lsof &> /dev/null; then
    # lsof is available (commonly on macOS and many Linux distros)
    lsof -i :7890 -t 2>/dev/null
  elif command -v netstat &> /dev/null; then
    # netstat is an alternative (available on most systems)
    netstat -tunlp 2>/dev/null | grep ":7890 " | awk '{print $7}' | cut -d/ -f1
  elif command -v ss &> /dev/null; then
    # ss is another alternative (newer Linux systems)
    ss -tunlp | grep ":7890 " | awk '{print $7}' | cut -d, -f2 | cut -d= -f2
  else
    print_message "${YELLOW}No suitable command found to check for processes on port 7890${NC}"
    return 1
  fi
}

PORT_PIDS=$(get_pid_on_port)

if [ -n "$PORT_PIDS" ]; then
  print_message "${YELLOW}Found processes listening on port 7890. Terminating...${NC}"
  
  # Kill each process
  for pid in $PORT_PIDS; do
    if kill -15 "$pid" 2>/dev/null; then
      print_message "${GREEN}Successfully terminated process with PID: $pid listening on port 7890${NC}"
    else
      print_message "${YELLOW}Process with PID: $pid already terminated or permission denied${NC}"
    fi
  done
  
  # Double-check if any processes are still using the port after a short delay
  sleep 1
  REMAINING_PIDS=$(get_pid_on_port)
  
  if [ -n "$REMAINING_PIDS" ]; then
    print_message "${YELLOW}Some processes still using port 7890. Attempting to force kill...${NC}"
    for pid in $REMAINING_PIDS; do
      if kill -9 "$pid" 2>/dev/null; then
        print_message "${GREEN}Force killed process with PID: $pid${NC}"
      else
        print_message "${RED}Failed to terminate process with PID: $pid${NC}"
      fi
    done
  fi
  
  print_message "${GREEN}All processes on port 7890 have been terminated.${NC}"
else
  print_message "${GREEN}No processes found listening on port 7890.${NC}"
fi

# Step 2: Remove the manifest files
print_message "${BLUE}Removing Native Messaging Host manifests...${NC}"

for dir in "$CHROME_NM_DIR" "$CHROME_CANARY_NM_DIR" "$CHROME_DEV_NM_DIR" "$CHROMIUM_NM_DIR"; do
  if [ -f "$dir/$MANIFEST_FILENAME" ]; then
    rm -f "$dir/$MANIFEST_FILENAME"
    print_message "${GREEN}Removed manifest from: $dir${NC}"
  else
    print_message "${YELLOW}No manifest found in: $dir${NC}"
  fi
done

# Step 3: Ask user if they want to keep logs
print_message "${YELLOW}Do you want to keep the log files?${NC}"
read -p "Keep logs? (y/n) [default: y]: " KEEP_LOGS
KEEP_LOGS=${KEEP_LOGS:-y}

# Step 4: Remove the installed files
print_message "${BLUE}Removing installed files...${NC}"

# Remove host script
if [ -f "$HOST_SCRIPT" ]; then
  rm -f "$HOST_SCRIPT"
  print_message "${GREEN}Removed host script: $HOST_SCRIPT${NC}"
fi

# Remove application files
if [ -d "$APP_DIR" ]; then
  rm -rf "$APP_DIR"
  print_message "${GREEN}Removed application directory: $APP_DIR${NC}"
fi

# Remove bin directory if empty
if [ -d "$BIN_DIR" ] && [ -z "$(ls -A "$BIN_DIR")" ]; then
  rmdir "$BIN_DIR"
  print_message "${GREEN}Removed empty binary directory: $BIN_DIR${NC}"
fi

# Handle log files based on user choice
if [ "$KEEP_LOGS" = "n" ] || [ "$KEEP_LOGS" = "N" ]; then
  if [ -d "$LOGS_DIR" ]; then
    rm -rf "$LOGS_DIR"
    print_message "${GREEN}Removed logs directory: $LOGS_DIR${NC}"
  fi
  
  # Remove nanobrowser directory if empty
  if [ -d "$NANOBROWSER_DIR" ] && [ -z "$(ls -A "$NANOBROWSER_DIR")" ]; then
    rmdir "$NANOBROWSER_DIR"
    print_message "${GREEN}Removed empty Nanobrowser directory: $NANOBROWSER_DIR${NC}"
  fi
else
  print_message "${GREEN}Keeping log files in: $LOGS_DIR${NC}"
fi

# Remove the local manifest file if it exists
MANIFEST_PATH="$SCRIPT_DIR/$MANIFEST_FILENAME"
if [ -f "$MANIFEST_PATH" ]; then
  rm -f "$MANIFEST_PATH"
  print_message "${GREEN}Removed local manifest: $MANIFEST_PATH${NC}"
fi

print_message "${GREEN}${BOLD}Nanobrowser MCP Native Messaging Host has been uninstalled successfully!${NC}"
print_message "${YELLOW}${BOLD}Important:${NC} If you are using Chrome, you may need to restart it for the changes to take effect."
