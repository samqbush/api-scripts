# Strava Activity Tracker (Water Sports & Cycling)

A collection of Bash scripts to fetch, analyze, and visualize water-sport and cycling activities from Strava, with location-based grouping and mileage tracking.

## Overview

These scripts allow you to:
- Fetch Strava activities for any date range
- Automatically refresh expired access tokens
- Analyze water-sport activities (Kitesurf, Windsurf, Sail, Swim) and cycling by location
- View yearly summaries with human-readable location names
- Track mileage by location with detailed breakdowns

## Prerequisites

- **Bash shell** (macOS/Linux/WSL)
- **curl** - for API requests
- **jq** - for JSON parsing (`brew install jq` on macOS)
- **Strava API credentials** - Create an application at https://www.strava.com/settings/api

## Setup

### 1. Get Strava API Credentials

1. Go to https://www.strava.com/settings/api
2. Create a new application (or use an existing one)
3. Note your **Client ID** and **Client Secret**

### 2. Create Secret Configuration File

Create a `.strava` file in the repository root with your credentials:

```bash
cd /path/to/api-scripts
cat > .strava <<'EOF'
STRAVA_CLIENT_ID=193221
STRAVA_CLIENT_SECRET=your_client_secret_here
STRAVA_ACCESS_TOKEN=your_access_token_here
STRAVA_REFRESH_TOKEN=your_refresh_token_here
EOF
chmod 600 .strava
```

**Important:** The `.strava` file is gitignored and should never be committed.

### 3. Get Your First Access Token

Generate an authorization code:

1. Visit this URL in your browser (replace `YOUR_CLIENT_ID`):
   ```
   https://www.strava.com/oauth/authorize?client_id=YOUR_CLIENT_ID&response_type=code&redirect_uri=http://localhost&approval_prompt=force&scope=activity:read_all
   ```

2. Click "Authorize"

3. Copy the `code` parameter from the redirect URL (e.g., `http://localhost/?code=XXXXX`)

4. Exchange the code for tokens and save to `.strava`:
   ```bash
   ./strava/get_token.sh --client-secret YOUR_SECRET --code PASTE_CODE_HERE --write-env
   ```

Your `.strava` file is now populated with access and refresh tokens!

## Usage

### Quick Start: Yearly Water Sports Summary

Fetch and analyze all water-sport activities for a given year:

```bash
./strava/water_sports_year.sh 2024
./strava/water_sports_year.sh 2025
```

### Quick Start: Yearly Cycling Summary

Fetch and analyze all cycling/mountain biking activities for a given year:

```bash
./strava/cycling_year.sh 2024
./strava/cycling_year.sh 2025
```

**Output:**
- Creates `strava_YEAR_report/` directory with raw data
- Displays activities grouped by location
- Shows mileage breakdown by location
- Lists activity counts by sport type

### Individual Scripts

#### 1. Fetch Activities (`get_activities.sh`)

Fetch activities for a custom date range:

```bash
# Fetch all 2025 activities
./strava/get_activities.sh --after 2025-01-01 --before 2026-01-01

# Fetch Q4 2024 activities
./strava/get_activities.sh --after 2024-10-01 --before 2025-01-01 --output-dir q4_2024

# Use custom token (overrides .strava)
./strava/get_activities.sh --token YOUR_TOKEN --after 2025-01-01 --before 2026-01-01
```

**Features:**
- Auto-loads credentials from `.strava`
- Auto-refreshes expired tokens
- Creates timestamped output directories
- Generates CSV summaries and distance reports

#### 2. Analyze Water Sports (`analyze_water_sports.sh`)

Analyze fetched activities to show water sports by location:

```bash
./strava/analyze_water_sports.sh strava_2024_report
```

**Output includes:**
- Activities grouped by location with dates and names
- Sport type summary (Kitesurf, Windsurf, Sail, Swim)
- Mileage breakdown by location
- Detailed spot breakdowns (e.g., Egypt split by island)

#### 3. Refresh Token (`refresh_token.sh`)

Manually refresh an expired access token:

```bash
./strava/refresh_token.sh
```

Auto-prompts for client secret and refresh token if not in `.strava`.

#### 4. Get New Token (`get_token.sh`)

Exchange an authorization code for access/refresh tokens:

```bash
# Interactive mode (prompts for all values)
./strava/get_token.sh

# Specify values and save to .strava
./strava/get_token.sh --client-secret SECRET --code AUTH_CODE --write-env
```

#### 5. List Water Sport Locations (`list_water_sport_locations.sh`)

Helper to identify unmapped coordinates:

```bash
./strava/list_water_sport_locations.sh strava_2024_report
```

Use this to find coordinates that need human-friendly labels. Look them up on Google Maps and update `analyze_water_sports.sh`.

## Customization

### Adding New Locations

Edit `strava/analyze_water_sports.sh` and add coordinates to the mapping sections:

```bash
# Location name mappings (for activity grouping)
LOCATION_NAMES="
...
39.62,-106.05|Lake Dillon, CO
41.21,-101.77|Lake McConaughy
...
"

# Mileage location mappings (for detailed mileage breakdown)
MILEAGE_LOCATION_NAMES="
...
39.62,-106.05|Lake Dillon, CO
41.21,-101.77|Lake McConaughy
...
"
```

**Tips:**
- Use 2-decimal precision for coordinates (e.g., `39.65,-105.17`)
- Group trip locations under broader names (e.g., all Egypt spots → "Red Sea, Egypt")
- Use detailed names in `MILEAGE_LOCATION_NAMES` for spot-specific mileage

### Filtering Activity Types

By default, these sports are included:
- Kitesurf
- Windsurf
- Sail
- Swim

To modify, edit the `test()` regex in `analyze_water_sports.sh`:

```bash
select((.sport_type|ascii_downcase) | test("kitesurf|windsurf|swim|sail"))
```

## Output Files

When you fetch activities, the output directory contains:

```
strava_YEAR_report/
├── raw_activities.json          # Complete API response data
├── activities_summary.csv       # Activity listing with metrics
├── activity_types.txt           # Summary of activity types
├── distance_summary.txt         # Total distance by sport type
└── available_fields.txt         # Available data fields from API
```

## Example Output

```
Water Sports Activities by Location
===================================

Soda Lake, CO
─────────────
   1. Kitesurf      2025-11-04  1st 6/5/4 DP
   2. Kitesurf      2025-06-06  Afternoon Kitesurf
   ...

La Paz, Mexico
──────────────
   1. Kitesurf      2025-03-13  1st Day LV - no wind
   2. Kitesurf      2025-03-15  1st Downwinder!!!
   ...

Summary by Sport Type
====================
  Kitesurf    :  97 sessions
  Windsurf    :   1 sessions
  Sail        :   4 sessions
  Swim        :   1 sessions

Total water-sport activities: 103

Mileage by Location
===================
  Soda Lake, CO                    188.47 miles
  Chatfield Reservoir, CO           68.20 miles
  Aurora Reservoir, CO              67.78 miles
  La Paz, Mexico                   122.63 miles
  ...
```

## Troubleshooting

### "Access token failed"

**Cause:** Your access token expired (they expire after ~6 hours).

**Solution:** The script auto-refreshes if you have a valid refresh token in `.strava`. If auto-refresh fails, re-authorize:

```bash
./strava/get_token.sh --write-env
```

### "activity:read_permission missing"

**Cause:** Your tokens were issued without the `activity:read_all` scope.

**Solution:** Re-authorize with the correct scope URL (see Setup step 3).

### Activities show "Unknown (lat,lon)"

**Cause:** The coordinate isn't mapped to a human-friendly name.

**Solution:** 
1. Run `./strava/list_water_sport_locations.sh strava_YEAR_report`
2. Look up coordinates on Google Maps
3. Add mappings to `analyze_water_sports.sh`

### Command not found: jq

**Solution:** Install jq:
- macOS: `brew install jq`
- Ubuntu/Debian: `sudo apt-get install jq`
- Other: https://stedolan.github.io/jq/download/

## Security Notes

- **Never commit `.strava`** - it contains your API credentials
- `.strava` is already in `.gitignore`
- Access tokens expire in ~6 hours (safe for local testing)
- Refresh tokens are long-lived; keep them secure
- If compromised, revoke access at https://www.strava.com/settings/apps

## File Structure

```
strava/
├── README.md                      # This file
├── water_sports_year.sh           # Main entry point (water sports year analysis)
├── cycling_year.sh                # Main entry point (cycling year analysis)
├── get_activities.sh              # Fetch activities from Strava API
├── analyze_water_sports.sh        # Analyze water sports and group by location
├── analyze_cycling.sh             # Analyze cycling and group by location
├── get_token.sh                   # Exchange auth code for tokens
├── refresh_token.sh               # Manually refresh access token
├── list_water_sport_locations.sh  # Helper to find unmapped water sport coordinates
└── list_cycling_locations.sh      # Helper to find unmapped cycling coordinates
```

## License

This project is part of the api-scripts repository. See LICENSE in the root directory.

## Contributing

To add new features or locations:
1. Create a feature branch
2. Update location mappings or add scripts
3. Test with your own Strava data
4. Submit a pull request

## Support

For issues or questions:
1. Check the Troubleshooting section above
2. Review Strava API docs: https://developers.strava.com/docs/reference/
3. Open an issue in the repository
