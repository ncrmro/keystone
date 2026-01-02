#!/usr/bin/env python3
"""
Keystone Agent - MicroVM sandbox manager for AI coding agents

This CLI manages isolated sandbox environments for running AI coding agents
like Claude, Gemini, and Codex.
"""

import argparse
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path

# Configuration
CONFIG_DIR = Path.home() / ".config" / "keystone" / "agent"
SANDBOXES_FILE = CONFIG_DIR / "sandboxes.json"
SANDBOXES_DIR = CONFIG_DIR / "sandboxes"
DEFAULT_SSH_PORT = 2223
DEFAULT_SSH_USER = "sandbox"

# Workspace modes
MODE_PASSTHROUGH = "passthrough"  # VirtioFS share - host files shared directly
MODE_CLONE = "clone"              # Git clone - repo cloned into sandbox
VALID_MODES = [MODE_PASSTHROUGH, MODE_CLONE]

# API tokens that can be forwarded to sandbox
FORWARDABLE_TOKENS = [
    "ANTHROPIC_API_KEY",
    "GEMINI_API_KEY",
    "OPENAI_API_KEY",
    "CLAUDE_API_KEY",
]


def ensure_config_dir():
    """Ensure configuration directory exists."""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)


def load_sandboxes() -> dict:
    """Load sandbox registry from disk."""
    if not SANDBOXES_FILE.exists():
        return {}
    with open(SANDBOXES_FILE) as f:
        return json.load(f)


def save_sandboxes(sandboxes: dict):
    """Save sandbox registry to disk."""
    ensure_config_dir()
    with open(SANDBOXES_FILE, "w") as f:
        json.dump(sandboxes, f, indent=2)


def get_ssh_public_key() -> str:
    """Get the user's SSH public key for passwordless authentication.

    Checks common key locations in order of preference.
    Returns empty string if no key found.
    """
    key_paths = [
        Path.home() / ".ssh" / "id_ed25519.pub",
        Path.home() / ".ssh" / "id_rsa.pub",
        Path.home() / ".ssh" / "id_ecdsa.pub",
    ]

    for key_path in key_paths:
        if key_path.exists():
            try:
                key = key_path.read_text().strip()
                if key:
                    return key
            except Exception:
                pass

    return ""


def get_git_identity() -> dict:
    """Extract git identity from host configuration.

    Only extracts safe fields (user.name, user.email) - never credentials.
    """
    identity = {}
    for key in ["user.name", "user.email"]:
        result = subprocess.run(
            ["git", "config", "--global", key],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            identity[key] = result.stdout.strip()
    return identity


def sync_git_identity(sandbox: dict) -> bool:
    """Sync host git identity to sandbox via SSH.

    Returns True if sync was successful.
    """
    identity = get_git_identity()
    if not identity:
        print("Warning: No git identity found on host, skipping sync")
        return False

    name = identity.get("user.name", "")
    email = identity.get("user.email", "")

    if not name or not email:
        print("Warning: Incomplete git identity, skipping sync")
        return False

    port = sandbox.get("ssh_port", DEFAULT_SSH_PORT)
    user = sandbox.get("ssh_user", DEFAULT_SSH_USER)

    # Escape values for shell
    name_escaped = shlex.quote(name)
    email_escaped = shlex.quote(email)

    # The .config/git/config may be a symlink to nix store (home-manager).
    # Remove it first to allow git to write a real file.
    # We use ~/.gitconfig as fallback which git also recognizes.
    setup_cmd = (
        "rm -f ~/.config/git/config 2>/dev/null; "
        "mkdir -p ~/.config/git 2>/dev/null; "
        f"git config --global user.name {name_escaped} && "
        f"git config --global user.email {email_escaped}"
    )

    cmd = [
        "ssh", "-p", str(port),
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "LogLevel=ERROR",
        f"{user}@localhost",
        setup_cmd,
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode == 0:
        print(f"Git identity synced: {name} <{email}>")
        return True
    else:
        print(f"Warning: Failed to sync git identity: {result.stderr}")
        return False


def get_available_tokens() -> dict:
    """Get API tokens available in host environment."""
    tokens = {}
    for var in FORWARDABLE_TOKENS:
        value = os.environ.get(var)
        if value:
            tokens[var] = value
    return tokens


def generate_sandbox_flake(sandbox: dict) -> str:
    """Generate a flake.nix for the sandbox microVM.

    The generated flake configures:
    - MicroVM with QEMU hypervisor
    - 9p shares for workspace (passthrough mode) with securityModel=mapped
    - SSH access with port forwarding
    - OpenSSH configured to accept token environment variables
    - Git identity from host
    - Unique build ID to bust Nix cache
    """
    import time

    name = sandbox["name"]
    mode = sandbox.get("mode", MODE_CLONE)
    project_path = sandbox.get("project", "")

    # Generate unique build ID to force Nix to rebuild (bust cache)
    # Without this, identical flake.nix content = same derivation hash = cached result
    build_id = str(int(time.time()))

    # Get git identity from host to bake into the VM config
    git_identity = get_git_identity()
    git_name = git_identity.get("user.name", "Sandbox User")
    git_email = git_identity.get("user.email", "sandbox@localhost")

    # Get SSH public key for passwordless authentication
    ssh_public_key = get_ssh_public_key()

    # Generate authorized keys line if SSH key exists
    if ssh_public_key:
        ssh_authorized_keys = f'openssh.authorizedKeys.keys = [ "{ssh_public_key}" ];'
    else:
        ssh_authorized_keys = ""

    # Base shares - always share /nix/store for faster builds
    shares_nix = '''
      {
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
      }'''

    # Add workspace share for passthrough mode
    # IMPORTANT: Use securityModel = "mapped" to allow guest to write files.
    # This stores guest UID/GID as extended attributes, allowing proper permission
    # handling between guest and host. Without this, files created in guest
    # won't be visible on host due to UID mapping issues.
    # NOTE: Do NOT specify proto = "virtiofs" - it requires a separate virtiofsd
    # daemon. The default (9p) is built into QEMU and works out of the box.
    if mode == MODE_PASSTHROUGH and project_path:
        shares_workspace = f'''
      {{
        tag = "workspace";
        source = "{project_path}";
        mountPoint = "/workspace";
        securityModel = "mapped";
      }}'''
        shares = f"[{shares_nix}{shares_workspace}\n    ]"
    else:
        shares = f"[{shares_nix}\n    ]"

    # Token environment variables that sshd should accept (as Nix list)
    token_vars = " ".join([f'"{t}"' for t in FORWARDABLE_TOKENS])

    flake_content = f'''{{
  description = "Keystone Agent Sandbox: {name}";

  inputs = {{
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    microvm.url = "github:astro/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";
  }};

  outputs = {{ self, nixpkgs, microvm, ... }}: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${{system}};
  in {{
    nixosConfigurations.sandbox = nixpkgs.lib.nixosSystem {{
      inherit system;
      modules = [
        microvm.nixosModules.microvm
        ({{ config, pkgs, ... }}: {{
          # MicroVM configuration
          microvm = {{
            hypervisor = "qemu";
            mem = 4096;
            vcpu = 2;

            # Disable QEMU sandbox (seccomp) to allow 9p file writes
            # The default -sandbox on blocks file creation in shared directories
            qemu.extraArgs = [ "-sandbox" "off" ];

            # User-mode networking with SSH port forward
            interfaces = [
              {{
                type = "user";
                id = "net0";
                mac = "02:00:00:00:00:01";
              }}
            ];

            forwardPorts = [
              {{
                from = "host";
                host.port = {DEFAULT_SSH_PORT};
                guest.port = 22;
              }}
            ];

            # VirtioFS shares
            shares = {shares};

            # Writable overlay for the nix store (needed for some operations)
            writableStoreOverlay = "/nix/.rw-store";
          }};

          # Make home directory writable via tmpfs
          fileSystems."/home" = {{
            device = "tmpfs";
            fsType = "tmpfs";
            options = [ "size=1G" "mode=755" ];
          }};

          # Override workspace mount options for better performance
          # With security_model=mapped, guest UIDs are stored as xattrs on host
          fileSystems."/workspace" = {{
            device = "workspace";
            fsType = "9p";
            options = [ "trans=virtio" "version=9p2000.L" "msize=65536" ];
          }};

          # Create sandbox user home directory after tmpfs mount
          systemd.services.create-sandbox-home = {{
            description = "Create sandbox user home directory";
            wantedBy = [ "multi-user.target" ];
            after = [ "local-fs.target" ];
            before = [ "systemd-user-sessions.service" ];
            serviceConfig = {{
              Type = "oneshot";
              ExecStart = "/run/current-system/sw/bin/mkdir -p /home/{DEFAULT_SSH_USER}";
              ExecStartPost = "/run/current-system/sw/bin/chown {DEFAULT_SSH_USER}:users /home/{DEFAULT_SSH_USER}";
              RemainAfterExit = true;
            }};
          }};

          # Basic system configuration
          networking.hostName = "{name}";
          system.stateVersion = "24.11";

          # SSH configuration
          services.openssh = {{
            enable = true;
            settings = {{
              PermitRootLogin = "no";
              PasswordAuthentication = true;
              # Accept API token environment variables from SSH client
              AcceptEnv = [ {token_vars} ];
            }};
          }};

          # Sandbox user with SSH key from host for passwordless login
          # SECURITY NOTE: User has passwordless sudo for /workspace access.
          # This is intentional for AI agent workflows but has security implications:
          # - Agents can execute any command as root inside the VM
          # - The VM is isolated but shares /workspace with host
          # - Malicious code could modify host files in /workspace
          # - The VM cannot escape to the host system outside /workspace
          users.users.{DEFAULT_SSH_USER} = {{
            isNormalUser = true;
            password = "{DEFAULT_SSH_USER}";
            extraGroups = [ "wheel" ];
            home = "/home/{DEFAULT_SSH_USER}";
            {ssh_authorized_keys}
          }};

          # Passwordless sudo for sandbox user to allow /workspace writes
          # Required because 9p mounts show files as root-owned in guest
          security.sudo.extraRules = [
            {{
              users = [ "{DEFAULT_SSH_USER}" ];
              commands = [ {{ command = "ALL"; options = [ "NOPASSWD" ]; }} ];
            }}
          ];

          # Development tools
          environment.systemPackages = with pkgs; [
            git
            vim
            curl
            wget
          ];

          # Set working directory to /workspace
          environment.variables.WORKSPACE = "/workspace";

          # Git identity from host (baked in at sandbox creation)
          environment.etc."gitconfig".text = ''
            [user]
                name = {git_name}
                email = {git_email}
          '';

          # Build ID for cache busting - changes derivation hash to force rebuild
          environment.etc."sandbox-build-id".text = "{build_id}";
        }})
      ];
    }};

    # MicroVM runner
    packages.${{system}}.default = self.nixosConfigurations.sandbox.config.microvm.declaredRunner;
  }};
}}
'''
    return flake_content


def get_sandbox_dir(name: str) -> Path:
    """Get the directory for a sandbox's files."""
    return SANDBOXES_DIR / name


def setup_sandbox_files(sandbox: dict) -> Path:
    """Set up the sandbox directory with flake.nix.

    Returns the path to the sandbox directory.
    """
    name = sandbox["name"]
    sandbox_dir = get_sandbox_dir(name)
    sandbox_dir.mkdir(parents=True, exist_ok=True)

    # Generate and write flake.nix
    flake_content = generate_sandbox_flake(sandbox)
    flake_path = sandbox_dir / "flake.nix"
    with open(flake_path, "w") as f:
        f.write(flake_content)

    print(f"Generated sandbox configuration: {flake_path}")
    return sandbox_dir


def build_microvm(sandbox_dir: Path) -> Path:
    """Build the microVM from the sandbox flake.

    Returns the path to the built runner.
    """
    # Delete flake.lock to force fresh input resolution
    # This prevents Nix from using cached derivations when inputs haven't changed
    lock_file = sandbox_dir / "flake.lock"
    if lock_file.exists():
        lock_file.unlink()
        print("Deleted flake.lock to force fresh build")

    print("Building microVM (this may take a while on first run)...")

    result = subprocess.run(
        ["nix", "build", f"{sandbox_dir}#default", "--no-link", "--print-out-paths"],
        capture_output=True,
        text=True,
        cwd=sandbox_dir,
    )

    if result.returncode != 0:
        raise RuntimeError(f"Failed to build microVM: {result.stderr}")

    runner_path = Path(result.stdout.strip())
    print(f"Built microVM: {runner_path}")
    return runner_path


def start_microvm(sandbox: dict, runner_path: Path) -> tuple:
    """Start the microVM in the background.

    Returns tuple of (PID, PGID) of the microVM process.
    The PGID is used for reliable process group killing.
    """
    sandbox_dir = Path(sandbox["sandbox_dir"])
    log_file = sandbox_dir / "microvm.log"

    # Find the run script
    run_script = runner_path / "bin" / "microvm-run"
    if not run_script.exists():
        raise RuntimeError(f"microVM run script not found: {run_script}")

    print(f"Starting microVM...")

    # Start the microVM in background, redirect output to log file
    # start_new_session=True creates a new process group with PGID = PID
    with open(log_file, "w") as log:
        process = subprocess.Popen(
            [str(run_script)],
            stdout=log,
            stderr=subprocess.STDOUT,
            cwd=sandbox_dir,
            start_new_session=True,  # Creates new session AND process group
        )

    # Get the process group ID (same as PID when using start_new_session)
    pgid = os.getpgid(process.pid)

    print(f"MicroVM started (PID: {process.pid}, PGID: {pgid}, log: {log_file})")
    return process.pid, pgid


def wait_for_ssh(sandbox: dict, timeout: int = 120) -> bool:
    """Wait for SSH to become available on the sandbox.

    Returns True if SSH is ready, False if timeout.
    """
    import time
    import socket

    port = sandbox.get("ssh_port", DEFAULT_SSH_PORT)
    start_time = time.time()

    print(f"Waiting for SSH on port {port}...", end="", flush=True)

    while time.time() - start_time < timeout:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(1)
            result = sock.connect_ex(("localhost", port))
            sock.close()

            if result == 0:
                print(" ready!")
                return True
        except socket.error:
            pass

        print(".", end="", flush=True)
        time.sleep(2)

    print(" timeout!")
    return False


def _verify_port_free(port: int, timeout: float = 3.0) -> bool:
    """Verify the port is actually free after killing.

    Returns True if port is free, False if still in use.
    """
    import socket
    import time

    start = time.time()
    while time.time() - start < timeout:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(("127.0.0.1", port))
            sock.close()
            return True
        except OSError:
            time.sleep(0.3)
        finally:
            try:
                sock.close()
            except Exception:
                pass
    return False


def _kill_by_port(port: int) -> bool:
    """Find and kill any process holding the port using lsof.

    Returns True if successful.
    """
    import signal
    import time

    result = subprocess.run(
        ["lsof", "-t", f"-i:{port}"],
        capture_output=True,
        text=True,
    )

    if result.returncode == 0 and result.stdout.strip():
        pids = result.stdout.strip().split('\n')
        for pid_str in pids:
            try:
                pid = int(pid_str)
                print(f"Force killing process {pid} on port {port}...")
                os.kill(pid, signal.SIGKILL)  # Use SIGKILL directly for zombies
            except (ValueError, OSError):
                pass
        time.sleep(0.5)
        return True
    return False


def stop_microvm(sandbox: dict) -> bool:
    """Stop a running microVM by killing its entire process group.

    Uses os.killpg() to kill ALL processes in the VM's process group,
    including QEMU and any child processes. This is more reliable than
    killing individual PIDs because:
    1. The microvm-run wrapper spawns QEMU as a child process
    2. Killing just the wrapper leaves QEMU running as an orphan
    3. Process groups ensure we kill everything

    Falls back to lsof port scanning if process group kill fails.
    Always verifies the port is actually free before returning.

    Returns True if stopped successfully.
    """
    import signal
    import time

    port = sandbox.get("ssh_port", DEFAULT_SSH_PORT)
    pgid = sandbox.get("pgid")
    pid = sandbox.get("pid")

    # Strategy 1: Kill by process group (most reliable)
    if pgid:
        try:
            print(f"Killing process group {pgid}...")
            os.killpg(pgid, signal.SIGTERM)

            # Wait for graceful shutdown
            for _ in range(10):
                try:
                    os.killpg(pgid, 0)  # Check if group still exists
                    time.sleep(0.5)
                except OSError:
                    break  # Group is gone
            else:
                # Force kill if still running
                print(f"Force killing process group {pgid}...")
                try:
                    os.killpg(pgid, signal.SIGKILL)
                except OSError:
                    pass

        except OSError as e:
            print(f"Process group {pgid} not found: {e}")

    # Strategy 2: Kill by PID (fallback)
    if pid and pid != pgid:
        try:
            os.kill(pid, signal.SIGTERM)
            time.sleep(1)
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
        except OSError:
            pass

    # Strategy 3: Kill by port (last resort for zombies)
    # Always try this to catch any orphaned QEMU processes
    _kill_by_port(port)

    # CRITICAL: Verify port is actually free before proceeding
    if not _verify_port_free(port, timeout=5.0):
        print(f"WARNING: Port {port} still in use after kill attempts!")
        # One more aggressive attempt
        _kill_by_port(port)
        time.sleep(1)
        if not _verify_port_free(port, timeout=2.0):
            print(f"ERROR: Could not free port {port}")
            return False

    print(f"Port {port} is now free")
    return True


def build_ssh_command(sandbox: dict, forward_tokens: bool = True, command: str = None) -> list:
    """Build SSH command with optional token forwarding.

    Args:
        sandbox: Sandbox configuration dict
        forward_tokens: Whether to forward API tokens
        command: Optional command to run (if None, starts interactive shell)

    Returns:
        List of command arguments for subprocess
    """
    port = sandbox.get("ssh_port", DEFAULT_SSH_PORT)
    user = sandbox.get("ssh_user", DEFAULT_SSH_USER)

    ssh_args = [
        "ssh", "-t",
        "-p", str(port),
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "LogLevel=ERROR",
        f"{user}@localhost",
    ]

    if forward_tokens:
        tokens = get_available_tokens()
        if tokens:
            # Build environment export commands
            exports = []
            for var, value in tokens.items():
                # Escape the value for shell
                escaped = shlex.quote(value)
                exports.append(f"export {var}={escaped}")

            env_setup = "; ".join(exports)

            if command:
                ssh_args.append(f"{env_setup}; {command}")
            else:
                ssh_args.append(f"{env_setup}; exec $SHELL -l")
        else:
            if command:
                ssh_args.append(command)
            # If no tokens and no command, SSH will start interactive shell
    else:
        if command:
            ssh_args.append(command)

    return ssh_args


# ============================================================================
# CLI Commands
# ============================================================================

def cmd_start(args):
    """Start a new sandbox or reattach to existing one."""
    sandboxes = load_sandboxes()

    name = args.name or "default"
    mode = getattr(args, "mode", MODE_PASSTHROUGH) or MODE_PASSTHROUGH
    fresh = getattr(args, "fresh", False)

    # Validate mode
    if mode not in VALID_MODES:
        print(f"Error: Invalid mode '{mode}'. Must be one of: {', '.join(VALID_MODES)}", file=sys.stderr)
        return 1

    # Handle --fresh: stop and remove existing sandbox first
    if fresh and name in sandboxes:
        print(f"Stopping and removing existing sandbox '{name}'...")
        existing = sandboxes[name]
        # Stop the microVM if running
        if existing.get("state") == "running":
            stop_microvm(existing)
        # Clean up sandbox directory
        sandbox_dir = get_sandbox_dir(name)
        if sandbox_dir.exists():
            import shutil
            shutil.rmtree(sandbox_dir)
        del sandboxes[name]
        save_sandboxes(sandboxes)
        # Give the system a moment to release resources
        import time
        time.sleep(1)

    if name in sandboxes and sandboxes[name].get("state") == "running":
        print(f"Sandbox '{name}' is already running")
        if not args.no_attach:
            return cmd_ssh(args)
        return 0

    # Resolve project path to absolute path
    project_path = args.project or os.getcwd()
    project_path = str(Path(project_path).resolve())

    # Validate project path exists for passthrough mode
    if mode == MODE_PASSTHROUGH:
        if not Path(project_path).is_dir():
            print(f"Error: Project directory does not exist: {project_path}", file=sys.stderr)
            return 1

    # Create sandbox configuration
    sandbox = {
        "name": name,
        "state": "running",
        "ssh_port": DEFAULT_SSH_PORT,
        "ssh_user": DEFAULT_SSH_USER,
        "project": project_path,
        "mode": mode,
    }

    # Generate sandbox flake.nix with virtiofs configuration
    sandbox_dir = setup_sandbox_files(sandbox)
    sandbox["sandbox_dir"] = str(sandbox_dir)

    # Build the microVM
    try:
        runner_path = build_microvm(sandbox_dir)
        sandbox["runner_path"] = str(runner_path)
    except RuntimeError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    # Start the microVM
    try:
        pid, pgid = start_microvm(sandbox, runner_path)
        sandbox["pid"] = pid
        sandbox["pgid"] = pgid  # Store process group ID for reliable killing
    except RuntimeError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    # Save sandbox state
    sandboxes[name] = sandbox
    save_sandboxes(sandboxes)

    # Get git identity that was baked in
    git_identity = get_git_identity()
    git_name = git_identity.get("user.name", "Sandbox User")
    git_email = git_identity.get("user.email", "sandbox@localhost")

    print(f"Sandbox '{name}' started")
    print(f"  Mode:    {mode}")
    if mode == MODE_PASSTHROUGH:
        print(f"  Share:   {project_path} -> /workspace (9p)")
    else:
        print(f"  Project: {project_path} (will be cloned)")
    print(f"  Git:     {git_name} <{git_email}>")
    print(f"  SSH:     ssh -p {DEFAULT_SSH_PORT} {DEFAULT_SSH_USER}@localhost")
    print(f"  Config:  {sandbox_dir}/flake.nix")

    # Wait for SSH to become available
    if not wait_for_ssh(sandbox, timeout=120):
        print("Warning: SSH not ready, sandbox may still be booting", file=sys.stderr)

    if not args.no_attach:
        return cmd_ssh(args)

    return 0


def cmd_stop(args):
    """Stop a running sandbox."""
    sandboxes = load_sandboxes()
    name = args.name or "default"

    if name not in sandboxes:
        print(f"Error: Sandbox '{name}' not found", file=sys.stderr)
        return 1

    sandbox = sandboxes[name]

    if sandbox.get("state") != "running":
        print(f"Sandbox '{name}' is not running")
        return 0

    # Stop the microVM process
    if stop_microvm(sandbox):
        print(f"Stopped microVM (PID: {sandbox.get('pid', 'unknown')})")
    else:
        print("Warning: Could not stop microVM process")

    sandboxes[name]["state"] = "stopped"
    sandboxes[name]["pid"] = None
    save_sandboxes(sandboxes)

    print(f"Sandbox '{name}' stopped")
    return 0


def cmd_ssh(args):
    """SSH into a running sandbox with token forwarding."""
    sandboxes = load_sandboxes()
    name = args.name or "default"

    if name not in sandboxes:
        print(f"Error: Sandbox '{name}' not found", file=sys.stderr)
        return 1

    sandbox = sandboxes[name]

    if sandbox.get("state") != "running":
        print(f"Error: Sandbox '{name}' is not running", file=sys.stderr)
        return 1

    forward_tokens = not getattr(args, "no_tokens", False)

    if forward_tokens:
        tokens = get_available_tokens()
        if tokens:
            print(f"Forwarding tokens: {', '.join(tokens.keys())}")

    cmd = build_ssh_command(sandbox, forward_tokens=forward_tokens)

    # Replace current process with SSH
    os.execvp(cmd[0], cmd)


def cmd_exec(args):
    """Execute a command in the sandbox."""
    sandboxes = load_sandboxes()
    name = args.name or "default"

    if name not in sandboxes:
        print(f"Error: Sandbox '{name}' not found", file=sys.stderr)
        return 1

    sandbox = sandboxes[name]

    if sandbox.get("state") != "running":
        print(f"Error: Sandbox '{name}' is not running", file=sys.stderr)
        return 1

    command = " ".join(args.command)
    forward_tokens = not getattr(args, "no_tokens", False)

    cmd = build_ssh_command(sandbox, forward_tokens=forward_tokens, command=command)

    result = subprocess.run(cmd)
    return result.returncode


def cmd_status(args):
    """Show status of sandbox(es)."""
    sandboxes = load_sandboxes()
    name = args.name

    if name:
        if name not in sandboxes:
            print(f"Error: Sandbox '{name}' not found", file=sys.stderr)
            return 1

        sandbox = sandboxes[name]
        mode = sandbox.get("mode", MODE_CLONE)
        print(f"Name:    {sandbox['name']}")
        print(f"State:   {sandbox['state']}")
        print(f"Mode:    {mode}")
        print(f"Project: {sandbox.get('project', 'N/A')}")
        if mode == MODE_PASSTHROUGH:
            print(f"Share:   {sandbox.get('project', 'N/A')} -> /workspace (9p)")
        print(f"SSH:     ssh -p {sandbox.get('ssh_port', DEFAULT_SSH_PORT)} {sandbox.get('ssh_user', DEFAULT_SSH_USER)}@localhost")
        if sandbox.get("sandbox_dir"):
            print(f"Config:  {sandbox['sandbox_dir']}/flake.nix")
    else:
        # List all sandboxes
        if not sandboxes:
            print("No sandboxes found")
            return 0

        print(f"{'NAME':<20} {'STATE':<10} {'MODE':<12} {'PROJECT'}")
        print("-" * 72)
        for name, sandbox in sandboxes.items():
            project = sandbox.get("project", "N/A")
            mode = sandbox.get("mode", MODE_PASSTHROUGH)
            state = sandbox.get("state", "unknown")
            if len(project) > 25:
                project = "..." + project[-22:]
            print(f"{name:<20} {state:<10} {mode:<12} {project}")

    return 0


def cmd_list(args):
    """List all sandboxes."""
    args.name = None
    return cmd_status(args)


def cmd_destroy(args):
    """Destroy a sandbox and its data."""
    sandboxes = load_sandboxes()
    name = args.name or "default"

    if name not in sandboxes:
        print(f"Error: Sandbox '{name}' not found", file=sys.stderr)
        return 1

    if not args.force:
        response = input(f"Are you sure you want to destroy sandbox '{name}'? [y/N] ")
        if response.lower() != "y":
            print("Aborted")
            return 0

    del sandboxes[name]
    save_sandboxes(sandboxes)

    print(f"Sandbox '{name}' destroyed")
    return 0


def cmd_sync(args):
    """Sync changes between host and sandbox."""
    sandboxes = load_sandboxes()
    name = args.name or "default"

    if name not in sandboxes:
        print(f"Error: Sandbox '{name}' not found", file=sys.stderr)
        return 1

    sandbox = sandboxes[name]

    if sandbox.get("state") != "running":
        print(f"Error: Sandbox '{name}' is not running", file=sys.stderr)
        return 1

    # Sync git identity if requested
    if args.git:
        sync_git_identity(sandbox)

    print(f"Sync completed for sandbox '{name}'")
    return 0


def cmd_tokens(args):
    """Show or manage API tokens."""
    tokens = get_available_tokens()

    if not tokens:
        print("No API tokens found in environment")
        print("")
        print("Set tokens via environment variables:")
        for var in FORWARDABLE_TOKENS:
            print(f"  export {var}=your-token-here")
        return 0

    print("Available tokens (will be forwarded to sandbox):")
    for var in tokens:
        # Show masked token
        value = tokens[var]
        if len(value) > 8:
            masked = value[:4] + "..." + value[-4:]
        else:
            masked = "***"
        print(f"  {var}: {masked}")

    return 0


# ============================================================================
# Main Entry Point
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        prog="keystone-agent",
        description="Manage MicroVM sandboxes for AI coding agents",
    )

    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    # start command
    start_parser = subparsers.add_parser("start", help="Start a sandbox")
    start_parser.add_argument("project", nargs="?", help="Project directory to mount")
    start_parser.add_argument("--name", "-n", help="Sandbox name (default: 'default')")
    start_parser.add_argument(
        "--mode", "-m",
        choices=VALID_MODES,
        default=MODE_PASSTHROUGH,
        help=f"Workspace mode: '{MODE_PASSTHROUGH}' shares host dir via virtiofs (default), '{MODE_CLONE}' clones repo"
    )
    start_parser.add_argument("--fresh", action="store_true", help="Remove existing sandbox and start fresh")
    start_parser.add_argument("--no-attach", action="store_true", help="Don't attach after starting")
    start_parser.set_defaults(func=cmd_start)

    # stop command
    stop_parser = subparsers.add_parser("stop", help="Stop a sandbox")
    stop_parser.add_argument("name", nargs="?", help="Sandbox name")
    stop_parser.set_defaults(func=cmd_stop)

    # ssh command
    ssh_parser = subparsers.add_parser("ssh", help="SSH into sandbox")
    ssh_parser.add_argument("name", nargs="?", help="Sandbox name")
    ssh_parser.add_argument("--no-tokens", action="store_true", help="Don't forward API tokens")
    ssh_parser.set_defaults(func=cmd_ssh)

    # exec command
    exec_parser = subparsers.add_parser("exec", help="Execute command in sandbox")
    exec_parser.add_argument("name", nargs="?", help="Sandbox name")
    exec_parser.add_argument("--no-tokens", action="store_true", help="Don't forward API tokens")
    exec_parser.add_argument("command", nargs=argparse.REMAINDER, help="Command to execute")
    exec_parser.set_defaults(func=cmd_exec)

    # status command
    status_parser = subparsers.add_parser("status", help="Show sandbox status")
    status_parser.add_argument("name", nargs="?", help="Sandbox name (omit for all)")
    status_parser.set_defaults(func=cmd_status)

    # list command
    list_parser = subparsers.add_parser("list", help="List all sandboxes")
    list_parser.set_defaults(func=cmd_list)

    # destroy command
    destroy_parser = subparsers.add_parser("destroy", help="Destroy a sandbox")
    destroy_parser.add_argument("name", nargs="?", help="Sandbox name")
    destroy_parser.add_argument("--force", "-f", action="store_true", help="Skip confirmation")
    destroy_parser.set_defaults(func=cmd_destroy)

    # sync command
    sync_parser = subparsers.add_parser("sync", help="Sync between host and sandbox")
    sync_parser.add_argument("name", nargs="?", help="Sandbox name")
    sync_parser.add_argument("--git", action="store_true", help="Sync git identity")
    sync_parser.set_defaults(func=cmd_sync)

    # tokens command
    tokens_parser = subparsers.add_parser("tokens", help="Show available API tokens")
    tokens_parser.set_defaults(func=cmd_tokens)

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 1

    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
