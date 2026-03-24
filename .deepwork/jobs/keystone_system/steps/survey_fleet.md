# Survey Fleet

## Objective

Gather the current state of the keystone fleet: what keystone revision is locked in nixos-config, what's on keystone main, the commit changelog between them, and a preliminary health check of all reachable hosts.

## Task

Build a comprehensive snapshot of the fleet's current state to inform the update plan. This step collects data only — no changes are made.

### Process

1. **Determine the keystone revision gap**
   - Find the config repo. The canonical path is `~/.keystone/repos/nixos-config` (will become `keystone-config`). Also check `$NIXOS_CONFIG_DIR` or `~/nixos-config` as fallbacks.
   - Read `flake.lock` to extract the currently locked keystone revision:
     ```bash
     nix eval --raw <nixos-config-path>#inputs.keystone.rev 2>/dev/null \
       || jq -r '.nodes.keystone.locked.rev' <nixos-config-path>/flake.lock
     ```
   - Get the latest commit on keystone main:
     ```bash
     git -C <keystone-path> rev-parse origin/main
     ```
   - If the revs differ, list all commits in the gap:
     ```bash
     git -C <keystone-path> log --oneline <locked-rev>..origin/main
     ```
   - If the revs match, note "keystone is up to date" and the workflow can be short-circuited

2. **Check nixos-config recent commits**
   - Review the last 20 commits on nixos-config's current branch (usually main):
     ```bash
     git -C <nixos-config-path> log --oneline -20
     ```
   - Note any uncommitted changes in nixos-config: `git -C <nixos-config-path> status`

3. **Check current host health directly**
   - **Do NOT run `ks doctor`** — that command is an AI entrypoint (`/ks.doctor` slash command) and would create a recursive loop
   - Instead, run direct shell health checks:
     ```bash
     systemctl is-system-running           # overall state: running / degraded
     systemctl --failed                    # list any failed units
     journalctl -p err --since '1 hour ago' --no-pager | tail -20
     ```
   - Note any failed units or recent errors — these are pre-existing issues, not caused by pending changes

4. **Gather fleet data via nix eval**
   Use the same nix eval patterns as `ks doctor` (see AGENTS.md "Nix Eval for System Context"):
   - **Hosts table**: `nix eval -f <config-path>/hosts.nix --json`
   - **Agents** (per host):
     ```bash
     nix eval <config-path>#nixosConfigurations.<HOST>.config.keystone.os.agents \
       --json --apply 'a: builtins.mapAttrs (_: v: {
         fullName = v.fullName; host = v.host or null;
         archetype = v.archetype; desktop = v.desktop.enable;
         mail = v.mail.provision; chrome = v.chrome.enable;
       }) a'
     ```
   - **Users** (per host):
     ```bash
     nix eval <config-path>#nixosConfigurations.<HOST>.config.keystone.os.users \
       --json --apply 'u: builtins.mapAttrs (_: v: { fullName = v.fullName or ""; }) u'
     ```
   - **Enabled services** (server hosts):
     ```bash
     nix eval <config-path>#nixosConfigurations.<HOST>.config.keystone.server._enabledServices \
       --json 2>/dev/null
     ```

5. **Check host reachability**
   - From the hosts table, for each host with an `sshTarget`, check reachability:
     ```bash
     ssh -o ConnectTimeout=5 -o BatchMode=yes root@<sshTarget> echo ok 2>/dev/null
     ```
   - Record which hosts are reachable and which are not
   - For reachable hosts, capture their current NixOS generation:
     ```bash
     ssh root@<sshTarget> readlink /nix/var/nix/profiles/system
     ```
   - Skip VMs and test hosts (those with `sshTarget: null` or `baremetal: false` where not cloud)

6. **Cross-reference known issues with GitHub**
   - For any failed units or health problems found in step 3, search GitHub before treating them as new:
     ```bash
     gh issue list --search "<keyword>" --repo ncrmro/keystone
     gh issue list --search "<keyword>" --repo ncrmro/nixos-config
     ```
   - Note the issue URL next to each finding in the health section — do not create duplicates

7. **Check for agenix-secrets changes**
   - If `agenix-secrets/` exists in nixos-config, check if it's clean and up to date:
     ```bash
     git -C <nixos-config-path>/agenix-secrets status --short
     git -C <nixos-config-path>/agenix-secrets log origin/main..HEAD --oneline
     ```

## Output Format

### fleet_survey.md

```markdown
# Fleet Survey

**Date**: [current date/time]
**nixos-config path**: [path]
**keystone path**: [path]

## Keystone Revision Gap

- **Locked in flake.lock**: `[commit hash]` ([date])
- **Latest on main**: `[commit hash]` ([date])
- **Commits behind**: [N]

### Changelog (oldest → newest)

| Hash | Message | Modules Touched |
|------|---------|-----------------|
| `abc1234` | feat(os): add new agent option | modules/os/agents/ |
| `def5678` | fix(terminal): shell prompt color | modules/terminal/ |
| ... | ... | ... |

## nixos-config Status

- **Branch**: [main]
- **Clean**: [yes | no — details]
- **Recent commits**:
  ```
  [last 10 commits one-line]
  ```

## Preliminary Health (Current Host)

- **Hostname**: [hostname]
- **System state**: [running | degraded | maintenance]
- **Failed units**: [list from `systemctl --failed`, or "None"]
- **Recent errors**: [summary from `journalctl -p err`, or "None"]

## Host Reachability

| Host | Role | SSH Target | Reachable | Generation | Notes |
|------|------|------------|-----------|------------|-------|
| ncrmro-workstation | client | ncrmro-workstation.mercury | yes | 142 | current host |
| ocean | server | ocean.mercury | yes | 87 | — |
| mercury | server | 216.128.136.32 | yes | 45 | VPS |
| maia | server | maia.mercury | no | — | offline |
| mox | client | mox.mercury | no | — | offline |

## Agenix Secrets

- **Status**: [clean | dirty — details]
- **Up to date**: [yes | no — commits behind]
```

## Quality Criteria

- The report shows the exact keystone commit currently locked in flake.lock and the latest commit on keystone main, with the full commit log between them
- All hosts in hosts.nix are listed with their reachability status — unreachable hosts are noted, not silently skipped
- Direct host health checks (`systemctl --failed`, `journalctl -p err`) were run on the current host and any issues are documented

## Context

This is the first step of the update workflow. The data collected here drives all subsequent decisions: the plan_update step uses the changelog to classify changes, the execute_fixes step uses pre-existing issues to prioritize work, and the run_update step uses host reachability to determine deployment targets. Accuracy here prevents surprises during deployment.
