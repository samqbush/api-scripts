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
    response=$(gh api graphql $GH_HOST_FLAG -f query="$query" 2>&1)

    if echo "$response" | jq -e '.errors' > /dev/null 2>&1; then
      echo "Error fetching organizations: $(echo "$response" | jq -r '.errors[0].message')" >&2
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

# Fetch all teams for a given org with member counts
fetch_teams() {
  local org="$1"

  gh api "orgs/$org/teams" $GH_HOST_FLAG --paginate --jq '.[] | {slug: .slug, name: .name, members_count: .members_count // 0}' 2>/dev/null | \
    while IFS= read -r team_json; do
      local team_name
      local member_count
      team_name=$(echo "$team_json" | jq -r '.name')
      member_count=$(echo "$team_json" | jq -r '.members_count')

      # If members_count is 0 or null, fetch actual count
      if [[ "$member_count" == "0" || "$member_count" == "null" ]]; then
        local slug
        slug=$(echo "$team_json" | jq -r '.slug')
        member_count=$(gh api "orgs/$org/teams/$slug/members" $GH_HOST_FLAG --paginate --jq 'length' 2>/dev/null | paste -sd+ - | bc 2>/dev/null || echo 0)
      fi

      echo "$org,$team_name,$member_count"
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
echo "org,team,member_count" > "$csv_file"

# Collect all results
all_results=()
org_count=0
team_total=0

while IFS= read -r org; do
  [[ -z "$org" ]] && continue
  org_count=$((org_count + 1))
  echo "[$org_count] Processing org: $org"

  while IFS= read -r line; do
    if [[ -n "$line" ]]; then
      all_results+=("$line")
      echo "$line" >> "$csv_file"
      team_total=$((team_total + 1))
    fi
  done < <(fetch_teams "$org")

  # Small delay to avoid rate limiting
  sleep 0.5
done <<< "$orgs"

# Generate JSON output
{
  echo "["
  local_first=true
  for row in "${all_results[@]}"; do
    IFS=',' read -r r_org r_team r_count <<< "$row"
    if [[ "$local_first" == "true" ]]; then
      local_first=false
    else
      echo ","
    fi
    # Escape any quotes in team names
    r_team=$(echo "$r_team" | sed 's/"/\\"/g')
    printf '  {"org": "%s", "team": "%s", "member_count": %s}' "$r_org" "$r_team" "${r_count:-0}"
  done
  echo ""
  echo "]"
} > "$json_file"

echo ""
echo "Done! Processed $org_count org(s), $team_total team(s) total."
echo "  CSV: $csv_file"
echo " JSON: $json_file"
