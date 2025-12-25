#!/usr/bin/env python3
"""
Keystone Agent Sandbox Manager

This script manages isolated MicroVM environments for AI coding agents (Claude Code,
Gemini CLI, Codex) to operate autonomously without host security restrictions.

Goals:
------
1. Launch sandboxes with isolated execution environments (MicroVM)
2. Provide secure bidirectional file transfer via host-initiated git sync
3. Manage terminal sessions with Zellij for multiplexing
4. Support multiple worktrees for parallel branch development
5. Proxy development servers to *.sandbox.local hostnames
6. Enable nested virtualization for infrastructure testing

Architecture:
-------------
Host System:
  - CLI (this script) manages sandbox lifecycle
  - Host-initiated git push/pull for code sync
  - Caddy reverse proxy for dev servers
  - State persisted in ~/.config/keystone/agent/

MicroVM Sandbox:
  - Isolated NixOS environment with AI agents
  - Workspace at /workspace/ with git worktrees
  - Zellij for session management
  - Optional nested virtualization (KVM passthrough)

Usage:
------
    keystone agent start [OPTIONS] [PROJECT_PATH]   # Launch sandbox
    keystone agent stop [NAME]                      # Stop sandbox
    keystone agent attach [NAME]                    # Attach to session
    keystone agent sync [NAME]                      # Sync changes to host
    keystone agent status [NAME]                    # Show sandbox status
    keystone agent list                             # List all sandboxes
    keystone agent destroy [NAME]                   # Remove sandbox completely

Examples:
---------
    keystone agent start                            # Start sandbox for current project
    keystone agent start --memory 16384 --vcpus 8   # Start with custom resources
    keystone agent start --fresh                    # Discard previous state
    keystone agent start --agent claude             # Auto-launch Claude Code
    keystone agent attach                           # Attach to running sandbox
    keystone agent sync                             # Sync changes to host
    keystone agent stop                             # Stop current sandbox
    keystone agent destroy my-project               # Remove specific sandbox

Configuration:
--------------
    ~/.config/keystone/agent/
    ├── agent.toml          # User configuration
    ├── sandboxes.json      # Sandbox registry
    └── sandboxes/          # Sandbox state directories
        └── <name>/
            ├── workspace/  # Git repository
            └── state/      # MicroVM state

See: specs/012-agent-sandbox/spec.md for full specification
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional, Dict, Any


# ANSI color codes for terminal output
class Colors:
    RESET = "\033[0m"
    BOLD = "\033[1m"
    RED = "\033[91m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    BLUE = "\033[94m"
    MAGENTA = "\033[95m"
    CYAN = "\033[96m"


def print_error(msg: str) -> None:
    """Print error message in red."""
    print(f"{Colors.RED}✗ {msg}{Colors.RESET}", file=sys.stderr)


def print_success(msg: str) -> None:
    """Print success message in green."""
    print(f"{Colors.GREEN}✓ {msg}{Colors.RESET}")


def print_info(msg: str) -> None:
    """Print info message in blue."""
    print(f"{Colors.BLUE}ℹ {msg}{Colors.RESET}")


def print_warning(msg: str) -> None:
    """Print warning message in yellow."""
    print(f"{Colors.YELLOW}⚠ {msg}{Colors.RESET}")


def print_warning(msg: str) -> None:
    """Print warning message in yellow."""
    print(f"{Colors.YELLOW}⚠ {msg}{Colors.RESET}")


class SandboxRegistry:
    """Manages the registry of sandboxes."""
    
    def __init__(self, registry_path: Path):
        self.registry_path = registry_path
        self.registry_path.parent.mkdir(parents=True, exist_ok=True)
    
    def load(self) -> Dict[str, Any]:
        """Load sandbox registry from disk."""
        if not self.registry_path.exists():
            return {}
        
        try:
            with open(self.registry_path, 'r') as f:
                return json.load(f)
        except json.JSONDecodeError:
            print_error(f"Failed to parse registry at {self.registry_path}")
            return {}
    
    def save(self, registry: Dict[str, Any]) -> None:
        """Save sandbox registry to disk."""
        with open(self.registry_path, 'w') as f:
            json.dump(registry, f, indent=2)
    
    def get_sandbox(self, name: str) -> Optional[Dict[str, Any]]:
        """Get sandbox by name."""
        registry = self.load()
        return registry.get(name)
    
    def add_sandbox(self, name: str, config: Dict[str, Any]) -> None:
        """Add or update sandbox in registry."""
        registry = self.load()
        registry[name] = config
        self.save(registry)
    
    def remove_sandbox(self, name: str) -> None:
        """Remove sandbox from registry."""
        registry = self.load()
        if name in registry:
            del registry[name]
            self.save(registry)
    
    def list_sandboxes(self) -> Dict[str, Any]:
        """List all sandboxes."""
        return self.load()


class AgentCLI:
    """Main CLI application for Agent Sandbox management."""
    
    def __init__(self):
        self.config_dir = Path.home() / ".config" / "keystone" / "agent"
        self.registry_path = self.config_dir / "sandboxes.json"
        self.sandboxes_dir = self.config_dir / "sandboxes"
        self.registry = SandboxRegistry(self.registry_path)
        
        # Ensure directories exist
        self.config_dir.mkdir(parents=True, exist_ok=True)
        self.sandboxes_dir.mkdir(parents=True, exist_ok=True)
    
    def run(self, args: argparse.Namespace) -> int:
        """Main entry point for CLI commands."""
        command = args.command
        
        if command == "start":
            return self.cmd_start(args)
        elif command == "stop":
            return self.cmd_stop(args)
        elif command == "attach":
            return self.cmd_attach(args)
        elif command == "sync":
            return self.cmd_sync(args)
        elif command == "status":
            return self.cmd_status(args)
        elif command == "list":
            return self.cmd_list(args)
        elif command == "destroy":
            return self.cmd_destroy(args)
        elif command == "worktree":
            return self.cmd_worktree(args)
        elif command == "exec":
            return self.cmd_exec(args)
        elif command == "ssh":
            return self.cmd_ssh(args)
        else:
            print_error(f"Unknown command: {command}")
            return 1
    
    def cmd_start(self, args: argparse.Namespace) -> int:
        """Start a sandbox."""
        # Determine project path
        project_path = Path(args.project_path if args.project_path else os.getcwd()).resolve()
        
        # Verify it's a git repository
        if not (project_path / ".git").exists():
            print_error(f"Not a git repository: {project_path}")
            return 1
        
        # Derive sandbox name from project directory if not provided
        sandbox_name = args.name if args.name else project_path.name
        
        # Check if sandbox already exists
        existing = self.registry.get_sandbox(sandbox_name)
        if existing and not args.fresh:
            if existing.get('status') == 'running':
                print_error(f"Sandbox '{sandbox_name}' is already running")
                print_info(f"Use 'keystone agent attach {sandbox_name}' to connect")
                print_info(f"Or use '--fresh' to discard and start new")
                return 2
        
        # Check KVM availability
        if not Path("/dev/kvm").exists():
            print_error("KVM is not available on this system")
            print_info("Nested virtualization requires KVM support")
            return 4
        
        # Create sandbox directory
        sandbox_dir = self.sandboxes_dir / sandbox_name
        workspace_dir = sandbox_dir / "workspace"
        state_dir = sandbox_dir / "state"
        
        if args.fresh and sandbox_dir.exists():
            print_info(f"Removing existing sandbox: {sandbox_name}")
            shutil.rmtree(sandbox_dir)
        
        sandbox_dir.mkdir(parents=True, exist_ok=True)
        workspace_dir.mkdir(parents=True, exist_ok=True)
        state_dir.mkdir(parents=True, exist_ok=True)
        
        # Initialize workspace with git clone
        if not (workspace_dir / ".git").exists():
            print_info(f"Initializing workspace from {project_path}")
            result = subprocess.run(
                ["git", "clone", str(project_path), str(workspace_dir)],
                capture_output=True,
                text=True
            )
            if result.returncode != 0:
                print_error(f"Failed to clone repository: {result.stderr}")
                return 1
        
        print_success(f"Starting sandbox '{sandbox_name}'...")
        print(f"  Project: {project_path}")
        print(f"  Memory: {args.memory} MB")
        print(f"  vCPUs: {args.vcpus}")
        print(f"  Nested virt: {'disabled' if args.no_nested else 'enabled'}")
        print(f"  Network: {args.network}")
        print(f"  Sync mode: {args.sync_mode}")
        
        # Generate flake.nix and configuration for the sandbox
        print_info("Generating sandbox configuration...")
        flake_content = self._generate_sandbox_flake(
            sandbox_name=sandbox_name,
            workspace_dir=workspace_dir,
            memory=args.memory,
            vcpus=args.vcpus,
            nested=not args.no_nested,
            network=args.network
        )
        
        # Write flake to state directory
        flake_path = state_dir / "flake.nix"
        with open(flake_path, 'w') as f:
            f.write(flake_content)
        
        # Try to copy flake.lock from keystone tests if available (for offline use)
        # Look in common keystone repo locations
        possible_keystone_paths = [
            Path.cwd(),  # Current directory
            Path.home() / "code" / "ncrmro" / "keystone",  # Common dev location
            Path("/home/runner/work/keystone/keystone"),  # CI location
        ]
        
        for keystone_path in possible_keystone_paths:
            test_lock = keystone_path / "tests" / "flake.lock"
            if test_lock.exists():
                print_info(f"Using flake.lock from {test_lock} for offline support")
                shutil.copy(test_lock, state_dir / "flake.lock")
                break
        else:
            print_warning("No flake.lock found - will require network access to build")
        
        # Initialize git repo for the flake (required by Nix flakes)
        if not (state_dir / ".git").exists():
            subprocess.run(["git", "init"], cwd=state_dir, capture_output=True, check=True)
            subprocess.run(["git", "add", "."], cwd=state_dir, capture_output=True, check=True)
            subprocess.run(
                ["git", "config", "user.email", "sandbox@keystone.local"],
                cwd=state_dir,
                capture_output=True,
                check=True
            )
            subprocess.run(
                ["git", "config", "user.name", "Keystone Agent Sandbox"],
                cwd=state_dir,
                capture_output=True,
                check=True
            )
            subprocess.run(
                ["git", "commit", "-m", "Initial sandbox configuration"],
                cwd=state_dir,
                capture_output=True,
                check=True
            )
        
        # Build the MicroVM runner
        print_info("Building MicroVM runner...")
        runner_path = state_dir / "runner"
        
        result = subprocess.run(
            [
                "nix", "build",
                "--offline",  # Use offline mode to prevent network fetches
                f"{state_dir}#nixosConfigurations.sandbox.config.microvm.declaredRunner",
                "--out-link", str(runner_path)
            ],
            capture_output=True,
            text=True
        )
        
        if result.returncode != 0:
            print_error(f"Failed to build MicroVM")
            print_error("Note: Building sandboxes requires network access on first use")
            print_error("to fetch microvm.nix and nixpkgs. After the first successful")
            print_error("build, the flake.lock can be reused for offline builds.")
            if result.stderr:
                print_info("Build error:")
                for line in result.stderr.split('\n')[-15:]:  # Show last 15 lines
                    if line.strip():
                        print(f"  {line}")
            return 3
        
        # Register sandbox
        self.registry.add_sandbox(sandbox_name, {
            'name': sandbox_name,
            'project_path': str(project_path),
            'sandbox_dir': str(sandbox_dir),
            'workspace_dir': str(workspace_dir),
            'state_dir': str(state_dir),
            'memory': args.memory,
            'vcpus': args.vcpus,
            'nested': not args.no_nested,
            'network': args.network,
            'sync_mode': args.sync_mode,
            'status': 'running',
            'runner_path': str(runner_path)
        })
        
        print_success(f"Sandbox '{sandbox_name}' started successfully!")
        print_info(f"Runner: {runner_path}/bin/microvm-run")
        
        if not args.no_attach:
            print_info("To start the MicroVM, run:")
            print(f"  {runner_path}/bin/microvm-run")
            print_warning("Auto-attach not yet implemented. Use 'keystone agent attach' to connect.")
        
        return 0
    
    def _generate_sandbox_flake(self, sandbox_name: str, workspace_dir: Path, 
                                 memory: int, vcpus: int, nested: bool, network: str) -> str:
        """Generate flake.nix for the sandbox MicroVM.
        
        Uses a simple standalone configuration that doesn't require network access
        when used within a nix develop shell that already has microvm.nix available.
        """
        return f'''{{
  description = "Agent Sandbox: {sandbox_name}";

  inputs = {{
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    microvm = {{
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    }};
  }};

  outputs = {{ self, nixpkgs, microvm }}: {{
    nixosConfigurations.sandbox = nixpkgs.lib.nixosSystem {{
      system = "x86_64-linux";
      modules = [
        microvm.nixosModules.microvm
        ({{ pkgs, config, lib, ... }}: {{
          microvm = {{
            hypervisor = "qemu";
            mem = {memory};
            vcpu = {vcpus};
            
            shares = [
              {{
                proto = "virtiofs";
                tag = "workspace";
                source = "{workspace_dir}";
                mountPoint = "/workspace";
              }}
            ];
            
            interfaces = [
              {{
                type = "{network}";
                id = "eth0";
                mac = "02:00:00:01:01:01";
              }}
            ];
          }};

          networking.hostName = "{sandbox_name}";
          
          users.users.sandbox = {{
            isNormalUser = true;
            description = "Sandbox User";
            extraGroups = [ "wheel" ];
            initialPassword = "sandbox";
          }};
          
          security.sudo.wheelNeedsPassword = false;
          
          # Development tools
          environment.systemPackages = with pkgs; [
            git
            vim
            curl
            htop
          ];
          
          services.openssh = {{
            enable = true;
            settings.PasswordAuthentication = true;
          }};
          
          system.stateVersion = "25.05";
        }})
      ];
    }};
  }};
}}
'''
    
    def cmd_stop(self, args: argparse.Namespace) -> int:
        """Stop a sandbox."""
        print_info("Command 'stop' not yet implemented")
        return 0
    
    def cmd_attach(self, args: argparse.Namespace) -> int:
        """Attach to a sandbox session."""
        print_info("Command 'attach' not yet implemented")
        return 0
    
    def cmd_sync(self, args: argparse.Namespace) -> int:
        """Sync changes between sandbox and host."""
        print_info("Command 'sync' not yet implemented")
        return 0
    
    def cmd_status(self, args: argparse.Namespace) -> int:
        """Show sandbox status."""
        print_info("Command 'status' not yet implemented")
        return 0
    
    def cmd_list(self, args: argparse.Namespace) -> int:
        """List all sandboxes."""
        sandboxes = self.registry.list_sandboxes()
        
        if not sandboxes:
            print_info("No sandboxes found")
            return 0
        
        print(f"{Colors.BOLD}Sandboxes:{Colors.RESET}")
        for name, config in sandboxes.items():
            status = config.get('status', 'unknown')
            print(f"  {name}: {status}")
        
        return 0
    
    def cmd_destroy(self, args: argparse.Namespace) -> int:
        """Destroy a sandbox."""
        print_info("Command 'destroy' not yet implemented")
        return 0
    
    def cmd_worktree(self, args: argparse.Namespace) -> int:
        """Manage worktrees in sandbox."""
        print_info("Command 'worktree' not yet implemented")
        return 0
    
    def cmd_exec(self, args: argparse.Namespace) -> int:
        """Execute command in sandbox."""
        print_info("Command 'exec' not yet implemented")
        return 0
    
    def cmd_ssh(self, args: argparse.Namespace) -> int:
        """SSH into sandbox."""
        print_info("Command 'ssh' not yet implemented")
        return 0


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Keystone Agent Sandbox Manager",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    
    subparsers = parser.add_subparsers(dest="command", help="Command to execute")
    
    # Start command
    start_parser = subparsers.add_parser("start", help="Launch a sandbox")
    start_parser.add_argument("project_path", nargs="?", help="Path to git repository (default: current directory)")
    start_parser.add_argument("--name", help="Sandbox name (derived from project if omitted)")
    start_parser.add_argument("--memory", type=int, default=8192, help="RAM in MB (default: 8192)")
    start_parser.add_argument("--vcpus", type=int, default=4, help="Virtual CPU count (default: 4)")
    start_parser.add_argument("--no-nested", action="store_true", help="Disable nested virtualization")
    start_parser.add_argument("--fresh", action="store_true", help="Discard previous sandbox state")
    start_parser.add_argument("--network", choices=["user", "tap", "macvtap", "bridge"], default="user", help="Network mode (default: user)")
    start_parser.add_argument("--sync-mode", choices=["manual", "auto-commit", "auto-idle"], default="manual", help="Sync mode (default: manual)")
    start_parser.add_argument("--no-attach", action="store_true", help="Start without attaching to session")
    start_parser.add_argument("--agent", choices=["claude", "gemini", "codex"], help="Auto-start agent")
    
    # Stop command
    stop_parser = subparsers.add_parser("stop", help="Stop a sandbox")
    stop_parser.add_argument("name", nargs="?", help="Sandbox name (default: current project)")
    stop_parser.add_argument("--sync", action="store_true", help="Sync before stopping")
    
    # Attach command
    attach_parser = subparsers.add_parser("attach", help="Attach to sandbox session")
    attach_parser.add_argument("name", nargs="?", help="Sandbox name (default: current project)")
    attach_parser.add_argument("--web", action="store_true", help="Open web UI instead of terminal")
    attach_parser.add_argument("--worktree", help="Attach to specific worktree")
    
    # Sync command
    sync_parser = subparsers.add_parser("sync", help="Sync changes to host")
    sync_parser.add_argument("name", nargs="?", help="Sandbox name (default: current project)")
    sync_parser.add_argument("--artifacts", action="store_true", help="Sync artifacts via rsync")
    sync_parser.add_argument("--dry-run", action="store_true", help="Show what would be synced")
    
    # Status command
    status_parser = subparsers.add_parser("status", help="Show sandbox status")
    status_parser.add_argument("name", nargs="?", help="Sandbox name (default: current project)")
    status_parser.add_argument("--json", action="store_true", help="Output in JSON format")
    
    # List command
    list_parser = subparsers.add_parser("list", help="List all sandboxes")
    list_parser.add_argument("--json", action="store_true", help="Output in JSON format")
    
    # Destroy command
    destroy_parser = subparsers.add_parser("destroy", help="Remove sandbox completely")
    destroy_parser.add_argument("name", help="Sandbox name")
    destroy_parser.add_argument("--force", action="store_true", help="Force destroy without confirmation")
    
    # Worktree commands
    worktree_parser = subparsers.add_parser("worktree", help="Manage worktrees")
    worktree_subparsers = worktree_parser.add_subparsers(dest="worktree_command")
    
    worktree_add = worktree_subparsers.add_parser("add", help="Add worktree")
    worktree_add.add_argument("branch", help="Branch name")
    worktree_add.add_argument("--sandbox", help="Sandbox name (default: current project)")
    
    worktree_list = worktree_subparsers.add_parser("list", help="List worktrees")
    worktree_list.add_argument("--sandbox", help="Sandbox name (default: current project)")
    
    worktree_remove = worktree_subparsers.add_parser("remove", help="Remove worktree")
    worktree_remove.add_argument("branch", help="Branch name")
    worktree_remove.add_argument("--sandbox", help="Sandbox name (default: current project)")
    
    # Exec command
    exec_parser = subparsers.add_parser("exec", help="Execute command in sandbox")
    exec_parser.add_argument("name", nargs="?", help="Sandbox name (default: current project)")
    exec_parser.add_argument("command", nargs=argparse.REMAINDER, help="Command to execute")
    
    # SSH command
    ssh_parser = subparsers.add_parser("ssh", help="SSH into sandbox")
    ssh_parser.add_argument("name", nargs="?", help="Sandbox name (default: current project)")
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return 1
    
    cli = AgentCLI()
    return cli.run(args)


if __name__ == "__main__":
    sys.exit(main())
