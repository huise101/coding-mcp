# Coding MCP launchers

- Double-click `F:\codingmcp\Start-CodingMCP.vbs` to choose a workspace and start Coding MCP without a console window.
- Double-click `F:\codingmcp\Stop-CodingMCP.vbs` to stop Coding MCP without a console window.
- Double-click `F:\codingmcp\Setup-CloudflareNamedTunnel.vbs` to configure a stable Cloudflare hostname for this computer.
- The start window shows the MCP URL and OAuth password after startup. Use the copy buttons to paste them into ChatGPT.

These launchers do not re-enable Windows startup tasks.

Use one live hostname per computer. Do not run two computers behind the same MCP URL at the same time, or ChatGPT requests can go to the wrong machine. Runtime files under `coding-tools-mcp\.runtime\` contain URL/password/tunnel secrets and must stay out of Git.
