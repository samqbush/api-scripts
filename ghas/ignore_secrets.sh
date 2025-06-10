#!/usr/bin/env bash

###############################################################################
# GitHub Secret Scanning Alert Manager
#
# This script fetches secret scanning alerts from a GitHub repository and 
# filters them based on commit dates. It helps identify when secrets were
# first introduced to the codebase.
#
# Prerequisites:
#   1. GitHub CLI (gh) must be installed and authenticated
#      Install from: https://cli.github.com/
#   2. jq must be installed for JSON parsing
#      On macOS: brew install jq
#   3. Proper permissions to access the repository's secret scanning alerts
#
# Usage: 
#   ./ignore_secrets.sh <repository> <date> [flags]
#
# Arguments:
#   <repository>    Owner/repo name (e.g., "octocat/hello-world")
#   <date>          Cut-off date in YYYY-MM-DD format
#                   Alerts with commits on or before this date are filtered
#
# Flags:
#   --dry-run       Show alerts that would be ignored (on or before the date)
#   --list-alerts   Fast mode: only list alerts without date filtering
#   --no-ignore     Show all alerts regardless of date (deprecated)
#   --verbose       Show detailed processing information
#   --debug         Show raw API responses for debugging
#
# Examples:
#   # Ignore alerts from commits on or before April 15, 2025
#   ./ignore_secrets.sh octocat/hello-world 2025-04-15
#
#   # Show what would be ignored (alerts on or before April 15, 2025)
#   ./ignore_secrets.sh octocat/hello-world 2025-04-15 --dry-run
#
#   # Quick list of all alerts without date filtering
#   ./ignore_secrets.sh octocat/hello-world 2025-04-15 --list-alerts
#
###############################################################################

# Exit immediately if a command exits with a non-zero status
set -e

# Function to show script usage
show_usage() {
  echo "Usage: $0 <repository> <date> [flags]"
  echo ""
  echo "Arguments:"
  echo "  <repository>    GitHub repository in owner/repo format"
  echo "  <date>          Cut-off date (YYYY-MM-DD) - alerts on or before this date are filtered"
  echo ""
  echo "Flags:"
  echo "  --dry-run       Show only alerts that would be ignored (on or before the date)"
  echo "  --list-alerts   Skip commit date lookups to list alerts quickly"
  echo "  --no-ignore     Show all alerts regardless of date (deprecated)"
  echo "  --verbose       Show detailed processing information"
  echo "  --debug         Show raw API responses for debugging"
  echo ""
  echo "Examples:"
  echo "  ./ignore_secrets.sh octocat/hello-world 2025-04-15"
  echo "  ./ignore_secrets.sh octocat/hello-world 2025-04-15 --dry-run"
}

# Check for required arguments
if [ $# -lt 2 ]; then
  show_usage
  exit 1
fi

REPO=$1
IGNORE_DATE=$2

# Validate repository format
if [[ ! "$REPO" =~ ^[^/]+/[^/]+$ ]]; then
  echo "Error: Invalid repository format. Must be 'owner/repo'"
  show_usage
  exit 1
fi

# Validate date format
if [[ ! "$IGNORE_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "Error: Invalid date format. Must be YYYY-MM-DD"
  show_usage
  exit 1
fi

# Default flag values
IGNORE_ALERTS=true
DRY_RUN=false
DEBUG=false
VERBOSE=false
LIST_ALERTS=false

# Process all flags
for arg in "$@"; do
  case "$arg" in
    --no-ignore)
      IGNORE_ALERTS=false
      ;;
    --dry-run)
      DRY_RUN=true
      IGNORE_ALERTS=false
      ;;
    --debug)
      DEBUG=true
      ;;
    --verbose)
      VERBOSE=true
      ;;
    --list-alerts)
      LIST_ALERTS=true
      ;;
    --help|-h)
      show_usage
      exit 0
      ;;
  esac
done

# Create temporary directory for data storage
setup_temp_storage() {
  # Create temporary directory for commit data and tracking files
  TEMP_DIR=$(mktemp -d)
  COMMITS_DIR="$TEMP_DIR/commits"
  DATE_TRACK_FILE="$TEMP_DIR/dates.txt"
  TOTAL_PROCESSED_FILE="$TEMP_DIR/total_processed"
  TOTAL_MATCHING_FILE="$TEMP_DIR/total_matching"
  
  mkdir -p "$COMMITS_DIR"
  touch "$DATE_TRACK_FILE"
  echo "0" > "$TOTAL_PROCESSED_FILE"
  echo "0" > "$TOTAL_MATCHING_FILE"
  
  # Register cleanup function to run on exit
  trap 'rm -rf "$TEMP_DIR"' EXIT
}

# Increment a counter in a file
increment_counter() {
  local file=$1
  local value=$(cat "$file")
  echo $((value + 1)) > "$file"
}

# Get commit data with caching to reduce API calls
get_commit_data() {
  local commit_hash=$1
  local commit_file="$COMMITS_DIR/$commit_hash"
  
  # Return cached commit data if available
  if [ -f "$commit_file" ]; then
    cat "$commit_file"
  else
    # Otherwise fetch from GitHub API and cache
    gh api "/repos/$REPO/commits/$commit_hash" > "$commit_file" 2>/dev/null
    if [ $? -ne 0 ] || [ ! -s "$commit_file" ]; then
      echo ""
      return 1
    fi
    cat "$commit_file"
  fi
}

# Track a date and increment its count
track_date() {
  local date=$1
  
  if [ -z "$date" ]; then
    return
  fi
  
  # Check if date exists in our tracking file
  if grep -q "^$date:" "$DATE_TRACK_FILE" 2>/dev/null; then
    # Increment the count for this date
    local count=$(grep "^$date:" "$DATE_TRACK_FILE" | cut -d':' -f2)
    local new_count=$((count + 1))
    sed -i.bak "s/^$date:$count/$date:$new_count/" "$DATE_TRACK_FILE"
    rm -f "${DATE_TRACK_FILE}.bak" 2>/dev/null
  else
    # Add new date with count 1
    echo "$date:1" >> "$DATE_TRACK_FILE"
  fi
}

# Print summary statistics
print_summary() {
  local total_processed=$1
  local total_matching=$2
  
  echo -e "\n--- Summary ---"
  echo "Total alerts processed: $total_processed"
  echo "Total matching alerts: $total_matching"
  
  # Only show detailed date information when not in list-alerts mode
  if [ "$LIST_ALERTS" != "true" ]; then
    if $DRY_RUN && [ $total_matching -eq 0 ]; then
      echo -e "\nNo alerts found with commit date on or before: $IGNORE_DATE"
      echo -e "\nAvailable commit dates:"
      
      # Sort dates for better readability
      sort "$DATE_TRACK_FILE" | while IFS=: read -r date count; do
        echo "  $date: $count alerts"
      done
    elif $DRY_RUN; then
      echo -e "\nFound $total_matching alerts with commit date on or before: $IGNORE_DATE"
      echo -e "\nAvailable commit dates:"
      
      # Sort dates for better readability
      sort "$DATE_TRACK_FILE" | while IFS=: read -r date count; do
        echo "  $date: $count alerts"
      done
    fi
  fi
}

# Function to ignore an alert by updating its state
ignore_alert() {
  local alert_id=$1
  local resolution_comment="Ignored by ignore_secrets.sh on $(date +%Y-%m-%d)"

  # Update the alert state to resolved with resolution as false_positive
  gh api -X PATCH \
    -H "Accept: application/vnd.github+json" \
    "/repos/$REPO/secret-scanning/alerts/$alert_id" \
    -f state="resolved" \
    -f resolution="false_positive" \
    -f resolution_comment="$resolution_comment" >/dev/null 2>&1

  if [ $? -eq 0 ]; then
    echo "Alert $alert_id successfully ignored."
  else
    echo "Failed to ignore alert $alert_id."
  fi
}

# Main function to process secret scanning alerts
process_alerts() {
  # Fetch secret scanning alerts with pagination
  echo "Fetching secret scanning alerts from $REPO..."
  ALERTS=$(gh api --paginate "/repos/$REPO/secret-scanning/alerts" 2>/dev/null)
  
  # Check if the API call was successful
  if [ $? -ne 0 ]; then
    echo "Error: Failed to fetch secret scanning alerts."
    echo "Please check the repository name and your permissions."
    exit 1
  fi
  
  # Validate the API response
  if [ -z "$ALERTS" ] || ! echo "$ALERTS" | jq -e . >/dev/null 2>&1; then
    echo "Error: Invalid or empty response from the GitHub API."
    exit 1
  fi
  
  # When using --paginate, the response might be an array of arrays, so flatten it
  FLATTENED_ALERTS=$(echo "$ALERTS" | jq -c 'if type == "array" and (.[0] | type == "array") then flatten else . end')
  
  # Count the number of alerts
  ALERT_COUNT=$(echo "$FLATTENED_ALERTS" | jq 'length')
  echo "Found $ALERT_COUNT alerts in repository $REPO"
  
  # Process each alert
  echo "$FLATTENED_ALERTS" | jq -c '.[]' 2>/dev/null | while read -r ALERT; do
    ALERT_ID=$(echo "$ALERT" | jq -r '.number')
    
    # Debug output
    if $DEBUG; then
      echo "Processing alert: $ALERT"
    fi
    
    # Extract locations URL
    LOCATIONS_URL=$(echo "$ALERT" | jq -r '.locations_url')
    if [ -z "$LOCATIONS_URL" ] || [ "$LOCATIONS_URL" = "null" ]; then
      echo "Skipping alert $ALERT_ID: locations_url is missing or invalid."
      continue
    fi
    
    # Fetch locations for the alert
    LOCATIONS=$(gh api "$LOCATIONS_URL" 2>/dev/null)
    
    # Debug output
    if $DEBUG; then
      echo "Raw locations data for alert $ALERT_ID: $LOCATIONS"
    fi
    
    if [ -z "$LOCATIONS" ] || ! echo "$LOCATIONS" | jq -e . >/dev/null 2>&1; then
      echo "Skipping alert $ALERT_ID: Failed to fetch locations or invalid response."
      continue
    fi
    
    # Extract all commit_sha values from the locations data
    COMMIT_COUNT=$(echo "$LOCATIONS" | jq 'length')
    COMMIT_HASHES=$(echo "$LOCATIONS" | jq -r '.[].details.commit_sha' 2>/dev/null)
    if [ -z "$COMMIT_HASHES" ] || [ "$COMMIT_HASHES" = "null" ]; then
      echo "Skipping alert $ALERT_ID: commit_sha is missing or invalid."
      continue
    fi
    
    # Fast mode - just show the first commit without date filtering
    if $LIST_ALERTS; then
      FIRST_COMMIT_HASH=$(echo "$COMMIT_HASHES" | head -n 1)
      if [ $COMMIT_COUNT -gt 1 ]; then
        echo "Alert $ALERT_ID is associated with $COMMIT_COUNT commits. First commit: $FIRST_COMMIT_HASH"
      else
        echo "Alert $ALERT_ID is associated with commit $FIRST_COMMIT_HASH"
      fi
      increment_counter "$TOTAL_PROCESSED_FILE"
      increment_counter "$TOTAL_MATCHING_FILE"
      continue
    fi
    
    # Process each commit hash to find the earliest
    FIRST_COMMIT=true
    EARLIEST_COMMIT_DATE=""
    EARLIEST_COMMIT_HASH=""
    
    for COMMIT_HASH in $COMMIT_HASHES; do
      # Skip empty lines
      if [ -z "$COMMIT_HASH" ]; then
        continue
      fi
      
      # Fetch commit details with caching
      COMMIT=$(get_commit_data "$COMMIT_HASH")
      if [ -z "$COMMIT" ] || ! echo "$COMMIT" | jq -e . >/dev/null 2>&1; then
        if $VERBOSE; then
          echo "  Warning: Failed to fetch details for commit $COMMIT_HASH for alert $ALERT_ID."
        fi
        continue
      fi
      
      # Extract commit date
      COMMIT_DATE=$(echo "$COMMIT" | jq -r '.commit.author.date' 2>/dev/null | cut -d'T' -f1)
      if [ -z "$COMMIT_DATE" ] || [ "$COMMIT_DATE" = "null" ]; then
        if $VERBOSE; then
          echo "  Warning: Date is missing for commit $COMMIT_HASH for alert $ALERT_ID."
        fi
        continue
      fi
      
      # Track all observed commit dates
      track_date "$COMMIT_DATE"
      
      # Track the earliest commit date
      if [ "$FIRST_COMMIT" = true ] || [[ "$COMMIT_DATE" < "$EARLIEST_COMMIT_DATE" ]]; then
        EARLIEST_COMMIT_DATE="$COMMIT_DATE"
        EARLIEST_COMMIT_HASH="$COMMIT_HASH"
        FIRST_COMMIT=false
      fi
    done
    
    # If no valid commits were found, skip this alert
    if [ "$FIRST_COMMIT" = true ]; then
      echo "Skipping alert $ALERT_ID: No valid commits found."
      continue
    fi
    
    # Use the earliest commit date for filtering
    COMMIT_DATE="$EARLIEST_COMMIT_DATE"
    COMMIT_HASH="$EARLIEST_COMMIT_HASH"
    
    increment_counter "$TOTAL_PROCESSED_FILE"
    
    # Decide whether to show or ignore this alert based on flags
    
    # For dry run mode, only show alerts on or before the cut-off date
    if $DRY_RUN && ! [[ "$COMMIT_DATE" < "$IGNORE_DATE" || "$COMMIT_DATE" == "$IGNORE_DATE" ]]; then
      if $VERBOSE; then
        echo "Skipping alert $ALERT_ID: earliest commit date $COMMIT_DATE is after ignore date $IGNORE_DATE."
      fi
      continue
    fi
    
    # In normal mode, ignore alerts on or before the cut-off date
    if $IGNORE_ALERTS && [[ "$COMMIT_DATE" < "$IGNORE_DATE" || "$COMMIT_DATE" == "$IGNORE_DATE" ]]; then
      echo "Ignoring alert $ALERT_ID from commit $COMMIT_HASH on $COMMIT_DATE (on or before $IGNORE_DATE)."
      ignore_alert "$ALERT_ID"
      continue
    fi
    
    increment_counter "$TOTAL_MATCHING_FILE"
    if [ $COMMIT_COUNT -gt 1 ]; then
      echo "Alert $ALERT_ID is associated with $COMMIT_COUNT commits. Earliest: $COMMIT_HASH on $COMMIT_DATE."
    else
      echo "Alert $ALERT_ID is associated with commit $COMMIT_HASH on $COMMIT_DATE."
    fi
  done
  
  # Read final counter values
  TOTAL_PROCESSED=$(cat "$TOTAL_PROCESSED_FILE")
  TOTAL_MATCHING=$(cat "$TOTAL_MATCHING_FILE")
  
  # Print summary statistics
  print_summary "$TOTAL_PROCESSED" "$TOTAL_MATCHING"
}

# Script execution starts here
setup_temp_storage
process_alerts