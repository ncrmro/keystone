# Research: Agent Sandbox Workflow Improvements (V2)

## Goal

This document explores questions and identifies problems related to improving the usability and seamlessness of the `keystone-agent` sandbox workflow, particularly from within a Nix development shell (devshell).

## Identified Problems and Questions

### 1. Devshell Integration

**Problem/Question**: How can the `keystone-agent` script be made easier to use and integrate more seamlessly when invoked from a Nix development shell?

*   What are the typical pain points for users when switching between host and sandbox contexts in a devshell?
*   Can we provide devshell-specific helper functions or aliases?
*   How can we ensure that the `keystone-agent` binary is always readily available and correctly configured in the devshell?

### 2. Issuing Tasks to Agents

**Problem/Question**: How can the process of issuing tasks to AI agents within the sandbox be made more seamless for the user?

*   What are the current methods for task issuance (e.g., direct chat in TUI, specific CLI commands)?
*   Can we implement a host-side command that forwards tasks directly to the agent in the sandbox without requiring manual SSH/TUI interaction?
*   How can agent responses and progress be communicated back to the user on the host in a non-intrusive way?
*   Consider scenarios where agents require clarifying questions. How is this interaction managed seamlessly?

### 3. Opening Code for Editing in the Sandbox

**Problem/Question**: How can the user open and edit code located within the sandbox in their preferred host-side editor (e.g., VS Code, Neovim) in a more integrated manner?

*   What are the current manual steps required to edit sandbox code from the host?
*   Can we leverage `sshfs` or similar protocols for a transparent filesystem view of the sandbox workspace on the host?
*   Can `keystone-agent` provide a command (e.g., `keystone agent open-code`) that automatically launches the host editor configured to access the sandbox's `/workspace`?
*   How do we handle real-time sync of changes made in the host editor to the sandbox?

### 4. Ensuring Git Username/Email Matches

**Problem/Question**: How can we ensure that the Git username and email configured inside the sandbox automatically match the user's host-side Git configuration, thereby maintaining consistent authorship?

*   What is the current process for setting Git identity in the sandbox?
*   Can `keystone-agent` automatically read `~/.gitconfig` or host Git environment variables and propagate them to the sandbox's Git configuration upon startup or sync?
*   Should this be configurable (e.g., allow a specific sandbox Git identity)?

### 5. Automatically Syncing Agent Tokens (Claude/Gemini)

**Problem/Question**: What is the most secure and seamless method for automatically syncing API tokens (e.g., Claude, Gemini) from the host to the sandbox, avoiding manual copy-pasting or insecure storage?

*   What are the security implications of syncing sensitive tokens?
*   Can we use environment variables, a secure key store, or a specific file pattern (like `.env`) that the agent already handles?
*   How can `keystone-agent` facilitate a secure, host-initiated transfer of these tokens without exposing them unnecessarily?
*   Should tokens be persisted in the sandbox, or should they be loaded dynamically per session?
*   Consider different token formats (e.g., plain text, base64 encoded).

---

## CRITICAL BUGS: VM Lifecycle and Passthrough Failures

These bugs have caused repeated failures where `--fresh` doesn't work and passthrough is broken.

### Bug Category 1: Zombie VM Processes (VM Never Actually Killed)

**Symptoms:**
- Running `--fresh` says "Stopping and removing existing sandbox" but old VM keeps running
- Home directory (`/home`, which is tmpfs) has files from previous sessions
- Port 2223 is held by a different PID than what's in the registry
- SSH connects to old VM instead of newly created one

**Root Causes (5 identified):**

1. **Stored PID is for wrapper, not QEMU**: `microvm-run` is a shell script that spawns QEMU as a child. The registry stores the wrapper PID, but killing it doesn't kill QEMU.

2. **Process tree isolation**: `start_new_session=True` creates a new session, but child QEMU becomes orphaned when wrapper exits.

3. **Stale registry state**: If VM crashes or is killed externally, registry PID doesn't match reality.

4. **SIGTERM doesn't propagate**: Sending SIGTERM to wrapper doesn't forward to QEMU subprocess.

5. **No port verification**: Code doesn't verify the port is actually free after killing.

**Solutions (ranked by reliability):**

1. **Use `os.killpg()` with process groups** (RECOMMENDED):
   ```python
   # start_new_session=True creates a process group
   pgid = os.getpgid(process.pid)
   os.killpg(pgid, signal.SIGTERM)  # Kills ALL processes in group
   ```

2. **Always verify port is free after kill**:
   ```python
   def _verify_port_free(port, timeout=2.0):
       sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
       try:
           sock.bind(("localhost", port))
           return True
       except OSError:
           return False
   ```

3. **Use systemd user services**: Let systemd track processes via cgroups with `KillMode=control-group`.

4. **Fallback to lsof + SIGKILL**: If process group kill fails, scan by port and force kill.

---

### Bug Category 2: MicroVM Build Caching (Old Config Still Used)

**Symptoms:**
- Generated `flake.nix` is correct (checked manually)
- But running VM still has old behavior
- Same Nix store path `/nix/store/xxx-microvm-qemu-default` every time
- Changes to workspace share config not reflected

**Root Causes (4 identified):**

1. **Derivation hashing**: Nix computes derivation hash from inputs. If generated `flake.nix` content is identical (same project path, same git identity), the hash is identical → cached result used.

2. **Lock file persistence**: `flake.lock` pins input versions. Even after `shutil.rmtree`, if inputs resolve to same versions, same derivation hash.

3. **Evaluation cache**: Nix caches evaluation results in `~/.cache/nix/eval-cache-v5/`.

4. **No unique identifier**: Nothing in the generated config changes between runs.

**Solutions (ranked by reliability):**

1. **Add build timestamp to derivation** (RECOMMENDED):
   ```nix
   # In generated flake.nix
   environment.etc."sandbox-build-id".text = "1735689600";  # Unix timestamp
   ```
   This changes derivation inputs → forces rebuild.

2. **Delete flake.lock before build**:
   ```python
   lock_file = sandbox_dir / "flake.lock"
   if lock_file.exists():
       lock_file.unlink()
   ```

3. **Disable eval cache**:
   ```python
   subprocess.run(["nix", "build", ..., "--option", "eval-cache", "false"])
   ```

4. **Use `--impure` with `builtins.currentTime`**: Guaranteed different each second, but breaks reproducibility.

---

### Bug Category 3: Passthrough/Share Not Working (Files Don't Sync)

**Symptoms:**
- Files created in `/workspace` inside VM don't appear on host
- Log shows: `Failed to connect to 'xxx-virtiofs-workspace.sock': No such file or directory`
- Using `proto = "virtiofs"` but virtiofsd daemon not running

**Root Causes (4 identified):**

1. **virtiofs requires separate daemon**: When using `proto = "virtiofs"`, the `virtiofsd` daemon must be started BEFORE QEMU. The `microvm-run` script doesn't start it.

2. **Default protocol (9p) has UID mapping issues**: Without `securityModel = "mapped"`, guest UID 1000 doesn't map to host user properly.

3. **microvm.nix standalone vs systemd**: The host module auto-starts virtiofsd, but imperative usage (keystone-agent) doesn't.

4. **Missing security model**: Default `securityModel = "none"` means QEMU runs as invoking user but guest permissions don't translate.

**Solutions (ranked by reliability):**

1. **Use 9p with `securityModel = "mapped"`** (RECOMMENDED):
   ```nix
   {
     tag = "workspace";
     source = "/path/to/project";
     mountPoint = "/workspace";
     # proto defaults to 9p
     securityModel = "mapped";  # Store guest permissions as xattrs
   }
   ```

2. **Remove `proto = "virtiofs"`**: Let it default to 9p which is built into QEMU.

3. **Manually start virtiofsd**: Run `./result/bin/virtiofsd-run` before `microvm-run` (complex).

4. **Use systemd host module**: Full microvm.nix integration with automatic daemon management.

---

### Implementation Checklist

- [x] Add `pgid` to sandbox registry, use `os.killpg()` for killing
- [x] Add `_verify_port_free()` check after every kill attempt
- [x] Add unique build timestamp to generated flake.nix
- [x] Delete `flake.lock` before each build
- [x] Use `securityModel = "mapped"` for 9p share (stores guest UID as xattrs)
- [x] Remove explicit `proto = "virtiofs"` (use 9p default)
- [x] Add `lsof` to package dependencies for fallback port scanning
- [x] Add passwordless sudo for sandbox user (optional, for system commands)
- [x] Add SSH public key from host for passwordless login
- [x] Direct workspace writes work without sudo (files created by sandbox appear sandbox-owned)

---

## Security Considerations for Agent Sandboxes

### Threat Model

The sandbox provides **workspace isolation**, not full security isolation:

| Threat | Mitigation | Residual Risk |
|--------|------------|---------------|
| Agent modifies host files | Limited to `/workspace` directory | Agent CAN modify project files |
| Agent escapes to host | VM isolation, no host access outside /workspace | Low - QEMU provides strong isolation |
| Agent installs malware | VM is ephemeral, destroyed on `--fresh` | None if `--fresh` used between sessions |
| Agent exfiltrates data | Network access allowed for git/API | Agent CAN access network |
| Agent DoS host | VM has limited resources (4GB RAM, 2 CPU) | Limited blast radius |

### Why Passwordless Sudo is Required

The 9p filesystem protocol has a fundamental limitation when running QEMU as a non-root user:

1. **Host files are owned by the host user** (e.g., ncrmro, UID 1000)
2. **QEMU runs as that same user** and can read/write files
3. **But inside the guest**, 9p shows files as owned by root (UID 0)
4. **The sandbox user (UID 1000)** can't write to root-owned files
5. **Solution**: Give sandbox user sudo access to write as root in guest

The sudo access is **contained within the VM** - it doesn't grant host privileges.

### Security Implications for AI Agents

**IMPORTANT: Agents running in the sandbox can:**

1. READ/WRITE any file in /workspace (your project directory)
2. Execute any command as root INSIDE the VM
3. Access the network (for git, API calls, etc.)
4. Modify git history, delete files, etc.

**Agents CANNOT:**

1. Access files outside /workspace
2. Execute commands on the host
3. Access host network interfaces directly
4. Persist changes outside the VM (except /workspace)

### Agent Escape Scenarios

| Scenario | Risk Level | Mitigation |
|----------|------------|------------|
| Agent writes malicious script to /workspace | Medium | Review changes before executing on host |
| Agent modifies .git/hooks | Medium | Git hooks run on HOST when you commit |
| Agent creates symlinks to escape | Low | 9p doesn't follow symlinks outside share |
| Agent exploits QEMU vulnerability | Very Low | Keep QEMU updated, use KVM isolation |
| Agent modifies build scripts | Medium | Review CI/build changes carefully |

### Recommended Usage Patterns

1. **Review agent changes before committing** - Use `git diff` after agent sessions
2. **Use `--fresh` between sessions** - Ensures clean VM state
3. **Keep sensitive files outside /workspace** - Credentials, keys, etc.
4. **Use git branches** - Easy to discard unwanted agent changes
5. **Don't run agent-created scripts blindly** - Review first

---
