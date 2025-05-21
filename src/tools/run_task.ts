/**
 * Run task tool
 *
 * This tool allows requesting the agent to complete a specified task through the browser.
 * It enables AI systems to perform complex operations in the browser environment such as:
 * 
 * - Web automation tasks (filling forms, clicking buttons, navigating between pages)
 * - Information extraction from web pages
 * - Multi-step browser interactions
 * - Data processing from web content
 * - Web scraping and content analysis
 * - Testing and validating web applications
 * 
 * The tool acts as a bridge between the MCP host and the browser extension, allowing
 * the AI to effectively operate within the browser context to complete user-requested tasks.
 */

import { z } from 'zod';
import { CallToolResult } from '@modelcontextprotocol/sdk/types.js';
import { NativeMessaging } from '../messaging.js';
import { createLogger } from '../logger.js';

/**
 * Implementation of the run_task tool
 */
export class RunTaskTool {
  private logger = createLogger('run_task_tool');

  /**
   * Tool name
   */
  public name = 'run_task';

  /**
   * Tool description
   */
  public description = 'Request the agent to complete a task within the browser environment';

  /**
   * Tool capabilities explanation - provides detailed information about what this tool can do
   */
  public capabilities = [
    'Execute web automation tasks (form filling, button clicking, etc.)',
    'Extract information from web pages',
    'Perform multi-step browser interactions',
    'Process and analyze web content',
    'Scrape web data with proper permissions',
    'Test and validate web applications',
    'Navigate complex web interfaces',
    'Interact with dynamic web content'
  ];

  /**
   * Private reference to the NativeMessaging instance
   */
  private messaging: NativeMessaging;

  /**
   * Constructor
   * @param messaging NativeMessaging instance for communication
   */
  constructor(messaging: NativeMessaging) {
    this.messaging = messaging;
  }

  /**
   * Input schema for the tool
   */
  public inputSchema = {
    task: z.string().describe('The task description to be completed by the agent (e.g., "Fill out the login form", "Extract product information from the current page")'),
    context: z.string().optional().describe('Additional context for the task, such as specific instructions, constraints, or information needed to complete the task successfully'),
    timeout: z.number().optional().default(300000).describe('Timeout in milliseconds (default: 300000ms/5min) after which the task execution will be aborted if not completed'),
  };

  /**
   * Execute the run_task tool
   * @param args Tool arguments containing the task and optional context
   * @returns Promise resolving to the action result
   */
  public execute = async (args: { task: string; context?: string; timeout?: number }): Promise<CallToolResult> => {
    this.logger.info('execute args:', args);

    if (!args.task) {
      throw new Error('Task description is required');
    }

    // Use the provided timeout or default to 300 seconds
    const timeout = args.timeout || 300000;

    const result = await this.messaging.rpcRequest(
      {
        method: 'run_task',
        params: {
          task: args.task,
          context: args.context || '',
        },
      },
      { timeout },
    );

    this.logger.info('call run_task result:', result);

    return {
      content: [
        {
          type: 'text',
          text: `Task completed: ${JSON.stringify(result) || 'No result provided'}`,
        },
      ],
    };
  };
}
