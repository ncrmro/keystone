# Darwin module-surface evaluation.
#
# Linux-runnable assertions on the keystone Darwin module tree. Covers
# the cross-platform invariants from conventions/os.cross-platform-modules.md
# without instantiating a closure. The companion validate-darwin.yml on
# macos-14 handles `system.build.toplevel`.
#
# Build: nix build .#checks.x86_64-linux.darwin-evaluation
{
  pkgs,
  lib,
  self,
}:
let
  inherit (self.lib.tests) admin evalDarwin;

  base = {
    keystone.os = {
      enable = true;
      adminUsername = admin.username;
    };
    age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  enableToken = {
    keystone.os.githubTokenNix.enable = true;
  };
  withToken = name: {
    keystone.os.githubTokenNix = {
      enable = true;
      tokenFile = "/run/agenix/${name}";
    };
  };

  cfg = modules: (evalDarwin { modules = [ base ] ++ modules; }).config;
  countFailing = c: builtins.length (builtins.filter (a: !a.assertion) c.assertions);

  default = cfg [ enableToken ];
  hostScoped = cfg [ (withToken "test-darwin-nix-flake-github-token") ];
  invalid = cfg [ (withToken "totally-wrong-name") ];
in
pkgs.runCommand "darwin-evaluation" { } ''
  set -eu
  fail() { echo "FAIL: $*" >&2; exit 1; }

  # adminUsername round-trips from the shared admin fixture
  [ ${
    lib.escapeShellArg (cfg [ ]).keystone.os.adminUsername
  } = ${lib.escapeShellArg admin.username} ] \
    || fail "adminUsername round-trip"

  # keystone.os.githubTokenNix.enable emits the Darwin launchd daemon
  echo ${lib.escapeShellArg (lib.concatStringsSep " " (builtins.attrNames default.launchd.daemons))} \
    | grep -qw nix-github-access-token \
    || fail "launchd.daemons.nix-github-access-token missing"

  # `!include` directive lands in nix.extraOptions so the daemon's output is consumed
  echo ${lib.escapeShellArg default.nix.extraOptions} \
    | grep -qF '!include /etc/nix/access-tokens.conf' \
    || fail "nix.extraOptions missing !include"

  # Default tokenFile matches the portable naming convention
  [ ${lib.escapeShellArg default.keystone.os.githubTokenNix.tokenFile} = /run/agenix/nix-flake-github-token ] \
    || fail "default tokenFile mismatch"

  # Host-scoped name validates; invalid name trips the assertion guard
  [ ${toString (countFailing hostScoped)} = 0 ] || fail "host-scoped basename rejected"
  [ ${toString (countFailing invalid)} != 0 ]   || fail "invalid basename accepted"

  mkdir -p $out && touch $out/ok
''
