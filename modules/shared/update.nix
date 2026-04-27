# Keystone Update Channel
#
# Zero-dependency module declaring keystone.update.channel.
# Import this in every module layer (NixOS, home-manager) so the channel
# selection is available everywhere. Nix deduplicates identical imports.
#
# The channel selects which GitHub source the Walker update menu
# (ks menu update) tracks. It is surfaced to `ks` at runtime via the
# KS_UPDATE_CHANNEL environment variable.
{ lib, ... }:
{
  options.keystone.update = {
    channel = lib.mkOption {
      type = lib.types.enum [
        "stable"
        "unstable"
      ];
      default = "stable";
      description = ''
        Release source the Walker update menu tracks.

        - `stable` — latest tagged release `v<major>.<minor>.<patch>`.
          Uses the GitHub `/releases/latest` endpoint.
        - `unstable` — HEAD of `main` on GitHub — a moving commit SHA,
          not a tagged release. Uses the GitHub
          `/repos/OWNER/REPO/branches/main` endpoint and tracks the tip
          commit directly.

        Changing the channel requires a flake rebuild so the new value is
        threaded into the ks-update.service environment and the user shell.
      '';
    };
  };
}
