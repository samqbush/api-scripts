#!/usr/bin/env bash

################################################################################
# Script: analyze_water_sports.sh
# Description: Extract water-sport activities (Kitesurf, Windsurf, Sail, Swim)
#              from Strava data, group by location, and display with labels.
#
# Usage:
#   ./analyze_water_sports.sh ACTIVITIES_DIR
#   ./analyze_water_sports.sh ../strava_activities_20260102_094234
#
# Arguments:
#   ACTIVITIES_DIR   Path to strava_activities_* directory with raw_activities.json
#
################################################################################

if [[ -z "$1" ]]; then
    echo "Usage: $0 <strava_activities_dir>"
    echo "Example: $0 ../strava_activities_20260102_094234"
    exit 1
fi

ACTIVITIES_DIR="$1"
RAW_FILE="$ACTIVITIES_DIR/raw_activities.json"

if [[ ! -f "$RAW_FILE" ]]; then
    echo "Error: $RAW_FILE not found"
    exit 1
fi

# Location name mappings as a colon-delimited list (lat,lon|label)
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
24.05,-109.99|La Paz, Mexico
24.09,-109.99|La Paz, Mexico
24.08,-110.00|La Ventana, Mexico
24.09,-110.00|La Ventana, Mexico
24.08,-110|La Ventana, Mexico
24.09,-110|La Ventana, Mexico
26.44,-81.92|SW Florida Coast (Stuart/Jupiter)
26.46,-81.97|SW Florida Coast (Stuart/Jupiter)
26.43,-81.92|SW Florida Coast (Stuart/Jupiter)
26.43,-81.93|SW Florida Coast (Stuart/Jupiter)
46.01,-89.51|Upper Peninsula, Michigan
46.00,-89.51|Upper Peninsula, Michigan
46.00,-89.52|Upper Peninsula, Michigan
46,-89.51|Upper Peninsula, Michigan
27.75,33.70|Ashrafi, Red Sea Egypt
27.74,33.69|Ashrafi, Red Sea Egypt
27.75,33.69|Ashrafi, Red Sea Egypt
27.54,33.78|Tawila/El Gouna, Red Sea Egypt
27.54,33.79|Tawila/El Gouna, Red Sea Egypt
"

# Helper function to look up location label
get_location_label() {
    local key="$1"
    local label=$(echo "$LOCATION_NAMES" | grep "^${key}|" | cut -d'|' -f2)
    if [[ -z "$label" ]]; then
        echo "Unknown ($key)"
    else
        echo "$label"
    fi
}

echo "Water Sports Activities by Location (2025)"
echo "=========================================="
echo ""

# Extract and group by location
jq -r '.[] | 
  select((.sport_type|ascii_downcase) | test("kitesurf|windsurf|swim|sail")) | 
  [.sport_type, .name, .start_date_local, ((.start_latlng//[])|join(",")), (.distance/1609.34)] | 
  @tsv' "$RAW_FILE" | \
while IFS=$'\t' read -r sport name date coords miles; do
    if [[ -n "$coords" ]]; then
        # Round coords to 2 decimals for grouping
        lat=$(echo "$coords" | cut -d',' -f1)
        lon=$(echo "$coords" | cut -d',' -f2)
        rounded_lat=$(printf "%.2f" "$lat")
        rounded_lon=$(printf "%.2f" "$lon")
        key="${rounded_lat},${rounded_lon}"
        
        # Look up label or use coordinates
        label=$(get_location_label "$key")
        echo "$label|$sport|$name|$date|$miles"
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
    miles_sum[location] += miles
    
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
    printf "  %2d. %-12s  %s  %s\n", activity_count, sport, date_short, name
  }
  END { print "" }
'

# Summary
echo ""
echo "Summary by Sport Type"
echo "===================="
jq -r '.[] | 
  select((.sport_type|ascii_downcase) | test("kitesurf|windsurf|swim|sail")) | 
  .sport_type' "$RAW_FILE" | sort | uniq -c | awk '{printf "  %-12s: %3d sessions\n", $2, $1}'

echo ""
echo "Total water-sport activities: $(jq '[.[] | select((.sport_type|ascii_downcase) | test("kitesurf|windsurf|swim|sail"))] | length' "$RAW_FILE")"

echo ""
echo "Mileage by Location"
echo "==================="

jq -r '.[] | 
  select((.sport_type|ascii_downcase) | test("kitesurf|windsurf|swim|sail")) | 
  select((.start_latlng//[])|length==2) |
  [((.start_latlng[0]*100|floor)/100), ((.start_latlng[1]*100|floor)/100), (.distance/1609.34)] | @tsv' "$RAW_FILE" |
awk -F'\t' '
  NR==FNR {
    # First file: mapping of coords to labels
    if ($0 == "") next;
    split($0, parts, "|");
    if (length(parts[1]) && length(parts[2])) {
      label[parts[1]] = parts[2];
    }
    next;
  }
  {
    key=$1","$2;
    miles=$3;
    lbl = (key in label) ? label[key] : "Unknown (" key ")";
    sum[lbl]+=miles;
  }
  END {
    for (lbl in sum) printf "  %-30s %8.2f miles\n", lbl, sum[lbl];
  }
' <(printf "%s\n" "$LOCATION_NAMES") - | sort
