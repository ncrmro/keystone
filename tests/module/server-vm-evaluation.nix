# server-vm template evaluation test
#
# Verifies that `mkServerVm` produces a host config whose bootloader, storage,
# and security defaults match the cloud/VPS contract:
#   - UEFI by default (grub-in-ESP, efiInstallAsRemovable for cloud-image friendliness)
#   - systemd-boot forced off (mkLinuxHost defaults it on; we override with mkForce)
#   - secureBoot + TPM off (cloud firmware doesn't expose them)
#   - storage.type = "ext4" (typical VPS layout)
#   - baremetal-only packages (lm_sensors) not pulled in
#
# Also exercises the `bios = true` opt-in path: efiSupport flips off, grub
# device becomes null (host must declare its own disk path).
#
# Build: nix build .#server-vm-evaluation
#
{
  pkgs,
  lib,
  self,
  nixpkgs ? null,
  home-manager ? null,
}:
let
  baseArgs = {
    hostname = "server-vm-default";
    admin = {
      fullName = "Server VM Admin";
      email = "vm@example.com";
      initialPassword = "changeme";
      terminal.enable = true;
    };
    storage.devices = [ "/dev/disk/by-id/vps-root-001" ];
    modules = [
      {
        networking.hostId = "deadbeef";
      }
    ];
  };

  defaultSystem = self.lib.mkServerVm baseArgs;

  biosSystem = self.lib.mkServerVm (
    baseArgs
    // {
      hostname = "server-vm-bios";
      bios = true;
    }
  );

  # Assertions encoded as a Nix list so a single failing check aborts eval
  # with a clear message — identical pattern to existing template tests.
  jsonOf = v: builtins.toJSON v;

  defaultConfig = defaultSystem.config;
  biosConfig = biosSystem.config;

  defaultChecks = [
    {
      name = "default: systemd-boot disabled";
      ok = defaultConfig.boot.loader.systemd-boot.enable == false;
      got = jsonOf defaultConfig.boot.loader.systemd-boot.enable;
      want = "false";
    }
    {
      name = "default: grub enabled";
      ok = defaultConfig.boot.loader.grub.enable == true;
      got = jsonOf defaultConfig.boot.loader.grub.enable;
      want = "true";
    }
    {
      name = "default: grub efiSupport on";
      ok = defaultConfig.boot.loader.grub.efiSupport == true;
      got = jsonOf defaultConfig.boot.loader.grub.efiSupport;
      want = "true";
    }
    {
      name = "default: grub efiInstallAsRemovable on";
      ok = defaultConfig.boot.loader.grub.efiInstallAsRemovable == true;
      got = jsonOf defaultConfig.boot.loader.grub.efiInstallAsRemovable;
      want = "true";
    }
    {
      name = "default: grub device == nodev";
      ok = defaultConfig.boot.loader.grub.device == "nodev";
      got = jsonOf defaultConfig.boot.loader.grub.device;
      want = "\"nodev\"";
    }
    {
      name = "default: secureBoot disabled";
      ok = defaultConfig.keystone.os.secureBoot.enable == false;
      got = jsonOf defaultConfig.keystone.os.secureBoot.enable;
      want = "false";
    }
    {
      name = "default: tpm disabled";
      ok = defaultConfig.keystone.os.tpm.enable == false;
      got = jsonOf defaultConfig.keystone.os.tpm.enable;
      want = "false";
    }
    {
      name = "default: storage.type == ext4";
      ok = defaultConfig.keystone.os.storage.type == "ext4";
      got = jsonOf defaultConfig.keystone.os.storage.type;
      want = "\"ext4\"";
    }
    {
      name = "default: lm_sensors NOT in systemPackages";
      ok =
        let
          pkgNames = builtins.map (p: p.pname or p.name or "") defaultConfig.environment.systemPackages;
        in
        !(builtins.elem "lm_sensors" pkgNames || builtins.elem "lm-sensors" pkgNames);
      got = "lm_sensors absent";
      want = "lm_sensors absent";
    }
  ];

  biosChecks = [
    {
      name = "bios: grub efiSupport off";
      ok = biosConfig.boot.loader.grub.efiSupport == false;
      got = jsonOf biosConfig.boot.loader.grub.efiSupport;
      want = "false";
    }
    {
      name = "bios: grub efiInstallAsRemovable off";
      ok = biosConfig.boot.loader.grub.efiInstallAsRemovable == false;
      got = jsonOf biosConfig.boot.loader.grub.efiInstallAsRemovable;
      want = "false";
    }
    {
      # NixOS option type for boot.loader.grub.device is `types.str` with
      # default "" (NOT nullOr str), so the plan's "device == null" assertion
      # is impossible — eval would reject `null` outright. We assert the
      # NixOS-default empty string instead, signalling "host must declare it."
      name = "bios: grub device unset (NixOS default \"\")";
      ok = biosConfig.boot.loader.grub.device == "";
      got = jsonOf biosConfig.boot.loader.grub.device;
      want = "\"\"";
    }
  ];

  allChecks = defaultChecks ++ biosChecks;

  failures = builtins.filter (c: !c.ok) allChecks;
  failureReport = lib.concatMapStringsSep "\n" (
    c: "  - ${c.name}: got=${c.got} want=${c.want}"
  ) failures;
  passReport = lib.concatMapStringsSep "\n" (c: "  - ${c.name}: OK") allChecks;
in
if failures != [ ] then
  throw ''
    server-vm-evaluation: ${toString (builtins.length failures)} assertion(s) failed:
    ${failureReport}
  ''
else
  pkgs.runCommand "test-server-vm-evaluation" { } ''
    mkdir -p $out
    cat > $out/server-vm-evaluation.json <<'ENDJSON'
    {
      "name": "server-vm-evaluation",
      "kind": "server-vm",
      "checks": ${toString (builtins.length allChecks)}
    }
    ENDJSON
    echo "server-vm-evaluation: ${toString (builtins.length allChecks)} checks passed"
    cat <<'EOF'
    ${passReport}
    EOF
  ''
