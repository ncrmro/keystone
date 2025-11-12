# Quick Start: GitHub Actions VM CI

**Date**: 2025-11-12
**Status**: Complete

## Overview

This guide shows how to use the GitHub Actions VM CI system for testing NixOS configurations, both manually and as a GitHub Copilot agent.

---

## For Human Developers

### Prerequisites

- Repository with `.github/workflows/copilot-vm-test.yml` deployed
- GitHub Actions enabled on the repository
- Valid NixOS configuration in flake.nix

### Manual Workflow Trigger

1. Navigate to the repository on GitHub
2. Click **Actions** tab
3. Select **Copilot VM Test** workflow
4. Click **Run workflow** dropdown
5. Select parameters:
   - **Branch**: Choose branch to test
   - **Config name**: `terminal`, `desktop`, or `server`
   - **Flake attr**: (optional) Override default flake attribute
   - **Debug**: (optional) Enable verbose logging
6. Click **Run workflow**

### View Results

#### Web UI (Human-Readable)
1. Click on the workflow run
2. Navigate to **Summary** tab
3. View formatted test results with status, duration, and phase details

#### Programmatic Access (JSON)
1. Click on the workflow run
2. Scroll to **Artifacts** section
3. Download `test-results-{run_id}` artifact
4. Extract and read `test-result.json`

### Automatic Workflow Trigger

The workflow automatically runs when you push commits that modify:
- `modules/**`
- `vms/**`
- `home-manager/**`
- `flake.nix`
- `flake.lock`

**Concurrency**: Only one workflow runs per branch at a time. New pushes cancel pending workflows.

---

## For GitHub Copilot Agents

### Triggering a Test

Use the GitHub API to trigger the workflow:

```bash
curl -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  "https://api.github.com/repos/ncrmro/keystone/actions/workflows/copilot-vm-test.yml/dispatches" \
  -d '{
    "ref": "011-github-actions-vm-ci",
    "inputs": {
      "config_name": "terminal",
      "debug": "false"
    }
  }'
```

### Polling for Results

1. **Get latest workflow run for branch**:
```bash
curl -H "Accept: application/vnd.github+json" \
     -H "Authorization: Bearer $GITHUB_TOKEN" \
     "https://api.github.com/repos/ncrmro/keystone/actions/runs?branch=011-github-actions-vm-ci&workflow_id=copilot-vm-test.yml" \
  | jq '.workflow_runs[0]'
```

2. **Check run status**:
```bash
RUN_ID="1234567890"
curl -H "Accept: application/vnd.github+json" \
     -H "Authorization: Bearer $GITHUB_TOKEN" \
     "https://api.github.com/repos/ncrmro/keystone/actions/runs/$RUN_ID" \
  | jq '.status, .conclusion'
```

Status values: `queued`, `in_progress`, `completed`
Conclusion values (when completed): `success`, `failure`, `cancelled`

3. **Retrieve structured results**:

**Option A: Job Outputs (Recommended)**
```bash
RUN_ID="1234567890"
curl -H "Accept: application/vnd.github+json" \
     -H "Authorization: Bearer $GITHUB_TOKEN" \
     "https://api.github.com/repos/ncrmro/keystone/actions/runs/$RUN_ID/jobs" \
  | jq '.jobs[0].outputs'
```

Returns:
```json
{
  "test_result": "{\"status\":\"success\",\"phase\":\"services\", ...}",
  "status": "success",
  "phase": "services"
}
```

**Option B: Download Artifact**
```bash
RUN_ID="1234567890"

# List artifacts
curl -H "Accept: application/vnd.github+json" \
     -H "Authorization: Bearer $GITHUB_TOKEN" \
     "https://api.github.com/repos/ncrmro/keystone/actions/runs/$RUN_ID/artifacts" \
  | jq '.artifacts[0].archive_download_url'

# Download artifact (URL from above)
curl -L -H "Authorization: Bearer $GITHUB_TOKEN" \
     "$ARTIFACT_URL" -o test-results.zip

unzip test-results.zip
cat test-result.json
```

### Interpreting Results

#### Success Example
```json
{
  "status": "success",
  "phase": "services",
  "timestamp": "2025-11-12T14:30:45Z",
  "duration_seconds": 420,
  "workflow_run_id": "1234567890",
  "commit_sha": "abc123...",
  "error": null,
  "results": {
    "build": {"success": true, "duration_seconds": 180, "outputs": [...]},
    "boot": {"success": true, "duration_seconds": 45, "boot_time_seconds": 12},
    "services": {"success": true, "running": ["sshd"], "failed": []}
  }
}
```

**Interpretation**: Configuration is valid and ready. All phases passed.

#### Build Failure Example
```json
{
  "status": "failure",
  "phase": "build",
  "timestamp": "2025-11-12T14:35:12Z",
  "duration_seconds": 90,
  "workflow_run_id": "1234567891",
  "commit_sha": "def456...",
  "error": {
    "message": "Package 'nonexistent-pkg' not found in nixpkgs",
    "phase": "build",
    "logs": "error: attribute 'nonexistent-pkg' missing\n  at /nix/store/...-source/flake.nix:45:10"
  },
  "results": {
    "build": {"success": false, "duration_seconds": 90, "outputs": []}
  }
}
```

**Interpretation**: Configuration has syntax/dependency error. Check `error.message` and `error.logs` for details.

#### Boot Failure Example
```json
{
  "status": "failure",
  "phase": "boot",
  "timestamp": "2025-11-12T14:40:22Z",
  "duration_seconds": 300,
  "error": {
    "message": "VM failed to boot within 5-minute timeout",
    "phase": "boot",
    "logs": "[    12.345] systemd[1]: service-name.service: Start request repeated too quickly"
  },
  "results": {
    "build": {"success": true, "duration_seconds": 180, "outputs": [...]},
    "boot": {"success": false, "duration_seconds": 300}
  }
}
```

**Interpretation**: Build succeeded but VM hangs during boot. Check `error.logs` for systemd service failures.

### Agent Decision Flow

```
1. Propose configuration change → Commit to branch
2. Trigger workflow via API
3. Poll for completion (check every 30 seconds)
4. Retrieve results JSON
5. Parse results:
   - If status="success" and phase="services" → Configuration is valid, proceed
   - If status="failure" and phase="build" → Fix dependency/syntax error
   - If status="failure" and phase="boot" → Fix service configuration
   - If status="failure" and phase="services" → Fix failed services
6. Refine configuration based on error details
7. Go to step 1 (iterate)
```

### Rate Limiting

- GitHub API rate limit: 5,000 requests/hour (authenticated)
- Workflow concurrency: 1 per branch (additional triggers cancel pending)
- Polling recommendation: Every 30 seconds while workflow is running

---

## Testing Different Configurations

### Terminal Development Environment
```bash
# Trigger
curl ... -d '{"ref": "main", "inputs": {"config_name": "terminal"}}'

# Tests:
# - Terminal-dev-environment module
# - Helix, Zsh, Zellij, Ghostty packages
# - Git configuration
# - SSH access
```

### Hyprland Desktop
```bash
# Trigger
curl ... -d '{"ref": "main", "inputs": {"config_name": "desktop"}}'

# Tests:
# - Hyprland compositor
# - Waybar, Mako, Hyprlock
# - PipeWire audio
# - greetd login manager
# - NetworkManager
```

### Server Configuration
```bash
# Trigger
curl ... -d '{"ref": "main", "inputs": {"config_name": "server"}}'

# Tests:
# - Server modules (VPN, DNS, etc.)
# - SystemD service activation
# - Network connectivity
```

---

## Troubleshooting

### Workflow Never Starts
- **Check**: Branch name is correct in API call
- **Check**: Workflow file exists at `.github/workflows/copilot-vm-test.yml`
- **Check**: GitHub Actions is enabled for the repository

### Workflow Stuck in Queue
- **Cause**: Another workflow is running on the same branch
- **Solution**: Wait for current workflow to complete, or cancel it manually

### Build Takes >15 Minutes
- **Cause**: Large dependency set or cache miss
- **Solution**: First build may be slow. Subsequent builds use cache and complete faster.
- **Check**: Is the configuration unnecessarily large for CI testing?

### KVM Not Available Error
- **Cause**: GitHub runner doesn't support hardware acceleration
- **Solution**: This is rare. Check GitHub Actions status page. May need to retry on different runner.

### Boot Timeout (5 Minutes)
- **Cause**: Service failing to start, causing boot hang
- **Solution**: Check `error.logs` for systemd service failures. Fix failing service or remove from CI test.

### Network Error During Build
- **Cause**: Package repository unreachable (per FR-003a: fail immediately)
- **Solution**: Workflow fails immediately with clear error. Retry if transient network issue suspected.

---

## Example: Iterative Development with Copilot

```bash
# 1. Make configuration change
git checkout -b feature/new-module
# ... edit flake.nix ...
git commit -m "Add new module"
git push origin feature/new-module

# 2. Trigger test
curl -X POST ... -d '{"ref": "feature/new-module", "inputs": {"config_name": "terminal"}}'
# Response: {"id": 123456}

# 3. Wait for workflow
sleep 60

# 4. Check status
curl ... /actions/runs?branch=feature/new-module | jq '.workflow_runs[0].status'
# "in_progress"

# 5. Wait more
sleep 120

# 6. Check again
curl ... /actions/runs?branch=feature/new-module | jq '.workflow_runs[0] | {status, conclusion}'
# {"status": "completed", "conclusion": "failure"}

# 7. Get results
RUN_ID=$(curl ... /actions/runs?branch=feature/new-module | jq -r '.workflow_runs[0].id')
curl ... /actions/runs/$RUN_ID/jobs | jq '.jobs[0].outputs.test_result' | jq '.error'
# {
#   "message": "Package 'missing-pkg' not found",
#   "phase": "build",
#   "logs": "error: attribute 'missing-pkg' missing..."
# }

# 8. Fix error
# ... edit flake.nix to fix package name ...
git commit -m "Fix package name"
git push origin feature/new-module

# 9. Repeat from step 2
# (Previous workflow run automatically cancelled due to concurrency settings)
```

---

## Schema Validation

Validate test results against the JSON schema:

```bash
# Install ajv-cli
npm install -g ajv-cli

# Validate result
ajv validate \
  -s specs/011-github-actions-vm-ci/contracts/test-result-schema.json \
  -d test-result.json
```

Expected output: `test-result.json valid`

---

## Further Reading

- **Spec**: `specs/011-github-actions-vm-ci/spec.md` - Full requirements
- **Data Model**: `specs/011-github-actions-vm-ci/data-model.md` - Entity definitions
- **Contracts**: `specs/011-github-actions-vm-ci/contracts/` - JSON schemas and workflow structure
- **GitHub Actions Docs**: https://docs.github.com/en/actions
- **GitHub API Docs**: https://docs.github.com/en/rest/actions
