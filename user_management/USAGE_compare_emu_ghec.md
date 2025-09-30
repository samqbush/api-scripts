# compare_emu_ghec_users.sh - Complete Usage Guide

**Version:** 1.1.0  
**Last Updated:** September 30, 2025

This guide provides comprehensive documentation for comparing users between GitHub Enterprise Managed User (EMU) instances and GitHub Enterprise Cloud (GHEC) organizations or enterprises.

## Table of Contents

- [Quick Start](#quick-start)
- [API Reference](#api-reference)
- [Prerequisites](#prerequisites)
- [Account Switching](#account-switching)
- [Basic Usage](#basic-usage)
- [Common Use Cases](#common-use-cases)
- [Understanding the Output](#understanding-the-output)
- [Troubleshooting](#troubleshooting)
- [API Rate Limits](#api-rate-limits)
- [Tips & Best Practices](#tips--best-practices)

---

## Quick Start

### Simple Comparison (Single Account)
```bash
# Prerequisites
gh auth login  # Authenticate once

# Run comparison
./compare_emu_ghec_users.sh \
  --emu-enterprise my-emu \
  --ghec-org my-org \
  --csv
```

### With Account Switching (EMU + Non-EMU accounts)
```bash
# Authenticate both accounts first
gh auth login  # Authenticate as EMU account
gh auth login  # Authenticate as non-EMU account

# Run comparison with automatic account switching
./compare_emu_ghec_users.sh \
  --emu-enterprise fabrikam \
  --emu-account samqbush_fabrikam \
  --ghec-enterprise octodemo \
  --ghec-account samqbush \
  --csv --markdown
```

---

This script uses the following GitHub APIs:

### EMU SCIM API
- **Endpoint**: `/scim/v2/enterprises/{enterprise}/Users`
- **Method**: GET
- **Authentication**: GitHub CLI (Personal Access Token or GitHub App)
- **Required Scopes**: `admin:enterprise` or `scim:enterprise`
- **Documentation**: [SCIM Provisioning for Enterprises](https://docs.github.com/en/enterprise-cloud@latest/rest/enterprise-admin/scim?apiVersion=2022-11-28#list-scim-provisioned-identities-for-an-enterprise)
- **Purpose**: Fetch all provisioned users from an EMU enterprise
- **Pagination**: Uses `startIndex` and `count` parameters

### GHEC Organization GraphQL API
- **Endpoint**: `/graphql`
- **Query**: `organization.samlIdentityProvider.externalIdentities`
- **Authentication**: GitHub CLI (Personal Access Token or GitHub App)
- **Required Scopes**: `read:org` or `admin:org`
- **Documentation**: 
  - [GraphQL API Overview](https://docs.github.com/en/graphql)
  - [Organization Object](https://docs.github.com/en/graphql/reference/objects#organization)
  - [SAMLIdentityProvider Object](https://docs.github.com/en/graphql/reference/objects#samlidentityprovider)
- **Purpose**: Fetch users with SAML identities from a GHEC organization
- **Pagination**: Cursor-based with `first` and `after` parameters
- **Requirements**: Organization must have SAML SSO configured

### GHEC Enterprise GraphQL API
- **Endpoint**: `/graphql`
- **Query**: `enterprise.ownerInfo.samlIdentityProvider.externalIdentities`
- **Authentication**: GitHub CLI (Personal Access Token or GitHub App)
- **Required Scopes**: `read:enterprise` or `admin:enterprise`
- **Documentation**:
  - [GraphQL API Overview](https://docs.github.com/en/graphql)
  - [Enterprise Object](https://docs.github.com/en/graphql/reference/objects#enterprise)
  - [EnterpriseOwnerInfo Object](https://docs.github.com/en/graphql/reference/objects#enterpriseownerinfo)
  - [SAMLIdentityProvider Object](https://docs.github.com/en/graphql/reference/objects#samlidentityprovider)
- **Purpose**: Fetch users with SAML identities from a GHEC enterprise
- **Pagination**: Cursor-based with `first` and `after` parameters
- **Requirements**: Enterprise must have SAML SSO configured

### Required Token Scopes Summary

| API | Minimum Scope | Recommended Scope | Notes |
|-----|---------------|-------------------|-------|
| EMU SCIM | `scim:enterprise` | `admin:enterprise` | Required for reading SCIM provisioning data |
| GHEC Org GraphQL | `read:org` | `admin:org` | Required for SAML identity access |
| GHEC Enterprise GraphQL | `read:enterprise` | `admin:enterprise` | Required for enterprise SAML identity access |

### Refreshing Token Scopes

If you need to add the required scopes to your GitHub CLI token:

```bash
# For SCIM enterprise access
gh auth refresh -h github.com -s admin:enterprise

# For organization access
gh auth refresh -h github.com -s read:org

# For all required scopes
gh auth refresh -h github.com -s admin:enterprise,read:org
```

---

## Account Switching

### Why Account Switching?

When comparing EMU and GHEC instances, you often need different GitHub accounts because:
- **EMU accounts** (e.g., `user_emu`) can access the EMU SCIM API
- **Non-EMU accounts** (e.g., `user`) can access GHEC enterprise GraphQL API
- EMU accounts typically have restricted GraphQL access to non-EMU resources

### Setup

**1. Authenticate both accounts:**
```bash
# Authenticate EMU account
gh auth login
# Follow prompts, authenticate as your_emu_account

# Authenticate non-EMU account (don't logout!)
gh auth login
# Follow prompts, authenticate as your_regular_account

# Verify both accounts are authenticated
gh auth status
```

You should see both accounts listed:
```
✓ Logged in to github.com account user_emu (keyring)
  - Active account: false
✓ Logged in to github.com account user (keyring)
  - Active account: true
```

**2. Use account switching flags:**
```bash
./compare_emu_ghec_users.sh \
  --emu-enterprise my-emu \
  --emu-account user_emu \
  --ghec-enterprise my-ghec \
  --ghec-account user
```

### How It Works

1. **Validates** both accounts are authenticated before starting
2. **Tracks** your current active account
3. **Switches** to EMU account when fetching EMU users
4. **Switches** to GHEC account when fetching GHEC users  
5. **Restores** your original account when complete (even on errors/Ctrl+C)

### Examples

**Compare with organization:**
```bash
./compare_emu_ghec_users.sh \
  --emu-enterprise fabrikam \
  --emu-account samqbush_fabrikam \
  --ghec-org my-org \
  --ghec-account samqbush \
  --csv
```

**Compare with enterprise:**
```bash
./compare_emu_ghec_users.sh \
  --emu-enterprise fabrikam \
  --emu-account samqbush_fabrikam \
  --ghec-enterprise octodemo \
  --ghec-account samqbush \
  --csv --markdown --debug
```

### Important Notes

- Both `--emu-account` and `--ghec-account` must be specified together (or neither)
- Both accounts must be authenticated via `gh auth login` before running
- The script automatically restores your original account when done
- Works with organizations (`--ghec-org`) or enterprises (`--ghec-enterprise`)

---

## Prerequisites

1. **Install GitHub CLI:**
   ```bash
   # macOS
   brew install gh
   
   # Other platforms: https://cli.github.com/
   ```

2. **Install jq:**
   ```bash
   # macOS
   brew install jq
   
   # Linux
   sudo apt-get install jq
   ```

3. **Authenticate:**
   ```bash
   gh auth login
   # Follow the prompts to authenticate with GitHub
   ```

## Basic Usage

### Simple Comparison with GHEC Organization

Compare users between an EMU enterprise and a GHEC organization:

```bash
./compare_emu_ghec_users.sh \
  --emu-enterprise my-emu-enterprise \
  --ghec-org my-ghec-org
```

**Output:**
- `compare_users_TIMESTAMP/comparison_results.json`
- `compare_users_TIMESTAMP/summary_report.md`

### Simple Comparison with GHEC Enterprise

Compare users between an EMU enterprise and a GHEC enterprise:

```bash
./compare_emu_ghec_users.sh \
  --emu-enterprise my-emu-enterprise \
  --ghec-enterprise my-ghec-enterprise
```

**Output:**
- `compare_users_TIMESTAMP/comparison_results.json`
- `compare_users_TIMESTAMP/summary_report.md`

**Note:** Use `--ghec-enterprise` when comparing with an entire GHEC enterprise, not just a single organization.

### With Account Switching

When you need different accounts for EMU and GHEC access:

```bash
./compare_emu_ghec_users.sh \
  --emu-enterprise fabrikam \
  --emu-account samqbush_fabrikam \
  --ghec-enterprise octodemo \
  --ghec-account samqbush \
  --csv
```

See [Account Switching](#account-switching) section for detailed setup instructions.

### With All Output Formats

Generate JSON, CSV, and Markdown reports (works with both `--ghec-org` and `--ghec-enterprise`):

```bash
# With organization
./compare_emu_ghec_users.sh \
  --emu-enterprise my-emu-enterprise \
  --ghec-org my-ghec-org \
  --csv

# With enterprise
./compare_emu_ghec_users.sh \
  --emu-enterprise my-emu-enterprise \
  --ghec-enterprise my-ghec-enterprise \
  --csv
```

**Output:**
- `comparison_results.json` - Full comparison data
- `summary_report.md` - Human-readable summary
- `users_in_both.csv` - Users in both systems
- `users_only_in_emu.csv` - Users only in EMU
- `users_only_in_ghec.csv` - Users only in GHEC

### Custom Output Directory

Specify a custom output directory with date:

```bash
./compare_emu_ghec_users.sh \
  --emu-enterprise my-emu-enterprise \
  --ghec-org my-ghec-org \
  --out user_audit_$(date +%Y%m%d) \
  --csv --markdown
```

### Debug Mode

Enable verbose output for troubleshooting (especially useful with enterprise names containing spaces):

```bash
./compare_emu_ghec_users.sh \
  --emu-enterprise "My EMU Enterprise" \
  --ghec-enterprise "My GHEC Enterprise" \
  --debug \
  --keep-tmp
```

**Debug features:**
- Verbose logging of API calls
- URL encoding details (for names with spaces/special characters)
- API endpoint information
- Pagination details
- Temporary files preserved in `tmp/` directory

## Common Use Cases

### 1. Identify Users Missing from GHEC

Find EMU users who need to be provisioned to GHEC:

```bash
./compare_emu_ghec_users.sh \
  --emu-enterprise my-emu \
  --ghec-org my-org \
  --csv

# Review the output file
cat compare_users_*/users_only_in_emu.csv
```

### 2. Find External Collaborators in GHEC

Identify users in GHEC who are not in EMU (may be external):

```bash
./compare_emu_ghec_users.sh \
  --emu-enterprise my-emu \
  --ghec-org my-org \
  --csv

# Review the output file
cat compare_users_*/users_only_in_ghec.csv
```

### 3. Regular Audit Report

Schedule monthly user audits:

```bash
#!/usr/bin/env bash
# monthly_user_audit.sh

OUTPUT_DIR="user_audit_$(date +%Y%m)"

./compare_emu_ghec_users.sh \
  --emu-enterprise my-emu-enterprise \
  --ghec-org my-ghec-org \
  --out "$OUTPUT_DIR" \
  --csv --markdown

echo "Audit complete! Report: $OUTPUT_DIR/summary_report.md"
```

### 4. Rate-Limited Execution

For very large organizations, add delays between API calls:

```bash
./compare_emu_ghec_users.sh \
  --emu-enterprise large-enterprise \
  --ghec-org large-org \
  --sleep-ms 500 \
  --csv
```

## Understanding the Output

### Summary Report (Markdown)

The `summary_report.md` includes:

- **Summary Table**: Total counts and match statistics
- **Match Rates**: Percentage of users in both systems
- **User Lists**: Sample of users in each category (first 10)
- **Recommendations**: Action items based on findings

### JSON Report

The `comparison_results.json` contains:

```json
{
  "summary": {
    "emu_total": 150,
    "ghec_total": 145,
    "in_both_count": 140,
    "only_in_emu_count": 10,
    "only_in_ghec_count": 5,
    "timestamp": "2025-09-30 14:30:00"
  },
  "comparison": {
    "in_both": [...],
    "only_in_emu": [...],
    "only_in_ghec": [...]
  }
}
```

### CSV Files

Three CSV files are generated when `--csv` is used:

1. **`users_in_both.csv`**
   - Columns: Email, EMU Username, GHEC Username, EMU Display Name
   - Shows users successfully matched between systems

2. **`users_only_in_emu.csv`**
   - Columns: Email, Username, Display Name, Active
   - Shows users who need GHEC provisioning

3. **`users_only_in_ghec.csv`**
   - Columns: Email, Username
   - Shows potential external collaborators

## Troubleshooting

### Authentication Errors

```
[ERROR] GitHub CLI is not authenticated.
```

**Solution:**
```bash
gh auth login
# Follow prompts to authenticate
```

### Missing Token Scopes

If you get permission errors, you may need to refresh your token with the required scopes:

```bash
# Add SCIM enterprise scope
gh auth refresh -h github.com -s admin:enterprise

# Add organization read scope
gh auth refresh -h github.com -s read:org

# Add all at once
gh auth refresh -h github.com -s admin:enterprise,read:org
```

**Verify your token scopes:**
```bash
gh auth status
```

### SCIM API Access

```
[ERROR] Failed to fetch EMU users: ...
```

**Check permissions:**
```bash
# List enterprises you have access to
gh api /user/enterprises

# Test SCIM access (replace with your enterprise slug)
gh api -H 'Accept: application/scim+json' \
  '/scim/v2/enterprises/YOUR-EMU/Users?startIndex=1&count=1'
```

**Required Scopes:** `admin:enterprise` or `scim:enterprise`

**Common Issues:**
- Enterprise slug is incorrect (check with `gh api /user/enterprises`)
- Enterprise name has spaces (script handles this, but verify the slug)
- Missing SCIM provisioning permissions
- SCIM provisioning not enabled on the enterprise

### SAML Not Configured

```
[ERROR] Organization 'my-org' does not have SAML identity provider configured
```

**Solution:** This script requires SAML SSO to be enabled on the GHEC organization or enterprise. 

- **For Organizations**: Configure SAML in organization settings
- **For Enterprises**: Configure SAML SSO at the enterprise level

**Documentation:**
- [Configuring SAML SSO for Organizations](https://docs.github.com/en/enterprise-cloud@latest/organizations/managing-saml-single-sign-on-for-your-organization)
- [Configuring SAML SSO for Enterprises](https://docs.github.com/en/enterprise-cloud@latest/admin/identity-and-access-management/using-saml-for-enterprise-iam)

### GraphQL Access Issues

```
[ERROR] Failed to fetch GHEC users: ...
```

**Check organization access:**
```bash
# Test GraphQL access for organization
gh api graphql -f query='{ organization(login: "YOUR-ORG") { login } }'

# Check SAML identity provider
gh api graphql -f query='{ 
  organization(login: "YOUR-ORG") { 
    samlIdentityProvider { 
      id 
    } 
  } 
}'
```

**Check enterprise access:**
```bash
# Test GraphQL access for enterprise
gh api graphql -f query='{ enterprise(slug: "YOUR-ENTERPRISE") { name } }'

# Check SAML identity provider
gh api graphql -f query='{ 
  enterprise(slug: "YOUR-ENTERPRISE") { 
    ownerInfo { 
      samlIdentityProvider { 
        id 
      } 
    } 
  } 
}'
```

**Required Scopes:**
- Organization: `read:org` or `admin:org`
- Enterprise: `read:enterprise` or `admin:enterprise`

## Integration Examples

### Use with jq for Filtering

Extract specific user information:

```bash
# Get email addresses of users only in EMU
jq -r '.comparison.only_in_emu[].email' compare_users_*/comparison_results.json

# Count users by category
jq '.summary | {emu_total, ghec_total, in_both_count}' compare_users_*/comparison_results.json
```

### Import CSV to Spreadsheet

```bash
# Open in Excel/Numbers/Google Sheets
open compare_users_*/users_only_in_emu.csv
```

### Script Automation

```bash
#!/usr/bin/env bash
# automated_user_sync.sh

# Run comparison
./compare_emu_ghec_users.sh \
  --emu-enterprise prod-emu \
  --ghec-org prod-org \
  --out latest_comparison \
  --json

# Check for users needing provisioning
MISSING_COUNT=$(jq '.summary.only_in_emu_count' latest_comparison/comparison_results.json)

if [ "$MISSING_COUNT" -gt 0 ]; then
  echo "⚠️  $MISSING_COUNT users need GHEC provisioning"
  # Send notification, create ticket, etc.
fi
```

## API Rate Limits

Both APIs used by this script have rate limits:

### REST API (SCIM)
- **Rate Limit**: 5,000 requests per hour (for authenticated requests)
- **Script Impact**: Each page of 100 users = 1 request
- **For 1,000 users**: ~10 requests
- **Documentation**: [REST API Rate Limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)

### GraphQL API
- **Rate Limit**: 5,000 points per hour
- **Script Impact**: Each query costs ~1 point per 100 users returned
- **For 1,000 users**: ~10 points
- **Documentation**: [GraphQL Rate Limits](https://docs.github.com/en/graphql/overview/rate-limits-and-node-limits-for-the-graphql-api)

**Mitigation:**
The script includes a configurable delay between API calls:
```bash
./compare_emu_ghec_users.sh \
  --emu-enterprise my-emu \
  --ghec-org my-org \
  --sleep-ms 500  # 500ms delay between calls
```

## Tips & Best Practices

1. **Run Regularly**: Schedule weekly or monthly comparisons to catch provisioning drift
2. **Review Gaps**: Investigate users in only one system - may indicate:
   - Delayed provisioning
   - Deprovisioned users
   - External collaborators
   - Service accounts
3. **Use Account Switching**: If accessing EMU and non-EMU resources, use `--emu-account` and `--ghec-account` flags
4. **Combine with Other Scripts**: Use alongside `compare_ghe_copilot_licenses.sh` for complete user/license audits
5. **Archive Results**: Keep historical comparisons to track changes over time
6. **Enterprise vs Organization**: Use `--ghec-enterprise` when you need to compare with an entire enterprise's SAML users, not just a single organization
7. **Debug Mode**: Use `--debug --keep-tmp` flags when troubleshooting issues
8. **Rate Limiting**: For very large datasets, use `--sleep-ms 500` to avoid rate limits

## Common Issues & Solutions

### Issue: EMU account can't access GHEC enterprise

**Problem:** When authenticated as an EMU account, GraphQL queries to non-EMU enterprises return `null`.

**Solution:** Use account switching with separate EMU and non-EMU accounts:
```bash
./compare_emu_ghec_users.sh \
  --emu-enterprise my-emu \
  --emu-account user_emu \
  --ghec-enterprise my-ghec \
  --ghec-account user_regular
```

### Issue: SAML not configured error

**Problem:** Script reports that SAML identity provider is not configured.

**Solution:** This script requires SAML SSO to be enabled. Without SAML, the script cannot fetch user email addresses for matching. Verify SAML is configured on your GHEC organization or enterprise.

### Issue: GitHub CLI not found

**Problem:** Script reports `gh is required but not installed` even though it's installed.

**Solution:** The script checks common installation paths. If `gh` is in a non-standard location, add it to your PATH or create a symlink to a standard location like `/usr/local/bin/gh`.

### Issue: Account switching fails

**Problem:** Script fails to switch accounts during execution.

**Solution:** Ensure both accounts are authenticated:
```bash
gh auth status  # Check which accounts are authenticated
gh auth login   # Authenticate missing accounts
```

## Version History

### v1.1.0 (September 30, 2025)
- ✅ Added automatic account switching with `--emu-account` and `--ghec-account` flags
- ✅ Added support for GHEC enterprises (not just organizations)
- ✅ Improved error messages with troubleshooting guidance
- ✅ Fixed `gh` CLI detection in non-standard PATH locations
- ✅ Added URL encoding for enterprise names with spaces
- ✅ Added trap handlers to restore accounts on error/interrupt

### v1.0.0 (September 30, 2025)
- Initial release
- EMU SCIM API support
- GHEC organization GraphQL API support
- JSON, CSV, and Markdown output formats

## Support & Contributing

For issues, questions, or contributions:
- Review error messages - they include specific troubleshooting commands
- Use `--debug --keep-tmp` to generate detailed logs
- Check `gh auth status` to verify authentication
- Test API access manually with the commands provided in error messages

---

## Full Command Reference

```bash
./compare_emu_ghec_users.sh [OPTIONS]

REQUIRED:
  --emu-enterprise SLUG       EMU enterprise slug/name
  --ghec-org ORG              GHEC organization name (use with org)
    OR
  --ghec-enterprise SLUG      GHEC enterprise slug (use with enterprise)

ACCOUNT SWITCHING (optional):
  --emu-account USERNAME      Account for EMU access (requires --ghec-account)
  --ghec-account USERNAME     Account for GHEC access (requires --emu-account)

OUTPUT OPTIONS:
  --out DIRECTORY             Output directory (default: compare_users_TIMESTAMP)
  --markdown                  Generate Markdown report (default: true)
  --json                      Generate JSON reports (default: true)
  --csv                       Generate CSV files

ADVANCED OPTIONS:
  --sleep-ms MS               Sleep between API calls in ms (default: 100)
  --keep-tmp                  Keep temporary files for debugging
  --debug                     Enable verbose debug output
  --help, -h                  Show help message
```

## Getting Help

```bash
# Show full help
./compare_emu_ghec_users.sh --help

# Enable debug mode for troubleshooting
./compare_emu_ghec_users.sh \
  --emu-enterprise my-emu \
  --ghec-org my-org \
  --debug --keep-tmp
```

For issues or questions, review the script's error messages - they include specific guidance and troubleshooting commands for common problems.
