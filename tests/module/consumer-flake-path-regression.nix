{ pkgs }:
# Regression gate for the canonical consumer-flake path convention
# (`conventions/architecture.consumer-flake-path.md`, issue #461).
#
# Several reverted PRs reintroduced pointer-file resolution because it
# matches NixOS training-corpus patterns. This check fails the build if any
# banned token appears in source — so the next agent that reaches for one
# gets a structural reason to stop, not a code review afterthought.
#
# CRITICAL: this check looks at the keystone source tree itself. Excluding
# `conventions/` and `flake.nix` lets the convention document the banned
# pattern and lets this check itself name the patterns it greps for. Any
# new exception MUST be carved out here with an explicit `--glob` and a
# comment explaining why it's safe.
let
  bannedPatterns = [
    "/run/current-system/keystone-system-flake"
    "keystone-current-system-flake"
    "KEYSTONE_SYSTEM_FLAKE"
    "KEYSTONE_CONFIG_REPO"
    "keystone\\.systemFlake"
  ];
  pattern = pkgs.lib.concatStringsSep "|" bannedPatterns;
  source = ../..;
in
pkgs.runCommand "consumer-flake-path-regression"
  {
    nativeBuildInputs = [ pkgs.ripgrep ];
    src = source;
    inherit pattern;
  }
  ''
    set -euo pipefail

    # Run rg against a writable copy of the source tree. Nix store inputs
    # are read-only and rg's --files-without-match does not need write
    # access, but the runCommand sandbox treats the symlinked input
    # identically — copying keeps things obvious and avoids surprises if
    # rg ever needs scratch space.
    cp -r "$src" "$TMPDIR/src"
    cd "$TMPDIR/src"

    # The conventions directory documents the banned tokens; the check
    # itself spells them out in the bannedPatterns list and would
    # self-trigger if scanned. Both are excluded by design.
    #
    # --hidden is required so the gate sees regressions in dotted
    # directories like .deepwork/, .github/, and .claude/ that have
    # historically contained the banned tokens. Git metadata is
    # explicitly excluded because rg with --no-ignore-vcs would
    # otherwise descend into .git/ if it were ever copied into the
    # source tree.
    if rg --no-ignore-vcs \
          --hidden \
          --glob '!.git/**' \
          --glob '!conventions/**' \
          --glob '!flake.nix' \
          --glob '!tests/module/consumer-flake-path-regression.nix' \
          "$pattern" \
          .
    then
      echo "" >&2
      echo "consumer-flake-path-regression FAILED" >&2
      echo "" >&2
      echo "One or more banned tokens reappeared in the keystone source." >&2
      echo "The consumer-flake path is a deterministic function of \$USER" >&2
      echo "and \$HOME — see conventions/architecture.consumer-flake-path.md." >&2
      echo "" >&2
      echo "Banned tokens:" >&2
      printf '  - %s\n' \
        '/run/current-system/keystone-system-flake' \
        'keystone-current-system-flake' \
        'KEYSTONE_SYSTEM_FLAKE (any variant)' \
        'KEYSTONE_CONFIG_REPO' \
        'keystone.systemFlake' >&2
      exit 1
    fi

    touch "$out"
  ''
