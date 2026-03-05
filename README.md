# GitHub API Scripts

All scripts were generated with the assistance of GitHub Copilot.

## Script Types & Usage Philosophy

> **Bash First:** These scripts prioritize Bash whenever possible for simplicity and portability. Python is only used when advanced data processing (pandas, numpy) or complex analysis is required.

> **GitHub CLI Recommended:** For most GitHub API interactions, consider using the [GitHub CLI](https://cli.github.com/) instead of custom scripts. The scripts here demonstrate API usage patterns and handle specific use cases not covered by the CLI.

## 📊 [Copilot Analytics](./copilot/)

### Bash Scripts (Recommended)
- [`inactive_copilot.sh`](./copilot/inactive_copilot.sh) - Identifies Copilot users active and inactive within 90 days
- [`compare_ghe_copilot_licenses.sh`](./compare_ghe_copilot_licenses.sh) - **License Gap Analysis** - Compares GitHub Enterprise Managed Users with Copilot licenses to identify users who have enterprise licenses but no Copilot license. Perfect for license optimization and provisioning planning.
   ```bash
   # Basic usage (using GitHub CLI authentication)
   gh auth login  # One-time setup
   ./compare_ghe_copilot_licenses.sh --enterprise your-enterprise
   
   # Complete analysis with all output formats
   ./compare_ghe_copilot_licenses.sh \
     --enterprise your-enterprise \
     --out license_audit_$(date +%Y%m%d) \
     --markdown --csv --json
   
   # Test mode with sample data (no authentication required)
   ./compare_ghe_copilot_licenses.sh --enterprise demo --test-mode --markdown --csv
   ```
   - **Required Permissions:** Enterprise admin access, Copilot billing access
   - **Key Output:** `license_gaps_emu_only.json` - EMU users missing Copilot licenses
   - **Reports:** JSON summary, CSV export, Markdown report with recommendations
   - **Features:** Test mode, comprehensive logging, license coverage analysis

## 👥 [User Management & Provisioning](./user_management/)

- [`compare_emu_ghec_users.sh`](./user_management/compare_emu_ghec_users.sh) - **EMU vs GHEC User Comparison** - Compares users between a GitHub Enterprise Managed User (EMU) instance and a GitHub Enterprise Cloud (GHEC) organization or enterprise. Uses SCIM API for EMU and GraphQL for GHEC. **[Full Documentation →](./user_management/USAGE_compare_emu_ghec.md)**
   ```bash
   # Simple comparison
   ./user_management/compare_emu_ghec_users.sh --emu-enterprise my-emu --ghec-org my-org --csv
   
   # With account switching (EMU vs non-EMU accounts)
   ./user_management/compare_emu_ghec_users.sh \
     --emu-enterprise my-emu \
     --emu-account user_emu \
     --ghec-enterprise my-ghec \
     --ghec-account user_regular \
     --csv --markdown
   ```
   - **Version:** 1.1.0
   - **Required Permissions:** EMU enterprise admin, GHEC org/enterprise access
   - **Key Features:** 
     - Automatic account switching for cross-account access
     - Supports both GHEC organizations and enterprises
     - Identifies provisioning gaps and external collaborators
     - Multiple output formats (JSON, CSV, Markdown)
   - **Requirements:** SAML SSO must be configured on GHEC target
   - **Documentation:** See [USAGE_compare_emu_ghec.md](./user_management/USAGE_compare_emu_ghec.md) for complete guide

## 🔄 [Disaster Recovery](./disaster_recovery/)

- [`owner_dr.sh`](./disaster_recovery/owner_dr.sh) - Creates text-based backups of organization owners in an enterprise and allows restoration of these permissions

## 🔒 [GitHub Advanced Security (GHAS)](./ghas/)

- [`ignore_secrets.sh`](./ghas/ignore_secrets.sh) - Fetches secret scanning alerts, filters by commit dates to identify when secrets were introduced, and resolves them as false positives

## 📈 [Repository Data Collection](./repo_data/)

### Bash Scripts (Recommended)
- [`get_commits.sh`](./repo_data/get_commits.sh) - Gathers commit counts for repositories across an organization over the last 3 months
- [`get_loc_stats.sh`](./repo_data/get_loc_stats.sh) - **Lines of Code Stats** - Collects lines added/deleted per contributor across an entire organization or enterprise using batched GraphQL queries. Scales to thousands of repos without exhausting API rate limits. Supports GitHub CLI and GitHub App authentication.
   ```bash
   # Single org, CLI auth
   ./repo_data/get_loc_stats.sh --org my-org --csv --json

   # Enterprise-wide, GitHub App auth (higher rate limits)
   ./repo_data/get_loc_stats.sh --enterprise my-ent --auth-mode app \
     --app-id 12345 --app-key app.pem --installation-id 67890 \
     --csv --json
   ```
   - **Auth modes:** GitHub CLI (`gh`, 5K req/hr) or GitHub App (JWT, 15K req/hr)
   - **Output:** Per-contributor and per-org CSV/JSON with summary stats
   - **Requirements:** jq, gh (CLI mode) or openssl + curl (App mode)
- [`github_emu_report.sh`](./repo_data/github_emu_report.sh) - Generates EMU (Enterprise Managed User) reports

### Python Scripts (Data Processing)
- [`get_commits.py`](./repo_data/get_commits.py) - Advanced commit analysis with data processing capabilities

## 👥 [Teams Management](./teams/)

- [`list_teams.sh`](./teams/list_teams.sh) - Lists teams in an organization with more than 5 members (useful for identifying teams eligible for Copilot team metrics)

## Prerequisites

### All Scripts
- GitHub CLI installed and authenticated (`gh auth login`)
- **Security Note:** GitHub CLI provides secure authentication without exposing tokens in command line or environment variables

### Python Scripts Only
```bash
# Install required packages
pip install pandas requests pyarrow matplotlib seaborn
```

### Token Scopes Required
- **Copilot scripts:** `manage_billing:copilot` or `read:enterprise`
- **Organization scripts:** `read:org`, `admin:org` (for management operations)
- **Repository scripts:** `repo`
- **Security scripts:** `security_events`

## Quick Start

1. **Set up authentication:**
   ```bash
   export GITHUB_TOKEN=your_token_here
   # or use GitHub CLI
   gh auth login
   ```

2. **Make scripts executable:**
   ```bash
   find . -name "*.sh" -exec chmod +x {} \;
   ```

3. **Run a script:**
   ```bash
   # Bash script example
   ./copilot/inactive_copilot.sh your-org

   ```

## Development Notes

- **Bash Compatibility:** Scripts use `#!/usr/bin/env bash` shebang for portability
- **Shell Version:** Compatible with Bash < 4.0 (no associative arrays)
- **Error Handling:** All scripts include comprehensive error checking and usage documentation
- **Output:** Most scripts provide both human-readable output and CSV/JSON for further processing
