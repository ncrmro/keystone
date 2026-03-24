# Validate

## Objective

Run `ks doctor` on the current host and check all affected hosts in the fleet to verify the system is nominal after deployment.

## Task

Verify that the deployed changes are working correctly across all hosts. This step can also be run standalone via the `doctor` workflow to check fleet health at any time.

### Process

1. **Check current host health directly**
   - **Do NOT run `ks doctor`** — it is an AI entrypoint (`/ks.doctor` slash command), not a shell diagnostic tool
   - Run direct health checks instead:
     ```bash
     systemctl is-system-running           # overall state
     systemctl --failed                    # list failed units
     journalctl -p err --since '1 hour ago' --no-pager | tail -30
     ```
   - For service-specific checks related to the deployed changes, run `systemctl status <service>` directly
   - Pay special attention to services related to the changes that were deployed

2. **Check the validation criteria from the plan**
   - If this step is running as part of the `develop` workflow, read the plan.md from the plan step
   - Verify each validation criterion defined in the plan is satisfied
   - Run the specific commands listed in the plan's "Validation Criteria" section

3. **Check agent health**
   - List all configured agents via nix eval (see AGENTS.md "Nix Eval for System Context"):
     ```bash
     nix eval ~/.keystone/repos/nixos-config#nixosConfigurations.<HOST>.config.keystone.os.agents \
       --json --apply 'a: builtins.mapAttrs (_: v: { fullName = v.fullName; host = v.host or null; archetype = v.archetype; desktop = v.desktop.enable; mail = v.mail.provision; chrome = v.chrome.enable; }) a'
     ```
   - For each agent on the current host, check:
     - `agentctl <agent> status` — are core services running?
     - `agentctl <agent> tasks` — are tasks processing or stuck?
     - `agentctl <agent> email` — is mail flowing?
   - For agents on remote hosts, SSH in and run equivalent checks
   - Note: `tailscale status` shows per-agent Tailscale nodes — offline agents should be flagged

4. **Determine fleet impact**
   - Read the hosts table: `ks agent` can show the fleet, or evaluate `hosts.nix` directly
   - Determine which other hosts are affected by the changes:
     - Server module changes affect the server host
     - Agent module changes affect hosts running agents
     - Terminal/desktop changes affect all workstations
     - Domain/services changes may affect all hosts
   - If no other hosts are affected, document why and skip multi-host checks

4. **Check other affected hosts**
   - For each affected remote host:
     - SSH in and check service status: `ssh root@<host> systemctl --failed`
     - Check for any deployment-related issues: `ssh root@<host> journalctl -p err --since '1 hour ago'`
     - If the remote host needs updating too, inform the human
   - Ask structured questions to confirm if the human wants to update remote hosts now

6. **Evaluate results**
   - If all checks pass: complete the workflow
   - If issues found on current host: document them. If they are caused by the recent changes, call `go_to_step` with `step_id: "plan"` to create a fix (this requires a new worktree since we already merged)
   - If remote hosts need attention: document what needs to happen

**Maximum loop iterations**: If this is the 2nd validation failure, stop looping and present all findings to the human for manual resolution.

## Output Format

### validation_report.md

```markdown
# Validation Report

## Current Host
- **Hostname**: [hostname]
- **System state**: [running | degraded | maintenance]
- **Failed units**: [from `systemctl --failed`, or "None"]
- **Recent errors**: [from `journalctl -p err`, or "None"]

## Plan Validation Criteria

| Criterion | Status | Evidence |
|-----------|--------|----------|
| [criterion from plan] | PASS/FAIL | [command output or observation] |
| [criterion from plan] | PASS/FAIL | [command output or observation] |

## Agent Health

| Agent | Host | Services | Tasks | Mail | Tailscale |
|-------|------|----------|-------|------|-----------|
| [agent-name] | [host] | [running/failed] | [X pending] | [ok/down] | [online/offline] |

## Fleet Impact Assessment
- **Changes affect**: [list of affected hosts, or "current host only"]
- **Hosts checked**: [list]
- **Hosts needing update**: [list, or "none"]

## Remote Host Status

### [hostname] (if applicable)
- **Status**: [nominal | issues found | needs update]
- **Details**: [findings]

## Overall Status
- **System nominal**: [yes | no — details]
- **All validation criteria met**: [yes | no — which failed]
- **Action needed**: [none | list of follow-up actions]
```

## Quality Criteria

- Direct health checks on the current host (`systemctl --failed`, `journalctl -p err`) show no critical issues
- All hosts affected by the changes have been checked or confirmed not impacted
- The specific validation criteria from the plan are confirmed working on the live system

## Context

This is the final quality gate in the develop workflow. It ensures that changes don't just build — they actually work on a live system. The multi-host check is critical because keystone manages a fleet of interconnected hosts, and a change that works on the workstation might break a server service or agent provisioning. This step can also be invoked standalone via the `doctor` workflow for routine fleet health checks.
