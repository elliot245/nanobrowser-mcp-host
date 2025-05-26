# Nanobrowser MCP Host

A Chrome Native Messaging Host implementation for the Model Context Protocol (MCP), enabling secure communication between Chrome extensions and AI systems.

## Overview

Nanobrowser MCP Host provides a standardized interface for AI systems to interact with browser functionality through:

- **Browser Resources**: Access to DOM structures, page states, and browser information
- **Browser Tools**: Navigation, element interaction, and other browser operations
- **Secure Communication**: Chrome Native Messaging for secure local communication

The implementation follows a two-layer architecture:
1. External interface via HTTP/MCP protocol for AI systems
2. Internal interface via Chrome Native Messaging for browser communication

## Features

- **MCP Protocol Support**: Standardized interface following the Model Context Protocol
- **Resource Exposure**: Browser DOM, state, and other information as MCP resources
- **Tool Integration**: Browser operations (navigation, etc.) as callable MCP tools
- **Secure by Design**: Local-only communication with proper security boundaries

## Capabilities & API Reference

For detailed information about the built-in tools and resources provided by this MCP Host, see:

**[📖 MCP Server Capabilities](./docs/mcp-server-capabilities.md)**

This reference includes:
- Supported tools (navigation, task automation, etc.)
- Exposed browser resources (current state, tabs, etc.)  
- Input schemas and resource URIs

This document is recommended for developers and integrators who want to understand or extend the host's API surface.

## Requirements

- **Node.js**: v14 or higher
- **Chrome/Chromium**: Latest version recommended
- **Operating System**: Linux or macOS (Windows support coming soon)
- **Chrome Extension**: A companion extension with Native Messaging permissions

## Installation

### Quick Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/nanobrowser/nanobrowser-mcp-host.git
   cd nanobrowser-mcp-host
   ```

2. **Build the project**:
   ```bash
   # Use the correct Node.js version
   nvm use
   
   # Install dependencies
   pnpm install
   
   # Build the project
   pnpm build
   ```

3. **Run the installer script**:
   ```bash
   ./install.sh
   ```

4. **Follow the prompts**:
   - Enter your Chrome extension ID
   - Choose log level (ERROR, WARN, INFO, DEBUG)

5. **Restart Chrome** to apply the changes

### Manual Installation

If the installer script doesn't work for your environment:

1. **Build the project** as described above
2. **Create necessary directories**:
   ```bash
   mkdir -p ~/.nanobrowser/logs
   mkdir -p ~/.nanobrowser/bin
   mkdir -p ~/.nanobrowser/app
   ```

3. **Copy application files**:
   ```bash
   cp -r dist/* ~/.nanobrowser/app/
   ```

4. **Create a host script** in `~/.nanobrowser/bin/mcp-host.sh`:
   ```bash
   #!/bin/bash
   
   # Set log level
   export LOG_LEVEL=INFO
   
   # Set log directory and file
   export LOG_DIR="$HOME/.nanobrowser/logs"
   export LOG_FILE="mcp-host.log"
   
   # Create logs directory if it doesn't exist
   mkdir -p "$LOG_DIR"
   
   # Use the installed application files
   cd "$HOME/.nanobrowser/app"
   
   # Run MCP host - logs are handled internally by the Logger class
   node index.js
   ```

3. **Make it executable**:
   ```bash
   chmod +x ~/.nanobrowser/bin/mcp-host.sh
   ```

4. **Create a manifest file** in the appropriate Chrome Native Messaging directory:
   ```json
   {
     "name": "ai.nanobrowser.mcp.host",
     "description": "Nanobrowser MCP Native Messaging Host",
     "path": "/home/username/.nanobrowser/bin/mcp-host.sh",
     "type": "stdio",
     "allowed_origins": ["chrome-extension://your-extension-id/"]
   }
   ```

5. **Place the manifest file** in the correct location:
   - Linux: `~/.config/google-chrome/NativeMessagingHosts/`
   - macOS: `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`

## Usage

### Configuration

The host can be configured through environment variables:

- `LOG_LEVEL`: Set logging verbosity (ERROR, WARN, INFO, DEBUG)
- `PORT`: HTTP server port (default: 7890)

### Log Files

Logs are written to:
```
~/.nanobrowser/logs/mcp-host.log
```

### Troubleshooting

If you encounter issues:

1. Check the log file for detailed error messages
2. Verify the Chrome extension ID is correct
3. Ensure Chrome has permission to execute the host script
4. Restart Chrome after installation

## Development

### Running Tests

```bash
# Run all tests
pnpm test

# Run integration tests only
pnpm test:integration

# Run tests in watch mode
pnpm test:watch
```

### Building for Development

```bash
# Start in development mode
pnpm dev
```

## License

This project is licensed under the Apache License 2.0. See the [LICENSE](./LICENSE) file for details.
