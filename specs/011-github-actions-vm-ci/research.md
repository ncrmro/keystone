# Research: GitHub Actions VM CI for Copilot Agent Iteration

**Date**: 2025-11-12
**Status**: Complete

## Research Topics

### 1. Hardware Acceleration in GitHub Actions

**Decision**: Use standard GitHub-hosted Linux runners with KVM support enabled via cachix/install-nix-action

**Rationale**:
- As of January 2024, `/dev/kvm` exists on all GitHub-hosted ubuntu-latest runners
- Standard runners now provide 4 vCPUs and 16 GB RAM (upgraded from 2 vCPU/7GB in 2024)
- Hardware acceleration is enabled automatically by the Determinate Nix Installer and cachix/install-nix-action
- Sufficient for testing NixOS configurations without full encryption/TPM overhead

**Alternatives Considered**:
1. **Larger runners** (up to 64 cores, 256GB RAM): Rejected due to cost. Standard runners provide sufficient resources.
2. **Self-hosted runners**: Rejected due to maintenance overhead. GitHub-hosted runners meet requirements.
3. **Third-party services** (Actuated): Rejected due to additional cost and complexity. Native KVM support is adequate.

**Trade-offs**:
- ✅ Advantages: No additional setup, native GitHub integration, automatic KVM enablement, cost-effective
- ❌ Disadvantages: Limited to 4 vCPU/16GB (acceptable for CI testing), no nested virtualization (not needed)

**References**:
- GitHub Changelog: "Hardware accelerated Android virtualization now available" (April 2, 2024)
- Determinate Systems: "KVM on GitHub Actions" blog
- Community discussion: github.com/orgs/community/discussions/8305

---

### 2. qemu-kvm-action vs nixos-rebuild build-vm

**Decision**: Use `nixos-rebuild build-vm` directly instead of qemu-kvm-action

**Rationale**:
- `nixos-rebuild build-vm` is built into NixOS, requires no external action dependencies
- Existing `bin/build-vm` script demonstrates this approach works successfully
- Direct integration with NixOS flake system
- qemu-kvm-action is a third-party action with limited stars (4) and activity
- NixOS community already has established patterns for VM testing in CI

**Alternatives Considered**:
1. **etchdroid/qemu-kvm-action**: Rejected because it's a generic QEMU wrapper not optimized for NixOS workflows
2. **docker/setup-qemu-action**: Rejected because it's for multi-arch builds, not VM testing
3. **Custom QEMU commands**: Rejected because `nixos-rebuild build-vm` handles all complexity

**Trade-offs**:
- ✅ Advantages: Native NixOS integration, no external dependencies, established patterns, simpler workflow
- ❌ Disadvantages: Less abstraction (need to understand nixos-rebuild), no pre-built screen recording features (not needed)

**References**:
- NixOS Wiki: "NixOS:nixos-rebuild build-vm"
- Blog: "Integration testing with NixOS in Github Actions" by Jon Seager
- Tutorial: "Test Your Apps and Services with GitHub Actions" on nixcademy.com
- Example repo: github.com/tfc/nixos-integration-test-example

---

### 3. GitHub Actions Workflow Queuing and Concurrency

**Decision**: Use `concurrency` keyword with `cancel-in-progress: true`

**Rationale**:
- Native GitHub Actions feature, no external actions needed
- Provides exact behavior specified in requirements: one workflow at a time per branch
- Automatically cancels older pending runs when new trigger arrives
- Configurable using expressions for branch-specific behavior

**Implementation Pattern**:
```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

**Alternatives Considered**:
1. **styfle/cancel-workflow-action**: Rejected because native concurrency feature provides same functionality
2. **Manual queue management**: Rejected due to complexity. Native feature is simpler and more reliable.
3. **Workflow dispatch with external queue**: Rejected due to unnecessary complexity

**Trade-offs**:
- ✅ Advantages: Native feature, declarative configuration, automatic handling, no extra dependencies
- ❌ Disadvantages: Cancels in-progress runs (acceptable per requirements), slightly coarse-grained control

**References**:
- GitHub Docs: "Control the concurrency of workflows and jobs"
- Tutorial: "GitHub Actions — Limit Concurrency and Cancel In-Progress Jobs" (Future Studio)
- Community discussion: github.com/orgs/community/discussions/69704

---

### 4. Structured Output from GitHub Actions

**Decision**: Use GitHub Actions job outputs combined with GITHUB_STEP_SUMMARY for structured JSON

**Rationale**:
- Workflows can set outputs using `echo "result=$JSON_DATA" >> $GITHUB_OUTPUT`
- `GITHUB_STEP_SUMMARY` provides markdown-formatted results visible in UI
- Artifacts can store full JSON output for programmatic access
- Copilot agents can access workflow results via GitHub API

**Implementation Approach**:
1. Generate JSON output in final step using format-results.sh script
2. Store JSON as job output for API access
3. Store JSON as artifact for download
4. Write formatted summary to GITHUB_STEP_SUMMARY for human readability

**Alternatives Considered**:
1. **Comments on commits/PRs**: Rejected because workflow_run events don't always have PR context
2. **GitHub Checks API**: Rejected due to complexity. Outputs and artifacts are simpler.
3. **External storage** (S3, etc.): Rejected due to additional dependencies and configuration

**Trade-offs**:
- ✅ Advantages: Native GitHub integration, dual output (API + artifact), human and machine readable
- ❌ Disadvantages: Requires parsing on consumer side (acceptable), limited to GitHub ecosystem

**Schema Structure**:
```json
{
  "status": "success" | "failure",
  "phase": "build" | "boot" | "runtime" | "services",
  "timestamp": "ISO 8601 string",
  "duration_seconds": 123,
  "error": {
    "message": "Error description",
    "phase": "Which phase failed",
    "logs": "Relevant log excerpt"
  },
  "results": {
    "build": { "success": true, "outputs": [...] },
    "boot": { "success": true, "time_seconds": 45 },
    "services": { "running": ["sshd", "..."], "failed": [] }
  }
}
```

**References**:
- GitHub Docs: "Workflow commands for GitHub Actions" (GITHUB_OUTPUT, GITHUB_STEP_SUMMARY)
- GitHub Docs: "Using artifacts to persist workflow data"
- GitHub API Docs: "Actions" (accessing workflow run results)

---

### 5. Resource Limits and Timeouts

**Decision**: Use standard GitHub-hosted runners with default timeout (6 hours), target 15-minute completion

**Rationale**:
- Standard runners now provide 4 vCPU, 16 GB RAM (upgraded in 2024)
- 14 GB available disk space sufficient for NixOS builds
- Default workflow timeout is 360 minutes (6 hours)
- Target 15 minutes per iteration aligns with requirements and resource availability

**Resource Configuration**:
- **CPU**: 4 vCPUs (standard runner)
- **Memory**: 16 GB RAM (standard runner)
- **Disk**: 14 GB available (GitHub-hosted runner default)
- **Workflow Timeout**: 6 hours default (360 minutes)
- **Job Timeout**: 15 minutes target per test iteration
- **VM Resources**: Configure via `virtualisation.vmVariant.virtualisation.cores` and `memorySize`

**Recommended VM Settings** (in NixOS configuration):
```nix
virtualisation.vmVariant.virtualisation = {
  cores = 2;           # Reserve 2 cores for VM (2 for host)
  memorySize = 4096;   # 4 GB RAM for VM (12 GB for host/build)
  diskSize = 8192;     # 8 GB disk image
};
```

**Alternatives Considered**:
1. **Larger runners** (64 core, 256 GB): Rejected due to cost ($0.128/minute vs $0.008/minute). Standard sufficient.
2. **Single-CPU runners** (ubuntu-slim): Rejected due to 15-minute timeout limit. Too restrictive.
3. **Self-hosted runners**: Rejected due to maintenance overhead. GitHub-hosted meets requirements.

**Trade-offs**:
- ✅ Advantages: Cost-effective, sufficient resources for testing, no maintenance, automatic KVM support
- ❌ Disadvantages: Limited disk space (mitigated by Nix binary cache), fixed resource allocation (acceptable for CI)

**Optimization Strategies**:
1. Use Nix binary caches (cache.nixos.org) to avoid rebuilding dependencies
2. Enable GitHub Actions caching for Nix store
3. Target minimal test configurations (skip full desktop stack when testing server modules)
4. Use `--dry-run` for syntax validation before actual builds

**References**:
- GitHub Changelog: "GitHub-hosted runners: Double the power for open source" (2024)
- GitHub Docs: "GitHub-hosted runners" (specifications)
- InfoQ: "GitHub Announces Upgrade to Action Runners with 4-vCPU, 16 GiB Memory"
- NixOS Wiki: "NixOS:nixos-rebuild build-vm" (VM configuration options)

---

## Summary of Key Decisions

| Component | Technology Choice | Primary Rationale |
|-----------|------------------|-------------------|
| VM Platform | nixos-rebuild build-vm | Native NixOS integration, no external dependencies |
| KVM Enablement | cachix/install-nix-action | Automatic KVM setup on GitHub-hosted runners |
| Workflow Queuing | Native concurrency keyword | Built-in feature, declarative, meets requirements exactly |
| Structured Output | Job outputs + Artifacts | Native GitHub integration, dual access (API + download) |
| Runner Type | Standard GitHub-hosted (4 vCPU/16GB) | Upgraded in 2024, sufficient for testing, cost-effective |
| Timeout Strategy | 6-hour max, 15-minute target | Balances thorough testing with fast iteration |

---

## Implementation Risks and Mitigations

### Risk 1: Build Time Exceeds 15-Minute Target
- **Likelihood**: Medium
- **Impact**: High (breaks Copilot agent iteration requirement)
- **Mitigation**:
  - Use Nix binary caches aggressively
  - Enable GitHub Actions cache for Nix store paths
  - Test with minimal configurations first
  - Provide configuration guidance for CI-optimized builds

### Risk 2: Disk Space Exhaustion
- **Likelihood**: Low
- **Impact**: Medium
- **Mitigation**:
  - 14 GB available on runners
  - Nix store mounted read-only from cache
  - VM disk images limited to 8 GB
  - Garbage collect between workflow runs (automatic on ephemeral runners)

### Risk 3: KVM Not Available on Runner
- **Likelihood**: Very Low
- **Impact**: High (workflow cannot proceed)
- **Mitigation**:
  - Fail fast with clear error message (per FR-002a)
  - Check `/dev/kvm` existence in early workflow step
  - Document hardware acceleration requirement prominently
  - Consider fallback to QEMU software emulation if acceptable (TBD)

### Risk 4: Network Failures During Package Fetch
- **Likelihood**: Low
- **Impact**: Medium
- **Mitigation**:
  - Fail immediately per FR-003a (no retry)
  - Clear error messages identifying unreachable package/repo
  - Use cache.nixos.org (highly available)
  - Consider nixos-cachix for custom packages (if needed)

---

## Open Questions

None. All technical unknowns from plan.md Technical Context have been resolved.

---

## Next Steps

Proceed to Phase 1: Design
1. Generate data-model.md (workflow state, test results, VM configuration entities)
2. Generate contracts/ (workflow YAML schema, JSON output schema)
3. Generate quickstart.md (usage guide for developers and Copilot agents)
4. Update agent context with new technologies (GitHub Actions workflows, nixos-rebuild build-vm)
