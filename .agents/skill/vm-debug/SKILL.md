# VM debug

Use this skill when a Keystone ISO/direct VM test fails after boot or reboot
and the VM must be inspected manually through libvirt, SPICE, serial console,
screenshots, or preserved qcow2/NVRAM artifacts.

Proactively use this skill whenever `bin/test-iso`, `bin/virtual-machine`,
libvirt, Secure Boot VM reboot validation, TPM enrollment VM validation, or an
OVMF/firmware boot failure is involved. Do not wait for the user to ask for the
skill by name.

## Goals

- Preserve the VM at the failure point instead of deleting the evidence.
- Connect to the guest display correctly from a remote workstation.
- Inspect text logs and libvirt metadata first; capture pictures only when the
  text path cannot answer the question.
- Distinguish "OS failed after boot" from "firmware menu/no OS loaded".

## Core rules

- Run `bin/test-iso` with `--no-delete` for interactive debugging.
- Do not assume `spice://hostname:5900` works. Keystone VMs usually bind SPICE
  to `127.0.0.1`; use SSH local forwarding from the machine running libvirt.
- The most token-efficient path is logs and metadata first: e2e output,
  `virsh domstate`, `domblklist`, `domifaddr`, `dumpxml`, and serial output.
- Pictures are a last resort. Capture a VM screenshot only when text output does
  not prove the current state, when the user asks to see the screen, or before
  changing boot order/NVRAM/disk state.
- Prefer a clean shutdown and a focused reinstall/retry over extended ad-hoc
  firmware poking when the captured state is ambiguous.
- If the display shows the OVMF/BHYVE-style firmware menu and there is no Linux
  serial output or SSH, treat it as a bootloader/NVRAM/EFI issue, not a userspace
  networking issue.

## Token-efficient triage order

1. Read the e2e output around the first failure and identify the failed phase.
2. If the VM was preserved, inspect libvirt state:

   ```bash
   VM=keystone-e2e-500916
   virsh domstate "$VM"
   virsh domblklist "$VM"
   virsh domifaddr "$VM" || true
   virsh dumpxml "$VM" | rg -n "loader|nvram|boot|disk|cdrom|graphics|serial" -C 2
   ```

3. Check serial text before pictures:

   ```bash
   virsh dumpxml "$VM" | rg "serial type='pty'|source path" -A 2
   timeout 5s cat /dev/pts/<N> | sed -n '1,120p' || true
   ```

4. If the text state is ambiguous, cleanly shut down and rerun once with
   `--no-delete`, watching the output as it arrives:

   ```bash
   virsh shutdown "$VM" || virsh destroy "$VM"
   cd ~/repos/noah/ks-config
   bash bin/test-iso --dev --e2e --ssh-timeout 1800 --no-delete
   ```

5. Use screenshots or SPICE only after the text path cannot answer whether the
   guest is in Linux/initrd/hyprlock/firmware.

6. For OVMF "no bootable option" failures, inspect the qcow2 ESP before
   changing firmware settings. Stop the VM first so the image is not locked,
   then use `guestfish` from `libguestfs-with-appliance`; do not rely on
   `virt-filesystems`, which may not be included in the Nix package:

   ```bash
   VM=keystone-e2e-500916
   virsh shutdown "$VM" || virsh destroy "$VM"

   nix shell nixpkgs#libguestfs-with-appliance -c guestfish --ro \
     -a /tmp/keystone-test-iso-disk.qcow2 <<'EOF'
   run
   list-filesystems
   mount-ro /dev/sda1 /
   ll /EFI
   ll /EFI/BOOT
   ll /EFI/Linux
   ll /EFI/nixos
   EOF
   ```

   If `/EFI/Linux` or `/EFI/nixos` exists but `/EFI/BOOT/BOOTX64.EFI` is
   missing, the installed system may be valid while firmware fallback boot is
   broken. Fix the installer/e2e fallback creation instead of debugging SSH.

## Start a preserved ISO e2e VM

From the consumer config repo:

```bash
cd ~/repos/noah/ks-config
bash bin/test-iso --dev --e2e --ssh-timeout 1800 --no-delete
```

For headless CI-style reproductions:

```bash
bash bin/test-iso --dev --headless --e2e --ssh-timeout 1800 --no-delete
```

When the test exits, note the printed VM name, disk path, screenshot path, and
SSH command. If the test is still running, use `virsh list --all` to find the
VM name.

## Inspect libvirt state

```bash
VM=keystone-e2e-500916

virsh domstate "$VM"
virsh domdisplay "$VM"
virsh domblklist "$VM"
virsh domifaddr "$VM" || true
virsh dumpxml "$VM" | rg -n "loader|nvram|boot|disk|cdrom|graphics|serial" -C 2
```

Expected post-install reboot shape:

- `domstate`: `running`
- `domdisplay`: usually `spice://127.0.0.1:5900`
- `domblklist`: installed qcow2 as `vda`, no ISO attached
- XML: `<boot dev='hd'/>` before `<boot dev='cdrom'/>`

No IP in `domifaddr` plus a firmware menu on screen means the OS likely never
loaded.

## Connect to the graphical display

If working directly on the libvirt host:

```bash
remote-viewer "$(virsh domdisplay "$VM")"
```

If connecting from another machine to `ncrmro-workstation`, tunnel the loopback
SPICE listener:

```bash
ssh -N -L 15900:127.0.0.1:5900 ncrmro@ncrmro-workstation
remote-viewer spice://127.0.0.1:15900
```

Use a different local port if `15900` is occupied. Do not use
`spice://ncrmro-workstation:5900` unless libvirt is explicitly listening on a
non-loopback address.

## Capture the current VM screen only when needed

Pictures cost more context than text and are often misleading when the display
pipeline is black. Prefer `virsh screenshot`; it captures from the VM, not the
local desktop:

```bash
VM=keystone-e2e-500916
OUT=/tmp/${VM}-screen.ppm
virsh screenshot "$VM" --file "$OUT" --screen 0
file "$OUT"
```

If `virsh screenshot` fails, use QEMU monitor screendump only when the VM was
started with a monitor socket:

```bash
printf 'screendump /tmp/%s-screen.ppm\n' "$VM" | socat - "UNIX-CONNECT:/tmp/qemu-e2e-monitor-<pid>.sock"
```

Convert for local inspection when needed:

```bash
nix shell nixpkgs#imagemagick -c magick /tmp/${VM}-screen.ppm /tmp/${VM}-screen.png
```

## Unlock LUKS from the QEMU monitor

Use this when the installed VM is confirmed to be at the initrd LUKS prompt and
the VM was started with `--monitor-socket`. Capture before and after screenshots
so the review trail proves whether the unlock was accepted.

```bash
VM=keystone-e2e-720584
MON=/tmp/qemu-e2e-manual-monitor.sock
REVIEW_DIR=/tmp/keystone-e2e-review-$(date +%Y%m%d)
mkdir -p "$REVIEW_DIR"

spicy-screenshot -h 127.0.0.1 -p 5900 -o "$REVIEW_DIR/luks-before.ppm"
nix shell nixpkgs#imagemagick -c magick \
  "$REVIEW_DIR/luks-before.ppm" \
  "$REVIEW_DIR/luks-before.png"

for c in k e y s t o n e; do
  printf 'sendkey %s\n' "$c" | socat - "UNIX-CONNECT:$MON"
  sleep 0.12
done
printf 'sendkey ret\n' | socat - "UNIX-CONNECT:$MON"

sleep 90
spicy-screenshot -h 127.0.0.1 -p 5900 -o "$REVIEW_DIR/luks-after.ppm"
nix shell nixpkgs#imagemagick -c magick \
  "$REVIEW_DIR/luks-after.ppm" \
  "$REVIEW_DIR/luks-after.png"

ssh -i ~/repos/noah/ks-config/.test-iso-dev-key \
  -p 12222 \
  -o UserKnownHostsFile=/dev/null \
  -o StrictHostKeyChecking=no \
  -o ConnectTimeout=10 \
  noah@localhost 'hostname && systemctl is-system-running || true'
```

Do not send the passphrase as a chord such as `sendkey k-e-y-s-t-o-n-e`; QEMU
interprets that as simultaneous key presses. Send one character per `sendkey`
command, then `ret`.

## Check the serial console

Find the serial PTY:

```bash
virsh dumpxml "$VM" | rg "serial type='pty'|source path" -A 2
```

Connect without consuming the PTY forever:

```bash
timeout 5s cat /dev/pts/<N> | sed -n '1,120p' || true
```

Interpretation:

- Linux/initrd output: continue debugging boot, LUKS, services, or networking.
- No Linux output and the display is firmware UI: debug EFI boot entry, ESP
  contents, NVRAM, Secure Boot signing, or bootloader install.

## Recognize the OVMF BIOS menu failure

If the screenshot or SPICE viewer shows the OVMF firmware menu and no OS is
loaded:

- Do not keep retrying SSH; sshd cannot start because Linux did not boot.
- Check whether the ISO is detached and the qcow2 is attached as `vda`.
- Check whether `/boot/EFI/BOOT/BOOTX64.EFI` and systemd-boot/lanzaboote were
  installed during `nixos-install`.
- Check whether the preserved NVRAM file is the same one used before and after
  `--post-install-reboot`.
- Inspect the ESP with `guestfish` if logs say the bootloader installed but
  OVMF cannot load any boot option. A missing `/EFI/BOOT/BOOTX64.EFI` with a
  signed loader under `/EFI/Linux` points to fallback boot preparation, not a
  failed OS install.
- Treat this as a bootloader/NVRAM/Secure Boot handoff failure until proven
  otherwise.

## Manual access commands

Installer SSH while the live ISO is booted:

```bash
ssh -i ~/repos/noah/ks-config/.test-iso-dev-key \
  -p 12222 \
  -o StrictHostKeyChecking=no \
  noah@localhost
```

Installed-system SSH after successful boot should use the same forwarded port.
If this fails and `domifaddr` is empty, inspect the display and serial console
before debugging SSH configuration.
