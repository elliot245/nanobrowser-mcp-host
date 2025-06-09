import { existsSync } from 'fs';
import { resolve } from 'path';
import { afterAll, afterEach, beforeAll, describe, expect, test, vi } from 'vitest';
import { RpcRequest, RpcResponse } from '../../../src/types';
import { BunBinaryTestEnvironment } from '../bun-binary-test-environment';

/**
 * Integration tests for the Bun-compiled binary
 * Tests that the compiled binary works the same as the Node.js version
 */
describe('Bun Binary Execution', () => {
  let testEnv: BunBinaryTestEnvironment;
  const binaryPath = resolve('./bin/nanobrowser-mcp-host-bun');

  beforeAll(async () => {
    // Suppress console.error during tests
    vi.spyOn(console, 'error').mockImplementation(() => {});
  });

  afterEach(async () => {
    if (testEnv) {
      await testEnv.cleanup();
    }
  });

  afterAll(async () => {
    vi.restoreAllMocks();
  });

  test('should have bun binary file available', () => {
    expect(existsSync(binaryPath)).toBe(true);
  }, 10000);

  test('should start binary and initialize MCP server', async () => {
    testEnv = new BunBinaryTestEnvironment();
    await testEnv.setup();

    // Verify the environment is set up correctly
    expect(testEnv.isHostRunning()).toBe(true);
    expect(testEnv.getBinaryPath()).toBe(binaryPath);
    expect(testEnv.getPort()).toBeGreaterThan(0);

    // Initialize MCP client
    const mcpClient = testEnv.getMcpClient();
    expect(mcpClient).not.toBeNull();
    
    await mcpClient!.initialize();
    
    // Verify MCP server responds
    const tools = await mcpClient!.listTools();
    expect(tools).toBeDefined();
    expect(tools.tools).toBeInstanceOf(Array);
  }, 30000);

  test('should execute navigate_to tool via binary', async () => {
    testEnv = new BunBinaryTestEnvironment();
    await testEnv.setup();

    // Initialize MCP client
    const mcpClient = testEnv.getMcpClient();
    expect(mcpClient).not.toBeNull();
    await mcpClient!.initialize();

    // List available tools
    const tools = await mcpClient!.listTools();
    expect(tools).toBeDefined();

    const browserState = {
      activeTab: {
        id: 1,
        url: 'https://example.com',
        title: 'Test Page',
        content: '<html><body><h1>Test</h1></body></html>',
      },
      tabs: [{ id: 1, url: 'https://example.com', title: 'Test Page', active: true }],
    };

    // Register RPC methods for browser state
    testEnv.registerRpcMethod('get_browser_state', async (request: RpcRequest): Promise<RpcResponse> => {
      return {
        id: request.id,
        result: browserState,
      };
    });

    testEnv.registerRpcMethod('navigate_to', async (req: RpcRequest): Promise<RpcResponse> => {
      browserState.activeTab.url = req.params.url;
      browserState.activeTab.title = `Page at ${req.params.url}`;

      return {
        result: 'success',
      };
    });

    // Verify navigate_to tool is available
    const navigateTool = tools.tools.find((t: any) => t.name === 'navigate_to');
    expect(navigateTool).toBeDefined();
    expect(navigateTool.name).toBe('navigate_to');

    // Execute the navigate_to tool
    const testUrl = 'https://bun-binary-test.com';
    const toolResp = await mcpClient!.callTool('navigate_to', { url: testUrl });
    expect(toolResp.content[0].text).toBe(`navigate_to ${testUrl} ok`);

    // Verify action was forwarded to the browser
    expect(browserState.activeTab.url).toBe(testUrl);
    expect(browserState.activeTab.title).toBe(`Page at ${testUrl}`);
  }, 30000);

  test('should execute run_task tool via binary', async () => {
    testEnv = new BunBinaryTestEnvironment();
    await testEnv.setup();

    // Initialize MCP client
    const mcpClient = testEnv.getMcpClient();
    expect(mcpClient).not.toBeNull();
    await mcpClient!.initialize();

    // List available tools
    const tools = await mcpClient!.listTools();
    expect(tools).toBeDefined();

    const browserState = {
      activeTab: {
        id: 1,
        url: 'https://example.com',
        title: 'Test Page',
        content: '<html><body><h1>Test</h1></body></html>',
      },
      tabs: [{ id: 1, url: 'https://example.com', title: 'Test Page', active: true }],
    };

    // Register RPC methods
    testEnv.registerRpcMethod('get_browser_state', async (request: RpcRequest): Promise<RpcResponse> => {
      return {
        id: request.id,
        result: browserState,
      };
    });

    let lastTaskExecuted: any = null;
    testEnv.registerRpcMethod('run_task', async (req: RpcRequest): Promise<RpcResponse> => {
      lastTaskExecuted = req.params;
      return {
        result: 'Task executed successfully',
      };
    });

    // Verify run_task tool is available
    const runTaskTool = tools.tools.find((t: any) => t.name === 'run_task');
    expect(runTaskTool).toBeDefined();
    expect(runTaskTool.name).toBe('run_task');

    // Execute the run_task tool
    const testTask = 'click button with text "Submit"';
    const toolResp = await mcpClient!.callTool('run_task', { task: testTask });
    
    // The response should contain the task and success information
    expect(toolResp.content[0].text).toContain('Task Execution Result');
    expect(toolResp.content[0].text).toContain('✅ Success');
    expect(toolResp.content[0].text).toContain(testTask);

    // Verify task was forwarded correctly
    expect(lastTaskExecuted).not.toBeNull();
    expect(lastTaskExecuted.task).toBe(testTask);
  }, 30000);

  test('should handle binary startup performance', async () => {
    const startTime = Date.now();
    
    testEnv = new BunBinaryTestEnvironment();
    await testEnv.setup();

    const setupTime = Date.now() - startTime;
    
    // Binary should start reasonably quickly (less than 10 seconds)
    expect(setupTime).toBeLessThan(10000);
    
    // Verify the binary is actually running
    expect(testEnv.isHostRunning()).toBe(true);
    
    // Verify MCP functionality works
    const mcpClient = testEnv.getMcpClient();
    expect(mcpClient).not.toBeNull();
    
    await mcpClient!.initialize();
    const tools = await mcpClient!.listTools();
    expect(tools.tools.length).toBeGreaterThan(0);
  }, 30000);

  test('should handle binary process lifecycle', async () => {
    testEnv = new BunBinaryTestEnvironment();
    await testEnv.setup();

    // Verify process is running
    expect(testEnv.isHostRunning()).toBe(true);
    expect(testEnv.getExitCode()).toBeNull();

    // Initialize and test basic functionality
    const mcpClient = testEnv.getMcpClient();
    await mcpClient!.initialize();
    
    // Send shutdown message and close stdin to trigger connection close
    await testEnv.sendMessage({ type: 'shutdown' }, true).catch(() => {
      // Ignore send errors as the process might exit before response
    });
    
    // Wait for the process to exit, with polling and timeout
    let exitCode: number | null = null;
    const startTime = Date.now();
    const timeout = 10000; // 10 seconds
    
    while (Date.now() - startTime < timeout) {
      exitCode = testEnv.getExitCode();
      if (exitCode !== null) {
        break;
      }
      
      // Check if process is still running
      if (!testEnv.isHostRunning()) {
        // Process stopped but exitCode might not be set yet, wait a bit more
        await new Promise(resolve => setTimeout(resolve, 100));
        exitCode = testEnv.getExitCode();
        if (exitCode !== null) {
          break;
        }
      }
      
      // Wait before next check
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    
    if (exitCode === null) {
      throw new Error(`Process did not exit after shutdown. Current state: ${testEnv.isHostRunning() ? 'running' : 'stopped'}, exitCode: ${testEnv.getExitCode()}`);
    }
    
    // Process should have exited cleanly
    expect(exitCode).toBe(0);
  }, 30000);

  test('should provide same tools as Node.js version', async () => {
    testEnv = new BunBinaryTestEnvironment();
    await testEnv.setup();

    const mcpClient = testEnv.getMcpClient();
    expect(mcpClient).not.toBeNull();
    await mcpClient!.initialize();

    const tools = await mcpClient!.listTools();
    expect(tools).toBeDefined();
    expect(tools.tools).toBeInstanceOf(Array);

    // Should have the expected tools
    const toolNames = tools.tools.map((t: any) => t.name);
    expect(toolNames).toContain('navigate_to');
    expect(toolNames).toContain('run_task');

    // Verify tool definitions are complete
    for (const tool of tools.tools) {
      expect(tool.name).toBeDefined();
      expect(tool.description).toBeDefined();
      expect(tool.inputSchema).toBeDefined();
    }
  }, 30000);
});
