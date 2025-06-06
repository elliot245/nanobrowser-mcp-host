#!/bin/bash

# Nanobrowser MCP Native Messaging Host Uninstaller
# This script uninstalls the Native Messaging Host and removes all files

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
  echo -e "$1"
}

# Print an error message and exit
error_exit() {
  print_message "${RED}${BOLD}ERROR:${NC} $1"
  exit 1
}

# Native messaging host name
HOST_NAME="ai.nanobrowser.mcp.host"

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  PLATFORM="linux"
  CHROME_NM_DIR="$HOME/.config/google-chrome/NativeMessagingHosts"
  CHROME_CANARY_NM_DIR="$HOME/.config/google-chrome-unstable/NativeMessagingHosts"
  CHROME_DEV_NM_DIR="$HOME/.config/google-chrome-unstable/NativeMessagingHosts"
  CHROMIUM_NM_DIR="$HOME/.config/chromium/NativeMessagingHosts"
elif [[ "$OSTYPE" == "darwin"* ]]; then
  PLATFORM="macos"
  CHROME_NM_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
  CHROME_CANARY_NM_DIR="$HOME/Library/Application Support/Google/Chrome Canary/NativeMessagingHosts"
  CHROME_DEV_NM_DIR="$HOME/Library/Application Support/Google/Chrome Dev/NativeMessagingHosts"
  CHROMIUM_NM_DIR="$HOME/Library/Application Support/Chromium/NativeMessagingHosts"
else
  error_exit "Unsupported platform: $OSTYPE. This script only supports Linux and macOS."
fi

print_message "${BLUE}${BOLD}Nanobrowser MCP Native Messaging Host Uninstaller${NC}"
print_message "${BLUE}Platform: $PLATFORM${NC}"

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Define paths
NANOBROWSER_DIR="$HOME/.nanobrowser"
MANIFEST_FILENAME="$HOST_NAME.json"

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
  
  # Method 2: Find by port usage (port 7890 is default for MCP Host)
  if command -v lsof &> /dev/null; then
    local port_pids=$(lsof -ti:7890 2>/dev/null || true)
    pids="$pids $port_pids"
  fi
  
  # Remove duplicates and empty entries, then return
  echo $pids | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' '
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

# Step 1: Kill running processes
print_message "${BLUE}Terminating running MCP Host processes...${NC}"

mcp_pids=$(find_mcp_processes)
if [ -n "$mcp_pids" ]; then
  print_message "${YELLOW}Found MCP Host processes: $mcp_pids${NC}"
  for pid in $mcp_pids; do
    [ -z "$pid" ] && continue
    terminate_process_gracefully $pid
  done
else
  print_message "${GREEN}No MCP Host processes found${NC}"
fi

# Clean up PID file
pid_file="$HOME/.nanobrowser/mcp-host.pid"
if [ -f "$pid_file" ]; then
  rm -f "$pid_file"
  print_message "${GREEN}Removed PID file: $pid_file${NC}"
fi

# Step 2: Remove manifest files
print_message "${BLUE}Removing manifest files...${NC}"

for dir in "$CHROME_NM_DIR" "$CHROME_CANARY_NM_DIR" "$CHROME_DEV_NM_DIR" "$CHROMIUM_NM_DIR"; do
  if [ -f "$dir/$MANIFEST_FILENAME" ]; then
    rm -f "$dir/$MANIFEST_FILENAME"
    print_message "${GREEN}Removed manifest from: $dir${NC}"
  fi
done

# Step 3: Remove all nanobrowser files
print_message "${BLUE}Removing all Nanobrowser files...${NC}"

if [ -d "$NANOBROWSER_DIR" ]; then
  rm -rf "$NANOBROWSER_DIR"
  print_message "${GREEN}Removed directory: $NANOBROWSER_DIR${NC}"
fi

# Remove local manifest
MANIFEST_PATH="$SCRIPT_DIR/$MANIFEST_FILENAME"
if [ -f "$MANIFEST_PATH" ]; then
  rm -f "$MANIFEST_PATH"
  print_message "${GREEN}Removed local manifest${NC}"
fi

# Remove backup files
rm -f "$SCRIPT_DIR"/*.bak 2>/dev/null || true

print_message "${GREEN}${BOLD}Uninstall completed successfully!${NC}"
print_message "${YELLOW}Please restart Chrome for changes to take effect.${NC}"
