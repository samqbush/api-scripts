#!/usr/bin/env bash

################################################################################
# Script: refresh_token.sh
# Description: Exchange a Strava refresh token for a new access token.
#
# Usage:
#   ./refresh_token.sh --refresh-token REFRESH \
#                      [--client-id 193221] [--client-secret YOUR_SECRET]
#
#   # Interactive prompts (omit arguments)
#   ./refresh_token.sh
#
# Arguments:
#   --client-id ID         Strava application Client ID (default: 193221)
#   --client-secret SECRET Strava application Client Secret
#   --refresh-token TOKEN  Strava refresh token
#   --help                 Show this help
#
# Output:
#   Prints access_token, refresh_token, and expiry. Does NOT store them.
################################################################################

set -e

CLIENT_ID="193221"
CLIENT_SECRET=""
REFRESH_TOKEN=""

# Load environment variables from .strava if present (keeps secrets out of the script)
if [[ -f "$(dirname "$0")/../.strava" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$(dirname "$0")/../.strava"
  set +a
fi

show_help() {
  sed -n '/^# Script:/,/^################################################################################$/p' "$0" | sed 's/^# //; s/^#//'
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --client-id)
      CLIENT_ID="$2"; shift 2 ;;
    --client-secret)
      CLIENT_SECRET="$2"; shift 2 ;;
    --refresh-token)
      REFRESH_TOKEN="$2"; shift 2 ;;
    --help)
      show_help; exit 0 ;;
    *)
      echo "Unknown option: $1"; show_help; exit 1 ;;
  esac
done

if [[ -z "$CLIENT_SECRET" ]]; then
  read -r -s -p "Enter Strava Client Secret: " CLIENT_SECRET
  echo ""
fi

if [[ -z "$REFRESH_TOKEN" ]]; then
  read -r -p "Enter Strava Refresh Token: " REFRESH_TOKEN
fi

echo "Refreshing token..."

RESPONSE=$(curl -s -X POST https://www.strava.com/oauth/token \
  -d client_id="${CLIENT_ID}" \
  -d client_secret="${CLIENT_SECRET}" \
  -d grant_type=refresh_token \
  -d refresh_token="${REFRESH_TOKEN}")

if echo "$RESPONSE" | jq -e 'has("access_token")' >/dev/null 2>&1; then
  ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r '.access_token')
  NEW_REFRESH_TOKEN=$(echo "$RESPONSE" | jq -r '.refresh_token')
  EXPIRES_AT=$(echo "$RESPONSE" | jq -r '.expires_at')

  if date --version >/dev/null 2>&1; then
    EXPIRES_HUMAN=$(date -d "@${EXPIRES_AT}" "+%Y-%m-%d %H:%M:%S")
  else
    EXPIRES_HUMAN=$(date -j -f "%s" "$EXPIRES_AT" "+%Y-%m-%d %H:%M:%S")
  fi

  echo "Success!"
  echo "Access Token:    ${ACCESS_TOKEN}"
  echo "Refresh Token:   ${NEW_REFRESH_TOKEN}"
  echo "Expires At:      ${EXPIRES_HUMAN} (epoch ${EXPIRES_AT})"
  echo ""
  echo "Use it now:"
  echo "  STRAVA_ACCESS_TOKEN=${ACCESS_TOKEN} ./strava/get_activities.sh"
else
  echo "Refresh failed. Response:" >&2
  echo "$RESPONSE" >&2
  exit 1
fi
