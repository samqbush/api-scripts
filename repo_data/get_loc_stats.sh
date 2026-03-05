#!/usr/bin/env bash

###############################################################################
# get_loc_stats.sh — Lines of Code Committed across an Organization/Enterprise
#
# Queries GitHub's GraphQL API to collect lines added/deleted per contributor
# across all repositories in an organization or enterprise. Uses batched
# GraphQL queries (multiple repos per call via aliases) to stay within API
# rate limits even for orgs with thousands of repos.
#
# Usage:
#   ./get_loc_stats.sh --org ORG [OPTIONS]
#   ./get_loc_stats.sh --enterprise ENTERPRISE [OPTIONS]
#
# Authentication Modes:
#   --auth-mode cli   (default) Uses GitHub CLI (gh). Run `gh auth login` first.
#   --auth-mode app   Uses a GitHub App. Requires --app-id, --app-key, and
#                     --installation-id. Provides higher rate limits (15K/hr).
#
# Options:
#   --org ORG              Target a single GitHub organization
#   --enterprise ENT       Target all organizations in a GitHub Enterprise
#   --days N               Lookback period in days (default: 30)
#   --batch-size N         Repos per GraphQL query (default: 5)
#   --auth-mode MODE       "cli" (default) or "app"
#   --app-id ID            GitHub App ID (required for app mode)
#   --app-key FILE         Path to GitHub App private key PEM (required for app mode)
#   --installation-id ID   GitHub App installation ID (required for app mode)
#   --csv                  Generate CSV output
#   --json                 Generate JSON output
#   --out DIR              Output directory (default: loc_stats_TIMESTAMP)
#   --test                 Test mode: process only the first batch of repos per org
#   --max-repos N          Limit to the first N repos per org (useful for testing)
#   --help, -h             Show this help message
#
# Prerequisites:
#   - jq (JSON processing)
#   - For cli mode: GitHub CLI (gh) installed and authenticated
#   - For app mode: openssl, curl
#
# Required GitHub Permissions:
#   Repository: Contents (Read), Metadata (Read)
#   Organization: Members (Read) — for enterprise mode org listing
#
# Examples:
#   # Single org, CLI auth, CSV output
#   ./get_loc_stats.sh --org my-org --csv
#
#   # Enterprise-wide, GitHub App auth, JSON + CSV
#   ./get_loc_stats.sh --enterprise my-ent --auth-mode app \
#     --app-id 12345 --app-key app.pem --installation-id 67890 \
#     --csv --json
#
#   # Custom lookback and batch size
#   ./get_loc_stats.sh --org my-org --days 90 --batch-size 10 --json
#
###############################################################################

set -e

# --- Defaults ---
ORG=""
ENTERPRISE=""
DAYS=30
BATCH_SIZE=5
AUTH_MODE="cli"
APP_ID=""
APP_KEY=""
INSTALLATION_ID=""
GENERATE_CSV=false
GENERATE_JSON=false
TEST_MODE=false
MAX_REPOS=0
OUT_DIR=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Logging ---
log()   { echo -e "${BLUE}[INFO]${NC} $*" >&2; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# --- Usage ---
show_usage() {
  sed -n '/^# Usage:/,/^###/p' "$0" | grep '^#' | sed 's/^# \?//'
}

# --- Argument Parsing ---
while [ $# -gt 0 ]; do
  case "$1" in
    --org)              ORG="$2"; shift 2 ;;
    --enterprise)       ENTERPRISE="$2"; shift 2 ;;
    --days)             DAYS="$2"; shift 2 ;;
    --batch-size)       BATCH_SIZE="$2"; shift 2 ;;
    --auth-mode)        AUTH_MODE="$2"; shift 2 ;;
    --app-id)           APP_ID="$2"; shift 2 ;;
    --app-key)          APP_KEY="$2"; shift 2 ;;
    --installation-id)  INSTALLATION_ID="$2"; shift 2 ;;
    --csv)              GENERATE_CSV=true; shift ;;
    --json)             GENERATE_JSON=true; shift ;;
    --test)             TEST_MODE=true; shift ;;
    --max-repos)        MAX_REPOS="$2"; shift 2 ;;
    --out)              OUT_DIR="$2"; shift 2 ;;
    --help|-h)          show_usage; exit 0 ;;
    *)                  error "Unknown option: $1"; show_usage; exit 1 ;;
  esac
done

# --- Validation ---
# Validate numeric parameters
validate_positive_int() {
  local name="$1" value="$2"
  case "$value" in
    ''|*[!0-9]*) error "$name must be a positive integer, got: '$value'"; exit 1 ;;
  esac
  if [ "$value" -le 0 ]; then
    error "$name must be a positive integer, got: '$value'"
    exit 1
  fi
}

validate_positive_int "--days" "$DAYS"
validate_positive_int "--batch-size" "$BATCH_SIZE"
if [ "$MAX_REPOS" != "0" ]; then
  validate_positive_int "--max-repos" "$MAX_REPOS"
fi

if [ -z "$ORG" ] && [ -z "$ENTERPRISE" ]; then
  error "Must specify --org or --enterprise"
  show_usage
  exit 1
fi

if [ -n "$ORG" ] && [ -n "$ENTERPRISE" ]; then
  error "Specify only one of --org or --enterprise"
  exit 1
fi

if [ "$GENERATE_CSV" = false ] && [ "$GENERATE_JSON" = false ]; then
  error "Must specify at least one output format: --csv and/or --json"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  error "jq is required. Install it (e.g., brew install jq)"
  exit 1
fi

if [ "$AUTH_MODE" = "cli" ]; then
  if ! command -v gh &>/dev/null; then
    error "GitHub CLI (gh) is required for cli auth mode. Install it or use --auth-mode app"
    exit 1
  fi
elif [ "$AUTH_MODE" = "app" ]; then
  if [ -z "$APP_ID" ] || [ -z "$APP_KEY" ] || [ -z "$INSTALLATION_ID" ]; then
    error "GitHub App mode requires --app-id, --app-key, and --installation-id"
    exit 1
  fi
  if [ ! -f "$APP_KEY" ]; then
    error "App key file not found: $APP_KEY"
    exit 1
  fi
  if ! command -v openssl &>/dev/null; then
    error "openssl is required for GitHub App authentication"
    exit 1
  fi
  if ! command -v curl &>/dev/null; then
    error "curl is required for GitHub App authentication"
    exit 1
  fi
else
  error "Invalid --auth-mode: $AUTH_MODE (must be 'cli' or 'app')"
  exit 1
fi

# --- Output directory ---
if [ -z "$OUT_DIR" ]; then
  OUT_DIR="loc_stats_$(date +%Y%m%d_%H%M%S)"
fi
mkdir -p "$OUT_DIR"

# --- Temp directory ---
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# OS-aware date helper (GNU vs BSD)
get_past_date() {
  local days="$1"
  if date --version >/dev/null 2>&1; then
    date -u -d "${days} days ago" +"%Y-%m-%dT%H:%M:%SZ"
  else
    date -u -v-"${days}d" +"%Y-%m-%dT%H:%M:%SZ"
  fi
}

# OS-aware epoch conversion helper (GNU vs BSD)
date_to_epoch() {
  local datestr="$1"
  if date --version >/dev/null 2>&1; then
    date -d "$datestr" +%s 2>/dev/null || echo 0
  else
    date -jf "%Y-%m-%dT%H:%M:%SZ" "$datestr" +%s 2>/dev/null || echo 0
  fi
}

# Calculate since date (ISO 8601)
SINCE_DATE=$(get_past_date "$DAYS")

log "Lookback period: $DAYS days (since $SINCE_DATE)"
log "Output directory: $OUT_DIR"
log "Auth mode: $AUTH_MODE"
log "Batch size: $BATCH_SIZE repos per GraphQL query"
if [ "$TEST_MODE" = true ]; then
  log "Test mode: will process only the first batch per org"
fi
if [ "$MAX_REPOS" -gt 0 ] 2>/dev/null; then
  log "Max repos per org: $MAX_REPOS"
fi

###############################################################################
# Authentication Layer
###############################################################################

# GitHub App JWT generation
generate_jwt() {
  local app_id="$1"
  local key_file="$2"

  local header
  header=$(printf '{"alg":"RS256","typ":"JWT"}' | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')

  local now
  now=$(date +%s)
  local iat=$((now - 60))
  local exp=$((now + 600))

  local payload
  payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$iat" "$exp" "$app_id" \
    | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')

  local signature
  signature=$(printf '%s.%s' "$header" "$payload" \
    | openssl dgst -sha256 -sign "$key_file" -binary \
    | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')

  printf '%s.%s.%s' "$header" "$payload" "$signature"
}

# Get installation access token from GitHub App
get_installation_token() {
  local jwt="$1"
  local inst_id="$2"

  local response
  response=$(curl -sS -X POST \
    -H "Authorization: Bearer $jwt" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/app/installations/$inst_id/access_tokens")

  local token
  token=$(echo "$response" | jq -r '.token // empty')
  if [ -z "$token" ]; then
    error "Failed to get installation token: $(echo "$response" | jq -r '.message // "unknown error"')"
    exit 1
  fi
  echo "$token"
}

# Initialize auth — sets INSTALL_TOKEN for app mode
INSTALL_TOKEN=""
if [ "$AUTH_MODE" = "app" ]; then
  log "Generating GitHub App JWT..."
  JWT=$(generate_jwt "$APP_ID" "$APP_KEY")
  log "Exchanging JWT for installation access token..."
  INSTALL_TOKEN=$(get_installation_token "$JWT" "$INSTALLATION_ID")
  log "GitHub App authentication successful"
fi

###############################################################################
# GraphQL Execution
###############################################################################

# Execute a GraphQL query, returns JSON response
graphql_query() {
  local query="$1"

  if [ "$AUTH_MODE" = "cli" ]; then
    gh api graphql -f query="$query"
  else
    local payload
    payload=$(jq -n --arg q "$query" '{query: $q}')
    curl -sS -X POST \
      -H "Authorization: bearer $INSTALL_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$payload" \
      "https://api.github.com/graphql"
  fi
}

# Check rate limit and sleep if needed
check_rate_limit() {
  local response="$1"
  local remaining
  remaining=$(echo "$response" | jq -r '.data.rateLimit.remaining // empty' 2>/dev/null)
  local reset_at
  reset_at=$(echo "$response" | jq -r '.data.rateLimit.resetAt // empty' 2>/dev/null)

  if [ -n "$remaining" ] && [ "$remaining" -lt 100 ] 2>/dev/null; then
    warn "Rate limit low: $remaining remaining. Resets at $reset_at"
    if [ -n "$reset_at" ]; then
      local reset_epoch
      reset_epoch=$(date_to_epoch "$reset_at")
      local now_epoch
      now_epoch=$(date +%s)
      local wait_secs=$(( reset_epoch - now_epoch + 5 ))
      if [ "$wait_secs" -gt 0 ] && [ "$wait_secs" -lt 3700 ]; then
        warn "Sleeping $wait_secs seconds until rate limit resets..."
        sleep "$wait_secs"
      fi
    fi
  fi
}

###############################################################################
# Repository Listing
###############################################################################

# List all repos for an org via GraphQL, writes repo names to stdout
list_org_repos() {
  local org="$1"
  local cursor=""
  local has_next=true

  while [ "$has_next" = "true" ]; do
    local after_clause=""
    if [ -n "$cursor" ]; then
      after_clause=", after: \"$cursor\""
    fi

    local query
    query="{ organization(login: \"$org\") { repositories(first: 100$after_clause) { nodes { name isArchived isEmpty } pageInfo { hasNextPage endCursor } } } rateLimit { remaining resetAt } }"

    local response
    response=$(graphql_query "$query")

    # Check for errors
    local errmsg
    errmsg=$(echo "$response" | jq -r '.errors[0].message // empty' 2>/dev/null)
    if [ -n "$errmsg" ]; then
      error "GraphQL error listing repos for $org: $errmsg"
      return 1
    fi

    check_rate_limit "$response"

    # Extract repo names (skip archived/empty repos)
    echo "$response" | jq -r '.data.organization.repositories.nodes[] | select(.isArchived == false and .isEmpty == false) | .name'

    has_next=$(echo "$response" | jq -r '.data.organization.repositories.pageInfo.hasNextPage')
    cursor=$(echo "$response" | jq -r '.data.organization.repositories.pageInfo.endCursor')
  done
}

# List all orgs for an enterprise, writes org logins to stdout
list_enterprise_orgs() {
  local ent="$1"
  local page=1

  while true; do
    local response
    if [ "$AUTH_MODE" = "cli" ]; then
      response=$(gh api "/enterprises/$ent/organizations?per_page=100&page=$page" 2>/dev/null)
    else
      response=$(curl -sS \
        -H "Authorization: bearer $INSTALL_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/enterprises/$ent/organizations?per_page=100&page=$page")
    fi

    local count
    count=$(echo "$response" | jq 'length')
    if [ "$count" = "0" ] || [ "$count" = "null" ]; then
      break
    fi

    echo "$response" | jq -r '.[].login'
    page=$((page + 1))
  done
}

###############################################################################
# Commit Stats Collection (Batched GraphQL)
###############################################################################

# Build a batched GraphQL query for N repos' commit history
build_commit_query() {
  local org="$1"
  shift
  local repos=("$@")

  local fragments=""
  local idx=0
  for repo in "${repos[@]}"; do
    local alias="repo_${idx}"
    fragments="${fragments}
    ${alias}: repository(owner: \"$org\", name: \"$repo\") {
      name
      defaultBranchRef {
        target {
          ... on Commit {
            history(since: \"$SINCE_DATE\", first: 100) {
              totalCount
              nodes {
                additions
                deletions
                author {
                  user { login }
                  name
                  email
                }
              }
              pageInfo { hasNextPage endCursor }
            }
          }
        }
      }
    }"
    idx=$((idx + 1))
  done

  echo "{ $fragments rateLimit { remaining resetAt } }"
}

# Fetch additional pages of commit history for a single repo
fetch_remaining_commits() {
  local org="$1"
  local repo="$2"
  local cursor="$3"
  local outfile="$4"

  local has_next=true
  while [ "$has_next" = "true" ]; do
    local query
    query="{ repository(owner: \"$org\", name: \"$repo\") { defaultBranchRef { target { ... on Commit { history(since: \"$SINCE_DATE\", first: 100, after: \"$cursor\") { nodes { additions deletions author { user { login } name email } } pageInfo { hasNextPage endCursor } } } } } } rateLimit { remaining resetAt } }"

    local response
    response=$(graphql_query "$query")
    check_rate_limit "$response"

    # Append commit data
    echo "$response" | jq -c '.data.repository.defaultBranchRef.target.history.nodes[]?' >> "$outfile"

    has_next=$(echo "$response" | jq -r '.data.repository.defaultBranchRef.target.history.pageInfo.hasNextPage // false')
    cursor=$(echo "$response" | jq -r '.data.repository.defaultBranchRef.target.history.pageInfo.endCursor // empty')
    if [ -z "$cursor" ]; then
      break
    fi
  done
}

# Process a batch of repos: query commits, append to raw data file
process_repo_batch() {
  local org="$1"
  shift
  local repos=("$@")
  local raw_file="$TEMP_DIR/raw_commits.jsonl"

  local query
  query=$(build_commit_query "$org" "${repos[@]}")

  local response
  response=$(graphql_query "$query")

  # Check for top-level errors
  local errmsg
  errmsg=$(echo "$response" | jq -r '.errors[0].message // empty' 2>/dev/null)
  if [ -n "$errmsg" ]; then
    warn "GraphQL error in batch: $errmsg (repos: ${repos[*]})"
    return 0
  fi

  check_rate_limit "$response"

  # Extract data for each repo in the batch
  local idx=0
  for repo in "${repos[@]}"; do
    local alias
    local alias="repo_${idx}"

    local repo_data
    repo_data=$(echo "$response" | jq -c ".data.${alias}" 2>/dev/null)

    if [ "$repo_data" = "null" ] || [ -z "$repo_data" ]; then
      idx=$((idx + 1))
      continue
    fi

    local repo_name
    repo_name=$(echo "$repo_data" | jq -r '.name // empty')
    if [ -z "$repo_name" ]; then
      repo_name="$repo"
    fi

    # Extract commits from first page
    echo "$repo_data" | jq -c --arg org "$org" --arg repo "$repo_name" \
      '.defaultBranchRef.target.history.nodes[]? | {org: $org, repo: $repo, additions: (.additions // 0), deletions: (.deletions // 0), author: (.author.user.login // .author.name // .author.email // "unknown")}' \
      >> "$raw_file" 2>/dev/null

    # Check if pagination needed
    local has_next
    has_next=$(echo "$repo_data" | jq -r '.defaultBranchRef.target.history.pageInfo.hasNextPage // false' 2>/dev/null)
    if [ "$has_next" = "true" ]; then
      local cursor
      cursor=$(echo "$repo_data" | jq -r '.defaultBranchRef.target.history.pageInfo.endCursor' 2>/dev/null)
      log "  Paginating commits for $org/$repo_name..."

      # Fetch remaining pages into a temp file, then convert to JSONL
      local page_file="$TEMP_DIR/page_${org}_${repo_name}.jsonl"
      fetch_remaining_commits "$org" "$repo_name" "$cursor" "$page_file"

      # Convert raw commit nodes to our standard format
      if [ -f "$page_file" ]; then
        jq -c --arg org "$org" --arg repo "$repo_name" \
          '{org: $org, repo: $repo, additions: (.additions // 0), deletions: (.deletions // 0), author: (.author.user.login // .author.name // .author.email // "unknown")}' \
          "$page_file" >> "$raw_file" 2>/dev/null
      fi
    fi

    idx=$((idx + 1))
  done
}

###############################################################################
# Main Processing
###############################################################################

# Collect repos for all target orgs
ORGS_FILE="$TEMP_DIR/orgs.txt"
REPOS_FILE="$TEMP_DIR/repos.txt"
RAW_FILE="$TEMP_DIR/raw_commits.jsonl"

touch "$RAW_FILE"

if [ -n "$ENTERPRISE" ]; then
  log "Listing organizations in enterprise: $ENTERPRISE"
  list_enterprise_orgs "$ENTERPRISE" > "$ORGS_FILE"
  org_count=$(wc -l < "$ORGS_FILE" | tr -d ' ')
  log "Found $org_count organizations"
else
  echo "$ORG" > "$ORGS_FILE"
fi

total_repos=0

while IFS= read -r current_org; do
  [ -z "$current_org" ] && continue
  log "Listing repos for org: $current_org"

  list_org_repos "$current_org" > "$REPOS_FILE"

  # Apply --max-repos limit if set
  if [ "$MAX_REPOS" -gt 0 ] 2>/dev/null; then
    head -n "$MAX_REPOS" "$REPOS_FILE" > "$REPOS_FILE.tmp" && mv "$REPOS_FILE.tmp" "$REPOS_FILE"
  fi

  repo_count=$(wc -l < "$REPOS_FILE" | tr -d ' ')
  total_repos=$((total_repos + repo_count))
  log "Found $repo_count repos in $current_org"

  # Process repos in batches
  batch=()
  batch_num=0
  while IFS= read -r repo_name; do
    [ -z "$repo_name" ] && continue
    batch+=("$repo_name")

    if [ ${#batch[@]} -ge "$BATCH_SIZE" ]; then
      batch_num=$((batch_num + 1))
      log "  Processing batch $batch_num (${#batch[@]} repos)..."
      process_repo_batch "$current_org" "${batch[@]}"
      batch=()
      if [ "$TEST_MODE" = true ]; then
        log "  Test mode: stopping after first batch"
        break
      fi
    fi
  done < "$REPOS_FILE"

  # Process remaining repos (skip if test mode already processed a batch)
  if [ ${#batch[@]} -gt 0 ] && { [ "$TEST_MODE" != true ] || [ "$batch_num" -eq 0 ]; }; then
    batch_num=$((batch_num + 1))
    log "  Processing batch $batch_num (${#batch[@]} repos)..."
    process_repo_batch "$current_org" "${batch[@]}"
  fi

done < "$ORGS_FILE"

log "Total repos processed: $total_repos"

###############################################################################
# Aggregation
###############################################################################

log "Aggregating results..."

CONTRIB_FILE="$TEMP_DIR/contrib_agg.json"
ORG_FILE="$TEMP_DIR/org_agg.json"

if [ ! -s "$RAW_FILE" ]; then
  warn "No commit data collected. This may indicate empty repos or permission issues."
  echo "[]" > "$CONTRIB_FILE"
  echo "[]" > "$ORG_FILE"
else
  # Per-contributor aggregation
  jq -s '
    group_by(.author) |
    map({
      contributor: .[0].author,
      additions: (map(.additions) | add),
      deletions: (map(.deletions) | add),
      commits: length,
      repos: (map(.repo) | unique | length),
      orgs: (map(.org) | unique)
    }) |
    sort_by(-.additions)
  ' "$RAW_FILE" > "$CONTRIB_FILE"

  # Per-org aggregation
  jq -s '
    group_by(.org) |
    map({
      organization: .[0].org,
      additions: (map(.additions) | add),
      deletions: (map(.deletions) | add),
      commits: length,
      repos: (map(.repo) | unique | length),
      contributors: (map(.author) | unique | length)
    }) |
    sort_by(-.additions)
  ' "$RAW_FILE" > "$ORG_FILE"
fi

# Summary stats
total_additions=$(jq '[.[].additions] | add // 0' "$CONTRIB_FILE")
total_deletions=$(jq '[.[].deletions] | add // 0' "$CONTRIB_FILE")
total_commits=$(jq '[.[].commits] | add // 0' "$CONTRIB_FILE")
total_contributors=$(jq 'length' "$CONTRIB_FILE")
total_orgs=$(jq 'length' "$ORG_FILE")

###############################################################################
# Output Generation
###############################################################################

# JSON output
if [ "$GENERATE_JSON" = true ]; then
  cp "$CONTRIB_FILE" "$OUT_DIR/loc_by_contributor.json"
  cp "$ORG_FILE" "$OUT_DIR/loc_by_org.json"

  jq -n \
    --arg since "$SINCE_DATE" \
    --argjson days "$DAYS" \
    --argjson repos "$total_repos" \
    --argjson contributors "$total_contributors" \
    --argjson orgs "$total_orgs" \
    --argjson additions "$total_additions" \
    --argjson deletions "$total_deletions" \
    --argjson commits "$total_commits" \
    '{
      since: $since,
      days: $days,
      total_repos: $repos,
      total_contributors: $contributors,
      total_orgs: $orgs,
      total_additions: $additions,
      total_deletions: $deletions,
      total_commits: $commits
    }' > "$OUT_DIR/summary.json"

  log "JSON output: $OUT_DIR/loc_by_contributor.json, loc_by_org.json, summary.json"
fi

# CSV output
if [ "$GENERATE_CSV" = true ]; then
  # Contributor CSV
  {
    echo "contributor,additions,deletions,commits,repos"
    jq -r '.[] | [.contributor, .additions, .deletions, .commits, .repos] | @csv' "$CONTRIB_FILE"
  } > "$OUT_DIR/loc_by_contributor.csv"

  # Org CSV
  {
    echo "organization,additions,deletions,commits,repos,contributors"
    jq -r '.[] | [.organization, .additions, .deletions, .commits, .repos, .contributors] | @csv' "$ORG_FILE"
  } > "$OUT_DIR/loc_by_org.csv"

  log "CSV output: $OUT_DIR/loc_by_contributor.csv, loc_by_org.csv"
fi

###############################################################################
# Summary
###############################################################################

echo ""
echo -e "${GREEN}=== Lines of Code Stats ===${NC}"
echo "Period:        Last $DAYS days (since $SINCE_DATE)"
echo "Organizations: $total_orgs"
echo "Repositories:  $total_repos"
echo "Contributors:  $total_contributors"
echo "Additions:     $total_additions"
echo "Deletions:     $total_deletions"
echo "Total commits: $total_commits"
echo "Output:        $OUT_DIR/"
echo ""

log "Done."
