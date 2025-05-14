#!/bin/bash
# This script fetches the billing seats data for a specified GitHub enterprise organization and calculates the difference in days between the created_at and last_activity_at dates for each user.
# If last_activity_at is null or empty, it lists the created_at date in a user-friendly format.
# https://docs.github.com/en/enterprise-cloud@latest/rest/copilot/copilot-user-management
# It uses the GitHub CLI to make API calls and jq to parse JSON data.

# - Fetches the billing seats data using the GitHub CLI.
# - Extracts the created_at and last_activity_at fields from the JSON response.
# - Converts the dates to seconds since epoch.
# - Calculates the difference in days between the two dates.
# - Outputs the result, categorizing users as active, inactive, or with null dates.

# Usage:
# ./inactive_copilot.sh [output_file]
# This script fetches the billing seats data for a specified GitHub enterprise organization and calculates user activity.
# Check if jq & gh cli are installed

# Variables:
# Replace all variables with your own values

# EMU: The slug of the GitHub enterprise organization to fetch billing seats data from.

EMU=octodemo

if ! command -v jq &> /dev/null; then
    echo "jq could not be found. Please install jq to run this script."
    exit 1
fi
# Check if gh is installed  
if ! command -v gh &> /dev/null; then
    echo "gh could not be found. Please install GitHub CLI to run this script."
    exit 1
fi

# Determine output destination
output_file=""
if [ "$#" -eq 1 ]; then
    output_file="$1"
fi

# Fetch the billing seats data
response=$(gh api /enterprises/$EMU/copilot/billing/seats --paginate)

# Initialize arrays to hold users based on their login activity
inactive_users=()
active_users=()
inactive_created_this_quarter=()
null_dates=()

# Iterate over each seat in the response
while IFS= read -r seat; do
    # Extract the login, created_at and last_activity_at fields using jq
    login=$(echo "$seat" | jq -r '.assignee.login')
    created_at=$(echo "$seat" | jq -r '.created_at')
    last_activity_at=$(echo "$seat" | jq -r '.last_activity_at')

    # Check if the dates are not null and not empty
    if [ "$created_at" != "null" ] && [ "$created_at" != "" ]; then
        current_date_seconds=$(date "+%s")
        
        # Convert dates to seconds
        if [[ "$(uname)" == "Darwin" ]]; then
            if [[ $created_at == *Z ]]; then
                created_at_seconds=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${created_at}" "+%s")
            else
                created_at_formatted=$(echo "${created_at}" | sed 's/\([+-][0-9][0-9]\):\([0-9][0-9]\)$/\1\2/')
                created_at_seconds=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "${created_at_formatted}" "+%s")
            fi
            if [ "$last_activity_at" != "null" ] && [ "$last_activity_at" != "" ]; then
                if [[ $last_activity_at == *Z ]]; then
                    last_activity_at_seconds=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${last_activity_at}" "+%s")
                else
                    last_activity_at_formatted=$(echo "${last_activity_at}" | sed 's/\([+-][0-9][0-9]\):\([0-9][0-9]\)$/\1\2/')
                    last_activity_at_seconds=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "${last_activity_at_formatted}" "+%s")
                fi
            fi
        else
            created_at_seconds=$(date -d "${created_at}" "+%s")
            if [ "$last_activity_at" != "null" ] && [ "$last_activity_at" != "" ]; then
                last_activity_at_seconds=$(date -d "${last_activity_at}" "+%s")
            fi
        fi

        # Compute differences in days
        diff_created_days=$(( (current_date_seconds - created_at_seconds) / 86400 ))
        if [ "$last_activity_at" != "null" ] && [ "$last_activity_at" != "" ]; then
            diff_last_activity=$(( (current_date_seconds - last_activity_at_seconds) / 86400 ))
        fi
        
        # Categorize users based on the criteria
        if [ "$last_activity_at" != "null" ] && [ "$last_activity_at" != "" ]; then
            if [ "$diff_last_activity" -gt 90 ]; then
                inactive_users+=("$login")
            else
                active_users+=("$login")
            fi
        else
            if [ "$diff_created_days" -gt 90 ]; then
                inactive_users+=("$login")
            else
                inactive_created_this_quarter+=("$login ($created_at_formatted)")
            fi
        fi
    else
        null_dates+=("$login")
    fi
done <<< "$(echo "$response" | jq -c '.seats[]')"

# Output the results in a table format
output() {
    printf "%-30s %-20s\n" "User" "Status"
    printf "%-30s %-20s\n" "----" "------"

    for user in "${inactive_users[@]}"; do
        printf "%-30s %-20s\n" "$user" "Inactive (90+ days)"
    done

    for user in "${active_users[@]}"; do
        printf "%-30s %-20s\n" "$user" "Active (<90 days)"
    done

    for user in "${inactive_created_this_quarter[@]}"; do
        printf "%-30s %-20s\n" "$user" "Inactive & Created within 90 days"
    done

    for user in "${null_dates[@]}"; do
        printf "%-30s %-20s\n" "$user" "Null Dates"
    done
}

if [ -n "$output_file" ]; then
    output > "$output_file"
    echo "Output written to $output_file"
else
    output
fi
