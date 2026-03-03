#!/usr/bin/env bash

################################################################################
# Script: water_sports_year.sh
# Description: Fetch and analyze water-sport activities for a specified year.
#              Combines get_activities.sh + analyze_water_sports.sh.
#
# Usage:
#   ./water_sports_year.sh 2024
#   ./water_sports_year.sh 2025
#
# Arguments:
#   YEAR   The year to analyze (e.g., 2024, 2025)
#
# Output:
#   - Fetches activities for Jan 1 - Dec 31 of the given year
#   - Creates strava_YEAR_report/ directory with raw data
#   - Displays water-sport summary grouped by location with mileage
#
################################################################################

if [[ -z "$1" ]]; then
    echo "Usage: $0 <year>"
    echo "Example: $0 2024"
    exit 1
fi

YEAR="$1"

# Validate that YEAR is a 4-digit number before using it in arithmetic
if ! [[ "$YEAR" =~ ^[0-9]{4}$ ]]; then
    echo "Error: YEAR must be a 4-digit number (e.g., 2024)."
    echo "Usage: $0 <year>"
    echo "Example: $0 2024"
    exit 1
fi

AFTER_DATE="${YEAR}-01-01"
BEFORE_DATE="$((YEAR + 1))-01-01"
OUTPUT_DIR="strava_${YEAR}_report"

SCRIPT_DIR="$(dirname "$0")"

echo "Fetching water-sport activities for $YEAR..."
echo ""

# Fetch activities for the year
"$SCRIPT_DIR/get_activities.sh" --after "$AFTER_DATE" --before "$BEFORE_DATE" --output-dir "$OUTPUT_DIR"

echo ""
echo "Analyzing water-sport activities..."
echo ""

# Analyze the fetched data and save to both console and file
"$SCRIPT_DIR/analyze_water_sports.sh" "$OUTPUT_DIR" | tee "$OUTPUT_DIR/water_sports_analysis.txt"

echo ""
echo "Done! Data saved in $OUTPUT_DIR/"
echo "  - Raw data: $OUTPUT_DIR/raw_activities.json"
echo "  - Analysis: $OUTPUT_DIR/water_sports_analysis.txt"
