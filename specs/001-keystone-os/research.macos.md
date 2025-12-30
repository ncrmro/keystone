# macOS (Apple Silicon) Installer ISO - Research & Troubleshooting Notes

This document captures research, design decisions, and troubleshooting steps related to building a functional installer ISO for macOS (Apple Silicon) devices.

---

## 1. Initial Build & TUI Integration Challenges

**Problem:** The initial design of the installer ISO aimed to include a Terminal User Interface (TUI) installer for interactive setup. However, this led to several issues after booting:
    *   `Failed to stat User Login Management` (related to `systemd-logind`).
    *   No interactive `bash` shell available upon exiting the TUI, despite `bashInteractive` being specified.
    *   General instability and unexpected behavior related to TTY control.

**Root Cause Analysis:**
The primary cause was identified as a conflict in systemd service enablement for `tty1` (where the TUI installer was configured to run).
1.  `modules/iso-installer.nix` and `modules/iso-installer-apple-silicon.nix` were defining `environment.systemPackages` with `lib.mkForce`, inadvertently removing essential system packages (like `coreutils`, `findutils`, default `bash`) that are typically inherited from `nixos/modules/installer/cd-dvd/installation-cd-minimal.nix`. This resulted in a very minimal (and broken) system environment.
2.  The `keystone-installer.service` (TUI) was configured to run on `tty1` and conflict with `getty@tty1.service` and `autovt@tty1.service`.
3.  `modules/iso-base.nix` (a refactored common module) was initially configured to unconditionally enable `getty@tty1.service` and `autovt@tty1.service`. This created a race condition or direct conflict with the TUI installer, preventing `systemd-logind` from establishing a proper user session.

**Solution/Fixes Implemented:**

1.  **Module Refactoring**:
    *   Created `modules/iso-base.nix` to hold common ISO configurations (SSH, root user, essential packages, network basics).
    *   Modified `modules/iso-installer.nix` (for x86_64) to import `iso-base.nix` and add only ZFS/x86-specific configurations.
    *   Modified `modules/iso-installer-apple-silicon.nix` to import `iso-base.nix` and add only Apple Silicon-specific configurations.
    *   **Crucially**: Removed `lib.mkForce` from `environment.systemPackages` in `modules/iso-installer-apple-silicon.nix` and ensured all required essential packages are inherited from `iso-base.nix` (which in turn builds upon `installation-cd-minimal.nix` defaults). This resolved missing basic shell commands like `bash` and `coreutils`.

2.  **TTY Management**:
    *   In `modules/iso-base.nix`, the enablement of `getty@tty1.service` and `autovt@tty1.service` was made conditional on `!enableTui`. This ensures that `getty` services are only active when the TUI installer is disabled, preventing conflicts.
    *   Added an `ExecStopPost` command to `keystone-installer.service` (in `iso-base.nix`) to explicitly start `getty@tty1.service` when the TUI installer exits cleanly. This ensures the user drops to a functional login shell after exiting the TUI.

3.  **TUI "Exit to Shell" Feature**: Added a "Exit to Shell" option directly into the `keystone-installer-ui` application, which gracefully exits the TUI and triggers the `ExecStopPost` action in systemd.

---

## 2. Transition to "Vanilla" macOS Installer ISO

**Decision**: Due to the complexities and debugging efforts required to integrate the TUI installer and provide a robust shell environment simultaneously, the user requested to make the macOS installer ISO as "vanilla" (minimal) as possible. The primary goal is to have an image that:
    *   Boots on Apple Silicon.
    *   Includes SSH access with pre-configured keys.
    *   Provides basic network functionality.
    *   Does *not* include the TUI installer or excessive extra modules.

**Implementation**:
    *   `modules/iso-installer-apple-silicon.nix` was extensively rewritten.
    *   It now directly imports `nixos/modules/installer/cd-dvd/installation-cd-minimal.nix` (implicitly via the flake) and applies only the necessary Apple Silicon-specific overrides.
    *   All TUI-related configurations were removed.
    *   SSH service and authorized keys for root are explicitly enabled.
    *   Basic networking (`iwd` and later `NetworkManager`) and essential command-line tools (`git`, `vim`, `parted`, `nixos-install-tools`, `usbutils`, `pciutils`, `ethtool`, `dhclient`, `dhcpcd`) are included.

---

## 3. Networking Notes After Booting into the Installer (Vanilla macOS ISO)

After booting into the newly vanilla macOS installer ISO, network connectivity can still be a challenge due to the minimal nature of the image and the behavior of USB Ethernet adapters.

**Observed Issues:**
*   USB Ethernet adapters may be detected by the kernel (`lsusb`, `dmesg`), but fail to obtain an IP address automatically.
*   Upon hot-plugging/re-plugging, the device might not re-appear or acquire an IP.
*   Essential DHCP client tools like `dhclient` or `dhcpcd` may not be installed by default in a very minimal configuration.

**ISO Configuration for Robust Networking (Next Builds):**
To ensure reliable networking for subsequent builds of the vanilla macOS installer ISO, the `modules/iso-installer-apple-silicon.nix` has been updated with the following:
*   **Enabled `NetworkManager`**:
    ```nix
    networking.networkmanager.enable = true;
    networking.networkmanager.wifi.backend = "iwd";
    ```
    This ensures `NetworkManager` is running, which is excellent for handling hot-plugged USB Ethernet devices and automatically obtaining IP addresses via DHCP.
*   **Explicitly Added Network Tools**:
    ```nix
    environment.systemPackages = with pkgs; [
      # ... other tools ...
      networkmanager
      dhclient
      dhcpcd
      usbutils
      pciutils
      ethtool
    ];
    ```
    This guarantees that `NetworkManager` (the package), `dhclient`, and `dhcpcd` (for manual DHCP if needed) are present in the ISO environment, along with diagnostic tools.

**Troubleshooting Steps for Current Booted Session (If NetworkManager/DHCP clients are missing):**

If your currently booted ISO lacks `NetworkManager`, `dhclient`, or `dhcpcd`, you will need to manually configure the network using `ip` commands. This requires knowing your network's IP address range, subnet mask, gateway, and DNS servers.

1.  **Identify your network interface name:**
    ```bash
    ip link show
    ```
    (Look for names like `eth0`, `enp...`, or `usb...`. Let's assume it's `<interface_name>` for the following steps.)

2.  **Verify USB Ethernet device detection:**
    ```bash
    lsusb
    dmesg | tail -n 20 # Check kernel messages for device detection
    ```

3.  **Bring the network interface up:**
    ```bash
    sudo ip link set <interface_name> up
    ```

4.  **Assign a static IP address and subnet mask:**
    ```bash
    sudo ip addr add 192.168.1.100/24 dev <interface_name>
    ```
    (Replace `192.168.1.100` with an available IP on your network, and `/24` with your subnet mask.)

5.  **Add a default route (gateway):**
    ```bash
    sudo ip route add default via 192.168.1.1
    ```
    (Replace `192.168.1.1` with your network's gateway IP.)

6.  **Configure DNS servers:**
    ```bash
    echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
    # (Optional: Add more nameservers)
    # echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf
    ```

After these steps, you should have network connectivity. You can verify with `ping google.com`.
