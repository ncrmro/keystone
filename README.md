# Keystone OS

Rebuilt from an empty root for v1 (history: `archive/*` branches and the
v0.x/rc tags). Current content: the **unified fleet harness** — one fleet
definition, testable as VMs, as baremetal machines, or as any mix of both
from the same script.

## Model

A fleet is a `hosts/` directory of plain NixOS modules fed to
`lib.mkFleet`. Every host has up to three *realizations*:

- **vm** — QEMU vmVariant with fresh-install semantics. ssh forwarded from
  `basePort + index`, graphical console on VNC display
  `vncDisplayBase + index` (unauthenticated — tailnet or ssh tunnel only).
- **machine** — a physical box (a test machine like `ks-test-delltop`)
  reached over ssh and deployed with `nixos-rebuild test|switch
  --target-host` (or `--build-host` for remote builds).
- **install** — the host's real disko-built disk image with emulated
  security hardware; see below.

`targets.<host>` declares the machine endpoint and the default realization;
`fleetMeta` exports the whole table as data. The `ks-fleet` runner consumes
it, so **a single run can mix VMs and baremetal**: ks-test-delltop live on the LAN
while the rest of the fleet boots as QEMU VMs beside it, all smoke-tested
together. VM hosts use QEMU user networking (outbound only); cross-host
reachability in mixed fleets rides the tailnet overlay once os#2's
first-node foundation lands.

```nix
fleet = keystone-os.lib.mkFleet {
  hostsDir = ./hosts;
  baseModules = [ keystone-os.nixosModules.default ];   # once modules return
  targets = {
    ks-test-delltop = {
      machine = { sshTarget = "192.168.1.64"; user = "ncrmro"; };
      vm = { memorySize = 8192; };   # still bootable as a VM
    };
    ocean.vm = false;                # machine-only host
  };
};
```

## Usage

```bash
nix run .#fleet              # boot every vm-default host headless
nix run .#vm-<host>          # boot one host as a VM (foreground)
nix run .#ks-fleet -- status # realization, endpoint, reachability table
nix run .#ks-fleet -- test   # deploy machines + boot VMs + smoke all
nix run .#ks-fleet -- test ks-demo-b --as vm     # force realization
nix run .#ks-fleet -- deploy ks-test-delltop --durable   # switch, not test
nix run .#ks-fleet -- down   # stop background VMs (state in .fleet/)
```

`ks-fleet test` is the fast loop: machine hosts get `nixos-rebuild test`
(activation without bootloader — reversible by reboot), VM hosts rebuild
and reboot, then every host must reach `systemctl is-system-running ==
running` (or `degraded` with `--allow-degraded`) or the run fails with its
failed units listed. Consumer flakes that have not adopted `lib.mkFleet`
still get vm realizations: ks-fleet falls back to the host's plain
`system.build.vm` and adds ssh forwarding via `QEMU_NET_OPTS`.

## Install realization (day-one: LUKS/TPM/FIDO2 in a VM)

Hosts with `targets.<host>.install = { }` gain `nix build .#install-<host>`
— disko builds the host's **real partition layout** (GPT/LUKS/LVM) into a
qcow2 and boots it (`system.build.vmWithDisko`) with an emulated TPM2
(swtpm, on by default) and optionally a canokey virtual FIDO2 token
(`install.fido2 = true`; needs a canokey-enabled qemu build), so users can
prove LUKS unlock flows — passphrase fallback, TPM auto-unlock enrollment,
yubikey FIDO2 — before touching hardware. `disko.tests.bootCommands` carry
the boot assertions; disko's LUKS type also supports `enrollFido2` for
enrolling the virtual token at format time.

Conventions and gotchas: LUKS `passwordFile` hosts add a guarded
`preCreateHook` writing disko's test passphrase (see
`examples/hosts/ks-demo-luks`); run from a short cwd or set
`NIX_SWTPM_DIR=/tmp/<short>` (unix-socket 108-char path limit, fails
silently); never pipe `/dev/null` into a `-nographic` qemu — drive the
serial console with expect.

The in-repo `examples/hosts` fleet is self-demonstrating: `ks-demo-a`
defaults to vm, `ks-demo-b` carries a (placeholder) machine target.

## Provenance

Unifies the keystone-systems fleet harness (`mkFleet` + `mkFleetHarness`,
see `~/repos/keystone-systems/NOTES.md`) with the machine-target metadata
pattern from ncrmro/ks-config `hosts.nix`. Plan:
`docs/reports/2026-07-Q3-org-stabilization-plan.md`.
