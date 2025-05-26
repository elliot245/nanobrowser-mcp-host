# MCP Host Server: Supported Tools and Resources

This document summarizes the built-in tools and resources provided by the MCP Host Server.

## Tools

| Name         | Description                                 | Capabilities / Input Schema                  |
|--------------|---------------------------------------------|----------------------------------------------|
| navigate_to  | Navigate to a specified URL                 | `{ url: string }`                            |
| run_task     | Request the agent to complete a browser task| - Web automation (form filling, clicking, etc.)<br>- Information extraction<br>- Multi-step interactions<br>- Data processing<br>- Web scraping<br>- Testing web apps<br>- Navigating complex interfaces<br>- Interacting with dynamic content |

## Resources

| URI                        | Name                  | MIME Type           | Description                                      |
|----------------------------|-----------------------|---------------------|--------------------------------------------------|
| browser://current/state    | Current Browser State | application/json    | Complete state of the current active page and all tabs |

## Details

### Tools

- **navigate_to**: Allows navigation to a specified URL in the browser. Input: `{ url: string }`.
- **run_task**: Enables the agent to perform complex browser tasks, including automation, extraction, and testing. Accepts structured task requests.

### Resources

- **CurrentStateResource**: Exposes the full browser state, including all tabs and the active page, as a JSON resource at `browser://current/state`.

---

This list is based on the current implementation in `src/tools` and `src/resources`. For extension, implement new classes following the `Tool` and `Resource` interfaces.
