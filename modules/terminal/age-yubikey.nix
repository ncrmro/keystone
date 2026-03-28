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
# By default, hwrekey only re-encrypts secrets whose recipients changed
# (selective rekey). Use `--full` to force re-encryption of all secrets.
#
# ```bash
# hwrekey -m "chore: add ocean host key"     # selective rekey (default)
# hwrekey --full -m "chore: rekey all"       # force full rekey of all secrets
# cd agenix-secrets && hwrekey -m "msg"      # also works from inside submodule
# hwrekey                                    # rekey only (no secretsFlakeInput set)
# hwrekey -h                                 # show usage
# ```
#
# Also called by `agentctl <name> provision` to rekey after creating agent secrets.
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
  identityFileText =
    concatStringsSep "\n" (map (id: "# serial:${id.serial}\n${id.identity}") cfg.identities) + "\n";

  hwrekeyScript = pkgs.writeShellScriptBin "hwrekey" ''
    set -euo pipefail
    export PATH="${
      lib.makeBinPath [
        pkgs.jq
        pkgs.age
      ]
    }:$PATH"

    IDENTITY_PATH="${cfg.identityPath}"
    SECRETS_FLAKE_INPUT="${toString cfg.secretsFlakeInput}"
    CONFIG_REPO_PATH="${cfg.configRepoPath}"

    # --- Parse arguments ---
    COMMIT_MSG=""
    FULL_REKEY=false
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -m)
          shift
          if [[ $# -eq 0 ]]; then
            echo "Error: -m requires a message argument."
            exit 1
          fi
          COMMIT_MSG="$1"
          shift
          ;;
        --full)
          FULL_REKEY=true
          shift
          ;;
        -h|--help)
          echo "Usage: hwrekey [-m <message>] [--full] [-h|--help]"
          echo ""
          echo "Re-encrypt agenix secrets using the connected YubiKey."
          echo "By default, only secrets whose recipients changed are re-encrypted."
          echo ""
          echo "  --full        Force re-encryption of ALL secrets (delegates to agenix --rekey)."
          if [ -n "$SECRETS_FLAKE_INPUT" ]; then
            echo "  -m <message>  Commit message (required). Describes what changed in secrets."
            echo "                The submodule commit uses this message directly."
            echo "                The parent commit uses: chore($SECRETS_FLAKE_INPUT): relock flake input - <message>"
          else
            echo "  -m <message>  Not used (no secretsFlakeInput configured)."
          fi
          echo "  -h, --help    Show this help."
          echo ""
          echo "Config repo: $CONFIG_REPO_PATH"
          echo "Secrets dir: $CONFIG_REPO_PATH/$SECRETS_FLAKE_INPUT"
          exit 0
          ;;
        *)
          echo "Error: Unknown argument: $1"
          echo "Run 'hwrekey -h' for usage."
          exit 1
          ;;
      esac
    done

    # Require -m when secretsFlakeInput is set (commits need a message)
    if [ -n "$SECRETS_FLAKE_INPUT" ] && [ -z "$COMMIT_MSG" ]; then
      echo "Error: -m <message> is required."
      echo "  hwrekey -m \"chore: add ocean host key\""
      echo ""
      echo "Run 'hwrekey -h' for usage."
      exit 1
    fi

    # --- Derive secrets directory from configRepoPath ---
    if [ -n "$SECRETS_FLAKE_INPUT" ]; then
      SECRETS_DIR="$CONFIG_REPO_PATH/$SECRETS_FLAKE_INPUT"
      if [ ! -d "$SECRETS_DIR" ]; then
        echo "Error: Secrets directory not found: $SECRETS_DIR"
        echo "Check keystone.terminal.ageYubikey.configRepoPath ($CONFIG_REPO_PATH)"
        exit 1
      fi
      cd "$SECRETS_DIR"
      echo "==> Working in $SECRETS_DIR"
    fi

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
    TEMP_PLAIN=$(mktemp)
    trap "rm -f $TEMP_ID $TEMP_PLAIN" EXIT

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
    REKEYED_FILES=()
    HASHES_FILE=".recipients-hashes"

    # Attempt to evaluate secrets.nix for selective rekey
    if [ "$FULL_REKEY" != true ]; then
      if SECRETS_JSON=$(nix eval --file secrets.nix --json 2>/dev/null); then
        : # secrets.nix evaluated successfully, proceed with selective rekey
      else
        echo "Warning: Failed to evaluate secrets.nix, falling back to full rekey."
        FULL_REKEY=true
      fi
    fi

    if [ "$FULL_REKEY" = true ]; then
      # Full rekey: delegate to agenix --rekey (original behavior)
      echo "==> Full rekey: re-encrypting ALL secrets..."
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

      # Track all .age files as rekeyed
      while IFS= read -r f; do
        REKEYED_FILES+=("$f")
      done < <(find . -name '*.age' -type f | sed 's|^\./||')

      # Update recipient hashes after full rekey
      if [ -z "''${SECRETS_JSON:-}" ]; then
        SECRETS_JSON=$(nix eval --file secrets.nix --json 2>/dev/null) || true
      fi
      if [ -n "''${SECRETS_JSON:-}" ]; then
        NEW_HASHES="{}"
        while IFS= read -r key; do
          [ -z "$key" ] && continue
          hash=$(echo "$SECRETS_JSON" | jq -r --arg k "$key" '.[$k].publicKeys | sort | .[]' | sha256sum | cut -d' ' -f1)
          NEW_HASHES=$(echo "$NEW_HASHES" | jq --arg k "$key" --arg v "$hash" '. + {($k): $v}')
        done < <(echo "$SECRETS_JSON" | jq -r 'keys[]')
        echo "$NEW_HASHES" > "$HASHES_FILE"
      fi
    else
      # Selective rekey: only re-encrypt secrets whose recipients changed
      echo "==> Checking which secrets need re-encryption..."
      NEEDS_REKEY=()
      SKIPPED=()

      while IFS= read -r secret; do
        [ -z "$secret" ] && continue

        # Compute hash of sorted recipients for this secret
        expected_hash=$(echo "$SECRETS_JSON" | jq -r --arg s "$secret" '.[$s].publicKeys | sort | .[]' | sha256sum | cut -d' ' -f1)

        # Get stored hash (if hashes file exists)
        stored_hash=""
        if [ -f "$HASHES_FILE" ]; then
          stored_hash=$(jq -r --arg s "$secret" '.[$s] // ""' "$HASHES_FILE")
        fi

        # Skip if the .age file doesn't exist yet
        if [ ! -f "$secret" ]; then
          echo "  Skipping $secret (file does not exist yet)"
          continue
        fi

        if [ "$expected_hash" = "$stored_hash" ]; then
          SKIPPED+=("$secret")
        else
          NEEDS_REKEY+=("$secret")
        fi
      done < <(echo "$SECRETS_JSON" | jq -r 'keys[]')

      if [ ''${#NEEDS_REKEY[@]} -eq 0 ]; then
        echo "No secrets need rekeying."
      else
        echo "==> Re-encrypting ''${#NEEDS_REKEY[@]} secret(s)..."
        if [ ''${#SKIPPED[@]} -gt 0 ]; then
          echo "    (''${#SKIPPED[@]} secret(s) unchanged, skipped)"
        fi

        for secret in "''${NEEDS_REKEY[@]}"; do
          # Get recipients for this secret
          mapfile -t recipients < <(echo "$SECRETS_JSON" | jq -r --arg s "$secret" '.[$s].publicKeys[]')

          # Build age encrypt arguments
          AGE_ARGS=()
          for key in "''${recipients[@]}"; do
            AGE_ARGS+=(-r "$key")
          done

          # Decrypt and re-encrypt with retry for pcscd contention
          MAX_ATTEMPTS=3
          for attempt in $(seq 1 $MAX_ATTEMPTS); do
            if age --decrypt -i "$TEMP_ID" "$secret" > "$TEMP_PLAIN" 2>/dev/null; then
              age --encrypt "''${AGE_ARGS[@]}" -o "$secret" "$TEMP_PLAIN"
              REKEYED_FILES+=("$secret")
              echo "  Rekeyed: $secret"
              break
            fi
            if [ "$attempt" -eq "$MAX_ATTEMPTS" ]; then
              echo "Error: Failed to rekey $secret after $MAX_ATTEMPTS attempts."
              exit 1
            fi
            echo "  Retry $secret in 3s... ($attempt/$MAX_ATTEMPTS)"
            sleep 3
          done
        done
      fi

      # Update recipient hashes for all secrets
      NEW_HASHES="{}"
      while IFS= read -r key; do
        [ -z "$key" ] && continue
        hash=$(echo "$SECRETS_JSON" | jq -r --arg k "$key" '.[$k].publicKeys | sort | .[]' | sha256sum | cut -d' ' -f1)
        NEW_HASHES=$(echo "$NEW_HASHES" | jq --arg k "$key" --arg v "$hash" '. + {($k): $v}')
      done < <(echo "$SECRETS_JSON" | jq -r 'keys[]')
      echo "$NEW_HASHES" > "$HASHES_FILE"
    fi

    echo "==> Rekey complete."

    # If no flake input configured, we're done
    if [ -z "$SECRETS_FLAKE_INPUT" ]; then
      echo "No secretsFlakeInput configured. Done — commit manually."
      exit 0
    fi

    # --- Step 3: Commit and push in secrets submodule ---
    if [ "$FULL_REKEY" = true ]; then
      # Full rekey: stage everything (original behavior)
      if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
        echo "==> Committing rekeyed secrets..."
        git add -A
        git commit -m "$COMMIT_MSG"
        echo "==> Pushing secrets submodule..."
        git push
      else
        echo "==> No changes to commit in secrets submodule."
      fi
    else
      # Selective: stage only rekeyed .age files + secrets.nix + .recipients-hashes
      STAGED=false
      for f in "''${REKEYED_FILES[@]}"; do
        git add "$f" && STAGED=true
      done
      # Stage secrets.nix if it has changes
      if ! git diff --quiet -- secrets.nix 2>/dev/null; then
        git add secrets.nix && STAGED=true
      fi
      # Stage .recipients-hashes
      if [ -f "$HASHES_FILE" ]; then
        git add "$HASHES_FILE" && STAGED=true
      fi
      if [ "$STAGED" = true ] && ! git diff --cached --quiet; then
        echo "==> Committing rekeyed secrets..."
        git commit -m "$COMMIT_MSG"
        echo "==> Pushing secrets submodule..."
        git push
      else
        echo "==> No changes to commit in secrets submodule."
      fi
    fi

    # --- Step 4: Update parent flake input ---
    echo "==> Updating flake input '$SECRETS_FLAKE_INPUT' in parent repo..."
    cd "$CONFIG_REPO_PATH"
    nix flake update "$SECRETS_FLAKE_INPUT"

    echo "==> Committing flake.lock in parent..."
    git add flake.lock
    git commit -m "chore($SECRETS_FLAKE_INPUT): relock flake input - $COMMIT_MSG"

    echo "==> Done. Parent repo committed. Push when ready."
  '';
in
{
  options.keystone.terminal.ageYubikey = {
    enable = mkEnableOption "age-plugin-yubikey identity file management";

    identities = mkOption {
      type = types.listOf (
        types.submodule {
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
        }
      );
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

    configRepoPath = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/nixos-config";
      description = ''
        Absolute path to the NixOS config repo checkout. hwrekey derives the
        secrets submodule path as <configRepoPath>/<secretsFlakeInput> so it
        can run from any directory.
      '';
      example = "/home/user/code/nixos-config";
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
