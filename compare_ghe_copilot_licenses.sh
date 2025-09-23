#!/usr/bin/env bash

# compare_ghe_copilot_licenses.sh
#
# Usage:
#   gh auth login  # One-time authentication setup
#   ./compare_ghe_copilot_licenses.sh --enterprise ENTERPRISE [OPTIONS]
#
# Description:
#   Compares GitHub Enterprise Managed Users (EMU) with enterprise licenses against 
#   GitHub Copilot license holders to identify users who have enterprise licenses 
#   but no Copilot license. Useful for license optimization and provisioning planning.
#
# Examples:
#   # Basic license comparison (using GitHub CLI authentication)
#   gh auth login  # One-time setup
#   ./compare_ghe_copilot_licenses.sh --enterprise octodemo
#
#   # Full analysis with all output formats
#   ./compare_ghe_copilot_licenses.sh \
#     --enterprise octodemo \
#     --out license_audit_20250922 \
#     --markdown --json --csv \
#     --fail-on-gaps
#
# Requirements:
#   - GitHub CLI (gh) installed and authenticated (gh auth login)
#   - jq must be installed  
#   - Access to GitHub Enterprise instance with required permissions
#
# Arguments:
#   --enterprise SLUG      Required. GitHub Enterprise slug/name
#   --out DIRECTORY        Output directory (default: license_compare_TIMESTAMP)
#   --markdown             Generate Markdown summary report
#   --json                 Generate detailed JSON reports (default: true)
#   --csv                  Generate CSV export for spreadsheet analysis
#   --fail-on-gaps         Exit with non-zero code if license gaps found
#   --min-gap-threshold N  Only fail if gaps exceed N users (default: 1)
#   --sleep-ms MS          Sleep between API calls in milliseconds (default: 100)
#   --keep-tmp             Keep temporary files for debugging
#   --debug                Enable verbose debug output
#   --help, -h             Show this help message

set -e

# Global variables
SCRIPT_NAME="compare_ghe_copilot_licenses.sh"
VERSION="1.0.0"
ENTERPRISE=""
OUT_DIR=""
GENERATE_MARKDOWN=false
GENERATE_JSON=true
GENERATE_CSV=false
FAIL_ON_GAPS=false
MIN_GAP_THRESHOLD=1
SLEEP_MS=100
KEEP_TMP=false
DEBUG=false
TEST_MODE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
  echo -e "${BLUE}[INFO]${NC} $*" >&2
}

debug() {
  if $DEBUG; then
    echo -e "${YELLOW}[DEBUG]${NC} $*" >&2
  fi
}

error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

success() {
  echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

# Usage documentation
usage() {
  cat << EOF
$SCRIPT_NAME v$VERSION

Compare GitHub Enterprise Managed Users with Copilot licenses to identify 
users who have enterprise licenses but no Copilot license.

USAGE:
  gh auth login  # Authenticate once
  $SCRIPT_NAME --enterprise ENTERPRISE [OPTIONS]

REQUIRED:
  --enterprise SLUG      GitHub Enterprise slug/name

OPTIONS:
  --out DIRECTORY        Output directory (default: license_compare_TIMESTAMP)
  --markdown             Generate Markdown summary report
  --json                 Generate detailed JSON reports (default: enabled)
  --csv                  Generate CSV export for spreadsheet analysis
  --fail-on-gaps         Exit with non-zero code if license gaps found
  --min-gap-threshold N  Only fail if gaps exceed N users (default: 1)
  --sleep-ms MS          Sleep between API calls in milliseconds (default: 100)
  --keep-tmp             Keep temporary files for debugging
  --debug                Enable verbose debug output
  --test-mode            Run in test mode with sample data (for demonstration)
  --help, -h             Show this help message

REQUIRED PERMISSIONS:
  - Enterprise admin access (for accessing enterprise members)
  - Copilot billing access (for accessing Copilot billing seats)

AUTHENTICATION:
  Use GitHub CLI for secure authentication:
  gh auth login

EXAMPLES:
  # Basic license comparison (using GitHub CLI authentication)
  gh auth login  # One-time setup
  $SCRIPT_NAME --enterprise octodemo

  # Complete analysis with all outputs
  $SCRIPT_NAME \\
    --enterprise octodemo \\
    --out license_audit_20250922 \\
    --markdown --json --csv \\
    --fail-on-gaps

  # CSV output for spreadsheet analysis
  $SCRIPT_NAME \\
    --enterprise mycompany \\
    --csv --out quarterly_license_audit

  # Test mode with sample data (no authentication required)
  $SCRIPT_NAME --enterprise demo --test-mode --markdown --csv

OUTPUT FILES:
  emu_users.json                 - All EMU users with enterprise licenses
  copilot_users.json             - All users with Copilot licenses
  license_gaps_emu_only.json     - EMU users missing Copilot (main target)
  license_gaps_copilot_only.json - Copilot users missing EMU
  license_overlaps_both.json     - Users with both licenses
  summary.json                   - License utilization summary
  summary.csv                    - CSV export (if --csv)
  summary.md                     - Markdown report (if --markdown)

EOF
}

# Parse command line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --enterprise)
        ENTERPRISE="$2"
        shift 2
        ;;
      --out)
        OUT_DIR="$2"
        shift 2
        ;;
      --markdown)
        GENERATE_MARKDOWN=true
        shift
        ;;
      --json)
        GENERATE_JSON=true
        shift
        ;;
      --csv)
        GENERATE_CSV=true
        shift
        ;;
      --fail-on-gaps)
        FAIL_ON_GAPS=true
        shift
        ;;
      --min-gap-threshold)
        MIN_GAP_THRESHOLD="$2"
        shift 2
        ;;
      --sleep-ms)
        SLEEP_MS="$2"
        shift 2
        ;;
      --keep-tmp)
        KEEP_TMP=true
        shift
        ;;
      --debug)
        DEBUG=true
        shift
        ;;
      --test-mode)
        TEST_MODE=true
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        error "Unknown option: $1"
        usage
        exit 2
        ;;
    esac
  done

  # Validate required arguments
  if [[ -z "$ENTERPRISE" ]]; then
    error "Missing required argument: --enterprise"
    usage
    exit 2
  fi

  # Set default output directory
  if [[ -z "$OUT_DIR" ]]; then
    OUT_DIR="license_compare_$(date +%Y%m%d_%H%M%S)"
  fi
}

# Check for required tools
require_tools() {
  local missing_tools=()
  
  if ! $TEST_MODE && ! command -v gh &> /dev/null; then
    missing_tools+=("gh (GitHub CLI)")
  fi
  
  if ! command -v jq &> /dev/null; then
    missing_tools+=("jq")
  fi
  
  if [[ ${#missing_tools[@]} -gt 0 ]]; then
    error "Missing required tools: ${missing_tools[*]}"
    error "Install missing tools:"
    error "  - GitHub CLI: https://cli.github.com/"
    error "  - jq: https://jqlang.github.io/jq/"
    exit 2
  fi
}

# Create sample test data for demonstration purposes
create_test_data() {
  log "Creating sample test data for demonstration..."
  
  local temp_dir="$OUT_DIR/tmp"
  
  # Ensure directory exists
  mkdir -p "$temp_dir"
  
  # Create sample EMU users data
  cat > "$temp_dir/all_enterprise_users.json" << 'EOF'
[
  {"login": "alice_corp", "id": 12345, "name": "Alice Smith", "type": "User"},
  {"login": "bob_corp", "id": 12346, "name": "Bob Johnson", "type": "User"},
  {"login": "charlie_corp", "id": 12347, "name": "Charlie Brown", "type": "User"},
  {"login": "diana_corp", "id": 12348, "name": "Diana Wilson", "type": "User"},
  {"login": "eve_corp", "id": 12349, "name": "Eve Davis", "type": "User"},
  {"login": "frank_corp", "id": 12350, "name": "Frank Miller", "type": "User"},
  {"login": "grace_corp", "id": 12351, "name": "Grace Lee", "type": "User"},
  {"login": "henry_corp", "id": 12352, "name": "Henry Taylor", "type": "User"}
]
EOF

  # Create sample Copilot seats data (some overlap, some gaps)
  cat > "$temp_dir/copilot_seats_array.json" << 'EOF'
[
  {
    "created_at": "2025-03-01T08:15:30Z",
    "last_activity_at": "2025-09-20T14:22:00Z",
    "last_activity_editor": "vscode",
    "assignee": {
      "login": "alice_corp",
      "id": 12345,
      "name": "Alice Smith",
      "type": "User"
    }
  },
  {
    "created_at": "2025-04-15T10:30:00Z",
    "last_activity_at": "2025-09-21T09:15:00Z",
    "last_activity_editor": "jetbrains",
    "assignee": {
      "login": "charlie_corp",
      "id": 12347,
      "name": "Charlie Brown", 
      "type": "User"
    }
  },
  {
    "created_at": "2025-05-01T14:45:00Z",
    "last_activity_at": "2025-09-19T16:30:00Z",
    "last_activity_editor": "vscode",
    "assignee": {
      "login": "eve_corp",
      "id": 12349,
      "name": "Eve Davis",
      "type": "User"
    }
  },
  {
    "created_at": "2025-06-10T11:20:00Z",
    "last_activity_at": "2025-09-22T08:45:00Z", 
    "last_activity_editor": "vscode",
    "assignee": {
      "login": "grace_corp",
      "id": 12351,
      "name": "Grace Lee",
      "type": "User"
    }
  },
  {
    "created_at": "2025-07-01T09:00:00Z",
    "last_activity_at": "2025-09-15T12:00:00Z",
    "last_activity_editor": "vim",
    "assignee": {
      "login": "external_user",
      "id": 99999,
      "name": "External Collaborator",
      "type": "User"
    }
  }
]
EOF

  log "Sample test data created:"
  log "  - 8 EMU users (alice_corp through henry_corp)"
  log "  - 5 Copilot users (4 overlap + 1 external)"
  log "  - Expected gaps: 4 EMU users without Copilot"
  log "  - Expected cleanup: 1 external user with Copilot"
}

# Test mode implementation
run_test_mode() {
  log "Running in TEST MODE with sample data"
  log "This demonstrates the script functionality without requiring real GitHub API access"
  
  # Skip API validation in test mode
  
  # Create sample data
  create_test_data
  
  # Continue with normal processing using sample data
  log "Proceeding with sample data analysis..."
  
  return 0
}

# Test GitHub CLI authentication and enterprise access
validate_api_access() {
  log "Validating GitHub CLI authentication and enterprise access..."
  
  # Test GitHub CLI authentication
  if ! gh auth status &>/dev/null; then
    error "GitHub CLI is not authenticated"
    error "Please run: gh auth login"
    exit 2
  fi
  
  debug "GitHub CLI authentication verified"
  
  # Try to access enterprise license data directly (what we actually need)
  debug "Testing enterprise license access for: $ENTERPRISE"
  local license_test
  if license_test=$(gh api "/enterprises/$ENTERPRISE/consumed-licenses" 2>&1); then
    debug "Enterprise license access verified"
    success "GitHub CLI access validated successfully"
    return 0
  fi
  
  # If license access fails, try the enterprise endpoint for better error reporting
  debug "License access failed, testing general enterprise access..."
  local enterprise_response
  
  if ! enterprise_response=$(gh api "/enterprises/$ENTERPRISE" 2>&1); then
    error "Failed to access enterprise: $ENTERPRISE"
    error "API Response: $enterprise_response"
    error "License test response: $license_test"
    error ""
    error "Possible issues:"
    error "  1. Enterprise name might be incorrect (try: gh api /user/orgs)"
    error "  2. Your account may not have enterprise admin access"
    error "  3. Try using organization endpoints instead:"
    error "     gh api /orgs/ORGNAME/members"
    error ""
    error "Debug commands to try:"
    error "  gh api /user"
    error "  gh api /user/orgs"
    error "  gh api /user/memberships/orgs"
    exit 2
  fi

  debug "Enterprise access verified: $ENTERPRISE"
  debug "Enterprise response: $enterprise_response"
  
  # Check if enterprise exists and has valid response
  if echo "$enterprise_response" | jq -e '.message' &>/dev/null; then
    local message=$(echo "$enterprise_response" | jq -r '.message')
    error "Enterprise API error: $message"
    exit 2
  fi
  
  success "GitHub CLI access validated successfully"
}

# Setup output directory structure
setup_output_directory() {
  log "Setting up output directory: $OUT_DIR"
  
  mkdir -p "$OUT_DIR"
  mkdir -p "$OUT_DIR/tmp"
  
  # Create log files
  touch "$OUT_DIR/request.log"
  touch "$OUT_DIR/errors.log"
  
  debug "Output directory structure created"
}

# Make authenticated GitHub API request using gh cli with logging
github_api_request() {
  local endpoint="$1"
  local output_file="$2"
  local start_time=$(date +%s)
  
  debug "Making API request to: $endpoint"
  
  # Use gh api command
  if gh api "$endpoint" > "$output_file" 2>/dev/null; then
    local status_code="200"
  else
    local status_code="error"
    error "API request failed: $endpoint"
    if [[ -f "$output_file" ]]; then
      error "Response: $(cat "$output_file")"
      echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) ERROR $endpoint $(cat "$output_file")" >> "$OUT_DIR/errors.log"
    fi
    return 1
  fi
  
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  # Log request
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) GET $endpoint $status_code ${duration}s" >> "$OUT_DIR/request.log"
  
  # Add small delay to be respectful to API
  if command -v bc &> /dev/null; then
    sleep $(echo "scale=3; $SLEEP_MS / 1000" | bc -l)
  else
    # Fallback if bc is not available
    sleep 0.1
  fi
  
  return 0
}

# Fetch enterprise consumed licenses (users with enterprise licenses)
fetch_enterprise_licenses() {
  log "Fetching Enterprise license consumption from: $ENTERPRISE"
  
  local temp_dir="$OUT_DIR/tmp"
  local endpoint="/enterprises/$ENTERPRISE/consumed-licenses"
  
  debug "Fetching enterprise consumed licenses"
  
  local licenses_file="$temp_dir/enterprise_licenses_raw.json"
  if ! github_api_request "$endpoint" "$licenses_file"; then
    error "Failed to fetch enterprise license data"
    error "Ensure your GitHub CLI authentication has enterprise admin access"
    return 1
  fi
  
  # Extract users from the license data
  local users_array_file="$temp_dir/all_enterprise_users.json"
  
  # The consumed-licenses API returns license consumption data
  # Extract users who have consumed licenses
  jq '.users // []' "$licenses_file" > "$users_array_file" 2>/dev/null || {
    # If .users doesn't exist, try different structures
    jq '. // []' "$licenses_file" > "$users_array_file"
  }
  
  local total_users=$(jq 'length' "$users_array_file")
  log "Successfully fetched $total_users users with enterprise licenses"
  
  return 0
}

# Fetch Copilot billing seats with pagination (based on inactive_copilot.sh pattern)
fetch_copilot_seats() {
  log "Fetching Copilot billing seats from enterprise: $ENTERPRISE"
  
  local temp_dir="$OUT_DIR/tmp"
  local seats_file="$temp_dir/copilot_seats_raw.json"
  local endpoint="/enterprises/$ENTERPRISE/copilot/billing/seats"
  
  debug "Fetching Copilot billing seats"
  
  # The Copilot billing API returns all seats in one response (with pagination handled internally)
  if ! github_api_request "$endpoint" "$seats_file"; then
    error "Failed to fetch Copilot billing seats"
    error "Ensure your GitHub CLI authentication has Copilot billing access"
    return 1
  fi
  
  # Extract seats array and total count
  local total_seats=$(jq '.total_seats // 0' "$seats_file")
  local seats_array_file="$temp_dir/copilot_seats_array.json"
  
  # Extract just the seats array
  jq '.seats // []' "$seats_file" > "$seats_array_file"
  
  local actual_seats=$(jq 'length' "$seats_array_file")
  log "Successfully fetched $actual_seats Copilot seats (total reported: $total_seats)"
  
  return 0
}

# Normalize enterprise license user data to standard schema
normalize_enterprise_user() {
  local input_file="$1"
  local output_file="$2"
  
  debug "Normalizing enterprise license user data"
  
  jq '[.[] | {
    login: .login,
    id: .id,
    name: (.name // null),
    email: (.email // null),
    created_at: (.created_at // null),
    license_type: "enterprise",
    source: "enterprise_license"
  }] | sort_by(.login)' "$input_file" > "$output_file"
  
  local count=$(jq 'length' "$output_file")
  debug "Normalized $count enterprise license users"
}

# Normalize Copilot user data to standard schema
normalize_copilot_user() {
  local input_file="$1"
  local output_file="$2"
  
  debug "Normalizing Copilot user data"
  
  jq '[.[] | {
    login: .assignee.login,
    id: .assignee.id,
    name: (.assignee.name // null),
    email: null,
    created_at: .created_at,
    last_activity_at: .last_activity_at,
    last_activity_editor: (.last_activity_editor // null),
    license_type: "copilot",
    source: "copilot"
  }] | sort_by(.login)' "$input_file" > "$output_file"
  
  local count=$(jq 'length' "$output_file")
  debug "Normalized $count Copilot users"
}

# Perform license gap analysis 
perform_license_gap_analysis() {
  log "Performing license gap analysis..."
  
  local enterprise_file="$OUT_DIR/enterprise_users.json"
  local copilot_file="$OUT_DIR/copilot_users.json"
  
  # Create lookup sets for efficient comparison
  local enterprise_logins_file="$OUT_DIR/tmp/enterprise_logins.json"
  local copilot_logins_file="$OUT_DIR/tmp/copilot_logins.json"
  
  jq '[.[].login]' "$enterprise_file" > "$enterprise_logins_file"
  jq '[.[].login]' "$copilot_file" > "$copilot_logins_file"
  
  # Find users only in Enterprise (have enterprise license, missing Copilot)
  local enterprise_only_file="$OUT_DIR/license_gaps_enterprise_only.json"
  jq --slurpfile copilot_logins "$copilot_logins_file" '
    map(select(.login as $login | $copilot_logins[0] | index($login) | not))
  ' "$enterprise_file" > "$enterprise_only_file"
  
  # Find users only in Copilot (have Copilot license, missing enterprise)
  local copilot_only_file="$OUT_DIR/license_gaps_copilot_only.json"
  jq --slurpfile enterprise_logins "$enterprise_logins_file" '
    map(select(.login as $login | $enterprise_logins[0] | index($login) | not))
  ' "$copilot_file" > "$copilot_only_file"
  
  # Find users with both licenses
  local both_licenses_file="$OUT_DIR/license_overlaps_both.json"
  jq --slurpfile copilot_logins "$copilot_logins_file" '
    map(select(.login as $login | $copilot_logins[0] | index($login)))
  ' "$enterprise_file" > "$both_licenses_file"
  
  # Calculate counts for summary
  local enterprise_only_count=$(jq 'length' "$enterprise_only_file")
  local copilot_only_count=$(jq 'length' "$copilot_only_file")
  local both_count=$(jq 'length' "$both_licenses_file")
  local total_enterprise=$(jq 'length' "$enterprise_file")
  local total_copilot=$(jq 'length' "$copilot_file")
  
  log "License Gap Analysis Results:"
  log "  Enterprise users without Copilot: $enterprise_only_count"
  log "  Copilot users without Enterprise: $copilot_only_count"
  log "  Users with both licenses: $both_count"
  log "  Total Enterprise users: $total_enterprise"
  log "  Total Copilot users: $total_copilot"
  
  # Store results for report generation
  echo "$enterprise_only_count" > "$OUT_DIR/tmp/enterprise_only_count"
  echo "$copilot_only_count" > "$OUT_DIR/tmp/copilot_only_count"
  echo "$both_count" > "$OUT_DIR/tmp/both_count"
  echo "$total_enterprise" > "$OUT_DIR/tmp/total_enterprise"
  echo "$total_copilot" > "$OUT_DIR/tmp/total_copilot"
  
  return 0
}

# Generate comprehensive summary report
emit_reports() {
  log "Generating reports..."
  
  # Read counts from temporary files
  local enterprise_only_count=$(cat "$OUT_DIR/tmp/enterprise_only_count")
  local copilot_only_count=$(cat "$OUT_DIR/tmp/copilot_only_count")
  local both_count=$(cat "$OUT_DIR/tmp/both_count")
  local total_enterprise=$(cat "$OUT_DIR/tmp/total_enterprise")
  local total_copilot=$(cat "$OUT_DIR/tmp/total_copilot")
  
  # Generate summary JSON
  if $GENERATE_JSON; then
    local summary_json="$OUT_DIR/summary.json"
    cat > "$summary_json" << EOF
{
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "script_version": "$VERSION",
  "enterprise": "$ENTERPRISE",
  "analysis": {
    "total_enterprise_users": $total_enterprise,
    "total_copilot_users": $total_copilot,
    "enterprise_only_count": $enterprise_only_count,
    "copilot_only_count": $copilot_only_count,
    "both_licenses_count": $both_count,
    "license_coverage_percentage": $(if command -v bc &> /dev/null; then echo "scale=2; $both_count * 100 / $total_enterprise" | bc -l; else echo "0"; fi),
    "license_gap_percentage": $(if command -v bc &> /dev/null; then echo "scale=2; $enterprise_only_count * 100 / $total_enterprise" | bc -l; else echo "0"; fi)
  },
  "recommendations": {
    "copilot_candidates": $enterprise_only_count,
    "license_cleanup_candidates": $copilot_only_count
  }
}
EOF
    log "Generated JSON summary: $summary_json"
  fi
  
  # Generate CSV export
  if $GENERATE_CSV; then
    local summary_csv="$OUT_DIR/summary.csv"
    
    # Create header
    echo "category,login,name,enterprise_created_at,copilot_created_at,last_activity_at,recommendation" > "$summary_csv"
    
    # Add Enterprise-only users (main target for Copilot provisioning)
    jq -r '.[] | ["enterprise_only", .login, .name, .created_at, null, null, "candidate_for_copilot"] | @csv' \
      "$OUT_DIR/license_gaps_enterprise_only.json" >> "$summary_csv"
    
    # Add users with both licenses
    jq -r '.[] | ["both_licenses", .login, .name, .created_at, null, null, "properly_licensed"] | @csv' \
      "$OUT_DIR/license_overlaps_both.json" >> "$summary_csv"
    
    # Add Copilot-only users (cleanup candidates)
    jq -r '.[] | ["copilot_only", .login, .name, null, .created_at, .last_activity_at, "review_license_assignment"] | @csv' \
      "$OUT_DIR/license_gaps_copilot_only.json" >> "$summary_csv"
    
    log "Generated CSV export: $summary_csv"
  fi
  
  # Generate Markdown report
  if $GENERATE_MARKDOWN; then
    local summary_md="$OUT_DIR/summary.md"
    
    cat > "$summary_md" << EOF
# GitHub Enterprise Copilot License Analysis

**Generated:** $(date -u +%Y-%m-%d\ %H:%M:%S\ UTC)  
**Enterprise:** $ENTERPRISE  
**Script Version:** $VERSION

## Executive Summary

| Metric | Count | Percentage |
|--------|-------|------------|
| Total EMU Users | $total_enterprise | 100% |
| Total Copilot Users | $total_copilot | - |
| Users with Both Licenses | $both_count | $(if command -v bc &> /dev/null; then echo "scale=1; $both_count * 100 / $total_enterprise" | bc -l; else echo "0"; fi)% |
| **EMU Users Missing Copilot** | **$enterprise_only_count** | **$(if command -v bc &> /dev/null; then echo "scale=1; $enterprise_only_count * 100 / $total_enterprise" | bc -l; else echo "0"; fi)%** |
| Copilot Users Missing EMU | $copilot_only_count | - |

## Key Findings

### 🎯 License Provisioning Opportunities
- **$enterprise_only_count EMU users** do not have Copilot licenses
- These users are candidates for Copilot license provisioning
- Represents $(if command -v bc &> /dev/null; then echo "scale=1; $enterprise_only_count * 100 / $total_enterprise" | bc -l; else echo "0"; fi)% of your EMU population

### ✅ Properly Licensed Users
- **$both_count users** have both enterprise and Copilot licenses
- $(if command -v bc &> /dev/null; then echo "scale=1; $both_count * 100 / $total_enterprise" | bc -l; else echo "0"; fi)% license coverage rate

### 🔍 License Review Required
- **$copilot_only_count users** have Copilot licenses but no EMU seat
- Review if these are external collaborators or cleanup candidates

## Recommendations

1. **Immediate Action:** Review the $enterprise_only_count EMU users without Copilot licenses
2. **License Provisioning:** Consider providing Copilot licenses to high-value developers
3. **Cost Optimization:** Review $copilot_only_count Copilot-only licenses for cleanup opportunities
4. **Regular Auditing:** Schedule quarterly license alignment reviews

## Files Generated

- \`emu_users.json\` - All Enterprise Managed Users
- \`copilot_users.json\` - All Copilot license holders  
- \`license_gaps_emu_only.json\` - **Primary target: EMU users without Copilot**
- \`license_gaps_copilot_only.json\` - Copilot users without EMU seats
- \`license_overlaps_both.json\` - Users with both licenses
- \`summary.csv\` - Spreadsheet-friendly export

---
*Report generated by $SCRIPT_NAME v$VERSION*
EOF
    
    log "Generated Markdown report: $summary_md"
  fi
}

# Main function
main() {
  log "Starting GitHub Enterprise Copilot License Comparison v$VERSION"
  
  # Parse arguments first
  parse_args "$@"
  
  log "Enterprise: $ENTERPRISE"
  log "Output Directory: $OUT_DIR"
  
  # Validate prerequisites
  require_tools
  
  if $TEST_MODE; then
    run_test_mode
  else
    validate_api_access
  fi
  
  setup_output_directory
  
  # Fetch data from GitHub APIs (or use test data)
  if $TEST_MODE; then
    log "Using sample test data..."
  else
    if ! fetch_enterprise_licenses; then
      error "Failed to fetch enterprise license data"
      exit 1
    fi
    
    if ! fetch_copilot_seats; then
      error "Failed to fetch Copilot billing seats"
      exit 1
    fi
  fi
  
  # Normalize data to consistent schema
  normalize_enterprise_user "$OUT_DIR/tmp/all_enterprise_users.json" "$OUT_DIR/enterprise_users.json"
  normalize_copilot_user "$OUT_DIR/tmp/copilot_seats_array.json" "$OUT_DIR/copilot_users.json"
  
  # Perform license gap analysis
  if ! perform_license_gap_analysis; then
    error "License gap analysis failed"
    exit 1
  fi
  
  # Generate reports
  emit_reports
  
  # Check if we should fail on gaps (read count before cleanup)
  enterprise_only_count=$(cat "$OUT_DIR/tmp/enterprise_only_count" 2>/dev/null || echo "0")
  
  # Clean up temporary files unless requested to keep them
  if ! $KEEP_TMP; then
    debug "Cleaning up temporary files"
    rm -rf "$OUT_DIR/tmp"
  fi
  if $FAIL_ON_GAPS && [[ $enterprise_only_count -gt $MIN_GAP_THRESHOLD ]]; then
    error "License gaps found: $enterprise_only_count Enterprise users without Copilot licenses (threshold: $MIN_GAP_THRESHOLD)"
    exit 1
  fi
  
  success "License comparison completed successfully"
  success "Results saved to: $OUT_DIR"
  success "Primary target: $enterprise_only_count Enterprise users without Copilot licenses"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi