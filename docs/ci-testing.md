# CI/CD Testing

This document describes the automated testing workflows for Keystone in GitHub Actions.

## Workflows

### verify-build.yml

**Purpose**: Fast validation of basic build correctness

**Triggers**: All pull requests

**Duration**: ~2-5 minutes

**What it does**:
- Validates flake syntax
- Dry-run builds ISO configuration
- Tests build-iso script
- Tests SSH key string handling

### test-deployment.yml

**Purpose**: Full VM deployment testing

**Triggers**: 
- Manual workflow dispatch
- Pull requests that modify:
  - `bin/test-deployment`
  - `bin/virtual-machine`
  - `bin/build-iso`
  - `modules/**`
  - `vms/test-server/**`
  - `flake.nix`
  - `.github/workflows/test-deployment.yml`

**Duration**: ~15-20 minutes

**What it does**:
1. Sets up KVM/libvirt virtualization environment
2. Configures secure PolicyKit access for libvirt
3. Creates test network (`keystone-net` at 192.168.100.0/24)
4. Generates SSH keys for deployment
5. Builds Keystone installer ISO with SSH keys
6. Creates and starts test VM with TPM 2.0 emulation
7. Deploys NixOS via `nixos-anywhere` to test VM
8. Verifies:
   - Secure Boot enrollment and status
   - ZFS pool and encryption
   - TPM enrollment with recovery key
   - TPM automatic disk unlock
   - ZFS user permissions
   - Terminal development environment (home-manager)
9. Captures logs on failure
10. Cleans up all resources

**Requirements**:
- GitHub Actions Ubuntu runner (ubuntu-latest)
- KVM support (available in GitHub Actions)
- Approximately 20-30 GB disk space
- 30-minute job timeout

## Manual Workflow Trigger

You can manually trigger the deployment test:

1. Go to the "Actions" tab in GitHub
2. Select "Test Deployment" workflow
3. Click "Run workflow"
4. Select the branch to test
5. Click "Run workflow"

## CI Environment Details

### KVM/Libvirt Setup

The workflow configures:
- **KVM** device at `/dev/kvm` (hardware acceleration)
- **libvirt** daemon for VM management
- **PolicyKit** rules for secure non-root access
- **OVMF** firmware for UEFI Secure Boot support
- **Python libvirt bindings** for `bin/virtual-machine` script
- **uv** for Python script dependency management

### Network Configuration

Test VMs use:
- Network: `keystone-net`
- Bridge: `virbr1`
- Subnet: `192.168.100.0/24`
- VM IP: `192.168.100.99` (static DHCP reservation)
- MAC: `52:54:00:12:34:56`

### Storage Configuration

- Default pool: `/var/lib/libvirt/images`
- Test VM disk: 20 GB qcow2
- Permissions: libvirt-qemu:kvm (775)

## Troubleshooting

### Test Failures

If the deployment test fails, the workflow captures:
- VM state (`virsh list --all`)
- VM info (`virsh dominfo`)
- Network status (`virsh net-list --all`)
- Storage pools (`virsh pool-list --all`)
- Recent kernel messages (`dmesg`)

Check the "Capture VM logs on failure" step in the workflow output.

### Common Issues

**Issue**: OVMF firmware not found
- **Solution**: The workflow installs the `ovmf` package, which provides UEFI firmware files
- **Check**: Look at "Checking OVMF firmware paths" output

**Issue**: libvirt permission denied
- **Solution**: The workflow uses PolicyKit to grant access
- **Check**: Verify PolicyKit configuration in "Set up KVM and libvirt" step

**Issue**: Timeout during deployment
- **Solution**: Increase timeout or check if VM is stuck waiting for input
- **Check**: Look for "waiting for SSH" or "waiting for disk unlock" messages

**Issue**: Disk space issues
- **Solution**: GitHub Actions runners have limited space; the ISO alone is several GB
- **Check**: Look at "Check disk space" step output

## Local Testing

To run the same test locally (on a NixOS or Linux system with libvirt):

```bash
# Ensure libvirt is running
sudo systemctl start libvirtd

# Run the test (requires SSH key at ~/.ssh/id_ed25519.pub)
./bin/test-deployment --rebuild-iso --debug
```

See `docs/testing-procedure.md` for complete local testing workflows.

## Security Considerations

The CI workflow:
- Uses **PolicyKit** for libvirt access (no world-writable sockets)
- Runs test commands as the **runner** user with proper group membership
- Uses **isolated test VMs** with no access to production systems
- **Cleans up** all resources after completion
- Only triggers on **specific file changes** to minimize resource usage

## Future Improvements

Potential enhancements:
- [ ] Cache ISO build to speed up reruns
- [ ] Parallel testing of multiple configurations
- [ ] Integration tests with real hardware (self-hosted runners)
- [ ] Performance benchmarking
- [ ] Artifact upload for failed deployments (VM disk images, logs)
