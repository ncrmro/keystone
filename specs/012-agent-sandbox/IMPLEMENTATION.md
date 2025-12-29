# Agent Sandbox Implementation Status

## Progress Summary

This document tracks the implementation of the Agent Sandbox feature (spec: `specs/012-agent-sandbox/spec.md`).

### Completed Phases

#### Phase 1: Setup ✅
- Created `modules/keystone/agent/` directory structure
- Added `bin/agent` CLI entrypoint with Python + argparse
- Created guest module directory structure
- Added home-manager module directory
- Exported agent module in `flake.nix`

#### Phase 2: Foundational ✅ 
- Implemented base NixOS module with `keystone.agent.enable` option
- Defined SandboxConfig options (memory, vcpus, nested_virt, network, sync_mode, persist)
- Defined Backend options (type, microvm config, kubernetes config stub)
- Created sandbox state directory and registry management in CLI
- Implemented Backend interface abstraction
- Created CLI application structure with subcommand routing
- Added color output and logging utilities to CLI

#### Phase 3: User Story 1 - In Progress 🚧
- ✅ Created guest OS base configuration
- ✅ Added development tools (git, direnv, jq, etc.) to guest
- ✅ Created MicroVM test configuration (`tests/microvm/agent-sandbox.nix`)
- ✅ Created test script (`bin/test-microvm-agent`)
- ⏳ Implement MicroVM backend create/start/stop/destroy
- ⏳ Configure virtiofs share for /workspace/ mount (config ready, needs testing)
- ⏳ Configure Claude Code package and auto-accept settings
- ⏳ Implement git clone/push workflow
- ⏳ Implement CLI commands (start, stop, status, list, destroy)
- ⏳ Add nested virtualization detection and KVM passthrough

## Module Structure

```
modules/keystone/agent/
├── backends/
│   ├── default.nix      # Backend abstraction layer (✅)
│   ├── microvm.nix      # MicroVM backend implementation (stub)
│   └── kubernetes.nix   # Kubernetes backend stub (P4)
├── guest/
│   ├── default.nix      # Guest OS base configuration (✅)
│   ├── agents.nix       # AI agent packages (stub)
│   ├── tools.nix        # Development tools (✅)
│   ├── zellij.nix       # Session management (stub)
│   └── worktree.nix     # Git worktree support (stub)
├── home/
│   └── tui.nix          # Optional TUI client (stub)
├── default.nix          # Main module with options (✅)
├── sync.nix             # Sync module (stub)
└── proxy.nix            # Proxy module (stub)
```

## CLI Commands

The `bin/agent` script provides the following commands:

### Implemented
- ✅ `keystone agent list` - List all sandboxes (shows empty list)

### Stubbed (return "not yet implemented")
- ⏳ `keystone agent start [OPTIONS] [PROJECT_PATH]` - Launch sandbox
- ⏳ `keystone agent stop [NAME]` - Stop sandbox
- ⏳ `keystone agent attach [NAME]` - Attach to session
- ⏳ `keystone agent sync [NAME]` - Sync changes to host
- ⏳ `keystone agent status [NAME]` - Show sandbox status
- ⏳ `keystone agent destroy [NAME]` - Remove sandbox
- ⏳ `keystone agent worktree {add,list,remove}` - Manage worktrees
- ⏳ `keystone agent exec [NAME] [CMD]` - Execute command in sandbox
- ⏳ `keystone agent ssh [NAME]` - SSH into sandbox

## Configuration Options

### keystone.agent.enable
Enable the Agent Sandbox system (default: false)

### keystone.agent.sandbox
- `memory` (int, default: 8192) - RAM allocation in MB
- `vcpus` (int, default: 4) - Virtual CPU count
- `nestedVirtualization` (bool, default: true) - Enable KVM passthrough
- `network` (enum, default: "nat") - Network mode: nat, none, bridge
- `syncMode` (enum, default: "manual") - Sync mode: manual, auto-commit, auto-idle
- `persist` (bool, default: true) - Persist sandbox state

### keystone.agent.backend
- `type` (enum, default: "microvm") - Backend: microvm, kubernetes
- `microvm.hypervisor` (enum, default: "qemu") - qemu, firecracker, cloud-hypervisor
- `microvm.shareType` (enum, default: "virtiofs") - virtiofs, 9p
- `kubernetes.*` - K8s config (stub)

### keystone.agent.proxy
- `enable` (bool, default: false) - Enable dev server proxy
- `domain` (string, default: "sandbox.local") - Base domain
- `port` (int, default: 8080) - Proxy server port

### keystone.agent.guest
- `packages` (list) - Additional packages for guest
- `agents.claudeCode.enable` (bool, default: true)
- `agents.claudeCode.autoAccept` (bool, default: true)
- `agents.geminiCli.enable` (bool, default: false)
- `agents.codex.enable` (bool, default: false)

## Testing

### MicroVM Test
```bash
# Test the guest configuration (requires network access)
./bin/test-microvm-agent
```

The test validates:
- Guest OS boots successfully
- Development tools are installed
- User 'sandbox' can execute commands
- /workspace/ mount point exists

### Manual CLI Testing
```bash
# Test CLI help
python3 bin/agent --help
python3 bin/agent start --help
python3 bin/agent list

# Test registry (should show empty list)
python3 bin/agent list
```

## Next Steps

### Phase 3 Completion (P1 - MVP)
1. Implement MicroVM backend lifecycle methods in `modules/keystone/agent/backends/microvm.nix`:
   - `create()` - Build and start MicroVM with virtiofs workspace share
   - `start()` - Start existing MicroVM
   - `stop()` - Gracefully stop MicroVM
   - `destroy()` - Remove MicroVM completely
   
2. Configure Claude Code in `modules/keystone/agent/guest/agents.nix`:
   - Install claude-code package (check `modules/keystone/terminal/claude-code/`)
   - Configure auto-accept settings
   - Set up environment for autonomous operation

3. Implement CLI commands in `bin/agent`:
   - `start` - Create/start sandbox, setup workspace, auto-attach
   - `stop` - Stop sandbox, optionally sync first
   - `status` - Show running status, resource usage, proxy URLs
   - `destroy` - Confirm and remove sandbox completely

4. Add nested virtualization:
   - Detect CPU support (`/sys/module/kvm_*/parameters/nested`)
   - Pass through KVM device to MicroVM
   - Configure `--no-nested` flag

### Phase 4: TUI Session (P1)
- Configure Zellij with web server
- Implement `attach` command
- Add worktree management

### Phase 5: Sync (P1 - MVP Complete)
- Git server in sandbox
- Host-initiated pull
- Auto-sync modes

## References

- **Specification**: `specs/012-agent-sandbox/spec.md`
- **Tasks**: `specs/012-agent-sandbox/tasks.md`
- **Plan**: `specs/012-agent-sandbox/plan.md`
- **CLI Spec**: `specs/012-agent-sandbox/contracts/cli-spec.md`
- **Data Model**: `specs/012-agent-sandbox/data-model.md`
- **Quickstart**: `specs/012-agent-sandbox/quickstart.md`
- **Related**: `docs/agent-microvms.md`

## Known Issues

- Network access required to build MicroVM configuration (DNS blocking in sandbox environment)
- Claude Code package installation needs to be implemented
- Git sync workflow not yet implemented
