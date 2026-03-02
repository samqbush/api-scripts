#!/usr/bin/env bash

################################################################################
# Script: cycling_year.sh
# Description: Fetch and analyze mountain biking activities for a specified year.
#              Combines get_activities.sh + analyze_cycling.sh.
#
# Usage:
#   ./cycling_year.sh 2024
#   ./cycling_year.sh 2025
#
# Arguments:
#   YEAR   The year to analyze (e.g., 2024, 2025)
#
# Output:
#   - Fetches activities for Jan 1 - Dec 31 of the given year
#   - Creates strava_cycling_YEAR_report/ directory with raw data
#   - Displays cycling summary grouped by location with mileage and elevation gain
#
################################################################################

if [[ -z "$1" ]]; then
    echo "Usage: $0 <year>"
    echo "Example: $0 2024"
    exit 1
fi

YEAR="$1"
AFTER_DATE="${YEAR}-01-01"
BEFORE_DATE="$((YEAR + 1))-01-01"
OUTPUT_DIR="strava_cycling_${YEAR}_report"

SCRIPT_DIR="$(dirname "$0")"

echo "Fetching cycling activities for $YEAR..."
echo ""

# Fetch activities for the year
"$SCRIPT_DIR/get_activities.sh" --after "$AFTER_DATE" --before "$BEFORE_DATE" --output-dir "$OUTPUT_DIR"

echo ""
echo "Analyzing cycling activities..."
echo ""

# Analyze the fetched data and save to both console and file
"$SCRIPT_DIR/analyze_cycling.sh" "$OUTPUT_DIR" | tee "$OUTPUT_DIR/cycling_analysis.txt"

echo ""
echo "Done! Data saved in $OUTPUT_DIR/"
echo "  - Raw data: $OUTPUT_DIR/raw_activities.json"
echo "  - Analysis: $OUTPUT_DIR/cycling_analysis.txt"
