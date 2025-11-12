# Data Model: GitHub Actions VM CI

**Date**: 2025-11-12
**Status**: Complete

## Overview

This document defines the data structures and entities for the GitHub Actions VM CI system. These models represent the workflow state, test execution results, VM configuration, and structured output consumed by Copilot agents.

---

## Entity: WorkflowConfiguration

Represents the GitHub Actions workflow configuration for VM testing.

### Fields

| Field | Type | Required | Description | Validation Rules |
|-------|------|----------|-------------|------------------|
| `name` | String | Yes | Workflow display name | Must be unique within repository |
| `trigger` | Object | Yes | Workflow trigger conditions | See TriggerConfig |
| `concurrency` | Object | Yes | Concurrency control settings | See ConcurrencyConfig |
| `jobs` | Map<String, Job> | Yes | Workflow jobs | At least one job required |
| `timeout_minutes` | Integer | No | Maximum workflow runtime | Default: 360, Max: 360 |

### Relationships
- Contains 1+ **Job** entities
- References **TriggerConfig**
- References **ConcurrencyConfig**

### Example
```yaml
name: Copilot VM Test
on: [workflow_dispatch, push]
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
jobs:
  test-vm: {...}
timeout-minutes: 360
```

---

## Entity: TriggerConfig

Defines when the workflow executes.

### Fields

| Field | Type | Required | Description | Validation Rules |
|-------|------|----------|-------------|------------------|
| `workflow_dispatch` | Object | No | Manual trigger settings | Can include input parameters |
| `push` | Object | No | Push event trigger | Can filter by branches/paths |
| `pull_request` | Object | No | PR event trigger | Can filter by branches/paths |

### State Transitions
- Idle → Triggered (when event matches conditions)
- Triggered → Queued (concurrency group check)
- Queued → Running (when concurrency slot available)

### Example
```yaml
on:
  workflow_dispatch:
    inputs:
      config_name:
        description: 'NixOS configuration to test'
        required: true
        type: choice
        options: [terminal, desktop, server]
  push:
    branches: ['**']
    paths: ['modules/**', 'vms/**', 'flake.nix']
```

---

## Entity: ConcurrencyConfig

Controls workflow execution concurrency and queueing behavior.

### Fields

| Field | Type | Required | Description | Validation Rules |
|-------|------|----------|-------------|------------------|
| `group` | String | Yes | Concurrency group identifier | Supports GitHub expressions |
| `cancel_in_progress` | Boolean | Yes | Cancel older runs when new queued | Must be true per FR-008 |

### Validation Rules
- `group` must create unique identifier per branch
- `cancel_in_progress` must be `true` to meet requirement FR-008

### Example
```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

---

## Entity: VMConfiguration

Represents the NixOS VM configuration under test.

### Fields

| Field | Type | Required | Description | Validation Rules |
|-------|------|----------|-------------|------------------|
| `flake_ref` | String | Yes | Flake reference for configuration | Must resolve to valid NixOS config |
| `cores` | Integer | No | Number of vCPUs | Default: 2, Range: 1-4 |
| `memory_mb` | Integer | No | RAM in megabytes | Default: 4096, Range: 1024-12288 |
| `disk_size_mb` | Integer | No | Disk size in megabytes | Default: 8192, Range: 2048-14336 |
| `type` | Enum | Yes | Configuration type | One of: terminal, desktop, server |

### State Transitions
- Unbuilt → Building (nixos-rebuild build-vm started)
- Building → Built (VM script generated successfully)
- Building → Failed (build error)
- Built → Booting (VM startup initiated)
- Booting → Running (SSH/console responsive)
- Booting → Failed (boot timeout or error)

### Example
```nix
{
  virtualisation.vmVariant.virtualisation = {
    cores = 2;
    memorySize = 4096;
    diskSize = 8192;
  };
}
```

---

## Entity: TestExecutionResult

Structured output from a test workflow run, consumed by Copilot agents.

### Fields

| Field | Type | Required | Description | Validation Rules |
|-------|------|----------|-------------|------------------|
| `status` | Enum | Yes | Overall test result | One of: success, failure |
| `phase` | Enum | Yes | Last completed phase | One of: build, boot, runtime, services |
| `timestamp` | String (ISO 8601) | Yes | Test execution time | Valid ISO 8601 datetime |
| `duration_seconds` | Integer | Yes | Total execution duration | Positive integer |
| `workflow_run_id` | String | Yes | GitHub workflow run ID | Numeric string |
| `commit_sha` | String | Yes | Git commit tested | 40-character hex string |
| `error` | ErrorDetail | No | Error details (if failure) | Required when status=failure |
| `results` | TestPhaseResults | Yes | Per-phase results | See TestPhaseResults |

### Validation Rules
- If `status == "failure"`, `error` must be present
- `phase` indicates furthest successful phase before failure
- `timestamp` must be valid ISO 8601 format
- `duration_seconds` must align with GitHub Actions execution time

### Example (Success)
```json
{
  "status": "success",
  "phase": "services",
  "timestamp": "2025-11-12T14:30:45Z",
  "duration_seconds": 420,
  "workflow_run_id": "1234567890",
  "commit_sha": "abc123def456...",
  "error": null,
  "results": {
    "build": {
      "success": true,
      "duration_seconds": 180,
      "outputs": ["result/bin/run-keystone-buildvm-terminal-vm"]
    },
    "boot": {
      "success": true,
      "duration_seconds": 45,
      "boot_time_seconds": 12
    },
    "services": {
      "success": true,
      "running": ["sshd", "systemd-journald"],
      "failed": []
    }
  }
}
```

### Example (Failure)
```json
{
  "status": "failure",
  "phase": "build",
  "timestamp": "2025-11-12T14:35:12Z",
  "duration_seconds": 90,
  "workflow_run_id": "1234567891",
  "commit_sha": "def456abc789...",
  "error": {
    "message": "Package 'nonexistent-pkg' not found in nixpkgs",
    "phase": "build",
    "logs": "error: attribute 'nonexistent-pkg' missing\n  at /nix/store/...-source/flake.nix:45:10"
  },
  "results": {
    "build": {
      "success": false,
      "duration_seconds": 90,
      "outputs": []
    }
  }
}
```

---

## Entity: ErrorDetail

Error information when test execution fails.

### Fields

| Field | Type | Required | Description | Validation Rules |
|-------|------|----------|-------------|------------------|
| `message` | String | Yes | Human-readable error summary | Max 500 chars, concise |
| `phase` | Enum | Yes | Phase where failure occurred | One of: build, boot, runtime, services |
| `logs` | String | Yes | Relevant log excerpt | Max 2000 chars, formatted |

### Validation Rules
- `message` should identify specific failure (package name, service name, etc.)
- `phase` must match the phase where error occurred
- `logs` should include context (2-5 lines before/after error)

---

## Entity: TestPhaseResults

Per-phase test results with detailed information.

### Fields

| Field | Type | Required | Description | Validation Rules |
|-------|------|----------|-------------|------------------|
| `build` | BuildResult | Yes | Build phase result | Always present |
| `boot` | BootResult | No | Boot phase result | Present if build succeeded |
| `services` | ServicesResult | No | Services validation result | Present if boot succeeded |

---

## Entity: BuildResult

Results from the NixOS build phase.

### Fields

| Field | Type | Required | Description | Validation Rules |
|-------|------|----------|-------------|------------------|
| `success` | Boolean | Yes | Build completion status | - |
| `duration_seconds` | Integer | Yes | Build time | Positive integer |
| `outputs` | Array<String> | Yes | Generated output paths | Empty if success=false |

---

## Entity: BootResult

Results from the VM boot phase.

### Fields

| Field | Type | Required | Description | Validation Rules |
|-------|------|----------|-------------|------------------|
| `success` | Boolean | Yes | Boot completion status | - |
| `duration_seconds` | Integer | Yes | Total boot attempt time | Positive integer |
| `boot_time_seconds` | Integer | No | Actual boot time (if success) | Present if success=true |

### Validation Rules
- If `success == false` and `duration_seconds >= 300`, boot timeout occurred
- `boot_time_seconds` measures time from VM start to SSH/console ready

---

## Entity: ServicesResult

Results from service validation phase.

### Fields

| Field | Type | Required | Description | Validation Rules |
|-------|------|----------|-------------|------------------|
| `success` | Boolean | Yes | All services healthy | false if any service failed |
| `running` | Array<String> | Yes | Successfully running services | Service names |
| `failed` | Array<String> | Yes | Failed services | Empty if success=true |

### Validation Rules
- `success` is true only if `failed` is empty
- Service names should match systemd unit names

---

## Data Flow

```
1. GitHub Event (push/workflow_dispatch)
   ↓
2. WorkflowConfiguration processed
   ↓ (concurrency check)
3. ConcurrencyConfig: queue or cancel previous
   ↓ (if slot available)
4. VMConfiguration: Build VM
   ↓ (build-vm execution)
5. VM State Transitions: Unbuilt → Building → Built → Booting → Running
   ↓ (test execution)
6. TestExecutionResult: Collect per-phase results
   ↓ (format output)
7. ErrorDetail (if failure) OR full results (if success)
   ↓ (store output)
8. Job Output + Artifact + Summary
   ↓
9. Copilot Agent Consumption (via GitHub API or artifact download)
```

---

## Storage and Access Patterns

### Workflow Configuration Storage
- **Location**: `.github/workflows/copilot-vm-test.yml`
- **Format**: YAML
- **Access**: GitHub Actions runtime, developers via repository

### Test Execution Results Storage
- **Primary**: GitHub Actions job outputs (programmatic access via API)
- **Secondary**: GitHub Actions artifacts (JSON file download)
- **Tertiary**: GitHub Actions summary (human-readable Markdown)
- **Retention**: 90 days default (GitHub Actions artifacts retention policy)

### Access Patterns
1. **Copilot Agent**: GitHub API → Workflow runs → Job outputs
2. **Human Developer**: GitHub UI → Workflow run → Summary tab
3. **Programmatic Analysis**: GitHub API → Artifacts → Download JSON
4. **Debugging**: GitHub UI → Workflow run → Logs

---

## Validation and Constraints

### Cross-Entity Constraints

1. **Workflow-VM Consistency**:
   - `WorkflowConfiguration.jobs.test-vm.flake_ref` must match `VMConfiguration.flake_ref`
   - Total VM resources (cores + memory) must not exceed runner limits (4 vCPU, 16 GB)

2. **Result-Phase Consistency**:
   - If `TestExecutionResult.phase == "build"`, only `BuildResult` is present
   - If `TestExecutionResult.phase == "boot"`, both `BuildResult` and `BootResult` are present
   - If `TestExecutionResult.phase == "services"`, all three phase results are present

3. **Error-Status Consistency**:
   - `TestExecutionResult.status == "failure"` requires `TestExecutionResult.error` to be present
   - `TestExecutionResult.error.phase` must be ≤ `TestExecutionResult.phase` (failure stops progress)

4. **Timeout Constraints**:
   - `WorkflowConfiguration.timeout_minutes` ≤ 360 (GitHub Actions limit)
   - `BootResult.duration_seconds` ≤ 300 (5-minute boot timeout per FR-004a)
   - `TestExecutionResult.duration_seconds` ≤ 900 (target 15 minutes per SC-001)

---

## JSON Schema References

See `contracts/test-result-schema.json` for formal JSON Schema definition of `TestExecutionResult` and related entities.

See `contracts/workflow-schema.yml` for GitHub Actions workflow YAML schema.

See `contracts/vm-config-schema.json` for NixOS VM configuration schema.
