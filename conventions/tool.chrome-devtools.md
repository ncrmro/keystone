
## Chrome DevTools MCP

## MCP Server Configuration

1. Every agent-space `.mcp.json` MUST include a `chrome-devtools` MCP server entry.
2. The server MUST use `npx -y chrome-devtools-mcp@latest` as the command.
3. The `--browserUrl` argument MUST point to `http://localhost:9222`.
4. The `.mcp.json` entry MUST follow this format:
   ```json
   {
     "chrome-devtools": {
       "command": "npx",
       "args": ["-y", "chrome-devtools-mcp@latest", "--browserUrl", "http://localhost:9222"]
     }
   }
   ```

## Chrome Remote Debugging

5. The host system MUST provision a Chromium instance with `--remote-debugging-port=9222`.
6. Agents SHOULD use the Chrome DevTools MCP for web browsing, page inspection, and screenshot capture.
7. Agents MUST NOT launch their own browser instances — they MUST use the pre-provisioned Chromium.

## Usage

8. Agents MAY use Chrome DevTools to navigate to URLs, inspect page content, and take screenshots.
9. Agents SHOULD prefer Chrome DevTools over `WebFetch` when full page rendering or JavaScript execution is required.
10. Agents MUST NOT use Chrome DevTools to access authenticated services unless credentials are provided via their own vault.
