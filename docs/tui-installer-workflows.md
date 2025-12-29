# TUI Installer Workflow Examples

This document provides step-by-step workflows for common TUI installer scenarios.

## Scenario 1: Server Installation with Ethernet

**Goal**: Install a headless NixOS server with encrypted ZFS storage

**Prerequisites**:
- Ethernet connection available
- Target machine booted from Keystone ISO
- Installation machine with nixos-anywhere ready (for remote method)

**Steps**:

1. **Boot**: Machine boots into Keystone ISO, TUI auto-starts on TTY1

2. **Network Detection**: Installer detects Ethernet connection and displays IP
   ```
   ✓ Network Connected
   Interface: enp0s3 - IP: 192.168.1.100
   
   Continue to Installation →
   ```

3. **Method Selection**: Choose installation method
   ```
   How would you like to install NixOS?
   > 💻 Local installation (on this machine)
     🖥️  Remote via SSH (nixos-anywhere)
     📦 Clone from existing repository
   ```

4. **Disk Selection**: Select target disk
   ```
   Select a disk for installation:
   > nvme0n1 - 500 GB (Samsung SSD 980 PRO)
     sda - 2 TB (WD Blue)
   ```

5. **Disk Confirmation**: Confirm data will be erased
   ```
   ⚠️ WARNING: ALL DATA WILL BE ERASED
   Selected disk: nvme0n1
   Size: 500 GB
   
   > ✓ Yes, erase this disk and continue
     ✗ No, go back
   ```

6. **Encryption**: Choose encryption
   ```
   Choose disk encryption option:
   > 🔒 Encrypted (ZFS + LUKS + TPM2) - Recommended
     🔓 Unencrypted (ext4) - Simple
   ```

7. **Hostname**: Enter hostname
   ```
   Enter a hostname for this machine:
   > my-server
   ```

8. **Username**: Enter primary user
   ```
   Enter a username for the primary account:
   > admin
   ```

9. **Password**: Set user password
   ```
   Enter a password for admin:
   > ********
   
   Confirm password for admin:
   > ********
   ```

10. **System Type**: Choose server
    ```
    Select the type of system to install:
    > 🖥️  Server (headless, infrastructure services)
      🖱️  Client (Hyprland desktop, graphical)
    ```

11. **Summary**: Review and confirm
    ```
    Installation Summary
    ┌──────────────────────────────┐
    │ Hostname: my-server          │
    │ Username: admin              │
    │ System Type: server          │
    │ Disk: nvme0n1 (500 GB)       │
    │ Encryption: ZFS + LUKS       │
    └──────────────────────────────┘
    
    > ✓ Start Installation
      ← Go back
    ```

12. **Installation**: Progress tracking
    ```
    ⋮ Running nixos-install...
    Progress: 75%
    
    Recent operations:
    ✓ create: Partition disk
    ✓ create: Format filesystems
    ✓ mount: Mount filesystems
    ✓ create: Generate configuration
    ⋮ execute: Running nixos-install
    ```

13. **Complete**: Installation finished
    ```
    ✓ NixOS has been successfully installed!
    
    Hostname: my-server
    Username: admin
    System Type: server
    
    Configuration saved to: ~/nixos-config/
    
    > 🔄 Reboot now
      📋 Exit without rebooting
    ```

## Scenario 2: Desktop Installation with WiFi

**Goal**: Install NixOS workstation with Hyprland desktop

**Prerequisites**:
- WiFi network available
- Target machine booted from Keystone ISO

**Steps**:

1. **Boot**: Machine boots into Keystone ISO, TUI auto-starts

2. **Network Detection**: No Ethernet detected
   ```
   ⚠ No Ethernet connection detected
   
   Would you like to set up WiFi?
   > Yes, scan for WiFi networks
     No, I'll configure manually
   ```

3. **WiFi Scanning**: Scanning for networks
   ```
   ⋮ Scanning for WiFi networks...
   ```

4. **Network Selection**: Choose WiFi network
   ```
   Select a WiFi network:
   > MyHomeNetwork
     GuestWiFi
     Office5G
   ```

5. **WiFi Password**: Enter password
   ```
   Network: MyHomeNetwork
   Enter password (press Enter when done):
   > ************
   ```

6. **Connecting**: Connecting to WiFi
   ```
   ⋮ Connecting to MyHomeNetwork...
   ```

7. **WiFi Connected**: Connected successfully
   ```
   ✓ WiFi Connected to MyHomeNetwork
   Interface: wlan0 - IP: 192.168.1.101
   
   Continue to Installation →
   ```

8. **Method Selection**: Choose local installation
   ```
   How would you like to install NixOS?
   > 💻 Local installation (on this machine)
   ```

9. **Disk Selection**: Select target disk
   ```
   Select a disk for installation:
   > nvme0n1 - 1 TB (WD BLACK SN850X)
   ```

10. **Encryption**: Choose encrypted
    ```
    Choose disk encryption option:
    > 🔒 Encrypted (ZFS + LUKS + TPM2) - Recommended
    ```

11. **Hostname**: Enter hostname
    ```
    Enter a hostname for this machine:
    > my-laptop
    ```

12. **Username**: Enter username
    ```
    Enter a username for the primary account:
    > user
    ```

13. **Password**: Set password (same as server example)

14. **System Type**: Choose client for desktop
    ```
    Select the type of system to install:
      🖥️  Server (headless, infrastructure services)
    > 🖱️  Client (Hyprland desktop, graphical)
    ```

15. **Summary**: Review configuration
    ```
    Installation Summary
    ┌──────────────────────────────┐
    │ Hostname: my-laptop          │
    │ Username: user               │
    │ System Type: client          │
    │ Disk: nvme0n1 (1 TB)         │
    │ Encryption: ZFS + LUKS       │
    └──────────────────────────────┘
    
    > ✓ Start Installation
    ```

16. **Installation**: Progress display (same as server)

17. **Complete**: Reboot into Hyprland desktop

## Scenario 3: Remote Installation via nixos-anywhere

**Goal**: Install server remotely using nixos-anywhere

**Prerequisites**:
- Installation machine with Nix and nixos-anywhere
- Target machine booted from Keystone ISO
- Network connection (Ethernet or WiFi)

**Steps on Target Machine**:

1-7. Same network setup as previous scenarios

8. **Method Selection**: Choose remote
   ```
   How would you like to install NixOS?
   > 🖥️  Remote via SSH (nixos-anywhere)
     💻 Local installation
     📦 Clone from repository
   ```

9. **Ready for Remote**: Display SSH command
   ```
   Ready for Remote Installation
   ┌─────────────────────────────────────────────┐
   │ From your deployment machine, run:         │
   │ nixos-anywhere --flake .#your-config \     │
   │   root@192.168.1.100                       │
   └─────────────────────────────────────────────┘
   ```

**Steps on Installation Machine**:

1. **Create Configuration**: On your machine, create flake config
   ```bash
   mkdir -p ~/my-server/hosts/server-1
   cd ~/my-server
   ```

2. **Generate Config**: Use Keystone template
   ```bash
   nix flake init -t github:ncrmro/keystone
   ```

3. **Edit Configuration**: Update `configuration.nix` with your settings
   ```nix
   keystone.os = {
     enable = true;
     storage = {
       type = "zfs";
       devices = [ "/dev/disk/by-id/nvme-..." ];
       swap.size = "16G";
     };
     users.admin = {
       fullName = "Administrator";
       email = "admin@server-1.local";
       authorizedKeys = [ "ssh-ed25519 AAAA..." ];
       hashedPassword = "$6$...";  # Generated with mkpasswd
       terminal.enable = true;
     };
   };
   ```

4. **Deploy**: Run nixos-anywhere
   ```bash
   nixos-anywhere --flake .#server-1 root@192.168.1.100
   ```

5. **Wait**: Installation proceeds remotely
   - Disk partitioning
   - NixOS installation
   - Configuration application
   - Automatic reboot

6. **SSH**: Connect to installed system
   ```bash
   ssh admin@192.168.1.100
   ```

## Scenario 4: Clone from Repository

**Goal**: Deploy existing configuration from git repository

**Prerequisites**:
- Git repository with NixOS configuration
- Repository has `hosts/` directory with host configurations

**Steps**:

1-7. Same network setup as previous scenarios

8. **Method Selection**: Choose clone
   ```
   How would you like to install NixOS?
     🖥️  Remote via SSH
     💻 Local installation
   > 📦 Clone from existing repository
   ```

9. **Repository URL**: Enter git URL
   ```
   Enter the git repository URL:
   > https://github.com/myuser/nixos-config
   
   HTTPS: https://github.com/user/repo
   SSH: git@github.com:user/repo
   ```

10. **Cloning**: Clone repository
    ```
    ⋮ Cloning https://github.com/myuser/nixos-config...
    ```

11. **Host Selection**: Choose host configuration
    ```
    Select a host configuration to deploy:
    > server-1
      server-2
      laptop
      workstation
    ```

12. **Summary**: Review deployment
    ```
    Installation Summary
    ┌──────────────────────────────┐
    │ Hostname: server-1           │
    │ Source: Cloned from repo     │
    └──────────────────────────────┘
    
    > ✓ Start Installation
    ```

13. **Installation**: Deploy configuration

14. **Complete**: Reboot into configured system

## Troubleshooting During Installation

### WiFi Connection Fails

**Symptoms**: Cannot connect to WiFi network

**Solution**:
1. Press Escape to go back to WiFi setup
2. Try entering password again
3. If still fails, press Ctrl+Alt+F2 to switch to shell
4. Manual connection:
   ```bash
   nmcli device wifi connect "SSID" password "password"
   ```
5. Press Ctrl+Alt+F1 to return to installer

### No Disks Found

**Symptoms**: Disk selection shows "No suitable disks found"

**Solution**:
1. Select "Refresh disk list"
2. If still no disks:
   - Press Ctrl+Alt+F2 for shell
   - Check with `lsblk` and `ls /dev/disk/by-id/`
   - Ensure disk drivers are loaded
   - Return to installer with Ctrl+Alt+F1

### Installation Hangs

**Symptoms**: Progress stuck at one operation

**Solution**:
1. Press Ctrl+Alt+F2 to switch to shell
2. Check logs:
   ```bash
   tail -f /tmp/keystone-install.log
   journalctl -u keystone-installer -f
   ```
3. Check if nixos-install is running:
   ```bash
   ps aux | grep nixos-install
   ```
4. If stuck on network download, check connectivity:
   ```bash
   ping -c 3 cache.nixos.org
   ```

### Out of Space

**Symptoms**: Installation fails with "No space left"

**Solution**:
1. Installer ISO has limited RAM-based storage
2. Ensure target disk has sufficient space
3. For large installations, use nixos-anywhere instead

## Post-Installation Steps

After successful installation:

1. **Reboot**: Select "Reboot now" or manually reboot

2. **First Boot**: System will boot from installed disk
   - For encrypted: Enter disk password (or automatic with TPM2)
   - For unencrypted: Direct boot to login

3. **Login**: Log in with configured user
   ```
   NixOS 25.05 (GNU/Linux)
   
   my-server login: admin
   Password: ********
   ```

4. **Initialize Git** (optional but recommended):
   ```bash
   cd ~/nixos-config
   git init
   git add .
   git commit -m "Initial configuration from TUI installer"
   ```

5. **Make Changes**: Edit configuration
   ```bash
   cd ~/nixos-config
   vim hosts/my-server/default.nix
   ```

6. **Rebuild**: Apply changes
   ```bash
   sudo nixos-rebuild switch --flake .#my-server
   ```

7. **Update**: Keep system up to date
   ```bash
   nix flake update
   sudo nixos-rebuild switch --flake .#my-server
   ```

## Tips and Best Practices

1. **Test in VM First**: Always test the installation process in a VM before deploying to production hardware

2. **Use Encryption**: Enable encryption for laptops and servers with sensitive data

3. **Document Passwords**: Securely store disk encryption and user passwords

4. **Version Control**: Initialize git in the configuration directory immediately after installation

5. **Backup**: Before making changes, backup the working configuration

6. **Review Config**: Always review generated configuration before rebooting

7. **Network Requirements**: Ensure stable internet connection for installation (downloads packages)

8. **Hardware Compatibility**: Verify hardware compatibility with NixOS before installation
