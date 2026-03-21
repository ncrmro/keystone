#!/usr/bin/env bash
set -euo pipefail

# Provision Forgejo user and API token for a normal user.
#
# Similar to provision-agent-git.sh but simplified: no repo creation,
# no SSH key provisioning, no admin collaborators. Focuses on ensuring
# the user exists and has a persistent API token for tea/fj CLI access.
#
# SECURITY: The persistent API token is scoped to the user (--username),
# not a global admin token. Each user gets their own token.
#
# Environment variables expected:
#   FORGEJO_USER: System user running Forgejo (e.g. forgejo)
#   STATE_DIR: Forgejo state directory
#   API_URL: Forgejo API URL
#   USERNAME: User's Forgejo username
#   EMAIL: User's email
#   SYSTEM_USER: OS username (for file ownership)
#   DOMAIN: Forgejo domain

FORGEJO="sudo -u ${FORGEJO_USER} forgejo --work-path ${STATE_DIR} admin"
API="${API_URL}"

# --- User provisioning (via CLI, no token needed) ---
if $FORGEJO user list 2>/dev/null | grep -q "^.*\b${USERNAME}\b"; then
  echo "${USERNAME}: Forgejo user already exists"
else
  echo "${USERNAME}: Creating Forgejo user..."
  RAND_PASS=$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 24)
  $FORGEJO user create \
    --username "${USERNAME}" \
    --email "${EMAIL}" \
    --password "$RAND_PASS" \
    --must-change-password=true
  echo "${USERNAME}: Forgejo user created (must change password on first login)"
fi

# --- Create short-lived provisioning token for API operations ---
TOKEN_NAME="provision-$(date +%s)"
TOKEN=$($FORGEJO user generate-access-token \
  --username "${USERNAME}" \
  --token-name "$TOKEN_NAME" \
  --scopes "write:user" \
  --raw 2>/dev/null || true)

if [ -z "$TOKEN" ]; then
  echo "${USERNAME}: Could not generate provisioning token, skipping API token setup"
  exit 0
fi
AUTH="Authorization: token $TOKEN"

# Cleanup function to delete the provisioning token when done
cleanup_token() {
  curl -sf -X DELETE -H "$AUTH" "$API/users/${USERNAME}/tokens/${TOKEN_NAME}" || true
}
trap cleanup_token EXIT

# --- Persistent API token for tea/fj CLI access ---
API_TOKEN_NAME="api-${SYSTEM_USER}"
EXISTING_API_TOKEN=$(curl -sf -H "$AUTH" "$API/users/${USERNAME}/tokens" \
  | jq -r --arg n "$API_TOKEN_NAME" '.[] | select(.name == $n) | .name' || true)

if [ -z "$EXISTING_API_TOKEN" ]; then
  echo "${USERNAME}: Generating persistent API token..."
  API_TOKEN=$($FORGEJO user generate-access-token \
    --username "${USERNAME}" \
    --token-name "$API_TOKEN_NAME" \
    --scopes "write:activitypub,write:issue,write:misc,write:notification,write:organization,write:package,write:repository,write:user" \
    --raw 2>/dev/null || true)

  if [ -n "$API_TOKEN" ]; then
    USER_HOME=$(eval echo "~${SYSTEM_USER}")

    # Write token into tea config
    TEA_FILE="$USER_HOME/.config/tea/config.yml"
    if [ -f "$TEA_FILE" ]; then
      API_TOKEN="$API_TOKEN" yq -i '.logins[0].token = strenv(API_TOKEN)' "$TEA_FILE"
      chown "${SYSTEM_USER}:users" "$TEA_FILE"
      chmod 0600 "$TEA_FILE"
      echo "${USERNAME}: Wrote API token to tea config"
    fi

    # Write token into fj keys.json (tagged enum format)
    FJ_FILE="$USER_HOME/.local/share/forgejo-cli/keys.json"
    if [ -f "$FJ_FILE" ]; then
      jq --arg host "${DOMAIN}" --arg token "$API_TOKEN" --arg name "$API_TOKEN_NAME" \
        '.hosts[$host] = {"type": "Application", "name": $name, "token": $token}' "$FJ_FILE" > "$FJ_FILE.tmp" \
        && mv "$FJ_FILE.tmp" "$FJ_FILE"
      chown "${SYSTEM_USER}:users" "$FJ_FILE"
      chmod 0600 "$FJ_FILE"
      echo "${USERNAME}: Wrote API token to fj config"
    fi
  else
    echo "${USERNAME}: Could not generate persistent API token"
  fi
else
  echo "${USERNAME}: Persistent API token already exists, skipping"
fi

echo "${USERNAME}: Forgejo provisioning complete"
