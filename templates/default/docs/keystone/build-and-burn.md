---
title: Build and burn the installer ISO
description: Build the Keystone installer ISO for your host and write it to a USB stick
---

# Build and burn the installer ISO

Companion to [`onboarding.md`](onboarding.md) steps 3–4. Pick the section that
matches your driver's OS.

## Build the ISO

Your `keystone-config` flake exposes a single ISO output. The image bakes in
installer targets for every Linux host you declared in `flake.nix`, so one
build covers the whole fleet.

```bash
nix build .#iso
```

After the build:

```bash
ls -lh result/iso/
```

You should see a `keystone-...-installer-X.Y.Z.iso` file in the few hundred
MB to ~2 GB range.

### Building x86_64-linux from an aarch64 MacBook

If you're driving from an Apple Silicon Mac, the build host architecture
(`aarch64-darwin`) doesn't match the target (`x86_64-linux`). Two options:

1. **Use a remote Linux builder.** Configure `nix.buildMachines` on your Mac to
   point at any x86_64-linux box you can SSH into. The Nix manual covers the
   wiring under "Distributed Builds". For one-shot use, the `--builders` flag
   on the build invocation works too.
2. **Rely on the cache.** Most ISO content is downloaded from
   `cache.nixos.org` and `ks-systems.cachix.org`. If your Mac is configured
   with both substituters, the local build mostly fetches binaries and
   links them — minimal cross-compilation needed. Add the keystone cache:
   ```bash
   # ~/.config/nix/nix.conf
   extra-substituters = https://ks-systems.cachix.org
   extra-trusted-public-keys = ks-systems.cachix.org-1:Abbd38auzcLIfJUtX7kSD6zdGUU4v831Sb2KfajR5Mo=
   ```

If the build still tries to compile something large from source (Chromium,
Rust toolchain, etc.), you're missing a cache hit. Cross-compilation under Nix
is usable but slow; remote builder is the saner path.

### Building from a Linux driver

No special setup. The build runs locally.

## Write the ISO to USB

⚠️ **`dd` destroys all data on the target device.** Verify the device path
twice before running the command. If you write to the wrong disk you can
unrecover-ably lose your driver's filesystem.

### Linux

1. Plug the USB in. Wait a beat.
2. List block devices:
   ```bash
   lsblk -dpno NAME,SIZE,MODEL,TRAN
   ```
   Identify the USB (`TRAN` column shows `usb`). Note the path, e.g.
   `/dev/sdb`. Common gotcha: the USB stick's size on the label is a marketing
   round-up — `lsblk` will show the slightly smaller actual size.
3. Unmount any partitions of the USB if your file manager auto-mounted them:
   ```bash
   sudo umount /dev/sdb*  # adjust device
   ```
4. Write:
   ```bash
   sudo dd if=result/iso/*.iso of=/dev/sdb bs=4M status=progress conv=fsync
   sync
   ```
5. Wait for `sync` to return. Pull the USB.

### macOS

1. Plug the USB in. Wait a beat. Dismiss any "Disk Not Readable" popup —
   that's the Mac complaining about the ISO9660 filesystem, which is fine.
2. List devices:
   ```bash
   diskutil list
   ```
   Identify the USB. It'll typically be `/dev/diskN` where `N` is something
   like `2` or `4`. Confirm by size and the absence of `Apple_APFS` partitions.
3. Unmount the whole device (do NOT eject):
   ```bash
   diskutil unmountDisk /dev/diskN
   ```
4. Write to the *raw* device (`/dev/rdiskN`, not `/dev/diskN`) for much faster
   throughput:
   ```bash
   sudo dd if=result/iso/*.iso of=/dev/rdiskN bs=4m status=progress
   sync
   ```
   (Lowercase `4m`, not `4M`, on macOS dd.)
5. Eject when `dd` finishes:
   ```bash
   diskutil eject /dev/diskN
   ```

### Windows

Use Rufus (<https://rufus.ie/>) in "DD Image" mode. Select the ISO file in
the WSL-shared `result/iso/` directory. Rufus handles the device picker and
unmount safely.

## Boot the target from USB

1. Plug the USB into the new host.
2. Power on, enter UEFI / BIOS setup (vendor-specific — common keys: F2, F10,
   F12, Del).
3. Disable Secure Boot for now (the keystone installer ISO is not signed
   with a key your firmware trusts yet — Step 7 of the onboarding doc enrolls
   keys).
4. Boot from the USB.

The Keystone installer banner appears. Once it auto-DHCPs, the system's IP
shows on the console. You can now follow Step 5 of [`onboarding.md`](onboarding.md).
