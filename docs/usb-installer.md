# USB Installer

Keystone includes a USB installer that contains SSH keys for remote installation using nixos-anywhere.

## Quick Start

1. Navigate to the example:
   ```bash
   cd examples/iso-installer
   ```

2. Edit `flake.nix` to add your SSH public keys

3. Build the ISO:
   ```bash
   nix build .#iso
   ```

4. Write to USB:
   ```bash
   nix run .#write-usb /dev/sdX
   ```

5. Boot target machine from USB and install remotely:
   ```bash
   nixos-anywhere --flake .#your-config root@<installer-ip>
   ```

See `examples/iso-installer/README.md` for detailed instructions.