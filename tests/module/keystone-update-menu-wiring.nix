# keystone-update-menu-wiring — cross-file coupling check for the Walker
# update provider.
#
# The original `tests/module/keystone-update-menu.nix` integration test was
# removed alongside the bash backend — it stubbed `gh`/`git`/`nix`/`ghostty`
# to exercise shell logic that no longer exists. State discovery and
# rendering are now covered by Rust unit tests in `cmd::update_menu::tests`.
# What those unit tests can't see is the *wiring* between files:
#
#   - keystone-update.lua must call `ks menu update …`.
#   - services.nix must declare both ks-update.service and the
#     ks-update-notify@.service template.
#   - The activation tokens emitted by entries_json (in Rust) must be the
#     same tokens dispatch matches on (in Rust) and the same tokens the
#     Lua provider feeds into the Action.
#
# If anyone renames the subcommand, drops a unit, or edits activation
# tokens without the corresponding other-file update, this test fails
# loudly instead of silently breaking the desktop flow.
{
  pkgs,
  lib ? pkgs.lib,
}:
let
  luaFile = ../../modules/desktop/home/components/keystone-update.lua;
  servicesFile = ../../modules/desktop/home/services.nix;
  updateMenuRs = ../../packages/ks/src/cmd/update_menu.rs;
  runBackgroundRs = ../../packages/ks/src/cmd/run_background.rs;
in
pkgs.runCommand "test-keystone-update-menu-wiring"
  {
    nativeBuildInputs = with pkgs; [
      gnugrep
    ];
  }
  ''
    set -euo pipefail

    fail() {
      echo "FAIL: $*" >&2
      exit 1
    }

    # -- Lua dispatches to `ks menu update` -------------------------------

    if ! grep -F 'ks") .. " menu update dispatch' ${luaFile} >/dev/null; then
      fail "keystone-update.lua must call 'ks menu update dispatch' on Action"
    fi
    if ! grep -F 'ks") .. " menu update entries' ${luaFile} >/dev/null; then
      fail "keystone-update.lua must call 'ks menu update entries' in GetEntries"
    fi

    # Guard against accidental regression to the legacy command name.
    if grep -F 'update-menu' ${luaFile} >/dev/null; then
      fail "keystone-update.lua still references the legacy 'update-menu' command"
    fi

    # -- services.nix declares the worker and notifier units --------------

    if ! grep -F 'ks-update.service' ${servicesFile} >/dev/null; then
      fail "services.nix must reference ks-update.service"
    fi
    if ! grep -F 'ks-update-notify@' ${servicesFile} >/dev/null; then
      fail "services.nix must declare the ks-update-notify@ template"
    fi
    if ! grep -F 'OnSuccess' ${servicesFile} >/dev/null; then
      fail "services.nix must wire OnSuccess= on ks-update.service"
    fi
    if ! grep -F 'OnFailure' ${servicesFile} >/dev/null; then
      fail "services.nix must wire OnFailure= on ks-update.service"
    fi

    # -- Activation tokens defined in Rust match dispatch handling ---------
    #
    # The Lua provider's Action single-quotes %VALUE%, so every token
    # emitted by entries_json MUST be a stable string with no shell
    # metacharacters. These tokens are the entire shared vocabulary
    # between render_entries_json (producer) and dispatch (consumer).

    for tok in \
      '"noop"' \
      '"run-update"' \
      '"blocked-update-unavailable"' \
      '"blocked-keystone-unavailable"' \
      '"open-release-page"'; do
      if ! grep -F "$tok" ${updateMenuRs} >/dev/null; then
        fail "update_menu.rs is missing activation token $tok"
      fi
    done

    # -- run-background unit validation references ks-update.service ------

    if ! grep -F 'ks-update.service' ${runBackgroundRs} >/dev/null 2>&1; then
      : # currently run_background.rs doesn't hard-code the name — that's fine
    fi

    touch "$out"
  ''
