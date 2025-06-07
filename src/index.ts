import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { createLogger } from './logger.js';
import { McpServerManager } from './mcp-server.js';
import { NativeMessaging } from './messaging.js';
import { CurrentStateResource } from './resources/index.js';
import { NavigateToTool, RunTaskTool } from './tools/index.js';
import { RpcRequest, RpcResponse } from './types.js';

// Create a logger instance for the main module
const logger = createLogger('main');

// Define version and basic information
const HOST_INFO = {
  name: 'nanobrowser-mcp-host',
  version: '0.1.0',
  runMode: process.env.RUN_MODE || 'stdio',
};

// PID file management
const nanobrowserDir = path.join(os.homedir(), '.nanobrowser');
const pidFilePath = path.join(nanobrowserDir, 'mcp-host.pid');

/**
 * Create PID file with current process ID
 */
function createPidFile(): void {
  try {
    // Ensure the directory exists
    if (!fs.existsSync(nanobrowserDir)) {
      fs.mkdirSync(nanobrowserDir, { recursive: true });
    }

    // Write current process PID to file
    fs.writeFileSync(pidFilePath, process.pid.toString(), 'utf8');
    logger.info(`Created PID file: ${pidFilePath} with PID: ${process.pid}`);
  } catch (error) {
    logger.error('Failed to create PID file:', error);
  }
}

/**
 * Remove PID file
 */
function removePidFile(): void {
  try {
    if (fs.existsSync(pidFilePath)) {
      fs.unlinkSync(pidFilePath);
      logger.info(`Removed PID file: ${pidFilePath}`);
    }
  } catch (error) {
    logger.error('Failed to remove PID file:', error);
  }
}

/**
 * Check if another instance is already running
 */
function checkExistingInstance(): boolean {
  if (!fs.existsSync(pidFilePath)) {
    return false;
  }

  try {
    const existingPid = parseInt(fs.readFileSync(pidFilePath, 'utf8').trim(), 10);
    
    if (isNaN(existingPid)) {
      logger.warn('Invalid PID in PID file, removing stale file');
      removePidFile();
      return false;
    }

    // Check if process with this PID is still running
    try {
      process.kill(existingPid, 0); // Signal 0 checks if process exists without killing it
      logger.warn(`Another MCP Host instance is already running with PID: ${existingPid}`);
      return true;
    } catch (error) {
      // Process doesn't exist, remove stale PID file
      logger.info(`Removing stale PID file for non-existent process ${existingPid}`);
      removePidFile();
      return false;
    }
  } catch (error) {
    logger.error('Error checking existing instance:', error);
    removePidFile();
    return false;
  }
}

// Check for existing instance before starting
if (checkExistingInstance()) {
  logger.error('Another MCP Host instance is already running. Exiting.');
  process.exit(1);
}

// Create PID file for this instance
createPidFile();

// Initialize status tracking
const hostStatus = {
  isConnected: true,
  startTime: Date.now(),
  lastPing: Date.now(),
  ...HOST_INFO,
};

logger.info(`Starting MCP Host in ${hostStatus.runMode} mode`);

// Auto-start port (use PORT env var or default to 3000)
const mcpServerPort = process.env.PORT ? parseInt(process.env.PORT, 10) : 9666;
const mcpServerManager = new McpServerManager({
  port: mcpServerPort,
  logLevel: 'info',
});

// Initialize the native messaging handler
const messaging = new NativeMessaging();

// Register handlers
messaging.registerHandler('init', async () => {
  logger.info('mcp_host received init');
});

messaging.registerHandler('shutdown', async () => {
  logger.info('mcp_host received shutdown');

  // Shut down MCP server if it's running
  if (mcpServerManager.isServerRunning()) {
    logger.info('Shutting down MCP server');
    await mcpServerManager.shutdown();
  }
});

messaging.registerHandler('error', async (data: any): Promise<void> => {
  logger.error('mcp_host received error:', data);
});

messaging.registerRpcMethod('ping', async (req: RpcRequest): Promise<RpcResponse> => {
  logger.debug('received ping request:', req);

  return {
    result: {
      timestamp: Date.now(),
    },
  };
});

const lowLevelToolsEnabled = process.env.LOW_LEVEL_TOOLS_ENABLED === 'true'

// Register resources with the MCP server manager
if (lowLevelToolsEnabled) {
  mcpServerManager.registerResource(new CurrentStateResource(messaging));
  logger.info(`Registered resources with MCP server`);
}

// Initialize tools with the messaging instance
if (lowLevelToolsEnabled) {
  mcpServerManager.registerTool(new NavigateToTool(messaging));
}

mcpServerManager.registerTool(new RunTaskTool(messaging));
logger.info(`Registered tools with MCP server`);

// Auto-start MCP Server when MCP Host starts
logger.info(`Auto-starting MCP HTTP server on port ${mcpServerPort}`);
mcpServerManager
  .start()
  .then(result => {
    if (result) {
      logger.info(`MCP HTTP server auto-started successfully on port ${mcpServerPort}`);
    } else {
      logger.error('Failed to auto-start MCP HTTP server: Server already running');
    }
  })
  .catch((error: Error & { code?: string }) => {
    if (error.code === 'EADDRINUSE') {
      logger.error(`Exception during MCP HTTP server auto-start: Port ${mcpServerPort} is already in use`);
    } else {
      logger.error('Exception during MCP HTTP server auto-start:', error);
    }

    process.exit(1); // Exit with error code to indicate failure
  });

// Send initial ready message to let the extension know we're available
messaging.sendMessage({
  type: 'status',
  data: {
    isConnected: true,
    startTime: hostStatus.startTime,
    version: hostStatus.version,
    runMode: hostStatus.runMode,
  },
});

// Handle exit signals gracefully, ensuring MCP server shutdown
process.on('SIGINT', async () => {
  logger.info('Received SIGINT signal, shutting down');

  // First shut down the MCP server
  if (mcpServerManager.isServerRunning()) {
    logger.info('Shutting down MCP server before exit');
    mcpServerManager.shutdown();
    logger.info('Shutting down MCP server before exit ok');
  }

  // Clean up PID file
  removePidFile();

  process.exit(0);
});

process.on('SIGTERM', async () => {
  logger.info('Received SIGTERM signal, shutting down');

  // First shut down the MCP server
  if (mcpServerManager.isServerRunning()) {
    logger.info('Shutting down MCP server before exit');
    await mcpServerManager.shutdown();
  }

  // Clean up PID file
  removePidFile();

  process.exit(0);
});

// Handle process exit to clean up PID file
process.on('exit', () => {
  removePidFile();
});

// Handle uncaught exceptions - clean up before exit
process.on('uncaughtException', error => {
  logger.error('Uncaught exception:', error);
  messaging.sendMessage({
    type: 'error',
    error: error.message,
    stack: error.stack,
  });
  
  // Clean up PID file before exit
  removePidFile();
  process.exit(1);
});

// Handle unhandled promise rejections
process.on('unhandledRejection', (reason, promise) => {
  logger.error('Unhandled promise rejection at:', promise, 'reason:', reason);
  
  // Clean up PID file before exit
  removePidFile();
  process.exit(1);
});

logger.info('MCP Host started successfully');
