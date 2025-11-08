# GPU Passthrough Guide

This guide covers GPU passthrough configurations for Keystone, enabling high-performance graphics for virtual machines. GPU passthrough allows a VM to directly access a physical GPU at near-native performance, essential for gaming, GPU computing, or graphics workstation VMs.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Approach 1: Dual GPU Passthrough](#approach-1-dual-gpu-passthrough)
- [Approach 2: Single GPU Passthrough with Dynamic Binding](#approach-2-single-gpu-passthrough-with-dynamic-binding)
- [Booting Directly into a VM from greetd](#booting-directly-into-a-vm-from-greetd)
- [Potential Issues and Warnings](#potential-issues-and-warnings)
- [Troubleshooting](#troubleshooting)
- [References](#references)

## Overview

GPU passthrough uses VFIO (Virtual Function I/O) to assign a physical PCI device directly to a virtual machine. There are two main approaches:

1. **Dual GPU Passthrough**: Dedicate one GPU to the host and pass through a second GPU to the VM (recommended for beginners)
2. **Single GPU Passthrough**: Dynamically unbind the GPU from the host and bind it to the VM when needed (advanced, more complex)

### When to Use GPU Passthrough

- Running Windows games on a Linux host with near-native performance
- GPU-accelerated workloads in VMs (machine learning, video editing, 3D rendering)
- Testing graphics drivers or GPU-dependent software
- Creating a dedicated gaming VM that boots from greetd

## Prerequisites

### Hardware Requirements

1. **CPU with IOMMU support**:
   - Intel: VT-d (most Core i3/i5/i7/i9 from 2008+)
   - AMD: AMD-Vi (most Ryzen and newer FX processors)

2. **Motherboard with IOMMU support**:
   - Check BIOS/UEFI for "VT-d" (Intel) or "AMD-Vi" (AMD) option
   - Some boards require "IOMMU" or "Virtualization" to be enabled

3. **GPU considerations**:
   - **Dual GPU setup**: Integrated GPU (iGPU) + Dedicated GPU (dGPU), or two dGPUs
   - **Single GPU setup**: One dGPU (requires stopping the display manager)
   - NVIDIA GPUs may require additional ROM configuration
   - AMD GPUs generally work better for passthrough

### Software Requirements

Ensure your NixOS configuration includes:

```nix
{
  # Enable virtualization
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      ovmf = {
        enable = true;
        packages = [ pkgs.OVMFFull.fd ];
      };
      swtpm.enable = true;
    };
  };

  # Add user to libvirtd group
  users.users.<youruser>.extraGroups = [ "libvirtd" ];

  # Enable IOMMU
  boot.kernelParams = [
    # Intel CPU
    "intel_iommu=on"
    # OR for AMD CPU
    # "amd_iommu=on"
  ];

  # Load VFIO modules early
  boot.initrd.kernelModules = [
    "vfio_pci"
    "vfio"
    "vfio_iommu_type1"
  ];
}
```

### Verify IOMMU is Enabled

After rebuilding and rebooting:

```bash
# Check if IOMMU is enabled
dmesg | grep -i iommu

# Expected output (Intel):
# [    0.000000] DMAR: IOMMU enabled

# Expected output (AMD):
# [    0.000000] AMD-Vi: IOMMU enabled
```

### Find Your GPU's PCI IDs

Identify your GPU's vendor and device IDs:

```bash
# List all PCI devices
lspci -nn | grep -i vga

# Example output:
# 01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP104 [GeForce GTX 1070] [10de:1b81] (rev a1)
#                                                                                         ^^^^^ ^^^^
#                                                                                         vendor device

# For audio device (usually paired with GPU):
lspci -nn | grep -i audio

# Example output:
# 01:00.1 Audio device [0403]: NVIDIA Corporation GP104 High Definition Audio Controller [10de:10f0] (rev a1)
```

In the example above:
- GPU vendor:device = `10de:1b81`
- Audio vendor:device = `10de:10f0`

## Approach 1: Dual GPU Passthrough

This is the **recommended approach** for most users. It requires two GPUs (or iGPU + dGPU).

### Architecture

```
┌─────────────────────────────────────────┐
│ Host (NixOS + Hyprland)                 │
│                                         │
│ ┌─────────────────┐                    │
│ │ Integrated GPU  │ ← Host display     │
│ │ (Intel/AMD)     │                    │
│ └─────────────────┘                    │
│                                         │
│ ┌─────────────────────────────────────┐ │
│ │ VM (Windows/Linux)                  │ │
│ │                                     │ │
│ │ ┌─────────────────┐                │ │
│ │ │ Dedicated GPU   │ ← VM display   │ │
│ │ │ (NVIDIA/AMD)    │                │ │
│ │ └─────────────────┘                │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

### Configuration

```nix
# configuration.nix
{ config, pkgs, ... }:

{
  # Enable IOMMU
  boot.kernelParams = [ "intel_iommu=on" ];  # or "amd_iommu=on"

  # Bind GPU to VFIO at boot (prevents host from using it)
  boot.kernelParams = [
    "vfio-pci.ids=10de:1b81,10de:10f0"  # Replace with your GPU's IDs
  ];

  boot.initrd.kernelModules = [
    "vfio_pci"
    "vfio"
    "vfio_iommu_type1"
  ];

  # Blacklist GPU drivers to prevent host from loading them
  boot.blacklistedKernelModules = [ "nouveau" "nvidia" ];  # For NVIDIA
  # boot.blacklistedKernelModules = [ "amdgpu" "radeon" ]; # For AMD

  # Enable libvirt
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      ovmf.enable = true;
      swtpm.enable = true;
    };
  };

  users.users.<youruser>.extraGroups = [ "libvirtd" ];

  # Ensure host uses integrated GPU
  # This may require BIOS settings to prioritize iGPU
}
```

### Verify GPU is Bound to VFIO

```bash
# Rebuild and reboot
sudo nixos-rebuild switch
sudo reboot

# After reboot, verify GPU is using vfio-pci driver
lspci -nnk -d 10de:1b81  # Replace with your GPU ID

# Expected output:
# 01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP104 [10de:1b81]
#         Kernel driver in use: vfio-pci
#         Kernel modules: nouveau
```

### Create VM with GPU Passthrough

Use virt-manager or virsh to create a VM, then attach the GPU:

```bash
# Get GPU PCI address
virsh nodedev-list --cap pci | grep -i vga

# Example output: pci_0000_01_00_0

# Get device details
virsh nodedev-dumpxml pci_0000_01_00_0

# Edit VM configuration
virsh edit <vm-name>
```

Add to VM XML configuration:

```xml
<domain type='kvm'>
  <!-- ... existing configuration ... -->

  <features>
    <acpi/>
    <apic/>
    <!-- Required for GPU passthrough -->
    <hyperv mode='custom'>
      <relaxed state='on'/>
      <vapic state='on'/>
      <spinlocks state='on' retries='8191'/>
      <vendor_id state='on' value='1234567890ab'/>
    </hyperv>
    <kvm>
      <hidden state='on'/>
    </kvm>
  </features>

  <cpu mode='host-passthrough' check='none'>
    <topology sockets='1' cores='4' threads='2'/>
  </cpu>

  <devices>
    <!-- GPU -->
    <hostdev mode='subsystem' type='pci' managed='yes'>
      <source>
        <address domain='0x0000' bus='0x01' slot='0x00' function='0x0'/>
      </source>
    </hostdev>

    <!-- GPU Audio (if present) -->
    <hostdev mode='subsystem' type='pci' managed='yes'>
      <source>
        <address domain='0x0000' bus='0x01' slot='0x00' function='0x1'/>
      </source>
    </hostdev>
  </devices>
</domain>
```

### Advantages

- Simpler to configure and maintain
- More stable (no dynamic driver loading/unloading)
- Host display remains functional at all times
- No display manager crashes or conflicts

### Disadvantages

- Requires two GPUs or iGPU + dGPU
- More expensive hardware requirement
- One GPU is dedicated to the VM (can't use both simultaneously on host)

## Approach 2: Single GPU Passthrough with Dynamic Binding

This approach dynamically unbinds the GPU from the host when the VM starts and rebinds it when the VM stops.

### Architecture

```
┌─────────────────────────────────────────┐
│ Host State: Desktop Running             │
│ ┌─────────────────┐                    │
│ │ GPU (host)      │ ← Hyprland running │
│ └─────────────────┘                    │
└─────────────────────────────────────────┘
              ↓ VM Start Hooks
┌─────────────────────────────────────────┐
│ Host State: TTY/Console Only            │
│ ┌─────────────────────────────────────┐ │
│ │ VM Running                          │ │
│ │ ┌─────────────────┐                │ │
│ │ │ GPU (passthru)  │ ← VM controls  │ │
│ │ └─────────────────┘                │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
              ↓ VM Stop Hooks
┌─────────────────────────────────────────┐
│ Host State: Desktop Running             │
│ ┌─────────────────┐                    │
│ │ GPU (host)      │ ← Hyprland running │
│ └─────────────────┘                    │
└─────────────────────────────────────────┘
```

### Warning: Complexity and Risks

⚠️ **This approach is significantly more complex and error-prone**. Potential issues include:

- Display manager may fail to restart after VM shutdown
- System may hang or require hard reboot if unbinding fails
- Some GPU drivers (especially NVIDIA) don't handle dynamic unbinding well
- Race conditions between display manager shutdown and GPU unbinding
- Increased system instability

**Only attempt this if**:
- You have only one GPU
- You're comfortable with system recovery from TTY/SSH
- You understand the risks and can troubleshoot kernel module issues

### Configuration

#### Step 1: Enable VFIO but Don't Bind at Boot

```nix
# configuration.nix
{ config, pkgs, ... }:

{
  boot.kernelParams = [ "intel_iommu=on" ];  # or "amd_iommu=on"

  boot.initrd.kernelModules = [
    "vfio_pci"
    "vfio"
    "vfio_iommu_type1"
  ];

  # DO NOT add vfio-pci.ids here (we'll bind dynamically via hooks)

  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      ovmf.enable = true;
    };
  };

  users.users.<youruser>.extraGroups = [ "libvirtd" ];
}
```

#### Step 2: Create Libvirt Hooks

Libvirt hooks run scripts at specific VM lifecycle events. Create hook scripts to unbind/rebind the GPU.

```nix
# configuration.nix
{ config, pkgs, ... }:

let
  # GPU PCI IDs (find with lspci -nn)
  gpuIds = "10de:1b81 10de:10f0";  # Replace with your IDs

  # Hook script to unbind GPU and stop display manager
  vmPrepareBegin = pkgs.writeShellScript "vm-prepare-begin" ''
    set -x

    # Stop display manager (kills Hyprland/greetd)
    systemctl stop display-manager.service

    # Wait for display manager to fully stop
    sleep 2

    # Unbind VT consoles
    echo 0 > /sys/class/vtconsole/vtcon0/bind
    echo 0 > /sys/class/vtconsole/vtcon1/bind

    # Unbind EFI framebuffer
    echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/unbind || true

    # Unload GPU drivers
    modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia || true  # NVIDIA
    # modprobe -r amdgpu || true  # AMD

    # Load VFIO modules
    modprobe vfio
    modprobe vfio_pci
    modprobe vfio_iommu_type1

    # Bind GPU to VFIO
    # Find GPU PCI address first
    GPU_PCI=$(lspci -D | grep -i vga | grep -i nvidia | awk '{print $1}')
    AUDIO_PCI=$(lspci -D | grep -i audio | grep -i nvidia | awk '{print $1}')

    if [ -n "$GPU_PCI" ]; then
      virsh nodedev-detach pci_$(echo $GPU_PCI | tr ':.' '_')
    fi

    if [ -n "$AUDIO_PCI" ]; then
      virsh nodedev-detach pci_$(echo $AUDIO_PCI | tr ':.' '_')
    fi
  '';

  # Hook script to rebind GPU and start display manager
  vmReleaseEnd = pkgs.writeShellScript "vm-release-end" ''
    set -x

    # Reattach GPU
    GPU_PCI=$(lspci -D | grep -i vga | grep -i nvidia | awk '{print $1}')
    AUDIO_PCI=$(lspci -D | grep -i audio | grep -i nvidia | awk '{print $1}')

    if [ -n "$GPU_PCI" ]; then
      virsh nodedev-reattach pci_$(echo $GPU_PCI | tr ':.' '_')
    fi

    if [ -n "$AUDIO_PCI" ]; then
      virsh nodedev-reattach pci_$(echo $AUDIO_PCI | tr ':.' '_')
    fi

    # Unload VFIO
    modprobe -r vfio_pci
    modprobe -r vfio_iommu_type1
    modprobe -r vfio

    # Reload GPU driver
    modprobe nvidia_drm
    modprobe nvidia_modeset
    modprobe nvidia_uvm
    modprobe nvidia
    # modprobe amdgpu  # AMD

    # Rebind VT consoles
    echo 1 > /sys/class/vtconsole/vtcon0/bind
    echo 1 > /sys/class/vtconsole/vtcon1/bind

    # Rebind EFI framebuffer
    echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/bind || true

    # Restart display manager
    systemctl start display-manager.service
  '';

in {
  # ... previous configuration ...

  # Install hooks
  systemd.tmpfiles.rules = [
    "d /var/lib/libvirt/hooks 0755 root root -"
    "d /var/lib/libvirt/hooks/qemu.d 0755 root root -"
  ];

  # You'll need to manually create symlinks for specific VMs:
  # mkdir -p /var/lib/libvirt/hooks/qemu.d/<VM-NAME>/prepare/begin
  # mkdir -p /var/lib/libvirt/hooks/qemu.d/<VM-NAME>/release/end
  # ln -s ${vmPrepareBegin} /var/lib/libvirt/hooks/qemu.d/<VM-NAME>/prepare/begin/start.sh
  # ln -s ${vmReleaseEnd} /var/lib/libvirt/hooks/qemu.d/<VM-NAME>/release/end/stop.sh
}
```

#### Step 3: Set Up Hooks for Your VM

After rebuilding:

```bash
# Replace <VM-NAME> with your actual VM name
VM_NAME="gaming-vm"

# Create hook directories
sudo mkdir -p /var/lib/libvirt/hooks/qemu.d/$VM_NAME/prepare/begin
sudo mkdir -p /var/lib/libvirt/hooks/qemu.d/$VM_NAME/release/end

# Find the hook scripts in the Nix store
# They'll be in /nix/store/...-vm-prepare-begin and /nix/store/...-vm-release-end
# You can find them by rebuilding and checking the symlinks

# Create symlinks (paths may vary)
sudo ln -s /nix/store/...-vm-prepare-begin \
  /var/lib/libvirt/hooks/qemu.d/$VM_NAME/prepare/begin/start.sh

sudo ln -s /nix/store/...-vm-release-end \
  /var/lib/libvirt/hooks/qemu.d/$VM_NAME/release/end/stop.sh

# Make executable
sudo chmod +x /var/lib/libvirt/hooks/qemu.d/$VM_NAME/prepare/begin/start.sh
sudo chmod +x /var/lib/libvirt/hooks/qemu.d/$VM_NAME/release/end/stop.sh
```

#### Step 4: Test the Hooks

```bash
# Start the VM
virsh start <VM-NAME>

# Check if display manager stopped
systemctl status display-manager

# Check if GPU is bound to VFIO
lspci -nnk -d 10de:1b81  # Replace with your GPU ID

# Stop the VM
virsh shutdown <VM-NAME>

# Check if display manager restarted
systemctl status display-manager

# Check if GPU driver reloaded
lspci -nnk -d 10de:1b81
```

### Advantages

- Works with a single GPU
- More cost-effective (no second GPU required)
- Can switch between host and VM use

### Disadvantages

- Complex setup with multiple failure points
- Display manager must stop/start (brief black screen)
- Risk of system instability
- GPU drivers may not unbind cleanly
- Requires manual recovery if hooks fail
- NVIDIA GPUs particularly problematic

## Booting Directly into a VM from greetd

For a dedicated gaming or workstation VM, you can configure greetd to automatically launch the VM instead of a desktop session.

### Use Case

This is ideal for:
- Dedicated gaming machine that boots into Windows VM
- Workstation that needs to switch between host Linux and guest Windows
- Single-GPU passthrough with automatic startup

### Configuration

```nix
# configuration.nix
{ config, pkgs, lib, ... }:

let
  # Script to start VM via virsh
  startVM = pkgs.writeShellScript "start-vm" ''
    #!/usr/bin/env bash

    VM_NAME="gaming-vm"

    # Start the VM
    virsh start "$VM_NAME"

    # Attach to VM console (optional)
    # This keeps the session alive and allows Ctrl+] to exit
    virsh console "$VM_NAME"

    # When console exits, shut down VM gracefully
    virsh shutdown "$VM_NAME"

    # Wait for shutdown
    while virsh list --name | grep -q "$VM_NAME"; do
      sleep 1
    done

    # Reboot host to return to greetd menu
    # Comment this out if you want to return to greetd instead
    # systemctl reboot
  '';

in {
  # Disable the default Hyprland session
  keystone.client.desktop.greetd.enable = lib.mkForce false;

  # Configure greetd manually
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        # Option 1: Automatically boot into VM
        command = "${startVM}";

        # Option 2: Show menu with VM option
        # command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd ${startVM}";
      };

      # Optional: Add a user-specific session for VM
      # This allows choosing between Hyprland and VM at login
      # initial_session = {
      #   command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time";
      #   user = "<youruser>";
      # };
    };
  };

  # Ensure libvirt starts before greetd
  systemd.services.greetd = {
    after = [ "libvirtd.service" ];
    wants = [ "libvirtd.service" ];
  };
}
```

### Alternative: Custom Session Script

For more flexibility, create a custom session script that users can select from tuigreet:

```nix
{ config, pkgs, ... }:

let
  vmSession = pkgs.writeShellScript "vm-session" ''
    #!/usr/bin/env bash

    VM_NAME="''${1:-gaming-vm}"

    # Function to cleanup on exit
    cleanup() {
      echo "Shutting down VM..."
      virsh shutdown "$VM_NAME"

      # Wait up to 30 seconds for graceful shutdown
      for i in {1..30}; do
        if ! virsh list --name | grep -q "$VM_NAME"; then
          echo "VM shut down successfully"
          return 0
        fi
        sleep 1
      done

      # Force destroy if still running
      echo "Force destroying VM..."
      virsh destroy "$VM_NAME"
    }

    trap cleanup EXIT

    # Check if VM exists
    if ! virsh list --all --name | grep -q "^$VM_NAME$"; then
      echo "Error: VM '$VM_NAME' not found"
      echo "Available VMs:"
      virsh list --all --name
      read -p "Press Enter to exit..."
      exit 1
    fi

    # Start VM if not running
    if ! virsh list --name | grep -q "^$VM_NAME$"; then
      echo "Starting VM: $VM_NAME"
      virsh start "$VM_NAME"
    fi

    # Connect to VM display (if available)
    # This requires remote-viewer to be installed
    if command -v remote-viewer &> /dev/null; then
      echo "Connecting to VM display..."
      DISPLAY_URI=$(virsh domdisplay "$VM_NAME")
      remote-viewer "$DISPLAY_URI" &
      VIEWER_PID=$!

      # Wait for remote-viewer to exit
      wait $VIEWER_PID
    else
      # Fallback to console
      echo "Connecting to VM console (Ctrl+] to exit)..."
      virsh console "$VM_NAME"
    fi
  '';

in {
  # Install the session script
  environment.systemPackages = [
    pkgs.virt-viewer  # For remote-viewer
    (pkgs.writeShellScriptBin "vm-gaming" ''
      ${vmSession} gaming-vm
    '')
  ];

  # Configure greetd to show tuigreet menu
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --remember-session";
      };
    };
  };
}
```

Users can then select "vm-gaming" from the tuigreet session menu.

### Adding Desktop Files for Session Selection

For proper desktop session integration:

```nix
{ config, pkgs, ... }:

{
  # Create a desktop session file for the VM
  environment.etc."wayland-sessions/gaming-vm.desktop".text = ''
    [Desktop Entry]
    Name=Gaming VM (Windows)
    Comment=Boot into Windows gaming VM
    Exec=${vmSession} gaming-vm
    Type=Application
  '';

  # This makes it appear in greetd/tuigreet session selection
}
```

### Workflow

1. System boots
2. greetd presents login screen
3. User selects "Gaming VM" session
4. VM starts automatically with GPU passthrough
5. User interacts with VM via graphical display
6. When done, close display viewer or Ctrl+] in console
7. VM shuts down
8. System returns to greetd (or reboots)

## Potential Issues and Warnings

### Display Manager Crashes

**Symptom**: After configuring GPU passthrough, display manager fails to start.

**Cause**: GPU driver conflict or incorrect BIOS settings.

**Solutions**:
- Ensure BIOS is set to use iGPU as primary display (for dual GPU setup)
- Check that GPU is properly bound to VFIO and not being claimed by host driver
- Verify display manager is configured to use the correct GPU

```bash
# Check which GPU the display manager is trying to use
cat /var/log/Xorg.0.log | grep -i "loading.*driver"

# For Wayland (Hyprland), check:
journalctl -u display-manager | grep -i gpu
```

### System Hangs During VM Shutdown

**Symptom**: System freezes or hangs when stopping a VM with GPU passthrough.

**Cause**: GPU driver not releasing resources properly, IOMMU issues, or kernel bugs.

**Solutions**:
- Update to latest kernel version
- Check for BIOS/UEFI updates (fixes IOMMU bugs)
- Try adding kernel parameter: `iommu=pt`
- For AMD GPUs, try: `amd_iommu=on iommu=pt`

### NVIDIA-Specific Issues

**Code 43 Error in Windows VM**:

NVIDIA drivers detect virtualization and disable the GPU.

**Solution**: Add KVM hidden state and vendor_id to VM XML:

```xml
<features>
  <hyperv mode='custom'>
    <vendor_id state='on' value='1234567890ab'/>
  </hyperv>
  <kvm>
    <hidden state='on'/>
  </kvm>
</features>
```

**Driver Unbinding Fails**:

NVIDIA drivers are notoriously difficult to unbind dynamically.

**Solutions**:
- Use dual GPU setup instead of single GPU passthrough
- Ensure all NVIDIA modules are unloaded in correct order:
  ```bash
  modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia
  ```
- Add `nvidia.NVreg_DynamicPowerManagement=0x02` to kernel params

### GPU Not Visible in VM

**Symptom**: VM starts but GPU doesn't appear in device manager.

**Cause**: Incorrect PCI address, missing OVMF/UEFI firmware, or IOMMU grouping issues.

**Solutions**:

1. **Check IOMMU groups**:
```bash
# View IOMMU groupings
for d in /sys/kernel/iommu_groups/*/devices/*; do
  n=${d#*/iommu_groups/*}
  n=${n%%/*}
  printf 'IOMMU Group %s ' "$n"
  lspci -nns "${d##*/}"
done
```

Ensure your GPU is in its own IOMMU group or shares only with its audio device.

2. **Verify VM is using UEFI**:
```bash
virsh dumpxml <vm-name> | grep -i ovmf
```

3. **Check PCI address is correct**:
```bash
lspci -D | grep -i vga
# Compare with VM XML <hostdev> addresses
```

### Black Screen on VM Display

**Symptom**: VM starts but display shows nothing.

**Causes**:
- GPU ROM not accessible (some GPUs need ROM file extracted)
- Display not connected to passed-through GPU
- VM trying to use wrong video output

**Solutions**:
- Connect display to passed-through GPU (not host GPU)
- Dump GPU ROM and provide to VM:
  ```bash
  cd /sys/bus/pci/devices/0000:01:00.0/
  echo 1 > rom
  cat rom > /var/lib/libvirt/vbios.bin
  echo 0 > rom
  ```

  Then add to VM XML:
  ```xml
  <hostdev mode='subsystem' type='pci' managed='yes'>
    <source>
      <address domain='0x0000' bus='0x01' slot='0x00' function='0x0'/>
    </source>
    <rom file='/var/lib/libvirt/vbios.bin'/>
  </hostdev>
  ```

### VM Performance Issues

**Symptom**: VM has poor GPU performance despite passthrough.

**Causes**:
- CPU pinning not configured
- Not using host-passthrough CPU mode
- Insufficient resources allocated

**Solutions**:

1. **Use host-passthrough CPU**:
```xml
<cpu mode='host-passthrough' check='none'>
  <topology sockets='1' cores='4' threads='2'/>
</cpu>
```

2. **Pin vCPUs to physical cores**:
```xml
<vcpu placement='static' cpuset='0-7'>8</vcpu>
<cputune>
  <vcpupin vcpu='0' cpuset='0'/>
  <vcpupin vcpu='1' cpuset='1'/>
  <vcpupin vcpu='2' cpuset='2'/>
  <vcpupin vcpu='3' cpuset='3'/>
  <vcpupin vcpu='4' cpuset='4'/>
  <vcpupin vcpu='5' cpuset='5'/>
  <vcpupin vcpu='6' cpuset='6'/>
  <vcpupin vcpu='7' cpuset='7'/>
</cputune>
```

3. **Enable hugepages**:
```nix
# configuration.nix
boot.kernelParams = [ "hugepagesz=1G" "hugepages=16" ];
```

### Audio Crackling or Stuttering

**Symptom**: Audio from VM has pops, clicks, or stutters.

**Solutions**:
- Pass through GPU's audio device (usually function 1 of GPU PCI device)
- Use PulseAudio/PipeWire passthrough instead of emulated audio
- Increase VM audio buffer size in QEMU

### Reset Bug (AMD GPUs)

**Symptom**: GPU works first time but fails on subsequent VM restarts.

**Cause**: Some AMD GPUs don't properly reset state when VM stops.

**Solutions**:
- Use vendor-reset kernel module: https://github.com/gnif/vendor-reset
- Add to NixOS configuration:
  ```nix
  boot.extraModulePackages = with config.boot.kernelPackages; [ vendor-reset ];
  boot.kernelModules = [ "vendor-reset" ];
  ```

### Host Becomes Unresponsive

**Symptom**: System freezes or becomes extremely slow when VM is running.

**Causes**:
- Overcommitting resources (too much RAM/CPU to VM)
- Memory balloon driver conflicts
- I/O scheduler issues

**Solutions**:
- Reduce VM resource allocation
- Ensure host has sufficient RAM remaining
- Pin host processes to specific CPUs not used by VM
- Disable memory ballooning in VM

## Troubleshooting

### Emergency Recovery

If your system becomes unusable after GPU passthrough configuration:

1. **Boot into recovery mode**:
   - At bootloader, press 'e' to edit boot entry
   - Remove GPU-related kernel parameters
   - Boot with `single` or `systemd.unit=multi-user.target`

2. **Disable display manager from TTY**:
   ```bash
   systemctl stop display-manager
   systemctl disable display-manager
   ```

3. **Unbind GPU from VFIO manually**:
   ```bash
   # Find GPU PCI device
   lspci -D | grep -i vga

   # Unbind from VFIO
   echo "0000:01:00.0" > /sys/bus/pci/drivers/vfio-pci/unbind

   # Bind to proper driver
   echo "0000:01:00.0" > /sys/bus/pci/drivers/nvidia/bind  # or amdgpu
   ```

4. **Rebuild with fixed configuration**:
   ```bash
   sudo nixos-rebuild switch
   ```

### Logging and Debugging

Enable debug logging for libvirt:

```nix
# configuration.nix
virtualisation.libvirtd = {
  enable = true;
  qemu.verbatimConfig = ''
    log_level = 1
    log_outputs="1:file:/var/log/libvirt/qemu.log"
  '';
};
```

Check logs:
```bash
# Libvirt daemon logs
journalctl -u libvirtd

# QEMU logs
tail -f /var/log/libvirt/qemu/<vm-name>.log

# Kernel messages (IOMMU, VFIO, etc.)
dmesg | grep -i vfio
dmesg | grep -i iommu
```

### Testing IOMMU Groups

Script to view IOMMU groupings:

```bash
#!/usr/bin/env bash
shopt -s nullglob
for g in /sys/kernel/iommu_groups/*; do
    echo "IOMMU Group ${g##*/}:"
    for d in $g/devices/*; do
        echo -e "\t$(lspci -nns ${d##*/})"
    done
done
```

Ideal scenario: GPU and its audio device are in the same IOMMU group, isolated from other devices.

Poor scenario: GPU in same group as USB controller, SATA controller, etc.

**Fix for poor IOMMU grouping**:
- Enable ACS override patch (use with caution, reduces security):
  ```nix
  boot.kernelParams = [ "pcie_acs_override=downstream,multifunction" ];
  ```

## References

### Official Documentation

- [NixOS Wiki: PCI Passthrough](https://wiki.nixos.org/wiki/PCI_passthrough)
- [libvirt: PCI passthrough](https://libvirt.org/formatdomain.html#host-device-assignment)
- [QEMU Documentation](https://www.qemu.org/docs/master/)

### Community Guides

- [Arch Wiki: PCI passthrough via OVMF](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF)
- [GPU Passthrough Setup for NixOS](https://astrid.tech/2022/09/22/0/nixos-gpu-vfio/)
- [Single GPU Passthrough](https://github.com/joeknock90/Single-GPU-Passthrough)
- [bryansteiner GPU Passthrough Tutorial](https://github.com/bryansteiner/gpu-passthrough-tutorial)

### Keystone-Specific

- [VM Secure Boot Testing](./examples/vm-secureboot-testing.md) - VM creation with bin/virtual-machine
- [CLAUDE.md](../CLAUDE.md) - Project overview and architecture

### Hardware Compatibility

- [VFIO Reddit Wiki](https://www.reddit.com/r/VFIO/wiki/index/)
- [VFIO Discord](https://discord.gg/f63cXwH) - Active community support

---

**Note**: GPU passthrough is a complex topic with many hardware-specific quirks. This guide provides a foundation, but your specific hardware may require additional configuration. Always test in a non-production environment first.
