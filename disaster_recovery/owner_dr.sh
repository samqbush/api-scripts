#!/usr/bin/env bash

# This script provides functionality to backup and restore GitHub organization owners.
# It uses the GitHub CLI (gh) and jq to interact with the GitHub API and process JSON data.

# Prequisites:
# An enterprise owner must join each organization as an organization owner that you wish to restore.

# Functions:
# - backup_owners: Backs up the list of organization owners (admins) for each organization
#   the user is an admin of. The list is saved to a file named <organization>_admins.txt.
# - restore_owners: Restores the organization owners from the backup files. It reads each
#   <organization>_admins.txt file and attempts to set the listed users as owners in the
#   corresponding organization.
# - test: Tests the script on a single organization provided as an argument.

# Usage:
# ./owner_dr.sh {backup|restore|test} [organization]
# - backup: Calls the backup_owners function to create backup files of organization owners.
# - restore: Calls the restore_owners function to restore organization owners from the backup files.
# - test: Calls the test function to test the script on a single organization.

# Permissions:
# - The script requires a fine-grained access token with "Members" organization permissions (read).
# - The actual API call to restore owners is commented out for safety. Uncomment the line to enable it.

function backup_owners() {
    # Get the list of organizations you are an enterprise owner for
    orgs=$(gh api /user/memberships/orgs | jq -r '.[] | select(.role=="admin") | .organization.login')

    # Iterate through each organization and get members with role=admin
    for ORG in $orgs; do
        echo "Organization: $ORG"
        gh api /orgs/$ORG/members?role=admin | jq -r '.[].login' > "${ORG}_admins.txt"
    done
}

function restore_owners() {
    # Loop through each file that matches the pattern *_admins.txt
    for file in *_admins.txt; do
        ORG=$(basename "$file" _admins.txt)
        echo "PROCESSING FILE: $file"
        # Read each line (username) from the file
        while IFS= read -r USERNAME; do
            echo "Restoring $USERNAME to owner in $ORG"
            # Uncomment the following line to actually perform the API call
            # gh api --method PUT /orgs/$ORG/memberships/$USERNAME -f "role=owner"
        done < "$file"
    done
}

function test() {
    if [ -z "$2" ]; then
        echo "Error: No organization provided for testing."
        echo "Usage: $0 test <organization>"
        exit 1
    fi

    ORG=$2
    echo "Testing on organization: $ORG"
    gh api /orgs/$ORG/members?role=admin | jq -r '.[].login' > "${ORG}_admins.txt"
    echo "Backup completed for $ORG. File: ${ORG}_admins.txt"
    echo "Restoring owners from ${ORG}_admins.txt"
    while IFS= read -r USERNAME; do
        echo "Restoring $USERNAME to owner in $ORG"
        # Uncomment the following line to actually perform the API call
        # gh api --method PUT /orgs/$ORG/memberships/$USERNAME -f "role=owner"
    done < "${ORG}_admins.txt"
}

if [ -z "$1" ]; then
    echo "Error: No argument provided."
    echo "Usage: $0 {backup|restore|test} [organization]"
    echo "Please provide an argument to specify the action: 'backup' to backup organization owners, 'restore' to restore them, or 'test' to test the script on a single organization."
    exit 1
elif [ "$1" == "backup" ]; then
    backup_owners
elif [ "$1" == "restore" ]; then
    restore_owners
elif [ "$1" == "test" ]; then
    test "$@"
else
    echo "Usage: $0 {backup|restore|test} [organization]"
    exit 1
fi