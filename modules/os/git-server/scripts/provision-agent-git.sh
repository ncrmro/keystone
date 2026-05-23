#!/usr/bin/env bash
set -euo pipefail

# Provision Forgejo user account and SSH key for an agent.
#
# Environment variables expected:
#   FORGEJO_USER: System user running Forgejo (e.g. forgejo)
#   STATE_DIR: Forgejo state directory
#   API_URL: Forgejo API URL
#   USERNAME: Agent's Forgejo username
#   EMAIL: Agent's email
#   AGENT_NAME: The identifier of the agent (e.g. drago)
#   AGENT_PUBKEY: (Optional) SSH public key for the agent
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
    --must-change-password=false
  echo "${USERNAME}: Forgejo user created"
fi

# --- Create short-lived admin token for API operations ---
TOKEN_NAME="provision-$(date +%s)"
TOKEN=$($FORGEJO user generate-access-token \
  --username "${USERNAME}" \
  --token-name "$TOKEN_NAME" \
  --scopes "write:user,write:repository" \
  --raw 2>/dev/null || true)

if [ -z "$TOKEN" ]; then
  echo "${USERNAME}: Could not generate API token, skipping SSH key provisioning"
  exit 0
fi
AUTH="Authorization: token $TOKEN"

# Cleanup function to delete the provisioning token when done
cleanup_token() {
  curl -sf -X DELETE -H "$AUTH" "$API/users/${USERNAME}/tokens/${TOKEN_NAME}" || true
}
trap cleanup_token EXIT

# --- SSH key provisioning ---
if [ -n "${AGENT_PUBKEY:-}" ]; then
  EXISTING_KEYS=$(curl -sf -H "$AUTH" "$API/users/${USERNAME}/keys" | jq length)
  if [ "$EXISTING_KEYS" -gt 0 ]; then
    echo "${USERNAME}: SSH key already registered, skipping"
  else
    echo "${USERNAME}: Adding SSH public key..."
    curl -sf -H "$AUTH" "$API/user/keys" \
      -H "Content-Type: application/json" \
      -d "$(jq -n \
        --arg title "agent-${AGENT_NAME}" \
        --arg key "${AGENT_PUBKEY}" \
        '{title: $title, key: $key}')"
    echo "${USERNAME}: SSH key added"
    echo "${USERNAME}: NOTE: To enable signed commit verification, verify the SSH key in Forgejo web UI: Settings → SSH/GPG Keys → Verify"
  fi
fi

# --- Persistent API token for tea/fj CLI access ---
API_TOKEN_NAME="api-agent-${AGENT_NAME}"
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
    AGENT_HOME=$(eval echo "~agent-${AGENT_NAME}")

    # Write token into tea config
    TEA_FILE="$AGENT_HOME/.config/tea/config.yml"
    if [ -f "$TEA_FILE" ]; then
      API_TOKEN="$API_TOKEN" yq -i '.logins[0].token = strenv(API_TOKEN)' "$TEA_FILE"
      chown "agent-${AGENT_NAME}:agents" "$TEA_FILE"
      chmod 0600 "$TEA_FILE"
      echo "${USERNAME}: Wrote API token to tea config"
    fi

    # Write token into fj keys.json (tagged enum format)
    FJ_FILE="$AGENT_HOME/.local/share/forgejo-cli/keys.json"
    if [ -f "$FJ_FILE" ]; then
      jq --arg host "${DOMAIN}" --arg token "$API_TOKEN" --arg name "$API_TOKEN_NAME" \
        '.hosts[$host] = {"type": "Application", "name": $name, "token": $token}' "$FJ_FILE" > "$FJ_FILE.tmp" \
        && mv "$FJ_FILE.tmp" "$FJ_FILE"
      chown "agent-${AGENT_NAME}:agents" "$FJ_FILE"
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
