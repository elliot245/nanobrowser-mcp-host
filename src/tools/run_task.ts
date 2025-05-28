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
    const startTime = Date.now();
    this.logger.info('execute args:', args);

    if (!args.task) {
      throw new Error('Task description is required');
    }

    // Use the provided timeout or default to 300 seconds
    const timeout = args.timeout || 300000;

    try {
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

      const executionTime = Date.now() - startTime;
      this.logger.info('call run_task result:', result);

      return {
        content: [
          {
            type: 'text',
            text: this.formatSuccessResult(args.task, result, executionTime),
          },
        ],
      };
    } catch (error) {
      const executionTime = Date.now() - startTime;
      this.logger.error('run_task execution failed:', error);

      return {
        content: [
          {
            type: 'text',
            text: this.formatErrorResult(args.task, error, executionTime),
          },
        ],
      };
    }
  };

  /**
   * Format successful task execution result as AI-friendly markdown
   * @param task The task description
   * @param result The execution result
   * @param executionTime Execution time in milliseconds
   * @returns Formatted markdown string
   */
  private formatSuccessResult(task: string, result: any, executionTime: number): string {
    const lines = [
      '# Task Execution Result',
      '',
      '**Status**: ✅ Success',
      `**Task**: ${task}`,
      `**Execution Time**: ${executionTime}ms`,
      ''
    ];

    if (result && typeof result === 'object') {
      lines.push('## Results');
      lines.push('');

      // Handle different result structures
      if (result.success !== undefined) {
        lines.push(`**Success**: ${result.success ? '✅ Yes' : '❌ No'}`);
      }

      if (result.message) {
        lines.push(`**Message**: ${result.message}`);
      }

      if (result.data) {
        lines.push('');
        lines.push('### Data');
        lines.push('```json');
        lines.push(JSON.stringify(result.data, null, 2));
        lines.push('```');
      }

      if (result.actions && Array.isArray(result.actions)) {
        lines.push('');
        lines.push('### Actions Performed');
        result.actions.forEach((action: any, index: number) => {
          lines.push(`${index + 1}. ${action.description || action.type || 'Unknown action'}`);
          if (action.target) {
            lines.push(`   - Target: ${action.target}`);
          }
          if (action.result) {
            lines.push(`   - Result: ${action.result}`);
          }
        });
      }

      // Handle any other properties
      const handledKeys = ['success', 'message', 'data', 'actions'];
      const remainingKeys = Object.keys(result).filter(key => !handledKeys.includes(key));
      
      if (remainingKeys.length > 0) {
        lines.push('');
        lines.push('### Additional Information');
        remainingKeys.forEach(key => {
          const value = result[key];
          if (typeof value === 'object') {
            lines.push(`**${key}**:`);
            lines.push('```json');
            lines.push(JSON.stringify(value, null, 2));
            lines.push('```');
          } else {
            lines.push(`**${key}**: ${value}`);
          }
        });
      }
    } else if (result) {
      lines.push('## Results');
      lines.push('');
      lines.push(`${result}`);
    } else {
      lines.push('## Results');
      lines.push('');
      lines.push('Task completed successfully with no additional data.');
    }

    return lines.join('\n');
  }

  /**
   * Format error result as AI-friendly markdown
   * @param task The task description
   * @param error The error that occurred
   * @param executionTime Execution time in milliseconds
   * @returns Formatted markdown string
   */
  private formatErrorResult(task: string, error: any, executionTime: number): string {
    const lines = [
      '# Task Execution Result',
      '',
      '**Status**: ❌ Failed',
      `**Task**: ${task}`,
      `**Execution Time**: ${executionTime}ms`,
      '',
      '## Error Details',
      ''
    ];

    // Determine error type and provide appropriate message
    if (error instanceof Error) {
      if (error.message.includes('timeout') || error.message.includes('RPC request timeout')) {
        lines.push('**Error Type**: Timeout');
        lines.push(`**Message**: The task execution timed out after ${executionTime}ms. This may indicate:`);
        lines.push('- The task is taking longer than expected to complete');
        lines.push('- The browser extension is not responding');
        lines.push('- The task requires more complex interactions than anticipated');
        lines.push('');
        lines.push('**Suggestions**:');
        lines.push('- Try breaking the task into smaller, more specific steps');
        lines.push('- Increase the timeout value if the task legitimately needs more time');
        lines.push('- Check if the browser extension is properly loaded and functioning');
      } else if (error.message.includes('connection') || error.message.includes('ECONNREFUSED')) {
        lines.push('**Error Type**: Connection Error');
        lines.push('**Message**: Unable to communicate with the browser extension. This may indicate:');
        lines.push('- The browser extension is not installed or enabled');
        lines.push('- The native messaging host is not properly configured');
        lines.push('- Chrome/Chromium is not running or accessible');
        lines.push('');
        lines.push('**Suggestions**:');
        lines.push('- Verify the browser extension is installed and enabled');
        lines.push('- Check that Chrome/Chromium is running');
        lines.push('- Restart the browser and try again');
      } else {
        lines.push('**Error Type**: Execution Error');
        lines.push(`**Message**: ${error.message}`);
        
        if (error.stack) {
          lines.push('');
          lines.push('### Stack Trace');
          lines.push('```');
          lines.push(error.stack);
          lines.push('```');
        }
      }
    } else if (typeof error === 'object' && error !== null) {
      lines.push('**Error Type**: Structured Error');
      lines.push('```json');
      lines.push(JSON.stringify(error, null, 2));
      lines.push('```');
    } else {
      lines.push('**Error Type**: Unknown Error');
      lines.push(`**Message**: ${String(error)}`);
    }

    lines.push('');
    lines.push('## Troubleshooting');
    lines.push('1. **Check Task Description**: Ensure the task is clearly defined and achievable');
    lines.push('2. **Verify Browser State**: Make sure the browser is on the correct page and ready for interaction');
    lines.push('3. **Review Context**: Provide more specific context or constraints if needed');
    lines.push('4. **Break Down Complex Tasks**: Split complex operations into smaller, sequential steps');
    lines.push('5. **Check Logs**: Review the MCP host logs for additional error details');

    return lines.join('\n');
  }
}
