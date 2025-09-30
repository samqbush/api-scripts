#!/usr/bin/env bash

# compare_emu_ghec_users.sh
#
# Usage:
#   gh auth login  # One-time authentication setup
#   ./compare_emu_ghec_users.sh --emu-enterprise ENTERPRISE --ghec-org ORGANIZATION [OPTIONS]
#
# Description:
#   Compares users between a GitHub Enterprise Managed User (EMU) instance and a 
#   GitHub Enterprise Cloud (GHEC) organization to identify differences in user provisioning.
#   Uses SCIM API for EMU and GraphQL API for GHEC to fetch and compare user emails.
#
# Examples:
#   # Basic comparison (using GitHub CLI authentication)
#   gh auth login  # One-time setup
#   ./compare_emu_ghec_users.sh --emu-enterprise my-emu --ghec-org my-org
#
#   # Full analysis with all output formats
#   ./compare_emu_ghec_users.sh \
#     --emu-enterprise my-emu \
#     --ghec-org my-org \
#     --out user_comparison_20250930 \
#     --markdown --json --csv \
#     --debug
#
# Requirements:
#   - GitHub CLI (gh) installed and authenticated (gh auth login)
#   - jq must be installed  
#   - Access to both EMU enterprise and GHEC organization with required permissions
#
# Arguments:
#   --emu-enterprise SLUG  Required. GitHub EMU Enterprise slug/name
#   --ghec-org ORG         Required. GitHub GHEC Organization name
#   --out DIRECTORY        Output directory (default: compare_users_TIMESTAMP)
#   --markdown             Generate Markdown summary report (default: true)
#   --json                 Generate detailed JSON reports (default: true)
#   --csv                  Generate CSV export for spreadsheet analysis
#   --sleep-ms MS          Sleep between API calls in milliseconds (default: 100)
#   --keep-tmp             Keep temporary files for debugging
#   --debug                Enable verbose debug output
#   --help, -h             Show this help message

set -e

# Global variables
SCRIPT_NAME="compare_emu_ghec_users.sh"
VERSION="1.1.0"
EMU_ENTERPRISE=""
EMU_ACCOUNT=""
GHEC_ORG=""
GHEC_ENTERPRISE=""
GHEC_ACCOUNT=""
GHEC_TARGET_TYPE=""  # "org" or "enterprise"
OUT_DIR=""
GENERATE_MARKDOWN=true
GENERATE_JSON=true
GENERATE_CSV=false
SLEEP_MS=100
KEEP_TMP=false
DEBUG=false
ORIGINAL_ACCOUNT=""  # Track original account to restore at end

# Temporary files
TMP_DIR=""
EMU_USERS_FILE=""
GHEC_USERS_FILE=""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

###################
# Utility Functions
###################

log() {
  echo -e "${GREEN}[INFO]${NC} $*" >&2
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

debug() {
  if [[ "$DEBUG" == "true" ]]; then
    echo -e "${BLUE}[DEBUG]${NC} $*" >&2
  fi
}

show_help() {
  cat << EOF
${SCRIPT_NAME} v${VERSION}

Compare users between GitHub Enterprise Managed User (EMU) and GitHub Enterprise Cloud (GHEC).

USAGE:
  ${SCRIPT_NAME} --emu-enterprise ENTERPRISE (--ghec-org ORG | --ghec-enterprise ENTERPRISE) [OPTIONS]

REQUIRED ARGUMENTS:
  --emu-enterprise SLUG       GitHub EMU Enterprise slug/name
  --ghec-org ORG              GitHub GHEC Organization name
    OR
  --ghec-enterprise SLUG      GitHub GHEC Enterprise slug/name

ACCOUNT SWITCHING (for cross-account access):
  --emu-account USERNAME      GitHub account to use for EMU access (e.g., user_emu)
  --ghec-account USERNAME     GitHub account to use for GHEC access (e.g., user)
  
  Note: Script will automatically switch between accounts as needed.
        Both accounts must be authenticated with 'gh auth login'.

OPTIONAL ARGUMENTS:
  --out DIRECTORY             Output directory (default: compare_users_TIMESTAMP)
  --markdown                  Generate Markdown report (default: true)
  --json                      Generate JSON reports (default: true)
  --csv                       Generate CSV export
  --sleep-ms MS               Sleep between API calls in ms (default: 100)
  --keep-tmp                  Keep temporary files for debugging
  --debug                     Enable verbose debug output
  --help, -h                  Show this help message

EXAMPLES:
  # Compare EMU with GHEC organization
  ${SCRIPT_NAME} --emu-enterprise my-emu --ghec-org my-org

  # Compare with account switching (EMU account vs non-EMU account)
  ${SCRIPT_NAME} \\
    --emu-enterprise my-emu \\
    --emu-account user_emu \\
    --ghec-enterprise my-ghec \\
    --ghec-account user

  # With all output formats and debugging
  ${SCRIPT_NAME} \\
    --emu-enterprise my-emu \\
    --emu-account user_emu \\
    --ghec-org my-org \\
    --ghec-account user \\
    --csv --debug

REQUIREMENTS:
  - GitHub CLI (gh) installed and authenticated
  - jq for JSON processing
  - Appropriate access permissions for both instances
  - If using account switching, both accounts must be authenticated

EOF
}

check_prerequisites() {
  log "Checking prerequisites..."
  
  # Check for jq
  if ! command -v jq &> /dev/null; then
    error "jq is required but not installed."
    error "Install with: brew install jq (macOS) or apt-get install jq (Linux)"
    exit 1
  fi
  
  # Check for gh - try common locations
  GH_CMD=""
  if command -v gh &> /dev/null; then
    GH_CMD="gh"
  elif [[ -x "/opt/homebrew/bin/gh" ]]; then
    GH_CMD="/opt/homebrew/bin/gh"
  elif [[ -x "/usr/local/bin/gh" ]]; then
    GH_CMD="/usr/local/bin/gh"
  elif [[ -x "$HOME/.local/bin/gh" ]]; then
    GH_CMD="$HOME/.local/bin/gh"
  else
    error "GitHub CLI (gh) is required but not found."
    error "Install from: https://cli.github.com/"
    error ""
    error "If gh is already installed, you may need to:"
    error "  1. Add it to your PATH"
    error "  2. Restart your terminal"
    error "  3. Check with: which gh"
    exit 1
  fi
  
  debug "Using gh at: $GH_CMD"
  
  # Check gh authentication
  if ! $GH_CMD auth status &> /dev/null; then
    error "GitHub CLI is not authenticated."
    error "Run: $GH_CMD auth login"
    exit 1
  fi
  
  # Get current active account
  ORIGINAL_ACCOUNT=$($GH_CMD auth status 2>&1 | grep "Active account: true" -B 2 | grep "Logged in to" | head -1 | awk '{print $6}' | tr -d '()')
  debug "Original active account: $ORIGINAL_ACCOUNT"
  
  # If using account switching, verify both accounts are authenticated
  if [[ -n "$EMU_ACCOUNT" ]]; then
    log "Verifying account authentication..."
    
    # Check EMU account
    if ! $GH_CMD auth status 2>&1 | grep -q "account $EMU_ACCOUNT"; then
      error "EMU account '$EMU_ACCOUNT' is not authenticated."
      error "Run: $GH_CMD auth login"
      error "Then authenticate as '$EMU_ACCOUNT'"
      exit 1
    fi
    debug "EMU account '$EMU_ACCOUNT' is authenticated"
    
    # Check GHEC account
    if ! $GH_CMD auth status 2>&1 | grep -q "account $GHEC_ACCOUNT"; then
      error "GHEC account '$GHEC_ACCOUNT' is not authenticated."
      error "Run: $GH_CMD auth login"
      error "Then authenticate as '$GHEC_ACCOUNT'"
      exit 1
    fi
    debug "GHEC account '$GHEC_ACCOUNT' is authenticated"
  fi
  
  debug "Prerequisites check passed"
}

switch_to_account() {
  local account="$1"
  local purpose="$2"
  
  if [[ -z "$account" ]]; then
    debug "No account switching needed for $purpose"
    return 0
  fi
  
  log "Switching to account '$account' for $purpose..."
  
  if ! $GH_CMD auth switch --user "$account" &> /dev/null; then
    error "Failed to switch to account '$account'"
    error "Make sure the account is authenticated with: $GH_CMD auth login"
    exit 1
  fi
  
  debug "Successfully switched to account '$account'"
}

restore_original_account() {
  if [[ -n "$ORIGINAL_ACCOUNT" ]] && [[ -n "$EMU_ACCOUNT" ]]; then
    log "Restoring original account '$ORIGINAL_ACCOUNT'..."
    $GH_CMD auth switch --user "$ORIGINAL_ACCOUNT" &> /dev/null || true
  fi
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --emu-enterprise)
        EMU_ENTERPRISE="$2"
        shift 2
        ;;
      --emu-account)
        EMU_ACCOUNT="$2"
        shift 2
        ;;
      --ghec-org)
        GHEC_ORG="$2"
        GHEC_TARGET_TYPE="org"
        shift 2
        ;;
      --ghec-enterprise)
        GHEC_ENTERPRISE="$2"
        GHEC_TARGET_TYPE="enterprise"
        shift 2
        ;;
      --ghec-account)
        GHEC_ACCOUNT="$2"
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
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        error "Unknown argument: $1"
        echo ""
        show_help
        exit 1
        ;;
    esac
  done
  
  # Validate required arguments
  if [[ -z "$EMU_ENTERPRISE" ]]; then
    error "Missing required argument: --emu-enterprise"
    show_help
    exit 1
  fi
  
  if [[ -z "$GHEC_ORG" ]] && [[ -z "$GHEC_ENTERPRISE" ]]; then
    error "Missing required argument: --ghec-org or --ghec-enterprise"
    show_help
    exit 1
  fi
  
  # Validate account switching logic
  if [[ -n "$EMU_ACCOUNT" ]] || [[ -n "$GHEC_ACCOUNT" ]]; then
    if [[ -z "$EMU_ACCOUNT" ]] || [[ -z "$GHEC_ACCOUNT" ]]; then
      error "Both --emu-account and --ghec-account must be specified together"
      show_help
      exit 1
    fi
  fi
  
  # Set default output directory if not provided
  if [[ -z "$OUT_DIR" ]]; then
    OUT_DIR="compare_users_$(date +%Y%m%d_%H%M%S)"
  fi
  
  debug "EMU Enterprise: $EMU_ENTERPRISE"
  if [[ -n "$EMU_ACCOUNT" ]]; then
    debug "EMU Account: $EMU_ACCOUNT"
  fi
  if [[ "$GHEC_TARGET_TYPE" == "org" ]]; then
    debug "GHEC Organization: $GHEC_ORG"
  else
    debug "GHEC Enterprise: $GHEC_ENTERPRISE"
  fi
  if [[ -n "$GHEC_ACCOUNT" ]]; then
    debug "GHEC Account: $GHEC_ACCOUNT"
  fi
  debug "Output directory: $OUT_DIR"
}

setup_directories() {
  log "Setting up output directories..."
  
  mkdir -p "$OUT_DIR"
  mkdir -p "$OUT_DIR/logs"
  
  # Create temporary directory
  TMP_DIR="$OUT_DIR/tmp"
  mkdir -p "$TMP_DIR"
  
  # Set temporary file paths
  EMU_USERS_FILE="$TMP_DIR/emu_users.json"
  GHEC_USERS_FILE="$TMP_DIR/ghec_users.json"
  
  debug "Created output directory: $OUT_DIR"
  debug "Created temporary directory: $TMP_DIR"
}

sleep_between_calls() {
  if [[ $SLEEP_MS -gt 0 ]]; then
    debug "Sleeping for ${SLEEP_MS}ms..."
    sleep "$(echo "scale=3; $SLEEP_MS / 1000" | bc)"
  fi
}

###################
# EMU Functions
###################

url_encode() {
  local string="$1"
  # Use jq to URL encode the string
  echo -n "$string" | jq -sRr @uri
}

fetch_emu_users() {
  # Switch to EMU account if specified
  switch_to_account "$EMU_ACCOUNT" "EMU access"
  
  log "Fetching users from EMU enterprise: $EMU_ENTERPRISE..."
  
  # URL encode the enterprise name
  local encoded_enterprise
  encoded_enterprise=$(url_encode "$EMU_ENTERPRISE")
  debug "Encoded enterprise: $encoded_enterprise"
  
  local start_index=1
  local count=100
  local all_users="[]"
  local has_more=true
  local total_fetched=0
  
  while [[ "$has_more" == "true" ]]; do
    debug "Fetching EMU users: startIndex=$start_index, count=$count"
    
    local response
    local endpoint="/scim/v2/enterprises/$encoded_enterprise/Users?startIndex=$start_index&count=$count"
    debug "Endpoint: $endpoint"
    
    if ! response=$($GH_CMD api \
      -H "Accept: application/scim+json" \
      "$endpoint" \
      2>&1); then
      error "Failed to fetch EMU users from SCIM API"
      error "Response: $response"
      error ""
      error "The SCIM API requires:"
      error "  - Enterprise admin access"
      error "  - SCIM provisioning to be enabled"
      error ""
      error "To verify SCIM access:"
      error "  $GH_CMD api -H 'Accept: application/scim+json' '/scim/v2/enterprises/$encoded_enterprise/Users?startIndex=1&count=1'"
      exit 1
    fi
    
    # Extract users from response
    local users
    users=$(echo "$response" | jq -c '.Resources // []')
    
    local users_count
    users_count=$(echo "$users" | jq 'length')
    
    if [[ $users_count -eq 0 ]]; then
      has_more=false
      break
    fi
    
    # Append users to all_users
    all_users=$(echo "$all_users" | jq --argjson new_users "$users" '. + $new_users')
    
    total_fetched=$((total_fetched + users_count))
    log "Fetched $users_count EMU users (total: $total_fetched)"
    
    # Check if there are more results
    local total_results
    total_results=$(echo "$response" | jq -r '.totalResults // 0')
    
    if [[ $total_fetched -ge $total_results ]]; then
      has_more=false
    else
      start_index=$((start_index + count))
      sleep_between_calls
    fi
  done
  
  # Normalize EMU user data
  local normalized_users
  normalized_users=$(echo "$all_users" | jq -c '[
    .[] | {
      source: "EMU",
      username: .userName,
      email: (.emails[0].value // ""),
      display_name: .displayName,
      user_id: .id,
      active: .active
    }
  ]')
  
  echo "$normalized_users" > "$EMU_USERS_FILE"
  
  log "Successfully fetched $total_fetched users from EMU enterprise"
  debug "EMU users saved to: $EMU_USERS_FILE"
}

###################
# GHEC Functions
###################

fetch_ghec_users() {
  # Switch to GHEC account if specified
  switch_to_account "$GHEC_ACCOUNT" "GHEC access"
  
  if [[ "$GHEC_TARGET_TYPE" == "org" ]]; then
    log "Fetching users from GHEC organization: $GHEC_ORG..."
    fetch_ghec_org_users
  else
    log "Fetching users from GHEC enterprise: $GHEC_ENTERPRISE..."
    fetch_ghec_enterprise_users
  fi
}

fetch_ghec_org_users() {
  local cursor="null"
  local has_next_page=true
  local all_users="[]"
  local total_fetched=0
  
  while [[ "$has_next_page" == "true" ]]; do
    debug "Fetching GHEC org users with cursor: $cursor"
    
    # Build GraphQL query for organization
    local query
    read -r -d '' query << EOF || true
query {
  organization(login: "$GHEC_ORG") {
    samlIdentityProvider {
      externalIdentities(first: 100, after: $cursor) {
        totalCount
        pageInfo {
          hasNextPage
          endCursor
        }
        edges {
          node {
            user {
              id
              login
            }
            samlIdentity {
              nameId
            }
          }
        }
      }
    }
  }
}
EOF
    
    local response
    if ! response=$($GH_CMD api graphql -f query="$query" 2>&1); then
      error "Failed to fetch GHEC users: $response"
      exit 1
    fi
    
    # Check if organization has SAML configured
    if echo "$response" | jq -e '.data.organization.samlIdentityProvider == null' > /dev/null; then
      error "Organization '$GHEC_ORG' does not have SAML identity provider configured"
      error "This script requires SAML SSO to be enabled on the organization"
      exit 1
    fi
    
    # Extract users from response
    local users
    users=$(echo "$response" | jq -c '.data.organization.samlIdentityProvider.externalIdentities.edges // []')
    
    local users_count
    users_count=$(echo "$users" | jq 'length')
    
    if [[ $users_count -eq 0 ]]; then
      break
    fi
    
    # Append users to all_users
    all_users=$(echo "$all_users" | jq --argjson new_users "$users" '. + $new_users')
    
    total_fetched=$((total_fetched + users_count))
    log "Fetched $users_count GHEC users (total: $total_fetched)"
    
    # Check pagination
    has_next_page=$(echo "$response" | jq -r '.data.organization.samlIdentityProvider.externalIdentities.pageInfo.hasNextPage')
    
    if [[ "$has_next_page" == "true" ]]; then
      local end_cursor
      end_cursor=$(echo "$response" | jq -r '.data.organization.samlIdentityProvider.externalIdentities.pageInfo.endCursor')
      cursor="\"$end_cursor\""
      sleep_between_calls
    fi
  done
  
  # Normalize GHEC user data
  local normalized_users
  normalized_users=$(echo "$all_users" | jq -c '[
    .[] | {
      source: "GHEC",
      username: .node.user.login,
      email: (.node.samlIdentity.nameId // ""),
      user_id: .node.user.id
    }
  ]')
  
  echo "$normalized_users" > "$GHEC_USERS_FILE"
  
  log "Successfully fetched $total_fetched users from GHEC organization"
  debug "GHEC users saved to: $GHEC_USERS_FILE"
}

fetch_ghec_enterprise_users() {
  local cursor="null"
  local has_next_page=true
  local all_users="[]"
  local total_fetched=0
  
  # URL encode the enterprise name
  local encoded_enterprise
  encoded_enterprise=$(url_encode "$GHEC_ENTERPRISE")
  debug "Encoded enterprise: $encoded_enterprise"
  
  while [[ "$has_next_page" == "true" ]]; do
    debug "Fetching GHEC enterprise users with cursor: $cursor"
    
    # Build GraphQL query for enterprise
    local query
    read -r -d '' query << EOF || true
query {
  enterprise(slug: "$GHEC_ENTERPRISE") {
    ownerInfo {
      samlIdentityProvider {
        externalIdentities(first: 100, after: $cursor) {
          totalCount
          pageInfo {
            hasNextPage
            endCursor
          }
          edges {
            node {
              user {
                id
                login
              }
              samlIdentity {
                nameId
              }
            }
          }
        }
      }
    }
  }
}
EOF
    
    local response
    if ! response=$($GH_CMD api graphql -f query="$query" 2>&1); then
      error "Failed to fetch GHEC enterprise users: $response"
      error ""
      error "Possible issues:"
      error "  1. Enterprise slug is incorrect"
      error "  2. You don't have access to this enterprise"
      error "  3. SAML SSO is not configured for the enterprise"
      error ""
      error "To verify enterprise access:"
      error "  $GH_CMD api graphql -f query='{ enterprise(slug: \"$GHEC_ENTERPRISE\") { name } }'"
      exit 1
    fi
    
    # Check if enterprise has SAML configured
    if echo "$response" | jq -e '.data.enterprise.ownerInfo.samlIdentityProvider == null' > /dev/null; then
      error "Enterprise '$GHEC_ENTERPRISE' does not have SAML identity provider configured"
      error "This script requires SAML SSO to be enabled on the enterprise"
      exit 1
    fi
    
    # Extract users from response
    local users
    users=$(echo "$response" | jq -c '.data.enterprise.ownerInfo.samlIdentityProvider.externalIdentities.edges // []')
    
    local users_count
    users_count=$(echo "$users" | jq 'length')
    
    if [[ $users_count -eq 0 ]]; then
      break
    fi
    
    # Append users to all_users
    all_users=$(echo "$all_users" | jq --argjson new_users "$users" '. + $new_users')
    
    total_fetched=$((total_fetched + users_count))
    log "Fetched $users_count GHEC users (total: $total_fetched)"
    
    # Check pagination
    has_next_page=$(echo "$response" | jq -r '.data.enterprise.ownerInfo.samlIdentityProvider.externalIdentities.pageInfo.hasNextPage')
    
    if [[ "$has_next_page" == "true" ]]; then
      local end_cursor
      end_cursor=$(echo "$response" | jq -r '.data.enterprise.ownerInfo.samlIdentityProvider.externalIdentities.pageInfo.endCursor')
      cursor="\"$end_cursor\""
      sleep_between_calls
    fi
  done
  
  # Normalize GHEC user data
  local normalized_users
  normalized_users=$(echo "$all_users" | jq -c '[
    .[] | {
      source: "GHEC",
      username: .node.user.login,
      email: (.node.samlIdentity.nameId // ""),
      user_id: .node.user.id
    }
  ]')
  
  echo "$normalized_users" > "$GHEC_USERS_FILE"
  
  log "Successfully fetched $total_fetched users from GHEC enterprise"
  debug "GHEC users saved to: $GHEC_USERS_FILE"
}

###################
# Comparison Functions
###################

normalize_email() {
  local email="$1"
  echo "$email" | tr '[:upper:]' '[:lower:]'
}

compare_users() {
  log "Comparing users between EMU and GHEC..."
  
  local emu_users
  emu_users=$(cat "$EMU_USERS_FILE")
  
  local ghec_users
  ghec_users=$(cat "$GHEC_USERS_FILE")
  
  local emu_count
  emu_count=$(echo "$emu_users" | jq 'length')
  
  local ghec_count
  ghec_count=$(echo "$ghec_users" | jq 'length')
  
  log "EMU users: $emu_count"
  log "GHEC users: $ghec_count"
  
  # Create comparison results
  local comparison
  comparison=$(jq -n \
    --argjson emu "$emu_users" \
    --argjson ghec "$ghec_users" '
    {
      summary: {
        emu_total: ($emu | length),
        ghec_total: ($ghec | length),
        timestamp: now | strftime("%Y-%m-%d %H:%M:%S")
      },
      emu_users: $emu,
      ghec_users: $ghec,
      comparison: {
        in_both: [],
        only_in_emu: [],
        only_in_ghec: []
      }
    }
  ')
  
  # Build email to user mappings for comparison
  local emu_email_map
  emu_email_map=$(echo "$emu_users" | jq -c 'map({(.email | ascii_downcase): .}) | add // {}')
  
  local ghec_email_map
  ghec_email_map=$(echo "$ghec_users" | jq -c 'map({(.email | ascii_downcase): .}) | add // {}')
  
  # Find users in both systems
  local in_both
  in_both=$(jq -n \
    --argjson emu_map "$emu_email_map" \
    --argjson ghec_map "$ghec_email_map" '
    $emu_map | to_entries | map(
      select($ghec_map[.key] != null) | {
        email: .key,
        emu_user: .value,
        ghec_user: $ghec_map[.key]
      }
    )
  ')
  
  # Find users only in EMU
  local only_in_emu
  only_in_emu=$(jq -n \
    --argjson emu_map "$emu_email_map" \
    --argjson ghec_map "$ghec_email_map" '
    $emu_map | to_entries | map(
      select($ghec_map[.key] == null) | .value
    )
  ')
  
  # Find users only in GHEC
  local only_in_ghec
  only_in_ghec=$(jq -n \
    --argjson emu_map "$emu_email_map" \
    --argjson ghec_map "$ghec_email_map" '
    $ghec_map | to_entries | map(
      select($emu_map[.key] == null) | .value
    )
  ')
  
  # Update comparison with results
  comparison=$(echo "$comparison" | jq \
    --argjson in_both "$in_both" \
    --argjson only_emu "$only_in_emu" \
    --argjson only_ghec "$only_in_ghec" '
    .comparison.in_both = $in_both |
    .comparison.only_in_emu = $only_emu |
    .comparison.only_in_ghec = $only_ghec |
    .summary.in_both_count = ($in_both | length) |
    .summary.only_in_emu_count = ($only_emu | length) |
    .summary.only_in_ghec_count = ($only_ghec | length)
  ')
  
  local in_both_count
  in_both_count=$(echo "$comparison" | jq '.summary.in_both_count')
  local only_emu_count
  only_emu_count=$(echo "$comparison" | jq '.summary.only_in_emu_count')
  local only_ghec_count
  only_ghec_count=$(echo "$comparison" | jq '.summary.only_in_ghec_count')
  
  log "Users in both systems: $in_both_count"
  log "Users only in EMU: $only_emu_count"
  log "Users only in GHEC: $only_ghec_count"
  
  echo "$comparison"
}

###################
# Report Generation
###################

generate_json_report() {
  local comparison="$1"
  local output_file="$OUT_DIR/comparison_results.json"
  
  log "Generating JSON report..."
  
  echo "$comparison" | jq '.' > "$output_file"
  
  log "JSON report saved to: $output_file"
}

generate_csv_report() {
  local comparison="$1"
  
  log "Generating CSV reports..."
  
  # Generate CSV for users in both systems
  echo "$comparison" | jq -r '
    ["Email", "EMU Username", "GHEC Username", "EMU Display Name"],
    (.comparison.in_both[] | [
      .email,
      .emu_user.username,
      .ghec_user.username,
      .emu_user.display_name
    ]) | @csv
  ' > "$OUT_DIR/users_in_both.csv"
  
  # Generate CSV for users only in EMU
  echo "$comparison" | jq -r '
    ["Email", "Username", "Display Name", "Active"],
    (.comparison.only_in_emu[] | [
      .email,
      .username,
      .display_name,
      .active
    ]) | @csv
  ' > "$OUT_DIR/users_only_in_emu.csv"
  
  # Generate CSV for users only in GHEC
  echo "$comparison" | jq -r '
    ["Email", "Username"],
    (.comparison.only_in_ghec[] | [
      .email,
      .username
    ]) | @csv
  ' > "$OUT_DIR/users_only_in_ghec.csv"
  
  log "CSV reports saved to:"
  log "  - $OUT_DIR/users_in_both.csv"
  log "  - $OUT_DIR/users_only_in_emu.csv"
  log "  - $OUT_DIR/users_only_in_ghec.csv"
}

generate_markdown_report() {
  local comparison="$1"
  local output_file="$OUT_DIR/summary_report.md"
  
  log "Generating Markdown report..."
  
  local emu_total
  emu_total=$(echo "$comparison" | jq '.summary.emu_total')
  local ghec_total
  ghec_total=$(echo "$comparison" | jq '.summary.ghec_total')
  local in_both_count
  in_both_count=$(echo "$comparison" | jq '.summary.in_both_count')
  local only_emu_count
  only_emu_count=$(echo "$comparison" | jq '.summary.only_in_emu_count')
  local only_ghec_count
  only_ghec_count=$(echo "$comparison" | jq '.summary.only_in_ghec_count')
  local timestamp
  timestamp=$(echo "$comparison" | jq -r '.summary.timestamp')
  
  local ghec_label
  local ghec_name
  if [[ "$GHEC_TARGET_TYPE" == "org" ]]; then
    ghec_label="GHEC Organization"
    ghec_name="$GHEC_ORG"
  else
    ghec_label="GHEC Enterprise"
    ghec_name="$GHEC_ENTERPRISE"
  fi
  
  cat > "$output_file" << EOF
# EMU vs GHEC User Comparison Report

**Generated:** $timestamp  
**EMU Enterprise:** $EMU_ENTERPRISE  
**$ghec_label:** $ghec_name

---

## Summary

| Metric | Count |
|--------|-------|
| Total EMU Users | $emu_total |
| Total GHEC Users | $ghec_total |
| Users in Both Systems | $in_both_count |
| Users Only in EMU | $only_emu_count |
| Users Only in GHEC | $only_ghec_count |

---

## Analysis

### Match Rate
- **EMU Match Rate:** $(echo "scale=2; $in_both_count * 100 / $emu_total" | bc)% of EMU users are in GHEC
- **GHEC Match Rate:** $(echo "scale=2; $in_both_count * 100 / $ghec_total" | bc)% of GHEC users are in EMU

### Users in Both Systems ($in_both_count)
These users exist in both the EMU enterprise and the GHEC $GHEC_TARGET_TYPE with matching email addresses.

EOF

  # Add sample of users in both (limit to 10)
  if [[ $in_both_count -gt 0 ]]; then
    echo "$comparison" | jq -r '
      .comparison.in_both[0:10] | 
      ["| Email | EMU Username | GHEC Username |"],
      ["|-------|--------------|---------------|"],
      (.[] | "| \(.email) | \(.emu_user.username) | \(.ghec_user.username) |")
      | .[]
    ' >> "$output_file"
    
    if [[ $in_both_count -gt 10 ]]; then
      echo "" >> "$output_file"
      echo "_Showing 10 of $in_both_count users. See \`users_in_both.csv\` for full list._" >> "$output_file"
    fi
  else
    echo "No users found in both systems." >> "$output_file"
  fi
  
  cat >> "$output_file" << EOF

---

### Users Only in EMU ($only_emu_count)
These users exist in the EMU enterprise but not in the GHEC $GHEC_TARGET_TYPE. They may need to be provisioned to GHEC.

EOF

  # Add sample of users only in EMU (limit to 10)
  if [[ $only_emu_count -gt 0 ]]; then
    echo "$comparison" | jq -r '
      .comparison.only_in_emu[0:10] | 
      ["| Email | Username | Display Name | Active |"],
      ["|-------|----------|--------------|--------|"],
      (.[] | "| \(.email) | \(.username) | \(.display_name) | \(.active) |")
      | .[]
    ' >> "$output_file"
    
    if [[ $only_emu_count -gt 10 ]]; then
      echo "" >> "$output_file"
      echo "_Showing 10 of $only_emu_count users. See \`users_only_in_emu.csv\` for full list._" >> "$output_file"
    fi
  else
    echo "All EMU users are present in GHEC." >> "$output_file"
  fi
  
  cat >> "$output_file" << EOF

---

### Users Only in GHEC ($only_ghec_count)
These users exist in the GHEC $GHEC_TARGET_TYPE but not in the EMU enterprise. They may be external collaborators or need to be added to EMU.

EOF

  # Add sample of users only in GHEC (limit to 10)
  if [[ $only_ghec_count -gt 0 ]]; then
    echo "$comparison" | jq -r '
      .comparison.only_in_ghec[0:10] | 
      ["| Email | Username |"],
      ["|-------|----------|"],
      (.[] | "| \(.email) | \(.username) |")
      | .[]
    ' >> "$output_file"
    
    if [[ $only_ghec_count -gt 10 ]]; then
      echo "" >> "$output_file"
      echo "_Showing 10 of $only_ghec_count users. See \`users_only_in_ghec.csv\` for full list._" >> "$output_file"
    fi
  else
    echo "All GHEC users are present in EMU." >> "$output_file"
  fi
  
  cat >> "$output_file" << EOF

---

## Recommendations

EOF

  if [[ $only_emu_count -gt 0 ]]; then
    cat >> "$output_file" << EOF
### Provision EMU Users to GHEC
There are **$only_emu_count** users in EMU that are not in the GHEC $GHEC_TARGET_TYPE. Consider:
1. Review the list in \`users_only_in_emu.csv\`
2. Provision these users to the GHEC $GHEC_TARGET_TYPE if they need access
3. Verify that SAML SSO is properly configured

EOF
  fi
  
  if [[ $only_ghec_count -gt 0 ]]; then
    cat >> "$output_file" << EOF
### Review GHEC-Only Users
There are **$only_ghec_count** users in GHEC that are not in EMU. Consider:
1. Review the list in \`users_only_in_ghec.csv\`
2. Determine if these are external collaborators or should be in EMU
3. Add missing users to EMU if they are internal employees

EOF
  fi
  
  cat >> "$output_file" << EOF

---

## Files Generated

- \`comparison_results.json\` - Complete comparison data in JSON format
EOF

  if [[ "$GENERATE_CSV" == "true" ]]; then
    cat >> "$output_file" << EOF
- \`users_in_both.csv\` - Users present in both systems
- \`users_only_in_emu.csv\` - Users only in EMU
- \`users_only_in_ghec.csv\` - Users only in GHEC
EOF
  fi
  
  cat >> "$output_file" << EOF

---

_Generated by ${SCRIPT_NAME} v${VERSION}_
EOF
  
  log "Markdown report saved to: $output_file"
}

cleanup() {
  # Restore original account if we were switching
  restore_original_account
  
  if [[ "$KEEP_TMP" == "false" ]] && [[ -d "$TMP_DIR" ]]; then
    debug "Cleaning up temporary files..."
    rm -rf "$TMP_DIR"
  else
    debug "Keeping temporary files in: $TMP_DIR"
  fi
}

###################
# Main Execution
###################

main() {
  log "Starting $SCRIPT_NAME v$VERSION"
  
  parse_arguments "$@"
  check_prerequisites
  setup_directories
  
  # Set up trap to restore account on exit
  trap restore_original_account EXIT INT TERM
  
  # Fetch users from both systems
  fetch_emu_users
  fetch_ghec_users
  
  # Compare users
  local comparison
  comparison=$(compare_users)
  
  # Generate reports
  if [[ "$GENERATE_JSON" == "true" ]]; then
    generate_json_report "$comparison"
  fi
  
  if [[ "$GENERATE_CSV" == "true" ]]; then
    generate_csv_report "$comparison"
  fi
  
  if [[ "$GENERATE_MARKDOWN" == "true" ]]; then
    generate_markdown_report "$comparison"
  fi
  
  cleanup
  
  log "Comparison complete! Results saved to: $OUT_DIR"
  
  if [[ "$GENERATE_MARKDOWN" == "true" ]]; then
    echo ""
    log "View the summary report: $OUT_DIR/summary_report.md"
  fi
}

# Run main function
main "$@"
