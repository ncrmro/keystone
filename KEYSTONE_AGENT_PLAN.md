# Keystone Agent Sandbox - Development Plan

## Current Goal
Use the keystone terminal module (`homeModules.terminal`) to provide development tools (helix, zsh, zellij, etc.) in the sandbox.

## Progress

### Completed
1. **Sync command** - Implemented `keystone agent sync` for host-initiated git fetch from sandbox
2. **Documentation** - Created `packages/keystone-agent/README.md` and `docs/agent-sandbox.md`
3. **SSH sessions start in /workspace** - Fixed `cmd_attach()` and `cmd_ssh()` to cd to /workspace
4. **Direnv configuration added to flake** - Added `direnv` and bash hooks to generated flake.
5. **Fixed Nix Caching Issue** - Added dynamic `build-id` timestamp to flake to force rebuilds.
6. **Refactored Workspace Storage** - Removed 9p shared folders in favor of local VM storage with `rsync` initialization.
7. **Keystone Terminal Module Integration** - Sandbox now uses `keystone.homeModules.terminal` for dev tools

### Keystone Terminal Module Integration

The sandbox flake now imports the keystone terminal module to get helix, zsh, zellij, lazygit, etc.

**Architecture:**
1. `flake.nix` exports `overlays.default` providing `pkgs.keystone.zesh` and `pkgs.keystone.claude-code`
2. `flake.nix` exports `homeModules.terminal` which uses the overlay packages
3. Sandbox flake applies the overlay and imports the terminal module

**Key Fix - Overlay Path Resolution:**
Paths inside overlay functions are evaluated when the overlay is *applied*, not *defined*. This breaks when a consumer flake fetches keystone from GitHub.

```nix
# BROKEN - path evaluated too late:
overlays.default = final: prev: {
  keystone.zesh = final.callPackage ./packages/zesh {};
};

# FIXED - path captured before function:
overlays.default = let
  zesh-src = ./packages/zesh;
in final: prev: {
  keystone.zesh = final.callPackage zesh-src {};
};
```

**Key Fix - Local vs GitHub Reference:**
For development, the sandbox must use the LOCAL keystone flake (with uncommitted changes), not GitHub.

```python
# In agent.py - detect if workspace is keystone repo
keystone_terminal_path = workspace_dir / "modules" / "keystone" / "terminal"
if keystone_terminal_path.exists():
    keystone_url = f"path:{workspace_dir}"  # Local development
else:
    keystone_url = "github:ncrmro/keystone"  # External project
```

### Bug Fixes Applied
1. Fixed Nix multi-line string syntax (`''` not `'''`)
2. Fixed `args.web` AttributeError when `cmd_start` calls `cmd_attach`
3. Added `--refresh` flag to `nix build` command
4. Added build ID timestamp to force cache invalidation
5. Fixed overlay path resolution (paths must be captured in `let` before function)
6. Fixed editor.nix to have optional inputs with fallbacks
7. Made sandbox detect local keystone repo vs external project

## Files Modified

| File | Changes |
|------|---------|
| `flake.nix` | Added `overlays.default` with path capture fix |
| `modules/keystone/terminal/shell.nix` | Uses `pkgs.keystone.zesh` from overlay |
| `modules/keystone/terminal/ai.nix` | Uses `pkgs.keystone.claude-code` from overlay |
| `modules/keystone/terminal/editor.nix` | Optional inputs with fallbacks |
| `packages/keystone-agent/agent.py` | Terminal module integration, local/GitHub detection |
| `packages/keystone-agent/README.md` | CLI quick reference |
| `docs/agent-sandbox.md` | Full user guide |

## Recent Commits

```
c77cbe9 fix(agent): force nix rebuild by injecting build_id into flake config
eb923e8 Fix args.web attribute error when start calls attach
ead59fb Fix Nix multi-line string syntax in direnv config
c57a639 Add direnv auto-load support in sandbox
336297d Start SSH sessions in /workspace directory
b5e565a Implement sync command and add user documentation
```

## Next Steps

1. **Test Terminal Module**: Verify helix, zsh, zellij work in sandbox
2. **Worktree Support**: Implement `keystone agent worktree` for parallel branches
3. **Web UI**: Implement `keystone agent attach --web`

## Commands for Testing

```bash
# Build and start sandbox with terminal module
nix build .#keystone-agent
result/bin/keystone-agent start --fresh

# Verify tools are available
hx --version
zellij --version
claude --version
```

## Background Context

- Branch: `copilot/implement-012-agent-sandbox`
- The sandbox uses MicroVM (QEMU) with user-mode networking
- SSH on port 2223 with key-based auth
- Workspace initialized via rsync to /workspace
- Terminal tools provided by `keystone.homeModules.terminal`
- Custom packages (zesh, claude-code) provided via `keystone.overlays.default`
