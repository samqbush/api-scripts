#!/usr/bin/env bash

# Usage:
#   ./list_org_teams.sh --enterprise <slug> [--hostname <ghes-host>] [--out <directory>]
#   ./list_org_teams.sh
#
# Description:
#   Lists all organizations in a GitHub Enterprise and all teams within each
#   organization, including member counts. Outputs results in both CSV and JSON.
#   Supports both GitHub Enterprise Cloud and GitHub Enterprise Server (3.16+).
#
# Arguments:
#   --enterprise <slug>      GitHub Enterprise slug (prompted if not provided)
#   --hostname <hostname>    GHES hostname (e.g., ghes.company.com). Omit for GitHub.com.
#   --out <directory>        Output directory for results (default: enterprise_teams_<timestamp>)
#
# Examples:
#   # GitHub Enterprise Cloud
#   ./list_org_teams.sh --enterprise my-enterprise
#
#   # GitHub Enterprise Server
#   ./list_org_teams.sh --enterprise my-enterprise --hostname ghes.company.com
#
# Prerequisites:
#   - GitHub CLI installed and authenticated (gh auth login)
#     For GHES: gh auth login --hostname ghes.company.com
#   - jq installed
#   - Enterprise admin or org read access
#   - GHES 3.16+ required for Enterprise Server instances
#
# Token Scopes Required:
#   - read:org
#   - read:enterprise
#
# Output Files:
#   <out>/enterprise_teams.csv   - CSV with columns: org,team,member_count
#   <out>/enterprise_teams.json  - JSON array of {org, team, member_count} objects

set -euo pipefail

ENTERPRISE=""
OUT_DIR=""
HOSTNAME=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --enterprise)
      ENTERPRISE="$2"
      shift 2
      ;;
    --hostname)
      HOSTNAME="$2"
      shift 2
      ;;
    --out)
      OUT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      head -38 "$0" | grep '^#' | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# Prompt for enterprise if not provided
if [[ -z "$ENTERPRISE" ]]; then
  read -rp "Enter GitHub Enterprise slug: " ENTERPRISE
  if [[ -z "$ENTERPRISE" ]]; then
    echo "Error: Enterprise slug is required."
    exit 1
  fi
fi

# Set default output directory
if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="enterprise_teams_$(date +%Y%m%d_%H%M%S)"
fi

# Build hostname flag for gh api calls
GH_HOST_FLAG=""
if [[ -n "$HOSTNAME" ]]; then
  GH_HOST_FLAG="--hostname $HOSTNAME"
fi

mkdir -p "$OUT_DIR"

echo "Enterprise: $ENTERPRISE"
if [[ -n "$HOSTNAME" ]]; then
  echo "Hostname: $HOSTNAME (GHES)"
else
  echo "Hostname: github.com (Cloud)"
fi
echo "Output directory: $OUT_DIR"
echo ""

# Fetch all organizations in the enterprise using GraphQL pagination
fetch_orgs() {
  local orgs=()
  local cursor=""
  local has_next="true"

  echo "Fetching organizations from enterprise '$ENTERPRISE'..." >&2

  while [[ "$has_next" == "true" ]]; do
    local after_clause=""
    if [[ -n "$cursor" ]]; then
      after_clause=", after: \"$cursor\""
    fi

    local query="query {
      enterprise(slug: \"$ENTERPRISE\") {
        organizations(first: 100${after_clause}) {
          pageInfo {
            hasNextPage
            endCursor
          }
          nodes {
            login
          }
        }
      }
    }"

    local response
    local gh_stderr
    gh_stderr=$(mktemp)
    response=$(gh api graphql $GH_HOST_FLAG -f query="$query" 2>"$gh_stderr") || {
      echo "Error calling GitHub API: $(cat "$gh_stderr")" >&2
      rm -f "$gh_stderr"
      exit 1
    }
    rm -f "$gh_stderr"

    local errmsg
    errmsg=$(echo "$response" | jq -r '.errors[0].message // empty')
    if [[ -n "$errmsg" ]]; then
      echo "Error fetching organizations: $errmsg" >&2
      exit 1
    fi

    local page_orgs
    page_orgs=$(echo "$response" | jq -r '.data.enterprise.organizations.nodes[].login')
    while IFS= read -r org; do
      if [[ -n "$org" ]]; then
        orgs+=("$org")
      fi
    done <<< "$page_orgs"

    has_next=$(echo "$response" | jq -r '.data.enterprise.organizations.pageInfo.hasNextPage')
    cursor=$(echo "$response" | jq -r '.data.enterprise.organizations.pageInfo.endCursor')
  done

  echo "Found ${#orgs[@]} organization(s)." >&2
  printf '%s\n' "${orgs[@]}"
}

# Fetch all teams for a given org with member counts (outputs NDJSON)
fetch_teams() {
  local org="$1"

  gh api "orgs/$org/teams" $GH_HOST_FLAG --paginate --jq '.[] | {slug: .slug, name: .name, members_count: .members_count}' 2>/dev/null | jq -c '.' | \
    while IFS= read -r team_json; do
      local team_name
      local member_count
      local slug
      team_name=$(echo "$team_json" | jq -r '.name')
      member_count=$(echo "$team_json" | jq -r '.members_count // empty')
      slug=$(echo "$team_json" | jq -r '.slug')

      # If members_count is null/missing, fetch actual count
      if [[ -z "$member_count" ]]; then
        member_count=$(gh api "orgs/$org/teams/$slug/members" $GH_HOST_FLAG --paginate --jq 'length' 2>/dev/null | awk '{s+=$1} END {print s+0}')
      fi

      # Output as JSON object for safe downstream handling
      jq -n --arg org "$org" --arg team "$team_name" --argjson count "${member_count:-0}" \
        '{org: $org, team: $team, member_count: $count}'
    done
}

# Main execution
orgs=$(fetch_orgs)

if [[ -z "$orgs" ]]; then
  echo "No organizations found in enterprise '$ENTERPRISE'."
  exit 0
fi

# Initialize CSV with header
csv_file="$OUT_DIR/enterprise_teams.csv"
json_file="$OUT_DIR/enterprise_teams.json"
echo '"org","team","member_count"' > "$csv_file"

# Collect all results as NDJSON
ndjson_file=$(mktemp)
org_count=0
team_total=0

while IFS= read -r org; do
  [[ -z "$org" ]] && continue
  org_count=$((org_count + 1))
  echo "[$org_count] Processing org: $org"

  while IFS= read -r line; do
    if [[ -n "$line" ]]; then
      echo "$line" >> "$ndjson_file"
      # Append properly quoted CSV row
      echo "$line" | jq -r '[.org, .team, (.member_count | tostring)] | @csv' >> "$csv_file"
      team_total=$((team_total + 1))
    fi
  done < <(fetch_teams "$org")

  # Small delay to avoid rate limiting
  sleep 0.5
done <<< "$orgs"

# Generate JSON array from NDJSON
jq -s '.' "$ndjson_file" > "$json_file"
rm -f "$ndjson_file"

echo ""
echo "Done! Processed $org_count org(s), $team_total team(s) total."
echo "  CSV: $csv_file"
echo " JSON: $json_file"
