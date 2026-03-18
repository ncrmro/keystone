# Research: AirPlay Receiver on NixOS

**Date**: 2025-12-30
**Component**: `keystone.os.services.airplay`
**Goal**: Enable AirPlay receiver (`shairport-sync`) as a system service that outputs audio to the desktop user's audio session (PipeWire/PulseAudio).

## 1. The Challenge
`shairport-sync` runs as a dedicated system user (`shairport-sync`) for security isolation. However, the desktop audio server (PipeWire) runs as the logged-in user (`ncrmro`). By default, the system service cannot access the user's audio socket.

## 2. Approach Attempted: PipeWire TCP Socket

### Configuration
1.  **Enable PipeWire TCP Listener**:
    Modified `modules/desktop/nixos.nix` to enable a TCP listener for the PulseAudio compatibility layer.
    ```nix
    services.pipewire.extraConfig.pipewire-pulse."10-tcp" = {
      "pulse.properties" = {
        "server.address" = [ "tcp:127.0.0.1:4713" ];
      };
    };
    ```

2.  **Configure Service**:
    Modified `modules/os/airplay.nix` to point to this TCP socket.
    ```nix
    systemd.services.shairport-sync.serviceConfig.Environment = "PULSE_SERVER=tcp:127.0.0.1:4713";
    # Backend used: pa (PulseAudio)
    ```

### Results
- **Success**: The `shairport-sync` service successfully connected to the TCP socket and entered the `active (running)` state.
- **Failure**: **Desktop audio broke.** Enabling the TCP listener via `extraConfig` seemingly interfered with the standard Unix socket activation or configuration for the local user session. The user lost audio output.

## 3. Findings
- Running `shairport-sync` as a system service requires bridging the isolation gap.
- Enabling TCP listeners globally on PipeWire can have side effects on the local user session if not configured carefully (e.g., it might override the default unix socket configuration if not merged correctly).
- Manual testing (`shairport-sync -o pa`) works fine when run as the user.

## 4. Recommendations for Future Implementation

### Option A: User Service (Recommended for Desktops)
Instead of a system service, run `shairport-sync` as a **systemd user service**.
- **Pros**: Natively shares the user's PipeWire session. No TCP/networking hacks needed.
- **Cons**: Only runs when the user is logged in (acceptable for a workstation).

### Option B: System Service with Unix Socket Access
Grant the `shairport-sync` user access to the logged-in user's PipeWire socket.
- **Mechanism**: Bind mount the socket or set ACLs? (Difficult due to dynamic user runtime dirs `/run/user/1000`).

### Option C: Refine TCP Configuration
Investigate why `extraConfig` broke local audio. It's possible `server.address` overwrote the default unix socket address instead of appending to it.
- **Potential Fix**: Ensure the configuration *adds* the TCP listener alongside `unix:native`.

## 5. Additional Findings (Web Research)

### PipeWire TCP Listener Issues
Enabling the TCP listener via `services.pipewire.extraConfig` can sometimes overwrite default socket settings if not carefully merged. The configuration:
```nix
"server.address" = [ "tcp:127.0.0.1:4713" ];
```
might have disabled the native unix socket `unix:native`, preventing local clients (like the desktop environment) from connecting. The correct approach should list *both* listeners if modifying this property.

### Recommended System-Wide Approach
Research suggests that for a robust system-wide AirPlay receiver, the system service should output to a system-wide PipeWire instance or use a properly configured backend that supports multi-user access.

**Key Configuration Patterns identified:**
1.  **Backend**: Use `--output=pipewire` (or `pw`) instead of PulseAudio (`pa`) when possible for native integration.
2.  **Firewall**: Ensure specific ports are open:
    - TCP: 3689, 5000
    - UDP: 5353 (mDNS), 6000-6009, 319-320
    - TCP/UDP High ports: 32768-60999
3.  **Session Control**: Use `--sessioncontrol-allow-session-interruption=yes` to allow multiple devices to take over streams.

### Updated Plan
1.  **Re-evaluate System Service**: If running as a system service is required, verify if `shairport-sync` can output to the system-wide PipeWire socket (if enabled) or if a user service is strictly better for single-user workstations.
2.  **User Service Viability**: A systemd user service (`systemd.user.services`) is likely the most stable solution for a personal workstation, as it naturally inherits the active user's audio session without permission hacks.

## 6. Proposed User Service Configuration

Since the desktop OS automatically logs in the user (starting Hyprland/PipeWire), a **User Service** is the ideal architecture. It runs *as the user*, inheriting the `XDG_RUNTIME_DIR` and access to the PulseAudio/PipeWire socket automatically.

### Configuration Snippet (NixOS Module)

This definition can live in the system `airplay.nix` module but define a user-space service. Note that firewall rules must still be applied at the system level.

```nix
{ config, pkgs, ... }: {
  # 1. Open Firewall Ports (System Level)
  networking.firewall = {
    allowedTCPPorts = [ 3689 5000 ];
    allowedUDPPorts = [ 5353 6000 6001 6002 ];
    allowedTCPPortRanges = [ { from = 32768; to = 60999; } ];
    allowedUDPPortRanges = [ { from = 32768; to = 60999; } ];
  };

  # 2. Define User Service (Runs for logged-in users)
  # This makes the service available to the user session manager
  systemd.user.services.shairport-sync = {
    description = "Shairport Sync AirPlay Receiver (User Session)";
    
    # Start automatically when the user session is ready
    wantedBy = [ "default.target" ];
    
    # Ensure audio subsystem is ready
    after = [ "pipewire.service" "pipewire-pulse.service" ];
    wants = [ "pipewire.service" "pipewire-pulse.service" ];

    serviceConfig = {
      # Path to executable
      ExecStart = ''
        ${pkgs.shairport-sync-airplay2}/bin/shairport-sync \
          -v \
          --name "AirPlay (%u)" \
          --output pa \
          --sessioncontrol-allow-session-interruption=yes
      '';
      
      # Restart reliability
      Restart = "always";
      RestartSec = "5s";
      
      # No special User/Group needed - it runs as the logged-in user!
    };
  };

  # 3. Ensure package is available
  environment.systemPackages = [ pkgs.shairport-sync-airplay2 ];
}
```

### Advantages
1.  **Zero Permission Issues**: Service runs as `ncrmro`, same as PipeWire.
2.  **Automatic Startup**: Starts immediately when the desktop session launches (Hyprland/Greetd auto-login).
3.  **Hardware Control**: Can natively control volume and metadata integration with desktop players (MPRIS).

### Constraints
- **Multi-user conflict**: If multiple users connect simultaneously, they might fight for the same fixed network ports (5000, etc.). On a single-user workstation, this is negligible.


