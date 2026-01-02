#!/usr/bin/env bash

################################################################################
# Script: get_token.sh
# Description: Exchange a Strava OAuth authorization code for an access token
#              with activity:read/activity:read_all scopes.
#
# Usage:
#   ./get_token.sh --client-id 12345 --client-secret abc --code AUTH_CODE \
#                  [--redirect-uri http://localhost] [--write-env]
#
#   # Interactive prompts (omit arguments)
#   ./get_token.sh
#
# Arguments:
#   --client-id ID         Strava application Client ID (default: 193221)
#   --client-secret SECRET Strava application Client Secret
#   --code CODE            Authorization code from redirect URL
#   --redirect-uri URI     Redirect URI used in OAuth (default: http://localhost)
#   --write-env            Save tokens into ../.strava (creates/overwrites)
#   --help                 Show this help
#
# Output:
#   Prints access_token, refresh_token, and expiry. With --write-env, writes ../.strava
#   (backup to ../.strava.bak if it exists).
#
# Notes:
#   1) Generate the code by visiting:
#      https://www.strava.com/oauth/authorize?client_id=YOUR_CLIENT_ID&response_type=code&redirect_uri=http://localhost&approval_prompt=force&scope=activity:read_all
#      After authorizing, copy the 'code' query param from the URL.
#   2) Tokens expire ~6 hours; keep the refresh_token safe for renewals.
################################################################################

set -e

# Defaults
CLIENT_ID="193221"
CLIENT_SECRET=""
AUTH_CODE=""
REDIRECT_URI="http://localhost"
WRITE_ENV=false

show_help() {
  sed -n '/^# Script:/,/^################################################################################$/p' "$0" | sed 's/^# //; s/^#//'
}

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --client-id)
      CLIENT_ID="$2"; shift 2 ;;
    --client-secret)
      CLIENT_SECRET="$2"; shift 2 ;;
    --code)
      AUTH_CODE="$2"; shift 2 ;;
    --redirect-uri)
      REDIRECT_URI="$2"; shift 2 ;;
    --write-env)
      WRITE_ENV=true; shift 1 ;;
    --help)
      show_help; exit 0 ;;
    *)
      echo "Unknown option: $1"; show_help; exit 1 ;;
  esac
done

 # Prompt for missing values
if [[ -z "$CLIENT_ID" ]]; then
  read -r -p "Enter Strava Client ID [default 193221]: " CLIENT_ID
fi

if [[ -z "$CLIENT_SECRET" ]]; then
  read -r -s -p "Enter Strava Client Secret: " CLIENT_SECRET
  echo ""
fi

if [[ -z "$AUTH_CODE" ]]; then
  echo "Paste the authorization code from the redirect URL (after code=):"
  read -r AUTH_CODE
fi

auth_url="https://www.strava.com/oauth/authorize?client_id=${CLIENT_ID}&response_type=code&redirect_uri=${REDIRECT_URI}&approval_prompt=force&scope=activity:read_all"

echo ""
echo "If you still need a code, open this URL in your browser:" 
echo "  ${auth_url}"
echo ""

echo "Exchanging code for tokens..."

# Exchange code for tokens
RESPONSE=$(curl -s -X POST https://www.strava.com/oauth/token \
  -d client_id="${CLIENT_ID}" \
  -d client_secret="${CLIENT_SECRET}" \
  -d code="${AUTH_CODE}" \
  -d grant_type=authorization_code)

# Basic error check
if echo "$RESPONSE" | jq -e 'has("access_token")' >/dev/null 2>&1; then
  ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r '.access_token')
  REFRESH_TOKEN=$(echo "$RESPONSE" | jq -r '.refresh_token')
  EXPIRES_AT=$(echo "$RESPONSE" | jq -r '.expires_at')
  SCOPE=$(echo "$RESPONSE" | jq -r '.token_type + " " + (.athlete.id | tostring)')

  # Human-readable expiry
  if date --version >/dev/null 2>&1; then
    EXPIRES_HUMAN=$(date -d "@${EXPIRES_AT}" "+%Y-%m-%d %H:%M:%S")
  else
    EXPIRES_HUMAN=$(date -j -f "%s" "$EXPIRES_AT" "+%Y-%m-%d %H:%M:%S")
  fi

  echo "Success!"
  echo "Access Token:    ${ACCESS_TOKEN}"
  echo "Refresh Token:   ${REFRESH_TOKEN}"
  echo "Expires At:      ${EXPIRES_HUMAN} (epoch ${EXPIRES_AT})"
  echo ""
  echo "Use it now:"
  echo "  STRAVA_ACCESS_TOKEN=${ACCESS_TOKEN} ./strava/get_activities.sh"
  echo ""
else
  echo "Token exchange failed. Response:" >&2
  echo "$RESPONSE" >&2
  exit 1
fi

if [[ "$WRITE_ENV" == "true" ]]; then
  ENV_PATH="$(dirname "$0")/../.strava"
  if [[ -f "$ENV_PATH" ]]; then
    cp "$ENV_PATH" "${ENV_PATH}.bak"
  fi
  cat > "$ENV_PATH" <<EOF
STRAVA_CLIENT_ID=${CLIENT_ID}
STRAVA_CLIENT_SECRET=${CLIENT_SECRET}
STRAVA_ACCESS_TOKEN=${ACCESS_TOKEN}
STRAVA_REFRESH_TOKEN=${REFRESH_TOKEN}
EOF
  echo "Saved tokens to ${ENV_PATH} (backup at ${ENV_PATH}.bak if it existed)."
fi
