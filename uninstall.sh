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

# Step 1: Kill running processes
print_message "${BLUE}Terminating running processes...${NC}"

# Kill mcp-host processes
if pgrep -f "node.*mcp-host" > /dev/null; then
  pkill -f "node.*mcp-host" 2>/dev/null || true
  print_message "${GREEN}Terminated mcp-host processes${NC}"
fi

# Kill processes on port 7890
if command -v lsof &> /dev/null; then
  PORT_PIDS=$(lsof -i :7890 -t 2>/dev/null || true)
  if [ -n "$PORT_PIDS" ]; then
    kill -9 $PORT_PIDS 2>/dev/null || true
    print_message "${GREEN}Terminated processes on port 7890${NC}"
  fi
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
