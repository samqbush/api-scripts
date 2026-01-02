#!/usr/bin/env bash

################################################################################
# Script: get_activities.sh
# Description: Fetch Strava activities for a specified date range and generate
#              summary reports. Defaults to July 2025 for exploratory analysis.
#
# Usage: 
#   STRAVA_ACCESS_TOKEN=your_token ./get_activities.sh
#   ./get_activities.sh --token your_token
#   ./get_activities.sh --token your_token --after 2025-01-01 --before 2025-12-31
#
# Arguments:
#   --token TOKEN        Strava API access token (or set STRAVA_ACCESS_TOKEN env var)
#   --after DATE         Start date in YYYY-MM-DD format (default: 2025-07-01)
#   --before DATE        End date in YYYY-MM-DD format (default: 2025-08-01)
#   --output-dir DIR     Custom output directory (default: strava_activities_TIMESTAMP)
#   --help               Show this help message
#
# Env file support:
#   Create a .strava (not committed) with values like:
#     STRAVA_ACCESS_TOKEN=...
#     STRAVA_REFRESH_TOKEN=...
#     STRAVA_CLIENT_ID=193221
#     STRAVA_CLIENT_SECRET=...
#   The script will source .strava automatically if present.
#
# Requirements:
#   - curl (for API calls)
#   - jq (for JSON parsing)
#   - date command (for timestamp conversion)
#
# Examples:
#   # Fetch July 2025 activities (default)
#   STRAVA_ACCESS_TOKEN=your_token ./get_activities.sh
#
#   # Fetch all 2025 activities
#   ./get_activities.sh --token your_token --after 2025-01-01 --before 2026-01-01
#
#   # Fetch Q4 2025 activities with custom output directory
#   ./get_activities.sh --token your_token --after 2025-10-01 --before 2026-01-01 --output-dir q4_activities
#
# Output:
#   Creates a timestamped directory containing:
#   - raw_activities.json: Complete API responses
#   - activities_summary.csv: Activity listing with key metrics
#   - activity_types.txt: Summary of activity types found
#   - distance_summary.txt: Total distance calculations
#
################################################################################

set -e  # Exit on error

# Default values
AFTER_DATE="2025-07-01"
BEFORE_DATE="2025-08-01"
OUTPUT_DIR=""
PER_PAGE=200
API_BASE="https://www.strava.com/api/v3"

# Load environment variables from .strava if available (keeps secrets out of the script)
if [[ -f "$(dirname "$0")/../.strava" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$(dirname "$0")/../.strava"
    set +a
fi

# Helper: refresh access token if refresh token and client credentials are available
REFRESHED=false
refresh_access_token() {
    if [[ -z "$STRAVA_REFRESH_TOKEN" || -z "$STRAVA_CLIENT_ID" || -z "$STRAVA_CLIENT_SECRET" ]]; then
        echo "Cannot refresh: STRAVA_REFRESH_TOKEN, STRAVA_CLIENT_ID, or STRAVA_CLIENT_SECRET missing."
        return 1
    fi

    echo "Access token failed; attempting refresh..."
    RESPONSE=$(curl -s -X POST https://www.strava.com/oauth/token \
        -d client_id="$STRAVA_CLIENT_ID" \
        -d client_secret="$STRAVA_CLIENT_SECRET" \
        -d grant_type=refresh_token \
        -d refresh_token="$STRAVA_REFRESH_TOKEN")

    if echo "$RESPONSE" | jq -e 'has("access_token")' >/dev/null 2>&1; then
        STRAVA_ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r '.access_token')
        STRAVA_REFRESH_TOKEN=$(echo "$RESPONSE" | jq -r '.refresh_token')
        EXPIRES_AT=$(echo "$RESPONSE" | jq -r '.expires_at')

        if date --version >/dev/null 2>&1; then
            EXPIRES_HUMAN=$(date -d "@${EXPIRES_AT}" "+%Y-%m-%d %H:%M:%S")
        else
            EXPIRES_HUMAN=$(date -j -f "%s" "$EXPIRES_AT" "+%Y-%m-%d %H:%M:%S")
        fi

        echo "Refresh succeeded; token expires at ${EXPIRES_HUMAN}."
        echo "(Update your .env with the new access and refresh tokens if you want them persisted.)"
        REFRESHED=true
        return 0
    else
        echo "Token refresh failed. Response: $RESPONSE"
        return 1
    fi
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --token)
            STRAVA_ACCESS_TOKEN="$2"
            shift 2
            ;;
        --after)
            AFTER_DATE="$2"
            shift 2
            ;;
        --before)
            BEFORE_DATE="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --help)
            sed -n '/^# Script:/,/^################################################################################$/p' "$0" | sed 's/^# //; s/^#//'
            exit 0
            ;;
        *)
            echo "Error: Unknown option $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check for required token (or ability to refresh one)
if [[ -z "$STRAVA_ACCESS_TOKEN" ]]; then
    if [[ -n "$STRAVA_REFRESH_TOKEN" && -n "$STRAVA_CLIENT_ID" && -n "$STRAVA_CLIENT_SECRET" ]]; then
        refresh_access_token || exit 1
    else
        echo "Error: Strava access token is required"
        echo "Set STRAVA_ACCESS_TOKEN or provide STRAVA_REFRESH_TOKEN + STRAVA_CLIENT_ID + STRAVA_CLIENT_SECRET"
        echo "Use --help for more information"
        exit 1
    fi
fi

# Check for required tools
for tool in curl jq date; do
    if ! command -v "$tool" &> /dev/null; then
        echo "Error: Required tool '$tool' is not installed"
        exit 1
    fi
done

# Convert dates to epoch timestamps
# macOS and Linux have different date command syntax
if date --version &>/dev/null 2>&1; then
    # GNU date (Linux)
    AFTER_EPOCH=$(date -d "$AFTER_DATE" +%s)
    BEFORE_EPOCH=$(date -d "$BEFORE_DATE" +%s)
else
    # BSD date (macOS)
    AFTER_EPOCH=$(date -j -f "%Y-%m-%d" "$AFTER_DATE" +%s)
    BEFORE_EPOCH=$(date -j -f "%Y-%m-%d" "$BEFORE_DATE" +%s)
fi

# Create output directory with timestamp if not specified
if [[ -z "$OUTPUT_DIR" ]]; then
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    OUTPUT_DIR="strava_activities_${TIMESTAMP}"
fi

mkdir -p "$OUTPUT_DIR"

echo "Fetching Strava activities from $AFTER_DATE to $BEFORE_DATE"
echo "Output directory: $OUTPUT_DIR"
echo ""

# Initialize variables
PAGE=1
TOTAL_ACTIVITIES=0
RAW_FILE="$OUTPUT_DIR/raw_activities.json"

# Start with empty array
echo "[]" > "$RAW_FILE"

# Fetch activities with pagination
while true; do
    echo "Fetching page $PAGE..."
    
    RESPONSE=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer $STRAVA_ACCESS_TOKEN" \
        "${API_BASE}/athlete/activities?after=${AFTER_EPOCH}&before=${BEFORE_EPOCH}&page=${PAGE}&per_page=${PER_PAGE}")
    
    # Extract HTTP status code (last line) and body (everything else)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    # Check HTTP status
    if [[ "$HTTP_CODE" != "200" ]]; then
        if [[ "$HTTP_CODE" == "401" && "$REFRESHED" == "false" ]]; then
            if refresh_access_token; then
                echo "Retrying with refreshed token..."
                continue
            fi
        fi
        echo "Error: API request failed with status code $HTTP_CODE"
        echo "Response: $BODY"
        exit 1
    fi
    
    # Check if we got any activities
    ACTIVITY_COUNT=$(echo "$BODY" | jq '. | length')
    
    if [[ "$ACTIVITY_COUNT" -eq 0 ]]; then
        echo "No more activities found"
        break
    fi
    
    echo "  Retrieved $ACTIVITY_COUNT activities"
    TOTAL_ACTIVITIES=$((TOTAL_ACTIVITIES + ACTIVITY_COUNT))
    
    # Append to raw file (merge arrays)
    TMP_FILE="$OUTPUT_DIR/tmp_activities.json"
    jq -s '.[0] + .[1]' "$RAW_FILE" <(echo "$BODY") > "$TMP_FILE"
    mv "$TMP_FILE" "$RAW_FILE"
    
    # If we got fewer than per_page, we're done
    if [[ "$ACTIVITY_COUNT" -lt "$PER_PAGE" ]]; then
        break
    fi
    
    PAGE=$((PAGE + 1))
    
    # Small delay to respect rate limits
    sleep 0.5
done

echo ""
echo "Total activities fetched: $TOTAL_ACTIVITIES"

if [[ "$TOTAL_ACTIVITIES" -eq 0 ]]; then
    echo "No activities found for the specified date range"
    exit 0
fi

echo ""
echo "Generating summary reports..."

# Generate CSV summary
CSV_FILE="$OUTPUT_DIR/activities_summary.csv"
echo "id,name,type,sport_type,date,distance_meters,distance_miles,moving_time_minutes,elapsed_time_minutes,elevation_gain_meters,average_speed_mph" > "$CSV_FILE"

jq -r '.[] | [
    .id,
    .name,
    .type,
    .sport_type,
    .start_date_local,
    .distance,
    (.distance / 1609.34 | floor),
    ((.moving_time / 60) | floor),
    ((.elapsed_time / 60) | floor),
    .total_elevation_gain,
    ((.average_speed * 2.23694) | floor)
] | @csv' "$RAW_FILE" >> "$CSV_FILE"

echo "  Created: $CSV_FILE"

# Generate activity types summary
TYPES_FILE="$OUTPUT_DIR/activity_types.txt"
{
    echo "Activity Types Summary"
    echo "====================="
    echo ""
    echo "By Type:"
    jq -r '.[].type' "$RAW_FILE" | sort | uniq -c | sort -rn
    echo ""
    echo "By Sport Type:"
    jq -r '.[].sport_type' "$RAW_FILE" | sort | uniq -c | sort -rn
} > "$TYPES_FILE"

echo "  Created: $TYPES_FILE"

# Generate distance summary
DISTANCE_FILE="$OUTPUT_DIR/distance_summary.txt"
{
    echo "Distance Summary"
    echo "==============="
    echo ""
    echo "Date Range: $AFTER_DATE to $BEFORE_DATE"
    echo "Total Activities: $TOTAL_ACTIVITIES"
    echo ""
    
    # Total distance in miles
    TOTAL_MILES=$(jq '[.[].distance] | add / 1609.34' "$RAW_FILE")
    printf "Total Distance: %.2f miles\n" "$TOTAL_MILES"
    
    # Total distance in kilometers
    TOTAL_KM=$(jq '[.[].distance] | add / 1000' "$RAW_FILE")
    printf "Total Distance: %.2f kilometers\n" "$TOTAL_KM"
    
    echo ""
    echo "Distance by Activity Type:"
    
    # Get unique types and calculate distance for each
    TYPES=$(jq -r '.[].type' "$RAW_FILE" | sort -u)
    while IFS= read -r type; do
        if [[ -n "$type" ]]; then
            MILES=$(jq --arg type "$type" '[.[] | select(.type == $type) | .distance] | add / 1609.34' "$RAW_FILE")
            printf "  %-15s: %.2f miles\n" "$type" "$MILES"
        fi
    done <<< "$TYPES"
    
    echo ""
    echo "Moving Time Summary:"
    TOTAL_HOURS=$(jq '[.[].moving_time] | add / 3600' "$RAW_FILE")
    printf "  Total: %.2f hours\n" "$TOTAL_HOURS"
    
    echo ""
    echo "Elevation Gain Summary:"
    TOTAL_ELEVATION=$(jq '[.[].total_elevation_gain] | add' "$RAW_FILE")
    printf "  Total: %.0f meters (%.0f feet)\n" "$TOTAL_ELEVATION" "$(echo "$TOTAL_ELEVATION * 3.28084" | bc)"
    
} > "$DISTANCE_FILE"

echo "  Created: $DISTANCE_FILE"

# Generate field inventory
FIELDS_FILE="$OUTPUT_DIR/available_fields.txt"
{
    echo "Available Fields in Activity Data"
    echo "=================================="
    echo ""
    echo "This file shows all fields available in the Strava activity data."
    echo "Use this to determine which fields to include in future analyses."
    echo ""
    jq -r '.[0] | keys[]' "$RAW_FILE" | sort
} > "$FIELDS_FILE"

echo "  Created: $FIELDS_FILE"

echo ""
echo "Summary reports generated successfully!"
echo ""
echo "Review the following files:"
echo "  - $DISTANCE_FILE (total miles and breakdown)"
echo "  - $TYPES_FILE (activity types found)"
echo "  - $FIELDS_FILE (available data fields)"
echo "  - $CSV_FILE (detailed activity listing)"
echo ""
cat "$DISTANCE_FILE"
