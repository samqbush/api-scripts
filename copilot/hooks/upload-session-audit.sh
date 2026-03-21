#!/usr/bin/env bash
set -euo pipefail

# upload-session-audit.sh
#
# Extracts the most recent Copilot CLI session from the local session store
# and uploads the full conversation payload to a configurable destination.
#
# Usage:
#   Copy this script and hooks.json into your repo's .github/hooks/ directory.
#   Set COPILOT_AUDIT_DEST to choose where audit data is sent.
#
# Destinations (via COPILOT_AUDIT_DEST env var):
#   file     - Write JSON to local audit log directory (default)
#   http     - POST to a generic HTTP/REST endpoint
#   datadog  - Send to Datadog Logs API
#   splunk   - Send to Splunk HTTP Event Collector (HEC)
#   s3       - Upload to an AWS S3 bucket
#
# Environment Variables:
#   COPILOT_AUDIT_DEST          - Destination type (default: "file")
#   COPILOT_AUDIT_DIR           - Local file output dir (default: ~/.copilot/audit-logs)
#   COPILOT_AUDIT_URL           - HTTP endpoint URL (required for http dest)
#   COPILOT_AUDIT_AUTH_HEADER   - HTTP Authorization header value (optional)
#   DD_API_KEY                  - Datadog API key (required for datadog dest)
#   DD_SITE                     - Datadog site (default: datadoghq.com)
#   DD_ENV                      - Datadog environment tag (default: dev)
#   SPLUNK_HEC_URL              - Splunk HEC endpoint (required for splunk dest)
#   SPLUNK_HEC_TOKEN            - Splunk HEC token (required for splunk dest)
#   COPILOT_AUDIT_S3_BUCKET     - S3 bucket name (required for s3 dest)
#   COPILOT_AUDIT_S3_PREFIX     - S3 key prefix (default: copilot-audit)
#   COPILOT_HOME                - Copilot config directory (default: ~/.copilot)

COPILOT_HOME="${COPILOT_HOME:-$HOME/.copilot}"
SESSION_DB="${COPILOT_HOME}/session-store.db"
AUDIT_DEST="${COPILOT_AUDIT_DEST:-file}"
AUDIT_DIR="${COPILOT_AUDIT_DIR:-$COPILOT_HOME/audit-logs}"

# Read hook input from stdin (sessionEnd provides timestamp, cwd, reason)
HOOK_INPUT=$(cat)
END_REASON=$(echo "$HOOK_INPUT" | jq -r '.reason // "unknown"')

# --- Dependency checks ---
for cmd in sqlite3 jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "⚠️  Audit upload skipped: '$cmd' not found" >&2
    exit 0
  fi
done

if [[ ! -f "$SESSION_DB" ]]; then
  echo "⚠️  Audit upload skipped: session store not found at $SESSION_DB" >&2
  exit 0
fi

# --- Extract session data from the local SQLite store ---

# Get the most recently updated session (the one that just ended)
SESSION_ROW=$(sqlite3 -json "$SESSION_DB" \
  "SELECT id, cwd, repository, branch, summary, host_type, created_at, updated_at
   FROM sessions ORDER BY updated_at DESC LIMIT 1;" 2>/dev/null)

if [[ -z "$SESSION_ROW" || "$SESSION_ROW" == "[]" ]]; then
  echo "⚠️  Audit upload skipped: no sessions found in store" >&2
  exit 0
fi

SESSION_ID=$(echo "$SESSION_ROW" | jq -r '.[0].id')

# Extract conversation turns (sqlite3 -json returns empty string for 0 rows)
TURNS=$(sqlite3 -json "$SESSION_DB" \
  "SELECT turn_index, user_message, assistant_response, timestamp
   FROM turns WHERE session_id = '$SESSION_ID'
   ORDER BY turn_index;" 2>/dev/null)
[[ -z "$TURNS" ]] && TURNS="[]"

# Extract checkpoints
CHECKPOINTS=$(sqlite3 -json "$SESSION_DB" \
  "SELECT checkpoint_number, title, overview
   FROM checkpoints WHERE session_id = '$SESSION_ID'
   ORDER BY checkpoint_number;" 2>/dev/null)
[[ -z "$CHECKPOINTS" ]] && CHECKPOINTS="[]"

TURN_COUNT=$(echo "$TURNS" | jq 'length')

# --- Build the standardized audit payload ---
PAYLOAD=$(jq -n \
  --arg schema_version "1.0" \
  --arg session_id "$SESSION_ID" \
  --arg repository "$(echo "$SESSION_ROW" | jq -r '.[0].repository // empty')" \
  --arg branch "$(echo "$SESSION_ROW" | jq -r '.[0].branch // empty')" \
  --arg cwd "$(echo "$SESSION_ROW" | jq -r '.[0].cwd // empty')" \
  --arg user "${USER:-unknown}" \
  --arg host_type "$(echo "$SESSION_ROW" | jq -r '.[0].host_type // "cli"')" \
  --arg summary "$(echo "$SESSION_ROW" | jq -r '.[0].summary // empty')" \
  --arg started_at "$(echo "$SESSION_ROW" | jq -r '.[0].created_at // empty')" \
  --arg ended_at "$(echo "$SESSION_ROW" | jq -r '.[0].updated_at // empty')" \
  --arg end_reason "$END_REASON" \
  --argjson turn_count "$TURN_COUNT" \
  --argjson turns "$TURNS" \
  --argjson checkpoints "$CHECKPOINTS" \
  '{
    schemaVersion: $schema_version,
    sessionId: $session_id,
    repository: $repository,
    branch: $branch,
    cwd: $cwd,
    user: $user,
    hostType: $host_type,
    summary: $summary,
    startedAt: $started_at,
    endedAt: $ended_at,
    endReason: $end_reason,
    turnCount: $turn_count,
    turns: $turns,
    checkpoints: $checkpoints
  }')

# --- Destination handlers ---

upload_to_file() {
  mkdir -p "$AUDIT_DIR"
  local filename="${AUDIT_DIR}/session-${SESSION_ID}.json"
  echo "$PAYLOAD" > "$filename"
  echo "✅ Audit log saved to $filename"
}

upload_to_http() {
  local url="${COPILOT_AUDIT_URL:?COPILOT_AUDIT_URL is required when COPILOT_AUDIT_DEST=http}"
  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$url" \
    -H "Content-Type: application/json" \
    ${COPILOT_AUDIT_AUTH_HEADER:+-H "Authorization: $COPILOT_AUDIT_AUTH_HEADER"} \
    -d "$PAYLOAD" \
    --max-time 30)

  if [[ "$status" -ge 200 && "$status" -lt 300 ]]; then
    echo "✅ Audit log uploaded to HTTP endpoint (HTTP $status)"
  else
    echo "⚠️  Audit upload failed: HTTP $status" >&2
  fi
}

upload_to_datadog() {
  local api_key="${DD_API_KEY:?DD_API_KEY is required when COPILOT_AUDIT_DEST=datadog}"
  local site="${DD_SITE:-datadoghq.com}"
  local url="https://http-intake.logs.${site}/api/v2/logs"

  local dd_payload
  dd_payload=$(jq -n \
    --arg ddsource "copilot-cli" \
    --arg ddtags "env:${DD_ENV:-dev},service:copilot-cli" \
    --arg hostname "$(hostname)" \
    --arg service "copilot-cli" \
    --argjson message "$PAYLOAD" \
    '[{
      ddsource: $ddsource,
      ddtags: $ddtags,
      hostname: $hostname,
      service: $service,
      message: $message
    }]')

  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$url" \
    -H "Content-Type: application/json" \
    -H "DD-API-KEY: $api_key" \
    -d "$dd_payload" \
    --max-time 30)

  if [[ "$status" -ge 200 && "$status" -lt 300 ]]; then
    echo "✅ Audit log sent to Datadog (HTTP $status)"
  else
    echo "⚠️  Datadog upload failed: HTTP $status" >&2
  fi
}

upload_to_splunk() {
  local hec_url="${SPLUNK_HEC_URL:?SPLUNK_HEC_URL is required when COPILOT_AUDIT_DEST=splunk}"
  local hec_token="${SPLUNK_HEC_TOKEN:?SPLUNK_HEC_TOKEN is required when COPILOT_AUDIT_DEST=splunk}"

  local splunk_payload
  splunk_payload=$(jq -n \
    --arg sourcetype "copilot:session" \
    --arg source "copilot-cli" \
    --argjson event "$PAYLOAD" \
    '{
      sourcetype: $sourcetype,
      source: $source,
      event: $event
    }')

  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$hec_url" \
    -H "Authorization: Splunk $hec_token" \
    -H "Content-Type: application/json" \
    -d "$splunk_payload" \
    --max-time 30)

  if [[ "$status" -ge 200 && "$status" -lt 300 ]]; then
    echo "✅ Audit log sent to Splunk HEC (HTTP $status)"
  else
    echo "⚠️  Splunk upload failed: HTTP $status" >&2
  fi
}

upload_to_s3() {
  local bucket="${COPILOT_AUDIT_S3_BUCKET:?COPILOT_AUDIT_S3_BUCKET is required when COPILOT_AUDIT_DEST=s3}"
  local prefix="${COPILOT_AUDIT_S3_PREFIX:-copilot-audit}"
  local key="${prefix}/$(date +%Y/%m/%d)/session-${SESSION_ID}.json"

  if ! command -v aws &>/dev/null; then
    echo "⚠️  Audit upload skipped: 'aws' CLI not found" >&2
    exit 0
  fi

  echo "$PAYLOAD" | aws s3 cp - "s3://${bucket}/${key}" \
    --content-type "application/json" \
    --quiet

  echo "✅ Audit log uploaded to s3://${bucket}/${key}"
}

# --- Route to the configured destination ---
case "$AUDIT_DEST" in
  file)    upload_to_file ;;
  http)    upload_to_http ;;
  datadog) upload_to_datadog ;;
  splunk)  upload_to_splunk ;;
  s3)      upload_to_s3 ;;
  *)
    echo "⚠️  Unknown COPILOT_AUDIT_DEST='$AUDIT_DEST'. Valid: file, http, datadog, splunk, s3" >&2
    exit 1
    ;;
esac
