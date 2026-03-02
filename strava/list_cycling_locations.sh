#!/usr/bin/env bash

################################################################################
# Script: list_cycling_locations.sh
# Description: Extract unique cycling activity locations and show counts.
#              Use this to identify which coordinates to relabel.
#
# Usage:
#   ./list_cycling_locations.sh ACTIVITIES_DIR
#
# Workflow:
#   1. Run this script to see all unique locations with counts
#   2. Look up each coordinate on Google Maps: https://google.com/maps?q=lat,lon
#   3. Note the actual location name
#   4. Provide the list back to update the analyze_cycling.sh mappings
#
################################################################################

if [[ -z "$1" ]]; then
    echo "Usage: $0 <strava_activities_dir>"
    exit 1
fi

RAW_FILE="$1/raw_activities.json"

if [[ ! -f "$RAW_FILE" ]]; then
    echo "Error: $RAW_FILE not found"
    exit 1
fi

echo "Unique Cycling Activity Locations"
echo "=================================="
echo ""
echo "Format: COUNT  LATITUDE,LONGITUDE"
echo ""
echo "Instructions:"
echo "1. Copy each coordinate (lat,lon)"
echo "2. Paste into Google Maps search: https://google.com/maps?q=lat,lon"
echo "3. Note the location name and area"
echo "4. Provide the list back as: LAT,LON|Friendly Location Name"
echo ""
echo "---"
echo ""

jq -r '.[] | 
  select((.sport_type|ascii_downcase) | test("mountainbikeride|ride")) | 
  ((.start_latlng//[])|join(","))' "$RAW_FILE" | \
awk 'NF {
  if (match($0, /^[0-9.-]+,[0-9.-]+$/)) {
    # Round to 2 decimals
    split($0, a, ",")
    lat = sprintf("%.3f", a[1])
    lon = sprintf("%.3f", a[2])
    key = lat "," lon
    count[key]++
  }
}
END {
  for (loc in count) {
    printf "%3d  %s\n", count[loc], loc
  }
}' | sort -rn

echo ""
echo "---"
echo ""
echo "Once you have the labels, provide them in this format (paste below or in a message):"
echo ""
echo "LAT,LON|Friendly Location Name"
echo "LAT,LON|Friendly Location Name"
echo "..."
