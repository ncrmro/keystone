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
import time
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

    def _resolve_sandbox_name(self, name: Optional[str]) -> Optional[str]:
        """Resolve sandbox name from argument or current directory."""
        if name:
            return name
        # Derive from current directory
        cwd = Path.cwd()
        if (cwd / ".git").exists():
            return cwd.name
        return None

    def _get_sandbox_or_error(self, name: Optional[str]) -> Optional[Dict[str, Any]]:
        """Get sandbox config or print error if not found."""
        resolved_name = self._resolve_sandbox_name(name)
        if not resolved_name:
            print_error("Could not determine sandbox name. Specify --name or run from a git repository.")
            return None

        sandbox = self.registry.get_sandbox(resolved_name)
        if not sandbox:
            print_error(f"Sandbox '{resolved_name}' not found")
            print_info("Use 'keystone agent list' to see available sandboxes")
            return None

        sandbox['_name'] = resolved_name  # Store resolved name
        return sandbox

    def _get_pid_file(self, sandbox_name: str) -> Path:
        """Get the PID file path for a sandbox."""
        return self.sandboxes_dir / sandbox_name / "state" / "microvm.pid"

    def _is_running(self, sandbox_name: str) -> bool:
        """Check if a sandbox is currently running."""
        pid_file = self._get_pid_file(sandbox_name)
        if not pid_file.exists():
            return False

        try:
            pid = int(pid_file.read_text().strip())
            # Check if process exists
            os.kill(pid, 0)
            return True
        except (ValueError, ProcessLookupError, PermissionError):
            return False

    def _update_status(self, sandbox_name: str) -> None:
        """Update sandbox status based on actual running state."""
        sandbox = self.registry.get_sandbox(sandbox_name)
        if sandbox:
            actual_status = "running" if self._is_running(sandbox_name) else "stopped"
            if sandbox.get('status') != actual_status:
                sandbox['status'] = actual_status
                self.registry.add_sandbox(sandbox_name, sandbox)

    def _run_in_sandbox(self, sandbox_name: str, command: list) -> subprocess.CompletedProcess:
        """Execute a command inside the sandbox via SSH.

        Args:
            sandbox_name: Name of the sandbox (used for error messages)
            command: Command and arguments to run in the sandbox

        Returns:
            CompletedProcess with stdout, stderr, and returncode
        """
        ssh_cmd = [
            "ssh",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "LogLevel=ERROR",
            "-o", "ConnectTimeout=10",
            "-p", "2223",
            "sandbox@localhost",
            "--"
        ] + command

        return subprocess.run(ssh_cmd, capture_output=True, text=True)

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
            # Ensure existing process is stopped before removing files
            if self._is_running(sandbox_name):
                print_info(f"Stopping running instance of '{sandbox_name}'...")
                self.cmd_stop(argparse.Namespace(name=sandbox_name, sync=False))
                # Give it a moment to release ports
                time.sleep(2)
            
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
        
        # Find user's SSH public key for authentication
        ssh_key = None
        for key_name in ["id_ed25519.pub", "id_rsa.pub", "id_ecdsa.pub"]:
            key_path = Path.home() / ".ssh" / key_name
            if key_path.exists():
                ssh_key = key_path.read_text().strip()
                print_info(f"Using SSH key: {key_path}")
                break

        if not ssh_key:
            print_warning("No SSH key found in ~/.ssh/")
            print_info("Generate one with: ssh-keygen -t ed25519")
            print_info("Falling back to password authentication (password: sandbox)")

        print_success(f"Starting sandbox '{sandbox_name}'...")
        print(f"  Project: {project_path}")
        print(f"  Memory: {args.memory} MB")
        print(f"  vCPUs: {args.vcpus}")
        print(f"  Nested virt: {'disabled' if args.no_nested else 'enabled'}")
        print(f"  Network: {args.network}")
        print(f"  Sync mode: {args.sync_mode}")
        print(f"  SSH auth: {'key' if ssh_key else 'password'}")

        # Generate flake.nix and configuration for the sandbox
        print_info("Generating sandbox configuration...")
        flake_content = self._generate_sandbox_flake(
            sandbox_name=sandbox_name,
            workspace_dir=workspace_dir,
            project_path=project_path,
            memory=args.memory,
            vcpus=args.vcpus,
            nested=not args.no_nested,
            network=args.network,
            ssh_key=ssh_key
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
        
        # Register sandbox (initially as stopped until we launch it)
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
            'status': 'stopped',
            'runner_path': str(runner_path),
            'ssh_auth': 'key' if ssh_key else 'password'
        })

        # Launch the MicroVM in the background
        print_info("Launching MicroVM...")
        microvm_run = runner_path / "bin" / "microvm-run"

        # Start the MicroVM process in background (must run in state_dir for socket paths)
        process = subprocess.Popen(
            [str(microvm_run)],
            cwd=str(state_dir),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True  # Detach from terminal
        )

        # Save PID for tracking
        pid_file = self._get_pid_file(sandbox_name)
        pid_file.write_text(str(process.pid))

        # Update status to running
        sandbox = self.registry.get_sandbox(sandbox_name)
        sandbox['status'] = 'running'
        sandbox['pid'] = process.pid
        self.registry.add_sandbox(sandbox_name, sandbox)

        print_success(f"Sandbox '{sandbox_name}' started successfully!")
        print_info(f"PID: {process.pid}")
        print_info("Waiting for SSH to become available...")

        # Wait for SSH to be ready (with timeout)
        # Just check if port is open, don't try to auth
        for i in range(30):  # Wait up to 30 seconds
            result = subprocess.run(
                ["nc", "-z", "localhost", "2223"],
                capture_output=True
            )
            if result.returncode == 0:
                print_success("SSH port is ready!")
                if not ssh_key:
                    print_info("Password: sandbox")
                break
            time.sleep(1)
        else:
            print_warning("SSH not ready after 30s - VM may still be booting")
            print_info("Try: keystone agent ssh")
        
        # Initialize sandbox workspace
        print_info("Initializing sandbox workspace...")
        # Give SSH service a moment to fully accept connections
        time.sleep(2)
        
        # Use rsync to push the repo to the VM
        rsync_cmd = [
            "rsync",
            "-avz",
            "--exclude", ".git",  # Exclude .git folder for speed (optional, but good for initial init)
            "--exclude", "node_modules",
            "--exclude", "target",
            "--exclude", "dist",
            "-e", "ssh -p 2223 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR",
            f"{workspace_dir}/",
            "sandbox@localhost:/workspace/"
        ]
        
        # We need to re-include .git if we want git to work inside, 
        # but for a large repo this might be slow on first boot.
        # Let's include it for now as it's required for git operations.
        # Removing exclusions for now.
        rsync_cmd = [
            "rsync",
            "-az",  # Archive mode, compress
            "-e", "ssh -p 2223 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR",
            f"{workspace_dir}/",
            "sandbox@localhost:/workspace/"
        ]

        # Retry rsync a few times as SSH might reject early connections
        for attempt in range(5):
            try:
                result = subprocess.run(rsync_cmd, capture_output=True, text=True, timeout=30)
                if result.returncode == 0:
                    print_success("Workspace initialized")
                    break
            except subprocess.TimeoutExpired:
                print_warning(f"Rsync attempt {attempt+1} timed out")
            
            time.sleep(2)
        else:
            print_error("Failed to initialize workspace")
            if 'result' in locals() and result.stderr:
                print(f"  {result.stderr.strip()}")

        if not args.no_attach:
            print_info("Attaching to sandbox...")
            return self.cmd_attach(args)

        return 0
    
    def _generate_sandbox_flake(self, sandbox_name: str, workspace_dir: Path,
                                 project_path: Path,
                                 memory: int, vcpus: int, nested: bool, network: str,
                                 ssh_key: Optional[str] = None) -> str:
        """Generate minimal flake.nix for the sandbox MicroVM.

        Uses a pinned nixpkgs revision for reproducibility and a minimal NixOS
        configuration with just basic development tools.
        """
        # Generate build ID to force cache invalidation
        # Why: Nix was aggressively caching the erofs disk image, causing it to lack
        #      newly added packages (like direnv) despite the flake config changing.
        #      This timestamp forces a unique input hash for every build.
        # Downside: This prevents caching of the VM image between runs, causing
        #           slower startup times (rebuilds every time).
        # TODO: Remove this once we identify why the cache invalidation is failing.
        build_id = int(time.time())

        # Pin to known-good nixpkgs revision from keystone flake.lock
        # This avoids build failures from transient breakage in nixos-unstable HEAD
        nixpkgs_rev = "c6245e83d836d0433170a16eb185cefe0572f8b8"

        # Determine keystone flake URL
        # If project is the keystone repo itself, use local path for development
        # Otherwise use the published GitHub version
        keystone_terminal_path = project_path / "modules" / "keystone" / "terminal"
        if keystone_terminal_path.exists():
            # Local keystone development - use path reference to ORIGINAL project
            # This captures uncommitted changes
            keystone_url = f"path:{project_path}"
        else:
            # External project - use published keystone
            keystone_url = "github:ncrmro/keystone"

        # Generate user config based on SSH key availability
        if ssh_key:
            # SSH key auth - more secure, no password needed
            user_config = f'''users.users.sandbox = {{
            isNormalUser = true;
            extraGroups = [ "wheel" ];
            openssh.authorizedKeys.keys = [ "{ssh_key}" ];
          }};'''
            ssh_config = '''services.openssh = {
            enable = true;
            settings = {
              PasswordAuthentication = false;
              PermitRootLogin = "no";
            };
          };'''
        else:
            # Fallback to password auth when no SSH key available
            user_config = '''users.users.sandbox = {
            isNormalUser = true;
            extraGroups = [ "wheel" ];
            initialPassword = "sandbox";
          };'''
            ssh_config = '''services.openssh = {
            enable = true;
            settings = {
              PasswordAuthentication = true;
              PermitRootLogin = "no";
            };
          };'''

        return f'''{{
  description = "Agent Sandbox: {sandbox_name}";

  inputs = {{
    nixpkgs.url = "github:NixOS/nixpkgs/{nixpkgs_rev}";
    microvm = {{
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    }};
    home-manager = {{
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    }};
    keystone = {{
      url = "{keystone_url}";
      inputs.nixpkgs.follows = "nixpkgs";
    }};
  }};

  outputs = {{ self, nixpkgs, microvm, home-manager, keystone }}: let
    # Apply keystone overlay to get keystone packages (zesh, claude-code)
    pkgs = import nixpkgs {{
      system = "x86_64-linux";
      config.allowUnfree = true;
      overlays = [ keystone.overlays.default ];
    }};
  in {{
    nixosConfigurations.sandbox = nixpkgs.lib.nixosSystem {{
      system = "x86_64-linux";
      modules = [
        microvm.nixosModules.microvm
        home-manager.nixosModules.home-manager
        ({{ ... }}: {{
          # Use the overlayed pkgs
          nixpkgs.pkgs = pkgs;

          # MicroVM configuration
          microvm = {{
            hypervisor = "qemu";
            mem = {memory};
            vcpu = {vcpus};

            interfaces = [{{
              type = "{network}";
              id = "eth0";
              mac = "02:00:00:01:01:01";
            }}];

            # Forward SSH port to localhost only
            forwardPorts = [
              {{ from = "host"; host.port = 2223; guest.port = 22; }}
            ];

            # Enable writable store overlay for Home Manager activation
            writableStoreOverlay = "/nix/.rw-store";
          }};

          # Minimal system config
          networking.hostName = "{sandbox_name}";
          environment.etc."build-id".text = "{build_id}";
          system.stateVersion = "25.05";
          
          # Enable Nix experimental features
          nix.settings.experimental-features = [ "nix-command" "flakes" ];

          # Create /workspace directory with correct ownership
          systemd.tmpfiles.rules = [
            "d /workspace 0755 sandbox users -"
          ];

          # User configuration
          {user_config}
          security.sudo.wheelNeedsPassword = false;

          # Home-manager configuration with keystone terminal
          home-manager = {{
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = {{
              inputs = {{
                inherit keystone;
              }};
            }};
            sharedModules = [
              keystone.homeModules.terminal
            ];
            users.sandbox = {{
              home.stateVersion = "25.05";

              # Enable keystone terminal module
              keystone.terminal = {{
                enable = true;
                git = {{
                  userName = "Sandbox User";
                  userEmail = "sandbox@keystone.local";
                }};
              }};
            }};
          }};

          # System-wide zsh
          users.defaultUserShell = pkgs.zsh;
          programs.zsh.enable = true;

          # Auto-allow direnv for /workspace
          environment.etc."direnv/direnv.toml".text = ''
            [whitelist]
            prefix = [ "/workspace" ]
          '';

          # SSH configuration
          {ssh_config}
        }})
      ];
    }};
  }};
}}
'''
    
    def cmd_stop(self, args: argparse.Namespace) -> int:
        """Stop a sandbox."""
        sandbox = self._get_sandbox_or_error(args.name)
        if not sandbox:
            return 1

        sandbox_name = sandbox['_name']
        state_dir = Path(sandbox.get('state_dir', ''))

        # Check if running
        if not self._is_running(sandbox_name):
            print_info(f"Sandbox '{sandbox_name}' is not running")
            return 0

        # Sync before stopping if requested
        if args.sync:
            print_info("Syncing changes before stopping...")
            # TODO: Implement sync logic
            print_warning("Sync not yet implemented, skipping")

        # Try graceful shutdown first
        shutdown_script = state_dir / "runner" / "bin" / "microvm-shutdown"
        if shutdown_script.exists():
            print_info(f"Stopping sandbox '{sandbox_name}'...")
            try:
                result = subprocess.run(
                    [str(shutdown_script)],
                    cwd=str(state_dir),
                    capture_output=True,
                    text=True,
                    timeout=10
                )
                if result.returncode == 0:
                    print_success(f"MicroVM stopped")
                else:
                    print_warning("Graceful shutdown failed, trying force kill...")
                    # Force kill via PID
                    pid_file = self._get_pid_file(sandbox_name)
                    if pid_file.exists():
                        try:
                            pid = int(pid_file.read_text().strip())
                            os.kill(pid, 15)  # SIGTERM
                            print_success(f"MicroVM terminated")
                        except (ValueError, ProcessLookupError):
                            pass
            except subprocess.TimeoutExpired:
                print_warning("Graceful shutdown timed out, trying force kill...")
                # Force kill via PID
                pid_file = self._get_pid_file(sandbox_name)
                if pid_file.exists():
                    try:
                        pid = int(pid_file.read_text().strip())
                        os.kill(pid, 15)  # SIGTERM
                        print_success(f"MicroVM terminated")
                    except (ValueError, ProcessLookupError):
                        pass
        else:
            # No shutdown script, try PID file
            pid_file = self._get_pid_file(sandbox_name)
            if pid_file.exists():
                try:
                    pid = int(pid_file.read_text().strip())
                    os.kill(pid, 15)  # SIGTERM
                    print_success(f"MicroVM terminated")
                except (ValueError, ProcessLookupError):
                    print_error(f"Could not stop sandbox '{sandbox_name}'")
                    return 1

        # Clean up PID file
        pid_file = self._get_pid_file(sandbox_name)
        if pid_file.exists():
            pid_file.unlink()

        # Update status
        sandbox['status'] = 'stopped'
        del sandbox['_name']  # Remove internal field
        self.registry.add_sandbox(sandbox_name, sandbox)

        print_success(f"Sandbox '{sandbox_name}' stopped")
        return 0
    
    def cmd_attach(self, args: argparse.Namespace) -> int:
        """Attach to a sandbox session via SSH."""
        sandbox = self._get_sandbox_or_error(args.name)
        if not sandbox:
            return 1

        sandbox_name = sandbox['_name']

        # Check if running
        if not self._is_running(sandbox_name):
            print_error(f"Sandbox '{sandbox_name}' is not running")
            print_info(f"Start it with: keystone agent start")
            return 1

        # For now, just SSH in (web UI not implemented)
        if getattr(args, 'web', False):
            print_warning("Web UI not yet implemented, using SSH instead")

        print_info(f"Attaching to sandbox '{sandbox_name}'...")
        print_info("Use 'exit' or Ctrl-D to detach")

        # SSH to the sandbox (user networking uses port forwarding)
        # Default SSH port is forwarded to localhost:2223 in user mode
        # Start in /workspace directory for convenience
        result = subprocess.run(
            [
                "ssh",
                "-t",  # Force pseudo-terminal for interactive shell
                "-o", "StrictHostKeyChecking=no",
                "-o", "UserKnownHostsFile=/dev/null",
                "-o", "LogLevel=ERROR",
                "-p", "2223",
                "sandbox@localhost",
                "cd /workspace && exec $SHELL -l"
            ]
        )

        return result.returncode
    
    def cmd_sync(self, args: argparse.Namespace) -> int:
        """Sync changes from sandbox back to host.

        This command pulls committed changes from the sandbox workspace
        back to the host repository using git fetch and merge.

        Exit codes:
            0 - Sync completed successfully
            1 - Sandbox not found or not running
            2 - No changes to sync
            3 - Merge conflict or fetch failed
        """
        # 1. Resolve sandbox
        sandbox = self._get_sandbox_or_error(args.name)
        if not sandbox:
            return 1

        sandbox_name = sandbox['_name']
        project_path = Path(sandbox.get('project_path'))

        # 2. Check sandbox is running
        if not self._is_running(sandbox_name):
            print_error(f"Sandbox '{sandbox_name}' is not running")
            print_info("Start it with: keystone agent start")
            return 1

        # 3. Check host repo state
        host_status = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=project_path,
            capture_output=True,
            text=True
        )

        if host_status.stdout.strip():
            print_warning("Host repository has uncommitted changes:")
            for line in host_status.stdout.strip().split('\n')[:5]:
                print(f"  {line}")
            if len(host_status.stdout.strip().split('\n')) > 5:
                print("  ...")
            print_info("Consider stashing: git stash")
            # Don't block, just warn - conflicts will be caught during merge

        # 4. Check sandbox for changes
        print_info(f"Checking sandbox '{sandbox_name}' for changes...")

        sandbox_status = self._run_in_sandbox(
            sandbox_name,
            ["git", "-C", "/workspace", "status", "--porcelain"]
        )

        sandbox_log = self._run_in_sandbox(
            sandbox_name,
            ["git", "-C", "/workspace", "log", "--oneline", "origin/HEAD..HEAD", "-n", "20"]
        )

        uncommitted = sandbox_status.stdout.strip() if sandbox_status.returncode == 0 else ""
        new_commits = sandbox_log.stdout.strip() if sandbox_log.returncode == 0 else ""

        # 5. Report findings
        has_changes = bool(new_commits)

        if not has_changes and not args.artifacts:
            if uncommitted:
                print_info("Sandbox has uncommitted changes (not synced):")
                for line in uncommitted.split('\n')[:10]:
                    print(f"  {line}")
                print_info("Commit changes in sandbox to sync them")
            else:
                print_info("Nothing to sync - sandbox is up to date with host")
            return 2

        # 6. Show what will be synced
        if new_commits:
            print(f"\n{Colors.CYAN}New commits in sandbox:{Colors.RESET}")
            for line in new_commits.split('\n'):
                print(f"  {line}")

        if uncommitted:
            print(f"\n{Colors.YELLOW}Uncommitted changes (will NOT sync):{Colors.RESET}")
            for line in uncommitted.split('\n')[:10]:
                print(f"  {line}")
            if len(uncommitted.split('\n')) > 10:
                print("  ...")

        # 7. Dry run stops here
        if args.dry_run:
            print_info("\nDry run complete - no changes made")
            return 0

        # 8. Perform git sync
        if new_commits:
            print_info("\nFetching changes from sandbox...")

            # Set up SSH command for git
            ssh_command = "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p 2223"
            env = {**os.environ, "GIT_SSH_COMMAND": ssh_command}

            # Fetch from sandbox
            result = subprocess.run(
                ["git", "fetch", "sandbox@localhost:/workspace", "HEAD"],
                cwd=project_path,
                capture_output=True,
                text=True,
                env=env
            )

            if result.returncode != 0:
                print_error("Failed to fetch from sandbox")
                if result.stderr:
                    for line in result.stderr.strip().split('\n')[-5:]:
                        print(f"  {line}")
                return 3

            # Try fast-forward merge
            result = subprocess.run(
                ["git", "merge", "--ff-only", "FETCH_HEAD"],
                cwd=project_path,
                capture_output=True,
                text=True
            )

            if result.returncode != 0:
                print_warning("Fast-forward merge not possible")
                print_info("The sandbox branch has diverged from host")
                print_info("To resolve, run in your project directory:")
                print(f"  cd {project_path}")
                print("  git merge FETCH_HEAD  # or: git rebase FETCH_HEAD")
                return 3

            print_success("Git changes synced successfully!")

        # 9. Sync artifacts if requested
        if args.artifacts:
            return self._sync_artifacts(sandbox_name, project_path, dry_run=False)

        return 0

    def _sync_artifacts(self, sandbox_name: str, project_path: Path,
                        dry_run: bool = False) -> int:
        """Rsync build artifacts from sandbox to host.

        Args:
            sandbox_name: Name of the sandbox
            project_path: Path to host project directory
            dry_run: If True, only show what would be synced

        Returns:
            0 on success, non-zero on failure
        """
        # Common artifact directories
        artifact_dirs = ["dist/", "build/", "target/", ".next/", "out/"]

        print_info("Syncing build artifacts...")

        synced_any = False
        for artifact_dir in artifact_dirs:
            # Check if directory exists in sandbox
            check = self._run_in_sandbox(
                sandbox_name,
                ["test", "-d", f"/workspace/{artifact_dir}"]
            )

            if check.returncode == 0:
                print_info(f"  Syncing {artifact_dir}...")

                rsync_cmd = [
                    "rsync",
                    "-avz",
                    "--progress",
                    "-e", "ssh -p 2223 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR",
                ]

                if dry_run:
                    rsync_cmd.append("--dry-run")

                source = f"sandbox@localhost:/workspace/{artifact_dir}"
                dest = str(project_path / artifact_dir)

                result = subprocess.run(
                    rsync_cmd + [source, dest],
                    capture_output=True,
                    text=True
                )

                if result.returncode != 0:
                    print_warning(f"  Failed to sync {artifact_dir}")
                    if result.stderr:
                        print(f"    {result.stderr.strip()}")
                else:
                    synced_any = True

        if not synced_any:
            print_info("No artifact directories found to sync")

        return 0
    
    def cmd_status(self, args: argparse.Namespace) -> int:
        """Show sandbox status."""
        sandbox = self._get_sandbox_or_error(args.name)
        if not sandbox:
            return 1

        sandbox_name = sandbox['_name']

        # Update status based on actual running state
        self._update_status(sandbox_name)
        sandbox = self.registry.get_sandbox(sandbox_name)

        # JSON output
        if args.json:
            print(json.dumps(sandbox, indent=2))
            return 0

        # Human-readable output
        status = sandbox.get('status', 'unknown')
        is_running = self._is_running(sandbox_name)

        # Status with color
        if is_running:
            status_str = f"{Colors.GREEN}running{Colors.RESET}"
        else:
            status_str = f"{Colors.YELLOW}stopped{Colors.RESET}"

        print(f"{Colors.BOLD}Sandbox: {sandbox_name}{Colors.RESET}")
        print(f"  Status:      {status_str}")
        print(f"  Project:     {sandbox.get('project_path', 'N/A')}")
        print(f"  Workspace:   {sandbox.get('workspace_dir', 'N/A')}")
        print(f"  Memory:      {sandbox.get('memory', 'N/A')} MB")
        print(f"  vCPUs:       {sandbox.get('vcpus', 'N/A')}")
        print(f"  Network:     {sandbox.get('network', 'N/A')}")
        print(f"  Nested virt: {'enabled' if sandbox.get('nested', False) else 'disabled'}")
        print(f"  Sync mode:   {sandbox.get('sync_mode', 'N/A')}")

        # Show runner path if available
        runner_path = sandbox.get('runner_path')
        if runner_path:
            print(f"  Runner:      {runner_path}")

        # Show PID if running
        if is_running:
            pid_file = self._get_pid_file(sandbox_name)
            if pid_file.exists():
                try:
                    pid = int(pid_file.read_text().strip())
                    print(f"  PID:         {pid}")
                except ValueError:
                    pass

        return 0
    
    def cmd_list(self, args: argparse.Namespace) -> int:
        """List all sandboxes."""
        sandboxes = self.registry.list_sandboxes()
        
        if not sandboxes:
            print_info("No sandboxes found")
            return 0
        
        # JSON output
        if args.json:
            import json
            print(json.dumps(sandboxes, indent=2))
            return 0
        
        # Table output
        # Header
        print(f"{Colors.BOLD}{'SANDBOX':<20} {'STATE':<12} {'BACKEND':<10} {'PROJECT':<40}{Colors.RESET}")
        print("─" * 82)
        
        # Rows
        for name, config in sorted(sandboxes.items()):
            status = config.get('status', 'unknown')
            backend = 'microvm'  # Default backend
            project_path = config.get('project_path', 'N/A')
            
            # Truncate project path if too long
            if len(project_path) > 38:
                project_path = '...' + project_path[-35:]
            
            # Color code status
            if status == 'running':
                status_colored = f"{Colors.GREEN}{status}{Colors.RESET}"
            elif status == 'stopped':
                status_colored = f"{Colors.YELLOW}{status}{Colors.RESET}"
            else:
                status_colored = status
            
            print(f"{name:<20} {status_colored:<21} {backend:<10} {project_path:<40}")
        
        print()
        print(f"Total: {len(sandboxes)} sandbox(es)")
        
        return 0
    
    def cmd_destroy(self, args: argparse.Namespace) -> int:
        """Destroy a sandbox completely."""
        sandbox_name = args.name
        sandbox = self.registry.get_sandbox(sandbox_name)

        if not sandbox:
            print_error(f"Sandbox '{sandbox_name}' not found")
            return 1

        # Check if running
        if self._is_running(sandbox_name):
            if not args.force:
                print_error(f"Sandbox '{sandbox_name}' is still running")
                print_info("Stop it first with: keystone agent stop")
                print_info("Or use --force to destroy anyway")
                return 1
            else:
                # Force stop first
                print_info(f"Force stopping sandbox '{sandbox_name}'...")
                pid_file = self._get_pid_file(sandbox_name)
                if pid_file.exists():
                    try:
                        pid = int(pid_file.read_text().strip())
                        os.kill(pid, 9)  # SIGKILL
                    except (ValueError, ProcessLookupError):
                        pass

        # Confirm destruction if not forced
        if not args.force:
            print_warning(f"This will permanently delete sandbox '{sandbox_name}'")
            print_warning("Including: workspace, state, and all configuration")
            response = input("Are you sure? [y/N] ").strip().lower()
            if response != 'y':
                print_info("Aborted")
                return 0

        # Remove sandbox directory
        sandbox_dir = self.sandboxes_dir / sandbox_name
        if sandbox_dir.exists():
            print_info(f"Removing sandbox directory: {sandbox_dir}")
            shutil.rmtree(sandbox_dir)

        # Remove from registry
        self.registry.remove_sandbox(sandbox_name)

        print_success(f"Sandbox '{sandbox_name}' destroyed")
        return 0
    
    def cmd_worktree(self, args: argparse.Namespace) -> int:
        """Manage worktrees in sandbox."""
        print_info("Command 'worktree' not yet implemented")
        return 0
    
    def cmd_exec(self, args: argparse.Namespace) -> int:
        """Execute command in sandbox via SSH."""
        sandbox = self._get_sandbox_or_error(args.name)
        if not sandbox:
            return 1

        sandbox_name = sandbox['_name']

        # Check if running
        if not self._is_running(sandbox_name):
            print_error(f"Sandbox '{sandbox_name}' is not running")
            return 1

        # Get command to execute
        command = args.exec_command if args.exec_command else []
        if not command:
            print_error("No command specified")
            print_info("Usage: keystone agent exec [sandbox] -- <command>")
            return 1

        # Execute via SSH
        result = subprocess.run(
            [
                "ssh",
                "-o", "StrictHostKeyChecking=no",
                "-o", "UserKnownHostsFile=/dev/null",
                "-o", "LogLevel=ERROR",
                "-p", "2223",
                "sandbox@localhost",
                "--"
            ] + command
        )

        return result.returncode

    def cmd_ssh(self, args: argparse.Namespace) -> int:
        """SSH into sandbox (alias for attach)."""
        sandbox = self._get_sandbox_or_error(args.name)
        if not sandbox:
            return 1

        sandbox_name = sandbox['_name']

        # Check if running
        if not self._is_running(sandbox_name):
            print_error(f"Sandbox '{sandbox_name}' is not running")
            print_info(f"Start it with: keystone agent start")
            return 1

        # SSH to the sandbox, starting in /workspace
        result = subprocess.run(
            [
                "ssh",
                "-t",  # Force pseudo-terminal for interactive shell
                "-o", "StrictHostKeyChecking=no",
                "-o", "UserKnownHostsFile=/dev/null",
                "-o", "LogLevel=ERROR",
                "-p", "2223",
                "sandbox@localhost",
                "cd /workspace && exec $SHELL -l"
            ]
        )

        return result.returncode


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
    exec_parser.add_argument("exec_command", nargs=argparse.REMAINDER, help="Command to execute")
    
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
