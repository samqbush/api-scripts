#!/usr/bin/env bash

# copilot_usage_dashboard.sh
#
# Usage:
#   gh auth login  # One-time authentication setup
#   ./copilot/copilot_usage_dashboard.sh --enterprise ENTERPRISE [OPTIONS]
#   ./copilot/copilot_usage_dashboard.sh --org ORGANIZATION [OPTIONS]
#
# Description:
#   Fetches GitHub Copilot usage metrics via the REST API and displays a
#   terminal dashboard with key adoption, engagement, and code-generation
#   statistics.  Supports enterprise-level and organization-level scopes as
#   well as optional user-level detail.
#
#   By default the script retrieves the latest 28-day aggregate report.
#   Pass --day YYYY-MM-DD to request a single-day report instead.
#
# API Reference:
#   https://docs.github.com/en/enterprise-cloud@latest/rest/copilot/copilot-usage-metrics
#
# Examples:
#   # Enterprise 28-day dashboard
#   ./copilot/copilot_usage_dashboard.sh --enterprise my-enterprise
#
#   # Organization single-day report with CSV export
#   ./copilot/copilot_usage_dashboard.sh --org my-org --day 2025-07-01 --csv
#
#   # Enterprise report with user-level detail, all export formats
#   ./copilot/copilot_usage_dashboard.sh --enterprise my-ent --users --csv --json --markdown
#
#   # Test mode — no API calls, uses sample data
#   ./copilot/copilot_usage_dashboard.sh --enterprise demo --test-mode
#
# Requirements:
#   - GitHub CLI (gh) installed and authenticated (gh auth login)
#   - jq must be installed
#   - curl must be installed
#
# Arguments:
#   --enterprise SLUG  Enterprise slug (mutually exclusive with --org)
#   --org NAME         Organization name (mutually exclusive with --enterprise)
#   --day YYYY-MM-DD   Fetch a single-day report instead of the 28-day aggregate
#   --users            Also fetch user-level metrics
#   --out DIRECTORY    Output directory (default: copilot_metrics_TIMESTAMP)
#   --csv              Export metrics as CSV
#   --json             Export raw downloaded report data as JSON
#   --markdown         Generate a Markdown summary report
#   --test-mode        Use sample data without making API calls
#   --debug            Enable verbose debug output
#   --help, -h         Show this help message

set -euo pipefail

###############################################################################
# Constants
###############################################################################
SCRIPT_NAME="copilot_usage_dashboard.sh"
VERSION="1.0.0"
API_VERSION="2026-03-10"

###############################################################################
# Default option values
###############################################################################
ENTERPRISE=""
ORG=""
DAY=""
FETCH_USERS=false
OUT_DIR=""
GENERATE_CSV=false
GENERATE_JSON=false
GENERATE_MARKDOWN=false
TEST_MODE=false
DEBUG=false

###############################################################################
# Colors
###############################################################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

###############################################################################
# Logging helpers
###############################################################################
log()   { echo -e "${BLUE}[INFO]${NC} $*" >&2; }
debug() { if $DEBUG; then echo -e "${DIM}[DEBUG]${NC} $*" >&2; fi; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

###############################################################################
# Usage / Help
###############################################################################
usage() {
  sed -n '3,/^[^#]/s/^# \{0,1\}//p' "$0"
  exit 0
}

###############################################################################
# Argument parsing
###############################################################################
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --enterprise) ENTERPRISE="$2"; shift 2 ;;
      --org)        ORG="$2";        shift 2 ;;
      --day)        DAY="$2";        shift 2 ;;
      --users)      FETCH_USERS=true; shift ;;
      --out)        OUT_DIR="$2";    shift 2 ;;
      --csv)        GENERATE_CSV=true;      shift ;;
      --json)       GENERATE_JSON=true;     shift ;;
      --markdown)   GENERATE_MARKDOWN=true; shift ;;
      --test-mode)  TEST_MODE=true;  shift ;;
      --debug)      DEBUG=true;      shift ;;
      --help|-h)    usage ;;
      *)            error "Unknown argument: $1"; usage ;;
    esac
  done

  # Validate: must supply exactly one of --enterprise / --org
  if [ -z "$ENTERPRISE" ] && [ -z "$ORG" ]; then
    error "You must provide --enterprise SLUG or --org NAME."
    exit 1
  fi
  if [ -n "$ENTERPRISE" ] && [ -n "$ORG" ]; then
    error "--enterprise and --org are mutually exclusive."
    exit 1
  fi

  # Validate --day format
  if [ -n "$DAY" ]; then
    if ! echo "$DAY" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
      error "--day must be in YYYY-MM-DD format."
      exit 1
    fi
  fi

  # Default output directory
  if [ -z "$OUT_DIR" ]; then
    OUT_DIR="copilot_metrics_$(date +%Y%m%d_%H%M%S)"
  fi
}

###############################################################################
# Dependency checks
###############################################################################
check_deps() {
  local missing=0
  for cmd in gh jq curl; do
    if ! command -v "$cmd" &>/dev/null; then
      error "$cmd is required but not installed."
      missing=1
    fi
  done
  if [ "$missing" -eq 1 ]; then
    exit 1
  fi
}

###############################################################################
# Sample / test data generators
###############################################################################
generate_sample_enterprise_data() {
  cat <<'SAMPLE_EOF'
[{
  "day_totals": [
    {
      "day": "2025-07-28",
      "enterprise_id": "1",
      "daily_active_users": 142,
      "weekly_active_users": 312,
      "monthly_active_users": 485,
      "monthly_active_chat_users": 320,
      "monthly_active_agent_users": 95,
      "code_generation_activity_count": 4820,
      "code_acceptance_activity_count": 3615,
      "user_initiated_interaction_count": 1890,
      "loc_suggested_to_add_sum": 28400,
      "loc_suggested_to_delete_sum": 0,
      "loc_added_sum": 21300,
      "loc_deleted_sum": 3200,
      "daily_active_cli_users": 18,
      "pull_requests": {
        "total_created": 87,
        "total_reviewed": 64,
        "total_merged": 52,
        "median_minutes_to_merge": 145.5,
        "total_suggestions": 38,
        "total_applied_suggestions": 22,
        "total_created_by_copilot": 12,
        "total_reviewed_by_copilot": 31,
        "total_merged_created_by_copilot": 8,
        "median_minutes_to_merge_copilot_authored": 98.0,
        "total_copilot_suggestions": 24,
        "total_copilot_applied_suggestions": 18
      },
      "totals_by_ide": [
        {"ide": "vscode", "code_generation_activity_count": 3200, "code_acceptance_activity_count": 2400, "loc_added_sum": 14200, "loc_deleted_sum": 2100, "loc_suggested_to_add_sum": 18900, "loc_suggested_to_delete_sum": 0, "user_initiated_interaction_count": 1200},
        {"ide": "jetbrains", "code_generation_activity_count": 1120, "code_acceptance_activity_count": 840, "loc_added_sum": 5100, "loc_deleted_sum": 800, "loc_suggested_to_add_sum": 6800, "loc_suggested_to_delete_sum": 0, "user_initiated_interaction_count": 490},
        {"ide": "neovim", "code_generation_activity_count": 500, "code_acceptance_activity_count": 375, "loc_added_sum": 2000, "loc_deleted_sum": 300, "loc_suggested_to_add_sum": 2700, "loc_suggested_to_delete_sum": 0, "user_initiated_interaction_count": 200}
      ],
      "totals_by_feature": [
        {"feature": "code_completion", "code_generation_activity_count": 3400, "code_acceptance_activity_count": 2890, "loc_added_sum": 15800, "loc_deleted_sum": 0, "loc_suggested_to_add_sum": 20900, "loc_suggested_to_delete_sum": 0, "user_initiated_interaction_count": 0},
        {"feature": "chat_panel", "code_generation_activity_count": 980, "code_acceptance_activity_count": 500, "loc_added_sum": 3800, "loc_deleted_sum": 1200, "loc_suggested_to_add_sum": 5200, "loc_suggested_to_delete_sum": 0, "user_initiated_interaction_count": 1400},
        {"feature": "inline_chat", "code_generation_activity_count": 440, "code_acceptance_activity_count": 225, "loc_added_sum": 1700, "loc_deleted_sum": 2000, "loc_suggested_to_add_sum": 2300, "loc_suggested_to_delete_sum": 0, "user_initiated_interaction_count": 490}
      ],
      "totals_by_language_feature": [
        {"language": "python", "feature": "code_completion", "code_generation_activity_count": 1200, "code_acceptance_activity_count": 1020, "loc_added_sum": 5600, "loc_deleted_sum": 0, "loc_suggested_to_add_sum": 7400, "loc_suggested_to_delete_sum": 0},
        {"language": "typescript", "feature": "code_completion", "code_generation_activity_count": 900, "code_acceptance_activity_count": 765, "loc_added_sum": 4200, "loc_deleted_sum": 0, "loc_suggested_to_add_sum": 5500, "loc_suggested_to_delete_sum": 0},
        {"language": "javascript", "feature": "code_completion", "code_generation_activity_count": 680, "code_acceptance_activity_count": 578, "loc_added_sum": 3100, "loc_deleted_sum": 0, "loc_suggested_to_add_sum": 4100, "loc_suggested_to_delete_sum": 0},
        {"language": "go", "feature": "code_completion", "code_generation_activity_count": 320, "code_acceptance_activity_count": 272, "loc_added_sum": 1500, "loc_deleted_sum": 0, "loc_suggested_to_add_sum": 2000, "loc_suggested_to_delete_sum": 0},
        {"language": "java", "feature": "code_completion", "code_generation_activity_count": 300, "code_acceptance_activity_count": 255, "loc_added_sum": 1400, "loc_deleted_sum": 0, "loc_suggested_to_add_sum": 1900, "loc_suggested_to_delete_sum": 0}
      ],
      "totals_by_cli": {
        "session_count": 42,
        "request_count": 156,
        "prompt_count": 89,
        "token_usage": {
          "output_tokens_sum": 248000,
          "prompt_tokens_sum": 186000,
          "avg_tokens_per_request": 2782.1
        }
      }
    },
    {
      "day": "2025-07-27",
      "enterprise_id": "1",
      "daily_active_users": 128,
      "weekly_active_users": 310,
      "monthly_active_users": 482,
      "monthly_active_chat_users": 318,
      "monthly_active_agent_users": 92,
      "code_generation_activity_count": 4200,
      "code_acceptance_activity_count": 3150,
      "user_initiated_interaction_count": 1720,
      "loc_suggested_to_add_sum": 25100,
      "loc_suggested_to_delete_sum": 0,
      "loc_added_sum": 18800,
      "loc_deleted_sum": 2900,
      "daily_active_cli_users": 15,
      "pull_requests": {
        "total_created": 72,
        "total_reviewed": 58,
        "total_merged": 45,
        "median_minutes_to_merge": 162.0,
        "total_suggestions": 30,
        "total_applied_suggestions": 18,
        "total_created_by_copilot": 9,
        "total_reviewed_by_copilot": 25,
        "total_merged_created_by_copilot": 6,
        "median_minutes_to_merge_copilot_authored": 105.0,
        "total_copilot_suggestions": 19,
        "total_copilot_applied_suggestions": 14
      },
      "totals_by_ide": [
        {"ide": "vscode", "code_generation_activity_count": 2800, "code_acceptance_activity_count": 2100, "loc_added_sum": 12600, "loc_deleted_sum": 1900, "loc_suggested_to_add_sum": 16800, "loc_suggested_to_delete_sum": 0, "user_initiated_interaction_count": 1100},
        {"ide": "jetbrains", "code_generation_activity_count": 980, "code_acceptance_activity_count": 735, "loc_added_sum": 4500, "loc_deleted_sum": 700, "loc_suggested_to_add_sum": 6000, "loc_suggested_to_delete_sum": 0, "user_initiated_interaction_count": 420},
        {"ide": "neovim", "code_generation_activity_count": 420, "code_acceptance_activity_count": 315, "loc_added_sum": 1700, "loc_deleted_sum": 300, "loc_suggested_to_add_sum": 2300, "loc_suggested_to_delete_sum": 0, "user_initiated_interaction_count": 200}
      ],
      "totals_by_feature": [
        {"feature": "code_completion", "code_generation_activity_count": 2950, "code_acceptance_activity_count": 2508, "loc_added_sum": 13900, "loc_deleted_sum": 0, "loc_suggested_to_add_sum": 18500, "loc_suggested_to_delete_sum": 0, "user_initiated_interaction_count": 0},
        {"feature": "chat_panel", "code_generation_activity_count": 870, "code_acceptance_activity_count": 445, "loc_added_sum": 3400, "loc_deleted_sum": 1100, "loc_suggested_to_add_sum": 4600, "loc_suggested_to_delete_sum": 0, "user_initiated_interaction_count": 1280},
        {"feature": "inline_chat", "code_generation_activity_count": 380, "code_acceptance_activity_count": 197, "loc_added_sum": 1500, "loc_deleted_sum": 1800, "loc_suggested_to_add_sum": 2000, "loc_suggested_to_delete_sum": 0, "user_initiated_interaction_count": 440}
      ],
      "totals_by_language_feature": [
        {"language": "python", "feature": "code_completion", "code_generation_activity_count": 1050, "code_acceptance_activity_count": 893, "loc_added_sum": 4900, "loc_deleted_sum": 0, "loc_suggested_to_add_sum": 6500, "loc_suggested_to_delete_sum": 0},
        {"language": "typescript", "feature": "code_completion", "code_generation_activity_count": 780, "code_acceptance_activity_count": 663, "loc_added_sum": 3700, "loc_deleted_sum": 0, "loc_suggested_to_add_sum": 4900, "loc_suggested_to_delete_sum": 0},
        {"language": "javascript", "feature": "code_completion", "code_generation_activity_count": 590, "code_acceptance_activity_count": 502, "loc_added_sum": 2700, "loc_deleted_sum": 0, "loc_suggested_to_add_sum": 3600, "loc_suggested_to_delete_sum": 0}
      ],
      "totals_by_cli": {
        "session_count": 35,
        "request_count": 130,
        "prompt_count": 72,
        "token_usage": {
          "output_tokens_sum": 210000,
          "prompt_tokens_sum": 158000,
          "avg_tokens_per_request": 2830.8
        }
      }
    }
  ],
  "enterprise_id": "1",
  "report_start_day": "2025-07-01",
  "report_end_day": "2025-07-28"
}]
SAMPLE_EOF
}

generate_sample_users_data() {
  cat <<'SAMPLE_EOF'
[
  {"user_id":1,"user_login":"alice","day":"2025-07-28","enterprise_id":"1","code_generation_activity_count":85,"code_acceptance_activity_count":68,"user_initiated_interaction_count":42,"loc_suggested_to_add_sum":620,"loc_added_sum":480,"loc_deleted_sum":75,"loc_suggested_to_delete_sum":0,"used_agent":true,"used_chat":true,"used_cli":true,"totals_by_ide":[{"ide":"vscode","code_generation_activity_count":85,"code_acceptance_activity_count":68,"loc_added_sum":480,"loc_deleted_sum":75,"loc_suggested_to_add_sum":620,"loc_suggested_to_delete_sum":0,"user_initiated_interaction_count":42}],"totals_by_feature":[{"feature":"code_completion","code_generation_activity_count":60,"code_acceptance_activity_count":51,"loc_added_sum":340,"loc_deleted_sum":0,"loc_suggested_to_add_sum":450,"loc_suggested_to_delete_sum":0,"user_initiated_interaction_count":0},{"feature":"chat_panel","code_generation_activity_count":25,"code_acceptance_activity_count":17,"loc_added_sum":140,"loc_deleted_sum":75,"loc_suggested_to_add_sum":170,"loc_suggested_to_delete_sum":0,"user_initiated_interaction_count":42}],"totals_by_language_feature":[{"language":"python","feature":"code_completion","code_generation_activity_count":40,"code_acceptance_activity_count":34,"loc_added_sum":220,"loc_deleted_sum":0,"loc_suggested_to_add_sum":290,"loc_suggested_to_delete_sum":0},{"language":"typescript","feature":"code_completion","code_generation_activity_count":20,"code_acceptance_activity_count":17,"loc_added_sum":120,"loc_deleted_sum":0,"loc_suggested_to_add_sum":160,"loc_suggested_to_delete_sum":0}],"totals_by_language_model":[],"totals_by_model_feature":[],"totals_by_cli":{"session_count":3,"request_count":12,"prompt_count":8,"token_usage":{"output_tokens_sum":18000,"prompt_tokens_sum":13500,"avg_tokens_per_request":2625.0},"last_known_cli_version":{"cli_version":"1.0.8","sampled_at":"2025-07-28T12:30:00.000Z"}}},
  {"user_id":2,"user_login":"bob","day":"2025-07-28","enterprise_id":"1","code_generation_activity_count":62,"code_acceptance_activity_count":43,"user_initiated_interaction_count":28,"loc_suggested_to_add_sum":450,"loc_added_sum":310,"loc_deleted_sum":40,"loc_suggested_to_delete_sum":0,"used_agent":false,"used_chat":true,"used_cli":false,"totals_by_ide":[{"ide":"jetbrains","code_generation_activity_count":62,"code_acceptance_activity_count":43,"loc_added_sum":310,"loc_deleted_sum":40,"loc_suggested_to_add_sum":450,"loc_suggested_to_delete_sum":0,"user_initiated_interaction_count":28}],"totals_by_feature":[{"feature":"code_completion","code_generation_activity_count":50,"code_acceptance_activity_count":38,"loc_added_sum":260,"loc_deleted_sum":0,"loc_suggested_to_add_sum":350,"loc_suggested_to_delete_sum":0,"user_initiated_interaction_count":0}],"totals_by_language_feature":[{"language":"java","feature":"code_completion","code_generation_activity_count":50,"code_acceptance_activity_count":38,"loc_added_sum":260,"loc_deleted_sum":0,"loc_suggested_to_add_sum":350,"loc_suggested_to_delete_sum":0}],"totals_by_language_model":[],"totals_by_model_feature":[]},
  {"user_id":3,"user_login":"carol","day":"2025-07-28","enterprise_id":"1","code_generation_activity_count":110,"code_acceptance_activity_count":92,"user_initiated_interaction_count":55,"loc_suggested_to_add_sum":820,"loc_added_sum":650,"loc_deleted_sum":120,"loc_suggested_to_delete_sum":0,"used_agent":true,"used_chat":true,"used_cli":false,"totals_by_ide":[{"ide":"vscode","code_generation_activity_count":110,"code_acceptance_activity_count":92,"loc_added_sum":650,"loc_deleted_sum":120,"loc_suggested_to_add_sum":820,"loc_suggested_to_delete_sum":0,"user_initiated_interaction_count":55}],"totals_by_feature":[{"feature":"code_completion","code_generation_activity_count":70,"code_acceptance_activity_count":60,"loc_added_sum":400,"loc_deleted_sum":0,"loc_suggested_to_add_sum":530,"loc_suggested_to_delete_sum":0,"user_initiated_interaction_count":0},{"feature":"chat_panel","code_generation_activity_count":40,"code_acceptance_activity_count":32,"loc_added_sum":250,"loc_deleted_sum":120,"loc_suggested_to_add_sum":290,"loc_suggested_to_delete_sum":0,"user_initiated_interaction_count":55}],"totals_by_language_feature":[{"language":"typescript","feature":"code_completion","code_generation_activity_count":45,"code_acceptance_activity_count":38,"loc_added_sum":250,"loc_deleted_sum":0,"loc_suggested_to_add_sum":330,"loc_suggested_to_delete_sum":0},{"language":"go","feature":"code_completion","code_generation_activity_count":25,"code_acceptance_activity_count":22,"loc_added_sum":150,"loc_deleted_sum":0,"loc_suggested_to_add_sum":200,"loc_suggested_to_delete_sum":0}],"totals_by_language_model":[],"totals_by_model_feature":[]}
]
SAMPLE_EOF
}

###############################################################################
# API helpers
###############################################################################

# Build the correct API path for the requested scope / period.
# Sets global: API_PATH
build_api_path() {
  local report_type="$1"  # "aggregate" or "users"

  if [ -n "$ENTERPRISE" ]; then
    if [ "$report_type" = "users" ]; then
      if [ -n "$DAY" ]; then
        API_PATH="/enterprises/${ENTERPRISE}/copilot/metrics/reports/users-1-day?day=${DAY}"
      else
        API_PATH="/enterprises/${ENTERPRISE}/copilot/metrics/reports/users-28-day/latest"
      fi
    else
      if [ -n "$DAY" ]; then
        API_PATH="/enterprises/${ENTERPRISE}/copilot/metrics/reports/enterprise-1-day?day=${DAY}"
      else
        API_PATH="/enterprises/${ENTERPRISE}/copilot/metrics/reports/enterprise-28-day/latest"
      fi
    fi
  else
    if [ "$report_type" = "users" ]; then
      if [ -n "$DAY" ]; then
        API_PATH="/orgs/${ORG}/copilot/metrics/reports/users-1-day?day=${DAY}"
      else
        API_PATH="/orgs/${ORG}/copilot/metrics/reports/users-28-day/latest"
      fi
    else
      if [ -n "$DAY" ]; then
        API_PATH="/orgs/${ORG}/copilot/metrics/reports/organization-1-day?day=${DAY}"
      else
        API_PATH="/orgs/${ORG}/copilot/metrics/reports/organization-28-day/latest"
      fi
    fi
  fi
}

# Fetch the download-links envelope and then download the actual report data.
# Usage:  fetch_report "aggregate"|"users"
# Outputs the combined NDJSON / JSON content to stdout.
fetch_report() {
  local report_type="$1"
  build_api_path "$report_type"

  log "Fetching ${report_type} report links from: ${API_PATH}"

  local envelope
  envelope=$(gh api \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: ${API_VERSION}" \
    "$API_PATH" 2>&1) || {
      error "API request failed for ${API_PATH}"
      error "$envelope"
      return 1
    }

  debug "Envelope response: $envelope"

  # Extract download links
  local links
  links=$(echo "$envelope" | jq -r '.download_links[]? // empty')

  if [ -z "$links" ]; then
    warn "No download links returned for ${report_type} report."
    echo "[]"
    return 0
  fi

  # Download each link and concatenate the NDJSON content.
  # Reports may be NDJSON (one JSON object per line) — we collect all lines.
  local combined=""
  while IFS= read -r url; do
    debug "Downloading report file: ${url:0:80}..."
    local content
    content=$(curl -sSL "$url") || {
      warn "Failed to download: ${url:0:80}..."
      continue
    }
    if [ -n "$combined" ]; then
      combined="${combined}"$'\n'"${content}"
    else
      combined="${content}"
    fi
  done <<< "$links"

  echo "$combined"
}

###############################################################################
# Dashboard rendering — aggregate / enterprise level
###############################################################################

render_dashboard() {
  local data="$1"
  local scope_label="$2"  # e.g. "Enterprise: my-ent" or "Org: my-org"

  # Extract report date range
  local report_start report_end
  report_start=$(echo "$data" | jq -r '.[0].report_start_day // .[0].day // "N/A"' 2>/dev/null || echo "N/A")
  report_end=$(echo "$data" | jq -r '.[0].report_end_day // .[0].day // "N/A"' 2>/dev/null || echo "N/A")

  # Aggregate across all day_totals entries.  The data structure wraps daily
  # records inside a day_totals array.  We flatten and aggregate.
  local agg
  agg=$(echo "$data" | jq '
    [ .[].day_totals[]? // .[] ] |
    length as $count | {
      days: $count,
      total_daily_active_users:              [.[].daily_active_users              // 0] | add,
      avg_daily_active_users:                (([.[].daily_active_users            // 0] | add) / $count),
      max_daily_active_users:                [.[].daily_active_users              // 0] | max,
      latest_weekly_active_users:            (sort_by(.day) | last.weekly_active_users  // 0),
      latest_monthly_active_users:           (sort_by(.day) | last.monthly_active_users // 0),
      latest_monthly_active_chat_users:      (sort_by(.day) | last.monthly_active_chat_users // 0),
      latest_monthly_active_agent_users:     (sort_by(.day) | last.monthly_active_agent_users // 0),
      total_code_gen:                        [.[].code_generation_activity_count   // 0] | add,
      total_code_accept:                     [.[].code_acceptance_activity_count   // 0] | add,
      total_interactions:                    [.[].user_initiated_interaction_count // 0] | add,
      total_loc_suggested:                   [.[].loc_suggested_to_add_sum        // 0] | add,
      total_loc_added:                       [.[].loc_added_sum                   // 0] | add,
      total_loc_deleted:                     [.[].loc_deleted_sum                 // 0] | add,
      total_pr_created:                      [.[].pull_requests.total_created           // 0] | add,
      total_pr_merged:                       [.[].pull_requests.total_merged            // 0] | add,
      total_pr_reviewed:                     [.[].pull_requests.total_reviewed          // 0] | add,
      total_pr_created_by_copilot:           [.[].pull_requests.total_created_by_copilot // 0] | add,
      total_pr_reviewed_by_copilot:          [.[].pull_requests.total_reviewed_by_copilot // 0] | add,
      total_pr_merged_copilot:               [.[].pull_requests.total_merged_created_by_copilot // 0] | add,
      avg_merge_time:                        ([.[].pull_requests.median_minutes_to_merge // empty] | if length > 0 then add/length else 0 end),
      avg_merge_time_copilot:                ([.[].pull_requests.median_minutes_to_merge_copilot_authored // empty] | if length > 0 then add/length else 0 end),
      total_copilot_suggestions:             [.[].pull_requests.total_copilot_suggestions // 0] | add,
      total_copilot_applied_suggestions:     [.[].pull_requests.total_copilot_applied_suggestions // 0] | add,
      ide_breakdown: (
        [ .[].totals_by_ide[]? ] | group_by(.ide) |
        map({
          ide: .[0].ide,
          code_gen: [.[].code_generation_activity_count // 0] | add,
          code_accept: [.[].code_acceptance_activity_count // 0] | add,
          loc_added: [.[].loc_added_sum // 0] | add
        }) | sort_by(-.code_gen)
      ),
      feature_breakdown: (
        [ .[].totals_by_feature[]? ] | group_by(.feature) |
        map({
          feature: .[0].feature,
          code_gen: [.[].code_generation_activity_count // 0] | add,
          code_accept: [.[].code_acceptance_activity_count // 0] | add,
          loc_added: [.[].loc_added_sum // 0] | add
        }) | sort_by(-.code_gen)
      ),
      language_breakdown: (
        [ .[].totals_by_language_feature[]? ] | group_by(.language) |
        map({
          language: .[0].language,
          code_gen: [.[].code_generation_activity_count // 0] | add,
          loc_added: [.[].loc_added_sum // 0] | add
        }) | sort_by(-.code_gen) | .[0:10]
      ),
      cli_sessions:  [.[].totals_by_cli.session_count  // 0] | add,
      cli_requests:  [.[].totals_by_cli.request_count  // 0] | add,
      cli_prompts:   [.[].totals_by_cli.prompt_count   // 0] | add
    }
  ')

  debug "Aggregated data: $agg"

  # Extract values
  local days avg_dau max_dau wau mau mau_chat mau_agent
  local total_gen total_accept acceptance_rate total_interactions
  local loc_suggested loc_added loc_deleted
  local pr_created pr_merged pr_reviewed pr_copilot_created pr_copilot_reviewed pr_copilot_merged
  local avg_merge avg_merge_copilot
  local copilot_suggestions copilot_applied
  local cli_sessions cli_requests cli_prompts

  days=$(echo "$agg" | jq '.days')
  avg_dau=$(echo "$agg" | jq '.avg_daily_active_users | floor')
  max_dau=$(echo "$agg" | jq '.max_daily_active_users')
  wau=$(echo "$agg" | jq '.latest_weekly_active_users')
  mau=$(echo "$agg" | jq '.latest_monthly_active_users')
  mau_chat=$(echo "$agg" | jq '.latest_monthly_active_chat_users')
  mau_agent=$(echo "$agg" | jq '.latest_monthly_active_agent_users')

  total_gen=$(echo "$agg" | jq '.total_code_gen')
  total_accept=$(echo "$agg" | jq '.total_code_accept')
  total_interactions=$(echo "$agg" | jq '.total_interactions')

  if [ "$total_gen" -gt 0 ] 2>/dev/null; then
    acceptance_rate=$(echo "$agg" | jq '(.total_code_accept / .total_code_gen * 100) | . * 10 | floor | . / 10')
  else
    acceptance_rate="0"
  fi

  loc_suggested=$(echo "$agg" | jq '.total_loc_suggested')
  loc_added=$(echo "$agg" | jq '.total_loc_added')
  loc_deleted=$(echo "$agg" | jq '.total_loc_deleted')

  pr_created=$(echo "$agg" | jq '.total_pr_created')
  pr_merged=$(echo "$agg" | jq '.total_pr_merged')
  pr_reviewed=$(echo "$agg" | jq '.total_pr_reviewed')
  pr_copilot_created=$(echo "$agg" | jq '.total_pr_created_by_copilot')
  pr_copilot_reviewed=$(echo "$agg" | jq '.total_pr_reviewed_by_copilot')
  pr_copilot_merged=$(echo "$agg" | jq '.total_pr_merged_copilot')
  avg_merge=$(echo "$agg" | jq '.avg_merge_time | . * 10 | floor | . / 10')
  avg_merge_copilot=$(echo "$agg" | jq '.avg_merge_time_copilot | . * 10 | floor | . / 10')
  copilot_suggestions=$(echo "$agg" | jq '.total_copilot_suggestions')
  copilot_applied=$(echo "$agg" | jq '.total_copilot_applied_suggestions')

  cli_sessions=$(echo "$agg" | jq '.cli_sessions')
  cli_requests=$(echo "$agg" | jq '.cli_requests')
  cli_prompts=$(echo "$agg" | jq '.cli_prompts')

  # ─── Print dashboard ───────────────────────────────────────────────
  local width=72
  local line
  line=$(printf '%0.s─' $(seq 1 $width))

  echo ""
  echo -e "${BOLD}${CYAN}╔$(printf '%0.s═' $(seq 1 $((width - 2))))╗${NC}"
  echo -e "${BOLD}${CYAN}║  GitHub Copilot Usage Dashboard$(printf '%*s' $((width - 35)) '')║${NC}"
  echo -e "${BOLD}${CYAN}╚$(printf '%0.s═' $(seq 1 $((width - 2))))╝${NC}"
  echo ""
  echo -e "${DIM}  Scope:   ${NC}${BOLD}${scope_label}${NC}"
  echo -e "${DIM}  Period:  ${NC}${report_start} → ${report_end}  (${days} day(s))${NC}"
  echo ""

  # ── Adoption ────────────────────────────────────────────────────────
  echo -e "${BOLD}  📊 Adoption & Active Users${NC}"
  echo -e "  ${line}"
  printf "  %-40s %s\n" "Avg Daily Active Users (DAU):" "$avg_dau"
  printf "  %-40s %s\n" "Peak DAU:" "$max_dau"
  printf "  %-40s %s\n" "Weekly Active Users (latest):" "$wau"
  printf "  %-40s %s\n" "Monthly Active Users (latest):" "$mau"
  printf "  %-40s %s\n" "Monthly Active Chat Users:" "$mau_chat"
  printf "  %-40s %s\n" "Monthly Active Agent Users:" "$mau_agent"
  echo ""

  # ── Code Generation ─────────────────────────────────────────────────
  echo -e "${BOLD}  💻 Code Generation & Acceptance${NC}"
  echo -e "  ${line}"
  printf "  %-40s %s\n" "Total Suggestions Generated:" "$total_gen"
  printf "  %-40s %s\n" "Total Suggestions Accepted:" "$total_accept"
  printf "  %-40s %s%%\n" "Acceptance Rate:" "$acceptance_rate"
  printf "  %-40s %s\n" "User-Initiated Interactions:" "$total_interactions"
  echo ""

  # ── Lines of Code ───────────────────────────────────────────────────
  echo -e "${BOLD}  📝 Lines of Code${NC}"
  echo -e "  ${line}"
  printf "  %-40s %s\n" "LoC Suggested to Add:" "$loc_suggested"
  printf "  %-40s %s\n" "LoC Actually Added:" "$loc_added"
  printf "  %-40s %s\n" "LoC Deleted:" "$loc_deleted"
  echo ""

  # ── Pull Requests ───────────────────────────────────────────────────
  echo -e "${BOLD}  🔀 Pull Requests${NC}"
  echo -e "  ${line}"
  printf "  %-40s %s\n" "Total Created:" "$pr_created"
  printf "  %-40s %s\n" "Total Merged:" "$pr_merged"
  printf "  %-40s %s\n" "Total Reviewed:" "$pr_reviewed"
  printf "  %-40s %s min\n" "Avg Median Time to Merge:" "$avg_merge"
  echo -e "  ${DIM}Copilot PR Activity:${NC}"
  printf "    %-38s %s\n" "Created by Copilot:" "$pr_copilot_created"
  printf "    %-38s %s\n" "Reviewed by Copilot:" "$pr_copilot_reviewed"
  printf "    %-38s %s\n" "Copilot-authored Merged:" "$pr_copilot_merged"
  printf "    %-38s %s min\n" "Copilot-authored Merge Time:" "$avg_merge_copilot"
  printf "    %-38s %s\n" "Copilot Review Suggestions:" "$copilot_suggestions"
  printf "    %-38s %s\n" "Copilot Suggestions Applied:" "$copilot_applied"
  echo ""

  # ── CLI Usage ───────────────────────────────────────────────────────
  if [ "$cli_sessions" != "0" ] && [ "$cli_sessions" != "null" ]; then
    echo -e "${BOLD}  🖥️  Copilot CLI Usage${NC}"
    echo -e "  ${line}"
    printf "  %-40s %s\n" "CLI Sessions:" "$cli_sessions"
    printf "  %-40s %s\n" "CLI Requests:" "$cli_requests"
    printf "  %-40s %s\n" "CLI Prompts:" "$cli_prompts"
    echo ""
  fi

  # ── IDE Breakdown ───────────────────────────────────────────────────
  local ide_count
  ide_count=$(echo "$agg" | jq '.ide_breakdown | length')
  if [ "$ide_count" -gt 0 ]; then
    echo -e "${BOLD}  🛠️  IDE Breakdown${NC}"
    echo -e "  ${line}"
    printf "  ${DIM}%-20s %12s %12s %12s${NC}\n" "IDE" "Suggestions" "Accepted" "LoC Added"
    echo "$agg" | jq -r '.ide_breakdown[] | "  \(.ide)\t\(.code_gen)\t\(.code_accept)\t\(.loc_added)"' | \
      while IFS=$'\t' read -r ide gen acc loc; do
        printf "  %-20s %12s %12s %12s\n" "$ide" "$gen" "$acc" "$loc"
      done
    echo ""
  fi

  # ── Feature Breakdown ──────────────────────────────────────────────
  local feature_count
  feature_count=$(echo "$agg" | jq '.feature_breakdown | length')
  if [ "$feature_count" -gt 0 ]; then
    echo -e "${BOLD}  ⚙️  Feature Breakdown${NC}"
    echo -e "  ${line}"
    printf "  ${DIM}%-20s %12s %12s %12s${NC}\n" "Feature" "Suggestions" "Accepted" "LoC Added"
    echo "$agg" | jq -r '.feature_breakdown[] | "  \(.feature)\t\(.code_gen)\t\(.code_accept)\t\(.loc_added)"' | \
      while IFS=$'\t' read -r feat gen acc loc; do
        printf "  %-20s %12s %12s %12s\n" "$feat" "$gen" "$acc" "$loc"
      done
    echo ""
  fi

  # ── Top Languages ──────────────────────────────────────────────────
  local lang_count
  lang_count=$(echo "$agg" | jq '.language_breakdown | length')
  if [ "$lang_count" -gt 0 ]; then
    echo -e "${BOLD}  🌐 Top Languages${NC}"
    echo -e "  ${line}"
    printf "  ${DIM}%-20s %12s %12s${NC}\n" "Language" "Suggestions" "LoC Added"
    echo "$agg" | jq -r '.language_breakdown[] | "  \(.language)\t\(.code_gen)\t\(.loc_added)"' | \
      while IFS=$'\t' read -r lang gen loc; do
        printf "  %-20s %12s %12s\n" "$lang" "$gen" "$loc"
      done
    echo ""
  fi
}

###############################################################################
# Dashboard rendering — user-level
###############################################################################

render_users_dashboard() {
  local data="$1"

  # Get the latest day's data, then sort users by code generation activity
  local user_summary
  user_summary=$(echo "$data" | jq -r '
    sort_by(.day) | group_by(.user_login) |
    map({
      user:            .[0].user_login,
      days_active:     length,
      total_gen:       [.[].code_generation_activity_count // 0]  | add,
      total_accept:    [.[].code_acceptance_activity_count // 0]  | add,
      interactions:    [.[].user_initiated_interaction_count // 0] | add,
      loc_added:       [.[].loc_added_sum // 0]                   | add,
      loc_deleted:     [.[].loc_deleted_sum // 0]                 | add,
      used_agent:      (any(.[]; .used_agent == true)),
      used_chat:       (any(.[]; .used_chat == true)),
      used_cli:        (any(.[]; .used_cli == true))
    }) | sort_by(-.total_gen)
  ')

  local user_count
  user_count=$(echo "$user_summary" | jq 'length')

  local width=72
  local line
  line=$(printf '%0.s─' $(seq 1 $width))

  echo -e "${BOLD}  👤 User-Level Metrics (${user_count} users)${NC}"
  echo -e "  ${line}"
  printf "  ${DIM}%-16s %6s %8s %8s %8s %5s %5s %5s${NC}\n" \
    "User" "Gen" "Accept" "LoC+" "LoC-" "Chat" "Agent" "CLI"

  echo "$user_summary" | jq -r '.[] | "\(.user)\t\(.total_gen)\t\(.total_accept)\t\(.loc_added)\t\(.loc_deleted)\t\(.used_chat)\t\(.used_agent)\t\(.used_cli)"' | \
    while IFS=$'\t' read -r user gen acc loc_a loc_d chat agent cli; do
      # Convert booleans to symbols
      chat_sym="·"; [ "$chat" = "true" ] && chat_sym="✓"
      agent_sym="·"; [ "$agent" = "true" ] && agent_sym="✓"
      cli_sym="·"; [ "$cli" = "true" ] && cli_sym="✓"
      printf "  %-16s %6s %8s %8s %8s %5s %5s %5s\n" \
        "$user" "$gen" "$acc" "$loc_a" "$loc_d" "$chat_sym" "$agent_sym" "$cli_sym"
    done
  echo ""
}

###############################################################################
# Export helpers
###############################################################################

export_csv() {
  local data="$1"
  local filepath="$2"
  local report_type="$3"

  if [ "$report_type" = "aggregate" ]; then
    # Flatten day_totals into CSV rows
    echo "$data" | jq -r '
      [ .[].day_totals[]? // .[] ] |
      sort_by(.day) |
      ["day","daily_active_users","weekly_active_users","monthly_active_users",
       "code_generation_activity_count","code_acceptance_activity_count",
       "user_initiated_interaction_count",
       "loc_suggested_to_add_sum","loc_added_sum","loc_deleted_sum",
       "pr_created","pr_merged","pr_reviewed",
       "pr_created_by_copilot","pr_reviewed_by_copilot"] as $header |
      ($header | @csv),
      (.[] |
        [
          .day,
          (.daily_active_users // 0),
          (.weekly_active_users // 0),
          (.monthly_active_users // 0),
          (.code_generation_activity_count // 0),
          (.code_acceptance_activity_count // 0),
          (.user_initiated_interaction_count // 0),
          (.loc_suggested_to_add_sum // 0),
          (.loc_added_sum // 0),
          (.loc_deleted_sum // 0),
          (.pull_requests.total_created // 0),
          (.pull_requests.total_merged // 0),
          (.pull_requests.total_reviewed // 0),
          (.pull_requests.total_created_by_copilot // 0),
          (.pull_requests.total_reviewed_by_copilot // 0)
        ] | @csv
      )
    ' > "$filepath"
  else
    # User-level CSV
    echo "$data" | jq -r '
      sort_by(.user_login) |
      ["user_login","day","code_generation_activity_count","code_acceptance_activity_count",
       "user_initiated_interaction_count","loc_suggested_to_add_sum","loc_added_sum","loc_deleted_sum",
       "used_agent","used_chat","used_cli"] as $header |
      ($header | @csv),
      (.[] |
        [
          .user_login,
          .day,
          (.code_generation_activity_count // 0),
          (.code_acceptance_activity_count // 0),
          (.user_initiated_interaction_count // 0),
          (.loc_suggested_to_add_sum // 0),
          (.loc_added_sum // 0),
          (.loc_deleted_sum // 0),
          (.used_agent // false),
          (.used_chat // false),
          (.used_cli // false)
        ] | @csv
      )
    ' > "$filepath"
  fi

  log "CSV exported to: ${filepath}"
}

export_json() {
  local data="$1"
  local filepath="$2"

  echo "$data" | jq '.' > "$filepath"
  log "JSON exported to: ${filepath}"
}

export_markdown() {
  local data="$1"
  local filepath="$2"
  local scope_label="$3"

  local report_start report_end
  report_start=$(echo "$data" | jq -r '.[0].report_start_day // .[0].day // "N/A"' 2>/dev/null || echo "N/A")
  report_end=$(echo "$data" | jq -r '.[0].report_end_day // .[0].day // "N/A"' 2>/dev/null || echo "N/A")

  local agg
  agg=$(echo "$data" | jq '
    [ .[].day_totals[]? // .[] ] | {
      days: length,
      avg_dau:       ([.[].daily_active_users // 0] | add / length | floor),
      max_dau:       ([.[].daily_active_users // 0] | max),
      latest_mau:    (sort_by(.day) | last.monthly_active_users // 0),
      total_gen:     [.[].code_generation_activity_count // 0] | add,
      total_accept:  [.[].code_acceptance_activity_count // 0] | add,
      loc_added:     [.[].loc_added_sum // 0] | add,
      loc_deleted:   [.[].loc_deleted_sum // 0] | add,
      pr_created:    [.[].pull_requests.total_created // 0] | add,
      pr_merged:     [.[].pull_requests.total_merged // 0] | add,
      pr_copilot_created: [.[].pull_requests.total_created_by_copilot // 0] | add,
      ide_breakdown: (
        [ .[].totals_by_ide[]? ] | group_by(.ide) |
        map({ide: .[0].ide, gen: ([.[].code_generation_activity_count // 0] | add), loc: ([.[].loc_added_sum // 0] | add)}) |
        sort_by(-.gen)
      ),
      lang_breakdown: (
        [ .[].totals_by_language_feature[]? ] | group_by(.language) |
        map({lang: .[0].language, gen: ([.[].code_generation_activity_count // 0] | add), loc: ([.[].loc_added_sum // 0] | add)}) |
        sort_by(-.gen) | .[0:10]
      )
    }
  ')

  {
    echo "# GitHub Copilot Usage Report"
    echo ""
    echo "**Scope:** ${scope_label}"
    echo "**Period:** ${report_start} → ${report_end}"
    echo "**Generated:** $(date -u '+%Y-%m-%d %H:%M UTC')"
    echo ""
    echo "## Adoption"
    echo ""
    echo "| Metric | Value |"
    echo "|--------|------:|"
    echo "| Avg Daily Active Users | $(echo "$agg" | jq '.avg_dau') |"
    echo "| Peak DAU | $(echo "$agg" | jq '.max_dau') |"
    echo "| Monthly Active Users | $(echo "$agg" | jq '.latest_mau') |"
    echo ""
    echo "## Code Generation"
    echo ""
    echo "| Metric | Value |"
    echo "|--------|------:|"
    echo "| Total Suggestions | $(echo "$agg" | jq '.total_gen') |"
    echo "| Total Accepted | $(echo "$agg" | jq '.total_accept') |"

    local rate
    rate=$(echo "$agg" | jq 'if .total_gen > 0 then (.total_accept / .total_gen * 100 | . * 10 | floor | . / 10) else 0 end')
    echo "| Acceptance Rate | ${rate}% |"
    echo "| Lines of Code Added | $(echo "$agg" | jq '.loc_added') |"
    echo "| Lines of Code Deleted | $(echo "$agg" | jq '.loc_deleted') |"
    echo ""
    echo "## Pull Requests"
    echo ""
    echo "| Metric | Value |"
    echo "|--------|------:|"
    echo "| Total Created | $(echo "$agg" | jq '.pr_created') |"
    echo "| Total Merged | $(echo "$agg" | jq '.pr_merged') |"
    echo "| Created by Copilot | $(echo "$agg" | jq '.pr_copilot_created') |"
    echo ""
    echo "## IDE Breakdown"
    echo ""
    echo "| IDE | Suggestions | LoC Added |"
    echo "|-----|------------:|----------:|"
    echo "$agg" | jq -r '.ide_breakdown[] | "| \(.ide) | \(.gen) | \(.loc) |"'
    echo ""
    echo "## Top Languages"
    echo ""
    echo "| Language | Suggestions | LoC Added |"
    echo "|----------|------------:|----------:|"
    echo "$agg" | jq -r '.lang_breakdown[] | "| \(.lang) | \(.gen) | \(.loc) |"'
    echo ""
  } > "$filepath"

  log "Markdown report exported to: ${filepath}"
}

###############################################################################
# Main
###############################################################################
main() {
  parse_args "$@"

  if ! $TEST_MODE; then
    check_deps
  fi

  local scope_label
  if [ -n "$ENTERPRISE" ]; then
    scope_label="Enterprise: ${ENTERPRISE}"
  else
    scope_label="Organization: ${ORG}"
  fi

  # ── Fetch or generate aggregate data ────────────────────────────────
  local aggregate_data
  if $TEST_MODE; then
    log "Running in test mode with sample data."
    aggregate_data=$(generate_sample_enterprise_data)
  else
    aggregate_data=$(fetch_report "aggregate") || {
      error "Failed to fetch aggregate report."
      exit 1
    }
  fi

  # Normalise: if the downloaded content is NDJSON (one object per line)
  # wrap it in an array for uniform processing.
  aggregate_data=$(echo "$aggregate_data" | jq -s 'if type == "array" and (.[0] | type) == "array" then .[0] else . end')

  # ── Render terminal dashboard ──────────────────────────────────────
  render_dashboard "$aggregate_data" "$scope_label"

  # ── User-level report ──────────────────────────────────────────────
  local users_data=""
  if $FETCH_USERS; then
    if $TEST_MODE; then
      users_data=$(generate_sample_users_data)
    else
      users_data=$(fetch_report "users") || {
        warn "Failed to fetch user-level report."
      }
    fi

    if [ -n "$users_data" ] && [ "$users_data" != "[]" ]; then
      users_data=$(echo "$users_data" | jq -s 'if type == "array" and (.[0] | type) == "array" then .[0] else . end')
      render_users_dashboard "$users_data"
    fi
  fi

  # ── Exports ─────────────────────────────────────────────────────────
  if $GENERATE_CSV || $GENERATE_JSON || $GENERATE_MARKDOWN; then
    mkdir -p "$OUT_DIR"
    log "Output directory: ${OUT_DIR}"
  fi

  if $GENERATE_CSV; then
    export_csv "$aggregate_data" "${OUT_DIR}/copilot_usage_aggregate.csv" "aggregate"
    if [ -n "$users_data" ] && [ "$users_data" != "[]" ]; then
      export_csv "$users_data" "${OUT_DIR}/copilot_usage_users.csv" "users"
    fi
  fi

  if $GENERATE_JSON; then
    export_json "$aggregate_data" "${OUT_DIR}/copilot_usage_aggregate.json"
    if [ -n "$users_data" ] && [ "$users_data" != "[]" ]; then
      export_json "$users_data" "${OUT_DIR}/copilot_usage_users.json"
    fi
  fi

  if $GENERATE_MARKDOWN; then
    export_markdown "$aggregate_data" "${OUT_DIR}/copilot_usage_report.md" "$scope_label"
  fi

  echo -e "${GREEN}${BOLD}  ✅ Dashboard complete.${NC}"
  if $GENERATE_CSV || $GENERATE_JSON || $GENERATE_MARKDOWN; then
    echo -e "${DIM}  Exports saved to: ${OUT_DIR}/${NC}"
  fi
  echo ""
}

main "$@"
