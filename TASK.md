---
repo: ncrmro/keystone
branch: fix/chrome-devtools-mcp-path
agent: claude
platform: github
issue: 166
status: ready
created: 2026-03-19
---

# Fix Agent PATH missing chrome-devtools-mcp binary

## Description

Agents with `chrome.mcp.enable = true` cannot start the Chrome DevTools MCP server
because `chrome-devtools-mcp` is not in their PATH. The package is defined in
`packages/chrome-devtools-mcp/default.nix` and exported in the flake overlay, but
was never added to `home.packages` in `home-manager.nix`.

Tech stack: Nix/NixOS, home-manager, `modules/os/agents/home-manager.nix`.

## Acceptance Criteria

- [x] `chrome-devtools-mcp` is in agent PATH when `chrome.mcp.enable = true`
- [x] Agent can successfully start the Chrome DevTools MCP server
- [x] `.mcp.json` generation uses the Nix-built binary directly instead of `npx`
- [x] Convention doc updated to reflect Nix-binary approach

## Key Files

- `modules/os/agents/home-manager.nix` — adds `pkgs.keystone.chrome-devtools-mcp` to `home.packages` and MCP server config
- `conventions/tool.chrome-devtools.md` — updated to document Nix-binary approach
