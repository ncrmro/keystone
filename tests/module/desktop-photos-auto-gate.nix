# Red/green gate for GitHub issue #399 (engineering #400) — auto-gate the
# Walker Photos entry on fleet Immich + user's api-key secret, and emit an
# eval-time warning with remediation steps when the fleet runs Immich but
# the secret is missing. Each assertion encodes one ISSUE-REQ from #400.
# Expected to fail on the base commit and pass once #400 lands.
{ pkgs }:
pkgs.runCommand "test-desktop-photos-auto-gate"
  {
    nativeBuildInputs = with pkgs; [ gnugrep ];
  }
  ''
    set -euo pipefail

    repo="${../..}"
    desktop_home="$repo/modules/desktop/home/default.nix"
    os_users="$repo/modules/os/users.nix"

    fail() {
      echo "FAIL: $1" >&2
      exit 1
    }

    # ISSUE-REQ-1, 5: the module must receive osConfig as an argument so the
    # default can read fleet-level and OS-level config. `osConfig ? null`
    # preserves standalone home-manager eval.
    if ! grep -F 'osConfig ? null' "$desktop_home" >/dev/null; then
      fail "ISSUE-REQ-1/5: modules/desktop/home/default.nix must accept 'osConfig ? null' as a module argument"
    fi

    # ISSUE-REQ-1: photos.enable default must read the fleet Immich host.
    # Using a multiline-friendly pattern since the default is an expression
    # block spanning several lines.
    if ! grep -E '"keystone"[[:space:]]+"services"[[:space:]]+"immich"[[:space:]]+"host"' "$desktop_home" >/dev/null \
      && ! grep -F 'keystone.services.immich.host' "$desktop_home" >/dev/null; then
      fail "ISSUE-REQ-1: photos.enable default must reference osConfig.keystone.services.immich.host"
    fi

    # ISSUE-REQ-1: photos.enable default must also require the user's
    # per-user Immich API key secret declaration.
    if ! grep -F -- '-immich-api-key' "$desktop_home" >/dev/null; then
      fail "ISSUE-REQ-1: photos.enable default must gate on the user's <username>-immich-api-key secret"
    fi
    if ! grep -E 'age[[:space:]]*\.?[[:space:]]*secrets|age"[[:space:]]+"secrets' "$desktop_home" >/dev/null; then
      fail "ISSUE-REQ-1: photos.enable default must read osConfig.age.secrets to detect the api-key secret"
    fi

    # ISSUE-REQ-3: agents.enable and contexts.enable defaults stay wired to
    # config.keystone.experimental. Regression guard — starts GREEN, must
    # stay GREEN after implementation.
    if ! grep -E 'agents\.enable = mkOption' "$desktop_home" >/dev/null; then
      fail "ISSUE-REQ-3: agents.enable option must remain declared in modules/desktop/home/default.nix"
    fi
    if ! grep -E 'contexts\.enable = mkOption' "$desktop_home" >/dev/null; then
      fail "ISSUE-REQ-3: contexts.enable option must remain declared in modules/desktop/home/default.nix"
    fi
    # Both options must keep their experimental default. Check by counting:
    # there must still be at least two `default = config.keystone.experimental`
    # occurrences (one for agents, one for contexts).
    experimental_defaults=$(grep -c 'default = config.keystone.experimental' "$desktop_home" || true)
    if [[ "$experimental_defaults" -lt 2 ]]; then
      fail "ISSUE-REQ-3: agents.enable and contexts.enable must keep default = config.keystone.experimental (found $experimental_defaults occurrences, expected >= 2)"
    fi

    # ISSUE-REQ-2: modules/os/users.nix must contain a Walker-Photos
    # warning block, mirroring the screenshotSync warning.
    if ! grep -F 'Walker Photos' "$os_users" >/dev/null; then
      fail "ISSUE-REQ-2: modules/os/users.nix must contain a 'Walker Photos' warning block"
    fi

    # ISSUE-REQ-2: the warning must name the per-user api-key secret by
    # referencing the Nix interpolation literal ''${username}-immich-api-key.
    if ! grep -F "\''${username}-immich-api-key" "$os_users" >/dev/null; then
      fail "ISSUE-REQ-2: the Walker Photos warning must reference the \$\{username\}-immich-api-key secret literal"
    fi

    # ISSUE-REQ-2: the warning must reference immichServiceCfg.host or
    # keystone.services.immich.host as the gate it fires under.
    if ! grep -E 'immichServiceCfg\.host|keystone\.services\.immich\.host' "$os_users" >/dev/null; then
      fail "ISSUE-REQ-2: the Walker Photos warning must guard on keystone.services.immich.host"
    fi

    # ISSUE-REQ-2: the warning must list all 3 remediation anchors.
    if ! grep -F "secrets/\''${username}-immich-api-key.age" "$os_users" >/dev/null; then
      fail "ISSUE-REQ-2: the Walker Photos warning must list the secrets.nix recipient step (secrets/\$\{username\}-immich-api-key.age)"
    fi
    if ! grep -F 'agenix -e secrets' "$os_users" >/dev/null; then
      fail "ISSUE-REQ-2: the Walker Photos warning must include the 'agenix -e secrets/...' remediation command"
    fi
    # The warning must include the age.secrets host declaration snippet.
    if ! grep -F "age.secrets.\''${username}-immich-api-key" "$os_users" >/dev/null; then
      fail "ISSUE-REQ-2: the Walker Photos warning must list the age.secrets.\$\{username\}-immich-api-key host declaration"
    fi

    touch "$out"
  ''
