#!/usr/bin/env bash
# github_emu_report.sh
#
# Usage:
#   GITHUB_TOKEN=your_token ./github_emu_report.sh --list-orgs
#     - Lists all organizations for the authenticated user and writes them to orgs.txt.
#
#   GITHUB_TOKEN=your_token ./github_emu_report.sh [output_file]
#     - Runs the report for orgs listed in orgs.txt. Output is written to stdout and [output_file] (default: github_emu_report.txt).
#
# Description:
#   Iterates through all organizations in orgs.txt, collects user activity and role data,
#   and outputs a human-readable table to stdout and a file.
#
# Requirements:
#   - GITHUB_TOKEN environment variable must be set with a GitHub personal access token (admin:org, repo, read:user scopes).
#   - curl, jq must be installed.
#
# Arguments:
#   [output_file]  Optional output file (default: github_emu_report.txt)


# For large organizations, it is recommended to build this script into something more robust and use a GitHub app to avoid rate limits
# https://docs.github.com/en/enterprise-cloud@latest/admin/managing-your-enterprise-account/creating-github-apps-for-your-enterprise

set -e

if [ -z "$GITHUB_TOKEN" ]; then
  echo "Error: GITHUB_TOKEN environment variable not set." >&2
  exit 1
fi

if [ -z "$1" ]; then
  OUTFILE="github_emu_report.txt"
else
  OUTFILE="$1"
fi

# Helper: GitHub API GET
gh_api() {
  url="$1"
  curl -sSL --http1.1 -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "$url"
}

# Step 1: List orgs for the authenticated user and output to orgs.txt
if [ "$1" = "--list-orgs" ]; then
  ORGS_URL="https://api.github.com/user/orgs?per_page=100"
  curl -sSL -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "$ORGS_URL" | jq -r '.[].login' > orgs.txt
  echo "Organization logins written to orgs.txt. Please review and edit as needed."
  exit 0
fi

# Step 2: Read orgs from orgs.txt (user must verify/edit this file)
if [ ! -f orgs.txt ]; then
  echo "orgs.txt not found. Run: $0 --list-orgs" >&2
  exit 1
fi
orgs=$(cat orgs.txt)

# Date 30 days ago (ISO 8601)
SINCE=$(date -u -v-30d '+%Y-%m-%dT%H:%M:%SZ')
NOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Table header
HEADER="| Username | User ID | Email | Role | Last Activity | PRs (30d) | Commits (30d) | Issues (30d) | Reviews (30d) | Comments (30d) |"
SEPARATOR="|---|---|---|---|---|---|---|---|---|---|"
echo "$HEADER" | tee "$OUTFILE"
echo "$SEPARATOR" | tee -a "$OUTFILE"

# Read already processed user/org pairs from OUTFILE
processed_pairs=""
if [ -f "$OUTFILE" ]; then
  processed_pairs=$(awk -F'|' 'NR>2 {gsub(/ /, "", $1); gsub(/ /, "", $3); print $1":"$3}' "$OUTFILE")
fi

for ORG in $orgs; do
  PAGE=1
  while :; do
    MEMBERS_URL="https://api.github.com/orgs/$ORG/members?per_page=100&page=$PAGE"
    members=$(gh_api "$MEMBERS_URL" | jq -r '.[].login')
    [ -z "$members" ] && break
    for USER in $members; do
      # Skip if already processed
      if echo "$processed_pairs" | grep -q "^$USER:$ORG$"; then
        continue
      fi
      # Get user info and org role (one call each)
      USER_URL="https://api.github.com/users/$USER"
      user_json=$(gh_api "$USER_URL")
      USER_ID=$(echo "$user_json" | jq -r '.id')
      EMAIL=$(echo "$user_json" | jq -r '.email // ""')
      ROLE_URL="https://api.github.com/orgs/$ORG/memberships/$USER"
      ROLE=$(gh_api "$ROLE_URL" | jq -r '.role')
      # Last activity (one events call)
      EVENTS_URL="https://api.github.com/users/$USER/events?per_page=100"
      events_json=$(gh_api "$EVENTS_URL")
      LAST_ACTIVITY=$(echo "$events_json" | jq -r '.[0].created_at // "N/A"')
      # PRs created in 30d (one search call)
      PRS=$(gh_api "https://api.github.com/search/issues?q=type:pr+author:$USER+org:$ORG+created:>=$SINCE" | jq -r '.total_count')
      # Issues opened in 30d (one search call)
      ISSUES=$(gh_api "https://api.github.com/search/issues?q=type:issue+author:$USER+org:$ORG+created:>=$SINCE" | jq -r '.total_count')
      # Comments in 30d (one search call for issue comments, one for PR review comments)
      COMMENTS_ISSUE=$(gh_api "https://api.github.com/search/issues?q=commenter:$USER+org:$ORG+updated:>=$SINCE" | jq -r '.total_count')
      COMMENTS_PR=$(gh_api "https://api.github.com/search/issues?q=type:pr+commenter:$USER+org:$ORG+updated:>=$SINCE" | jq -r '.total_count')
      COMMENTS=$((COMMENTS_ISSUE + COMMENTS_PR))
      # Commits pushed in 30d (estimate: count PushEvent in events_json)
      COMMITS=$(echo "$events_json" | jq -r --arg SINCE "$SINCE" '[.[] | select(.type=="PushEvent" and .created_at >= $SINCE)] | length')
      # Code reviews in 30d (estimate: count PullRequestReviewEvent in events_json)
      REVIEWS=$(echo "$events_json" | jq -r --arg SINCE "$SINCE" '[.[] | select(.type=="PullRequestReviewEvent" and .created_at >= $SINCE)] | length')
      # Output row
      printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n" "$USER" "$USER_ID" "$EMAIL" "$ROLE" "$LAST_ACTIVITY" "$PRS" "$COMMITS" "$ISSUES" "$REVIEWS" "$COMMENTS" | tee -a "$OUTFILE"
    done
    PAGE=$((PAGE+1))
  done
done

printf "\nReport complete. Output saved to %s\n" "$OUTFILE"
