#!/bin/bash

# Usage:
# ./list_teams.sh
# This script fetches all teams in a specified GitHub organization and checks the number of members in each team.
# If a team has more than 5 members, it prints a message indicating that the team has more than 5 developers.
#
# Variables:
# ORG_NAME: The name of the GitHub organization to fetch teams from.
# PER_PAGE: The number of items to fetch per page when using pagination.
#
# Functions:
# get_teams: Fetches all teams in the specified organization using pagination and returns a JSON array of team names and member URLs.
#
# Main Script:
# 1. Fetches all teams using the get_teams function.
# 2. Loops through each team and extracts the team name and members URL.
# 3. Fetches the number of members in each team using the members URL.
# 4. Checks if the team has more than 5 members and prints a message if true.

ORG_NAME="octodemo"
PER_PAGE=100

# Function to get all teams using pagination
get_teams() {
  echo "Fetching all teams..."
  gh api "orgs/$ORG_NAME/teams" --paginate | jq -c '.[] | {name: .name, members_url: .members_url}'
}

# Get all teams
teams=$(get_teams)

# Loop through each team and check the number of members
echo "Processing teams..."
echo "$teams" | while read -r team; do
  team_name=$(echo "$team" | jq -r '.name')
  members_url=$(echo "$team" | jq -r '.members_url' | sed 's/{\/member}//g')
  
  # Get the number of members in the team
  member_count=$(gh api "$members_url" --paginate | jq '. | length' 2>/dev/null || echo 0)
  
  # Check if the team has more than 5 members
  if [ "$member_count" -gt 5 ] 2>/dev/null; then
    echo "$team_name has more than 5 developers"
  fi
done
