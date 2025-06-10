#!/usr/bin/env bash

# Usage:
# ./get_commits.sh
# This script gathers the number of commits to repositories across an organization over the last 3 months.

# Add the following permissions to the GitHub fine-grained token:
# Repository Permissions:
#     Contents: Read-only
#     Metadata: Read-only
#     Commit statuses: Read-only
# Organization Permissions:
#     Email addresses: Read-only (if you need to access organization member information)

# Make sure to: install GitHub CLI (e.g., brew install gh) and login with gh auth login
# Make sure to: install jq (e.g., brew install jq)

# GitHub organization and token
organization="octodemo"

if [ -z "$token" ]; then
  echo "GITHUB_TOKEN environment variable not set" >&2
  exit 1
fi

# Calculate date three months ago
since_date=$(date -u -v-3m +"%Y-%m-%dT%H:%M:%SZ")

# Get list of repositories in the organization
repos=$(gh repo list $organization --limit 100 --json name --jq '.[].name')

# Iterate over repositories and get the number of commits in the last 3 months
for repo_name in $repos; do
  commits=$(gh api -H "Accept: application/vnd.github.v3+json" \
    "/repos/$organization/$repo_name/commits?since=$since_date" | jq length)
  echo "Repository: $repo_name, Commits in last 3 months: $commits"
done