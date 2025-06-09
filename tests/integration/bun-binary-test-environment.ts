import { ChildProcess, spawn } from 'child_process';
import { accessSync, constants, existsSync } from 'fs';
import * as net from 'net';
import { resolve } from 'path';
import { createLogger } from '../../src/logger';
import { NativeMessaging } from '../../src/messaging.js';
import { MessageHandler, type RpcHandler, RpcRequest, RpcRequestOptions, RpcResponse } from '../../src/types';
import { McpHttpClient } from './mcp-http-client';

/**
 * Test environment for Bun Binary integration tests
 * Similar to McpHostTestEnvironment but uses the compiled binary instead of Node.js
 */
export class BunBinaryTestEnvironment {
  private logger = createLogger('bun-binary-test-environment');
  private hostProcess: ChildProcess | null = null;
  private mcpClient: McpHttpClient | null = null;
  private nativeMessaging: NativeMessaging | null = null;
  private testNanobrowserDir: string | null = null;

  private port: number;
  private exitCode: number | null = null;
  private exitPromise: Promise<number> | null = null;
  private binaryPath: string;

  /**
   * Create a new test environment for Bun binary
   * @param options Configuration options
   */
  constructor(options?: { port?: number; binaryPath?: string }) {
    // Use provided port or find an available one
    this.port = options?.port || 0; // 0 will be replaced with actual port during setup
    this.binaryPath = options?.binaryPath || resolve('./bin/nanobrowser-mcp-host-bun');
  }

  /**
   * Verify that the Bun binary exists and is executable
   * @returns Promise that resolves if binary is ready, rejects otherwise
   */
  private async verifyBinaryExists(): Promise<void> {
    if (!existsSync(this.binaryPath)) {
      throw new Error(`Bun binary not found at ${this.binaryPath}. Run 'npm run build:bun' first.`);
    }

    try {
      // Check if file is executable
      accessSync(this.binaryPath, constants.F_OK | constants.X_OK);
      this.logger.info(`Bun binary verified at ${this.binaryPath}`);
    } catch (error) {
      throw new Error(`Bun binary at ${this.binaryPath} is not executable: ${error}`);
    }
  }

  /**
   * Find an available port for the MCP host to listen on
   * This allows multiple test instances to run in parallel
   * @returns A promise that resolves to an available port number
   */
  private async findAvailablePort(): Promise<number> {
    return new Promise((resolve, reject) => {
      // Create a server to listen on port 0 (OS will assign a free port)
      const server = net.createServer();
      server.on('error', reject);

      // Listen on port 0 (OS will assign an available port)
      server.listen(0, () => {
        // Get the assigned port
        const address = server.address() as net.AddressInfo;
        const port = address.port;

        // Close the server and resolve with the port
        server.close(() => {
          resolve(port);
        });
      });
    });
  }

  /**
   * Wait for the host to be ready
   * @param timeout Maximum time to wait in milliseconds
   * @returns A promise that resolves when the host is ready
   */
  private async waitForHostReady(timeout = 30000): Promise<void> {
    const startTime = Date.now();
    let attemptCount = 0;

    this.logger.info(`Waiting for Bun binary host to be ready at http://localhost:${this.port}...`);

    // Check repeatedly until host is ready or timeout
    while (Date.now() - startTime < timeout) {
      attemptCount++;
      try {
        // Try to connect to the HTTP server
        if (this.mcpClient) {
          this.logger.debug(`Attempt ${attemptCount}: Testing connection to MCP server...`);
          // Attempt a basic request
          await this.mcpClient.initialize();
          this.logger.info(`Bun binary host is ready on port ${this.port}`);
          return; // Success
        } else {
          this.logger.debug(`MCP client not initialized yet`);
        }
      } catch (error) {
        this.logger.debug(
          `Attempt ${attemptCount} failed: ${error instanceof Error ? error.message : 'Unknown error'}`,
        );
      }

      // Wait a bit before retrying
      const waitTime = 500; // Longer wait between attempts
      this.logger.debug(`Waiting ${waitTime}ms before retrying...`);
      await new Promise(resolve => setTimeout(resolve, waitTime));
    }

    // If we get here, host is not ready within timeout
    if (this.hostProcess) {
      this.logger.error('Process output:', this.hostProcess.stdio);
    }

    throw new Error(`Bun binary host not ready after ${timeout}ms (attempted ${attemptCount} times)`);
  }

  /**
   * Setup the test environment
   * @returns A promise that resolves when the environment is ready
   */
  async setup(): Promise<void> {
    // First verify the binary exists
    await this.verifyBinaryExists();

    // Find available port if not specified
    if (this.port === 0) {
      this.port = await this.findAvailablePort();
    }

    // Create unique test instance directory to avoid conflicts
    const { tmpdir } = await import('os');
    const { join } = await import('path');
    const { existsSync, mkdirSync, rmSync } = await import('fs');
    
    // Create a unique test instance ID
    const testInstanceId = `bun-test-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
    const testNanobrowserDir = join(tmpdir(), 'nanobrowser-test', testInstanceId);
    
    // Clean up any existing test directory
    if (existsSync(testNanobrowserDir)) {
      try {
        rmSync(testNanobrowserDir, { recursive: true, force: true });
        this.logger.debug('Cleaned up existing test directory');
      } catch (error) {
        this.logger.warn('Failed to clean up test directory:', error);
      }
    }
    
    // Create the test directory
    mkdirSync(testNanobrowserDir, { recursive: true });
    this.logger.debug(`Created test directory: ${testNanobrowserDir}`);
    
    // Store the test directory for cleanup
    this.testNanobrowserDir = testNanobrowserDir;

    // Start the MCP host process using the Bun binary
    this.logger.info(`Starting Bun binary: ${this.binaryPath}`);
    this.hostProcess = spawn(this.binaryPath, [], {
      stdio: ['pipe', 'pipe', 'inherit'], // Make stderr inherit to show logs in console
      env: {
        ...process.env,
        LOG_LEVEL: 'DEBUG',
        PORT: this.port.toString(),
        LOW_LEVEL_TOOLS_ENABLED: 'true',
        NANOBROWSER_HOME: testNanobrowserDir, // Use isolated directory for this test instance
      },
    });

    // Handle process exit
    this.exitPromise = new Promise<number>(resolve => {
      if (this.hostProcess) {
        this.hostProcess.on('exit', (code, signal) => {
          this.logger.info(`Bun binary hostProcess exit with code: ${code}, signal: ${signal}`);

          this.exitCode = code ?? -1;
          resolve(this.exitCode);
        });

        this.hostProcess.on('close', (code, signal) => {
          this.logger.info(`Bun binary hostProcess close with code: ${code}, signal: ${signal}`);
          // Update exitCode if not already set
          if (this.exitCode === null) {
            this.exitCode = code ?? -1;
          }
        });

        // Forward stderr output to parent process
        if (this.hostProcess.stderr) {
          this.hostProcess.stderr.on('data', data => {
            process.stderr.write(data);
          });
        }
      } else {
        resolve(-1);
      }
    });

    // Connect mock stdio to the process
    if (this.hostProcess && this.hostProcess.stdout && this.hostProcess.stdin) {
      this.nativeMessaging = new NativeMessaging(this.hostProcess.stdout, this.hostProcess.stdin);

      this.nativeMessaging.registerHandler('status', async (data: any): Promise<void> => {
        this.logger.info('received status:', data);
      });

      this.nativeMessaging.sendMessage({
        type: 'init',
      });
    }

    // Create MCP client connected to the host's HTTP server
    this.mcpClient = new McpHttpClient(`http://localhost:${this.port}/mcp`);

    // Wait for host to initialize
    await this.waitForHostReady();
  }

  /**
   * Clean up the test environment
   * @returns A promise that resolves when cleanup is complete
   */
  async cleanup(): Promise<void> {
    // Close MCP client if it exists
    if (this.mcpClient) {
      await this.mcpClient.close().catch(() => {});
      this.mcpClient = null;
    }

    // Kill the host process if it's still running
    if (this.hostProcess && !this.hostProcess.killed) {
      this.hostProcess.kill();

      // Wait for process to exit
      if (this.exitPromise) {
        await Promise.race([
          this.exitPromise,
          new Promise(resolve => setTimeout(resolve, 1000)), // Timeout after 1s
        ]);
      }

      this.hostProcess = null;
    }

    // Clean up the test directory
    if (this.testNanobrowserDir) {
      try {
        const { existsSync, rmSync } = await import('fs');
        if (existsSync(this.testNanobrowserDir)) {
          rmSync(this.testNanobrowserDir, { recursive: true, force: true });
          this.logger.debug(`Cleaned up test directory: ${this.testNanobrowserDir}`);
        }
      } catch (error) {
        this.logger.warn('Failed to clean up test directory:', error);
      }
      this.testNanobrowserDir = null;
    }
  }

  /**
   * Send a message to the host via stdio using Chrome native messaging format
   * @param message The message to send
   * @param closeAfter Whether to close stdin after sending the message (useful for shutdown)
   * @returns A promise that resolves with the response
   */
  async sendMessage(message: any, closeAfter: boolean = false): Promise<any> {
    if (!this.hostProcess || !this.hostProcess.stdin) {
      throw new Error('Host process not available');
    }

    // Convert message to Chrome native messaging format (4-byte length prefix + JSON)
    const messageJson = JSON.stringify(message);
    const messageBuffer = Buffer.from(messageJson, 'utf8');
    const length = messageBuffer.length;

    const buffer = Buffer.alloc(4 + length);
    buffer.writeUInt32LE(length, 0);
    messageBuffer.copy(buffer, 4);

    this.logger.debug(`Sending message to binary: ${messageJson}${closeAfter ? ' (closing stdin after)' : ''}`);
    
    // Write the message to stdin
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Message send timeout'));
      }, 5000);

      try {
        this.hostProcess!.stdin!.write(buffer, (error) => {
          clearTimeout(timeout);
          if (error) {
            reject(error);
          } else {
            // Close stdin if requested (important for shutdown to trigger connection close)
            if (closeAfter && this.hostProcess!.stdin) {
              this.hostProcess!.stdin.end();
            }
            resolve(undefined);
          }
        });
      } catch (error) {
        clearTimeout(timeout);
        reject(error);
      }
    });
  }

  /**
   * Get the MCP client
   * @returns The MCP client or null if not initialized
   */
  getMcpClient(): McpHttpClient | null {
    return this.mcpClient;
  }

  /**
   * Get the port this instance is using
   * @returns The port number
   */
  getPort(): number {
    return this.port;
  }

  /**
   * Get the binary path being used
   * @returns The binary path
   */
  getBinaryPath(): string {
    return this.binaryPath;
  }

  /**
   * Check if the host process is running
   * @returns True if the host is running, false otherwise
   */
  isHostRunning(): boolean {
    return !!this.hostProcess && !this.hostProcess.killed && this.exitCode === null;
  }

  /**
   * Get the exit code of the host process
   * @returns The exit code or null if the process hasn't exited
   */
  getExitCode(): number | null {
    return this.exitCode;
  }

  /**
   * Shutdown the test environment
   * @returns A promise that resolves when shutdown is complete
   */
  async shutdown(): Promise<void> {
    // Send shutdown message
    await this.sendMessage({
      type: 'shutdown',
    }).catch(() => {});

    // Clean up
    await this.cleanup();
  }

  public registerMessageHandler(type: string, handler: MessageHandler): void {
    this.nativeMessaging?.registerHandler(type, handler);
  }

  public registerRpcMethod(method: string, handler: RpcHandler): void {
    this.nativeMessaging?.registerRpcMethod(method, handler);
  }

  public async rpcRequest(rpc: RpcRequest, options: RpcRequestOptions = {}): Promise<RpcResponse> {
    if (this.nativeMessaging) {
      return this.nativeMessaging.rpcRequest(rpc, options);
    }

    return {
      error: {
        code: -32000,
        message: 'nativeMessaging is null',
      },
    };
  }
}
