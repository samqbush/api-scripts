#!/usr/bin/env bash

################################################################################
# Script: analyze_cycling.sh
# Description: Extract mountain biking activities (MountainBikeRide, Ride)
#              from Strava data, group by location, and display with mileage
#              and elevation gain breakdown.
#
# Usage:
#   ./analyze_cycling.sh ACTIVITIES_DIR
#   ./analyze_cycling.sh ../strava_activities_20260106_123456
#
# Arguments:
#   ACTIVITIES_DIR   Path to strava_activities_* directory with raw_activities.json
#
################################################################################

if [[ -z "$1" ]]; then
    echo "Usage: $0 <strava_activities_dir>"
    echo "Example: $0 ../strava_activities_20260106_123456"
    exit 1
fi

ACTIVITIES_DIR="$1"
RAW_FILE="$ACTIVITIES_DIR/raw_activities.json"

if [[ ! -f "$RAW_FILE" ]]; then
    echo "Error: $RAW_FILE not found"
    exit 1
fi

# Location name mappings (lat,lon|label)
LOCATION_NAMES="
39.65,-105.17|Soda Lake, CO
39.64,-105.17|Soda Lake, CO
39.65,-105.15|Bear Creek Lake, CO
39.65,-105.18|Soda Lake, CO
39.64,-105.18|Soda Lake, CO
39.61,-104.67|Aurora Reservoir, CO
39.61,-104.68|Aurora Reservoir, CO
39.54,-105.08|Chatfield Reservoir, CO
39.55,-105.07|Chatfield Reservoir, CO
39.55,-105.08|Chatfield Reservoir, CO
39.54,-105.07|Chatfield Reservoir, CO
39.54,-105.09|Chatfield Reservoir, CO
39.53,-105.09|Chatfield Reservoir, CO
39.23,-105.22|South Platte, CO
39.23,-105.23|South Platte, CO
40.01,-106.20|Williams Fork, CO
40.01,-106.21|Williams Fork, CO
39.62,-106.05|Lake Dillon, CO
39.63,-106.05|Lake Dillon, CO
39.64,-105.15|Lake McConaughy
41.21,-101.77|Lake McConaughy
39.668,-105.258|Lair of the Bear
40.148,-105.300|Heil Valley Ranch, Boulder CO
39.677,-105.183|Trails from Garage Door
"

# Mileage location mappings (more detailed for mileage/elevation breakdown)
MILEAGE_LOCATION_NAMES="
39.65,-105.17|Soda Lake, CO
39.64,-105.17|Soda Lake, CO
39.65,-105.15|Bear Creek Lake, CO
39.65,-105.18|Soda Lake, CO
39.64,-105.18|Soda Lake, CO
39.61,-104.67|Aurora Reservoir, CO
39.61,-104.68|Aurora Reservoir, CO
39.54,-105.08|Chatfield Reservoir, CO
39.55,-105.07|Chatfield Reservoir, CO
39.55,-105.08|Chatfield Reservoir, CO
39.54,-105.07|Chatfield Reservoir, CO
39.54,-105.09|Chatfield Reservoir, CO
39.53,-105.09|Chatfield Reservoir, CO
39.23,-105.22|South Platte, CO
39.23,-105.23|South Platte, CO
40.01,-106.20|Williams Fork, CO
40.01,-106.21|Williams Fork, CO
39.62,-106.05|Lake Dillon, CO
39.63,-106.05|Lake Dillon, CO
39.64,-105.15|Lake McConaughy
41.21,-101.77|Lake McConaughy
39.668,-105.258|Lair of the Bear
40.148,-105.300|Heil Valley Ranch, Boulder CO
39.677,-105.183|Trails from Garage Door
"

# Helper function to look up location label
get_location_label() {
    local key="$1"
    local label=$(echo "$LOCATION_NAMES" | grep -F "${key}|" | cut -d'|' -f2)
    if [[ -z "$label" ]]; then
        echo "Unknown ($key)"
    else
        echo "$label"
    fi
}

# Optional keyword-based label override from activity name
KEYWORDS_FILE="$(dirname "$0")/cycling_location_keywords.txt"
get_keyword_label() {
  local name="$1"
  local name_lc="$(echo "$name" | tr '[:upper:]' '[:lower:]')"
  if [[ -f "$KEYWORDS_FILE" ]]; then
    while IFS='|' read -r keyword label; do
      [[ -z "$keyword" || -z "$label" ]] && continue
      local kw_lc="$(echo "$keyword" | tr '[:upper:]' '[:lower:]')"
      if [[ "$name_lc" == *"$kw_lc"* ]]; then
        echo "$label"
        return 0
      fi
    done < "$KEYWORDS_FILE"
  fi
  echo ""
}

echo "Mountain Biking Activities by Location"
echo "======================================"
echo ""

# Calculate total mileage and elevation
TOTAL_MILES=$(jq '[.[] | select((.sport_type|ascii_downcase) | test("mountainbikeride|ride")) | .distance/1609.34] | add // 0' "$RAW_FILE")
TOTAL_MILES=$(printf "%.2f" "$TOTAL_MILES")

TOTAL_ELEVATION=$(jq '[.[] | select((.sport_type|ascii_downcase) | test("mountainbikeride|ride")) | .total_elevation_gain] | add // 0' "$RAW_FILE")
TOTAL_ELEVATION=$(printf "%.0f" "$TOTAL_ELEVATION")

echo "Total Cycling Mileage: $TOTAL_MILES miles"
echo "Total Elevation Gain: $TOTAL_ELEVATION feet"
echo ""

# Extract and group by location
jq -r '.[] | 
  select((.sport_type|ascii_downcase) | test("mountainbikeride|ride")) | 
  [.sport_type, .name, .start_date_local, ((.start_latlng//[])|join(",")), (.distance/1609.34), (.total_elevation_gain//0)] | 
  @tsv' "$RAW_FILE" | \
while IFS=$'\t' read -r sport name date coords miles elevation; do
    if [[ -n "$coords" ]]; then
        # Round coords to 3 decimals for grouping
        lat=$(echo "$coords" | cut -d',' -f1)
        lon=$(echo "$coords" | cut -d',' -f2)
        rounded_lat=$(printf "%.3f" "$lat")
        rounded_lon=$(printf "%.3f" "$lon")
        key="${rounded_lat},${rounded_lon}"
        
        # Look up label or use coordinates
        label=$(get_location_label "$key")
        # Override with keyword mapping if activity name contains a match
        kw_label=$(get_keyword_label "$name")
        if [[ -n "$kw_label" ]]; then
          label="$kw_label"
        fi
        echo "$label|$sport|$name|$date|$miles|$elevation"
    fi
done | sort | \
awk -F'|' '
  BEGIN { current_location = ""; activity_count = 0; }
  {
    location = $1
    sport = $2
    name = $3
    date = $4
    miles = $5
    elevation = $6
    miles_sum[location] += miles
    elev_sum[location] += elevation
    
    if (location != current_location) {
      if (activity_count > 0) print ""
      printf "\n%s\n", location
      printf "%s\n", substr("─────────────────────────────────────────────────────────", 1, length(location))
      current_location = location
      activity_count = 0
    }
    
    # Extract date portion for readability
    date_short = substr(date, 1, 10)
    activity_count++
    printf "  %2d. %-20s  %s  %s\n", activity_count, sport, date_short, name
  }
  END { print "" }
'

# Summary
echo ""
echo "Summary by Activity Type"
echo "======================="
jq -r '.[] | 
  select((.sport_type|ascii_downcase) | test("mountainbikeride|ride")) | 
  .sport_type' "$RAW_FILE" | sort | uniq -c | awk '{printf "  %-20s: %3d sessions\n", $2, $1}'

echo ""
echo "Total cycling activities: $(jq '[.[] | select((.sport_type|ascii_downcase) | test("mountainbikeride|ride"))] | length' "$RAW_FILE")"

echo ""
echo "Mileage & Elevation by Location"
echo "==============================="

# Recompute labels with keyword overrides and aggregate
jq -r '.[] | 
  select((.sport_type|ascii_downcase) | test("mountainbikeride|ride")) | 
  [.sport_type, .name, ((.start_latlng//[])|join(",")), (.distance/1609.34), (.total_elevation_gain//0)] | 
  @tsv' "$RAW_FILE" | \
while IFS=$'\t' read -r sport name coords miles elevation; do
    if [[ -n "$coords" ]]; then
        lat=$(echo "$coords" | cut -d',' -f1)
        lon=$(echo "$coords" | cut -d',' -f2)
        rounded_lat=$(printf "%.3f" "$lat")
        rounded_lon=$(printf "%.3f" "$lon")
        key="${rounded_lat},${rounded_lon}"
        label=$(get_location_label "$key")
        kw_label=$(get_keyword_label "$name")
        if [[ -n "$kw_label" ]]; then
            label="$kw_label"
        fi
        printf "%s\t%.4f\t%.1f\n" "$label" "$miles" "$elevation"
    fi
done | awk -F'\t' '{m[$1]+=$2; e[$1]+=$3} END{for (l in m){printf "  %-30s %8.2f miles  %6d ft gain\n", l, m[l], int(e[l]+0.5)}}' | sort
