# Keystone Terminal Age-YubiKey Identity Management
#
# Manages age-plugin-yubikey identity files and provides `hwrekey` — a script
# that re-encrypts agenix secrets using YubiKey identity and optionally handles
# the full submodule commit/push/flake-update workflow.
#
# Requires `ykman` (yubikey-manager) for reliable YubiKey detection.
#
# ## Example Usage
#
# ```nix
# keystone.terminal.ageYubikey = {
#   enable = true;
#   identities = [
#     { serial = "36854515"; identity = "AGE-PLUGIN-YUBIKEY-17DDRYQ..."; }
#     { serial = "36862273"; identity = "AGE-PLUGIN-YUBIKEY-1G9UNYQ..."; }
#   ];
#   secretsFlakeInput = "agenix-secrets";  # optional: enables submodule workflow
# };
# ```
#
# ## hwrekey
#
# ```bash
# cd agenix-secrets && hwrekey   # rekey + commit + push + update flake input
# hwrekey                        # rekey in-place (no secretsFlakeInput set)
# ```
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.keystone.terminal.ageYubikey;

  # Generate identity file with serial comments so hwrekey can filter
  identityFileText = concatStringsSep "\n" (
    map (id: "# serial:${id.serial}\n${id.identity}") cfg.identities
  ) + "\n";

  hwrekeyScript = pkgs.writeShellScriptBin "hwrekey" ''
    set -euo pipefail

    IDENTITY_PATH="${cfg.identityPath}"
    SECRETS_FLAKE_INPUT="${toString cfg.secretsFlakeInput}"

    # --- Step 1: Detect connected YubiKey and select matching identity ---
    # age-plugin-yubikey errors (and disrupts pcscd state) when it tries to
    # open a YubiKey that isn't physically present. We detect connected serials
    # via ykman which reliably works across USB-A, USB-C, and hubs.
    if ! command -v ykman &>/dev/null; then
      echo "Error: ykman not found. Install yubikey-manager (keystone.hardwareKey.enable)."
      exit 1
    fi

    CONNECTED_SERIALS=$(ykman list --serials 2>/dev/null)
    if [ -z "$CONNECTED_SERIALS" ]; then
      echo "Error: No YubiKey detected. Plug one in and try again."
      exit 1
    fi

    TEMP_ID=$(mktemp)
    trap "rm -f $TEMP_ID" EXIT

    # Parse identity file: lines starting with "# serial:<N>" tag the next identity
    CURRENT_SERIAL=""
    MATCHED=false
    while IFS= read -r line; do
      if [[ "$line" =~ ^#\ serial: ]]; then
        CURRENT_SERIAL="''${line#\# serial:}"
        continue
      fi
      [[ -z "$line" || "$line" = \#* ]] && continue
      if [ -n "$CURRENT_SERIAL" ] && echo "$CONNECTED_SERIALS" | grep -q "$CURRENT_SERIAL"; then
        echo "$line" >> "$TEMP_ID"
        MATCHED=true
        echo "==> Using YubiKey serial $CURRENT_SERIAL"
      fi
      CURRENT_SERIAL=""
    done < "$IDENTITY_PATH"

    if [ "$MATCHED" = false ]; then
      echo "Error: Connected YubiKey(s) ($CONNECTED_SERIALS) don't match any configured identity."
      exit 1
    fi

    # --- Step 2: Rekey secrets ---
    # ykman's pcscd/CCID session may still be held when age-plugin-yubikey tries
    # to open the key. Retry with backoff since pcscd release timing varies.
    echo "==> Rekeying secrets with YubiKey identity..."
    MAX_ATTEMPTS=3
    for attempt in $(seq 1 $MAX_ATTEMPTS); do
      if agenix --rekey -i "$TEMP_ID"; then
        break
      fi
      if [ "$attempt" -eq "$MAX_ATTEMPTS" ]; then
        echo "Error: Failed to rekey after $MAX_ATTEMPTS attempts. Is pcscd stuck?"
        exit 1
      fi
      echo "==> YubiKey busy (pcscd contention), retrying in 3s... (attempt $attempt/$MAX_ATTEMPTS)"
      sleep 3
    done
    echo "==> Rekey complete."

    # If no flake input configured, we're done
    if [ -z "$SECRETS_FLAKE_INPUT" ]; then
      echo "No secretsFlakeInput configured. Done — commit manually."
      exit 0
    fi

    # --- Step 3: Commit and push in secrets submodule ---
    if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
      echo "==> Committing rekeyed secrets..."
      git add -A
      git commit -m "chore: rekey secrets"
      echo "==> Pushing secrets submodule..."
      git push
    else
      echo "==> No changes to commit in secrets submodule."
    fi

    # --- Step 4: Update parent flake input ---
    SUBMODULE_DIR="$(pwd)"
    PARENT_ROOT="$(git -C "$SUBMODULE_DIR" rev-parse --show-superproject-working-tree 2>/dev/null || true)"

    if [ -z "$PARENT_ROOT" ]; then
      echo "Warning: Not inside a submodule — skipping flake update."
      exit 0
    fi

    echo "==> Updating flake input '$SECRETS_FLAKE_INPUT' in parent repo..."
    cd "$PARENT_ROOT"
    nix flake update "$SECRETS_FLAKE_INPUT"

    # Compute relative submodule path for git add
    RELATIVE_SUBMODULE="$(realpath --relative-to="$PARENT_ROOT" "$SUBMODULE_DIR")"

    echo "==> Committing submodule + flake.lock in parent..."
    git add "$RELATIVE_SUBMODULE" flake.lock
    git commit -m "chore: update $SECRETS_FLAKE_INPUT (rekey)"

    echo "==> Done. Parent repo committed. Push when ready."
  '';
in
{
  options.keystone.terminal.ageYubikey = {
    enable = mkEnableOption "age-plugin-yubikey identity file management";

    identities = mkOption {
      type = types.listOf (types.submodule {
        options = {
          serial = mkOption {
            type = types.str;
            description = "YubiKey serial number (from `ykman info`)";
            example = "36854515";
          };
          identity = mkOption {
            type = types.str;
            description = "AGE-PLUGIN-YUBIKEY identity string (from `age-plugin-yubikey`)";
            example = "AGE-PLUGIN-YUBIKEY-17DDRYQ5ZFMHALWQJTKHAV";
          };
        };
      });
      default = [ ];
      description = ''
        Age-plugin-yubikey identities with serial numbers. Generate identity with:
          age-plugin-yubikey --identity
        Get serial with:
          ykman info
      '';
    };

    identityPath = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.age/yubikey-identity.txt";
      description = "Path where the combined identity file is written";
    };

    secretsFlakeInput = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Flake input name for the secrets submodule (e.g. "agenix-secrets").
        When set, hwrekey will commit+push the submodule and update the
        parent flake input. When null, hwrekey only runs agenix --rekey.
      '';
      example = "agenix-secrets";
    };
  };

  config = mkIf cfg.enable {
    home.file.".age/yubikey-identity.txt" = {
      text = identityFileText;
    };

    home.sessionVariables = {
      AGE_IDENTITIES_FILE = cfg.identityPath;
    };

    home.packages = [ hwrekeyScript ];
  };
}
