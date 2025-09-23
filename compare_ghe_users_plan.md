# GitHub Enterprise License Comparison Script – Plan

## 1. Goal
Create a script to compare GitHub Enterprise Managed User (EMU) licenses with GitHub Copilot licenses within the same enterprise, identifying:
- EMU users with enterprise licenses but no Copilot license
- Users with Copilot licenses but no enterprise seat (edge case)
- Users with both enterprise and Copilot licenses
- License utilization and gap analysis for cost optimization

## 2. Primary Use Cases
1. License audit - identify who has GHE seats but no Copilot license
2. Cost optimization - understand license utilization gaps
3. Deployment planning - target users for Copilot license provisioning
4. Compliance reporting - enterprise license vs feature license alignment
5. Budget planning - forecast Copilot licensing needs based on EMU population

## 3. Assumptions (To Confirm)
- You have a GitHub token with necessary scopes for enterprise billing and member access:
  - Classic PAT: `admin:enterprise`, `manage_billing:copilot`, `read:org`, `read:user`
  - Or Fine-grained PAT with enterprise permissions for Members and Billing
- Single GitHub Enterprise environment (GHEC EMU or GHES with Copilot enabled)
- Enterprise slug/name available for API calls
- `jq` and `curl` available (Bash preferred per repo guidelines)
- Pagination required (GitHub default 30; we'll request 100 per page)
- Rate limits acceptable for periodic license auditing
- Comparison attributes: `login`, `id`, `name`, `email`, `created_at`, `last_activity_at`
- Output directory configurable (default: `license_compare/`)
- Leverages existing patterns from `inactive_copilot.sh` and `github_emu_report.sh`

## 4. Tooling Choice
**Bash + curl + jq** (Phase 1) — simple, aligns with existing repo scripts like `inactive_copilot.sh` and `github_emu_report.sh`. 
Python fallback reserved for advanced analytics if needed in future phases.

Artifacts to implement: `compare_ghe_copilot_licenses.sh` (core script).

## 5. High-Level Flow
1. Parse inputs (enterprise name, flags/env vars)
2. Validate prerequisites (tools + tokens + enterprise access)
3. Fetch EMU users from enterprise → normalize → `emu_users.json`
4. Fetch Copilot billing seats → normalize → `copilot_users.json`
5. Build maps keyed by `login` for both datasets
6. Compute license gaps:
   - `emu_only`: Users with enterprise licenses but no Copilot
   - `copilot_only`: Users with Copilot but no enterprise seat (rare)
   - `both_licenses`: Users with both licenses
7. Generate reports (JSON, CSV, Markdown summary)
8. Optional: non-zero exit if license gaps found (`--fail-on-gaps`)

## 6. Inputs
Environment Variables:
- `GITHUB_TOKEN` - Token with enterprise and billing access
- `ENTERPRISE_SLUG` - GitHub Enterprise slug (e.g., "octodemo")
- `OUT_DIR` (default `license_compare`)
- `DEBUG` (verbose logging)

CLI Flags:
```bash
./compare_ghe_copilot_licenses.sh \
  --enterprise octodemo \
  --token env:GITHUB_TOKEN \
  --out license_analysis_20250922 \
  --markdown --json --csv \
  --fail-on-gaps \
  --min-gap-threshold 10
```

Token Spec Formats:
- Raw string (not recommended)
- `env:VAR_NAME` (recommended - look up environment variable)
- `file:@/path/to/token` (future convenience)

## 7. Endpoints
Primary APIs:
- `GET /enterprises/{enterprise}/members?per_page=100&page=N` (EMU users with enterprise seats)
- `GET /enterprises/{enterprise}/copilot/billing/seats?per_page=100&page=N` (Copilot license holders)
- `GET /users/{username}` for user detail enrichment (optional)

Alternative/Fallback:
- `GET /orgs/{org}/members?per_page=100&page=N` (if enterprise-wide access unavailable)
- Combined with org list iteration similar to existing `github_emu_report.sh` pattern

## 8. Data Collection Strategy
For EMU users:
1. Paginate through `/enterprises/{enterprise}/members` to collect all enterprise users
2. Extract core user attributes: `login`, `id`, `name`, `created_at`
3. Optionally enrich with user details via `/users/{username}` for email, company, etc.
4. Normalize and cache as `emu_users.json`

For Copilot users:
1. Paginate through `/enterprises/{enterprise}/copilot/billing/seats` 
2. Extract user information from seat assignments
3. Include Copilot-specific data: `created_at`, `last_activity_at` 
4. Leverage existing patterns from `inactive_copilot.sh`
5. Normalize and cache as `copilot_users.json`

Caching Layout:
```
$OUT_DIR/tmp/
  emu_members_page1.json
  emu_members_page2.json
  copilot_seats_page1.json
  copilot_seats_page2.json
  emu_users.json (normalized)
  copilot_users.json (normalized)
```

## 9. Normalization Rules
EMU User Schema:
```json
{
  "login": "alice_corp",
  "id": 12345,
  "name": "Alice Smith",
  "email": "alice@corp.example",
  "created_at": "2023-01-15T12:34:56Z",
  "license_type": "enterprise"
}
```

Copilot User Schema:
```json
{
  "login": "alice_corp", 
  "id": 12345,
  "name": "Alice Smith",
  "created_at": "2023-03-01T08:15:30Z",
  "last_activity_at": "2025-09-20T14:22:00Z",
  "license_type": "copilot"
}
```

Missing fields → `null`. Sort final arrays by `login` for determinism.

## 10. License Gap Analysis Logic
Using `jq`:
- Build lookup objects: `{login: userObject}` for EMU and Copilot datasets
- `emu_only`: logins in EMU but not in Copilot (primary target group)
- `copilot_only`: logins in Copilot but not in EMU (edge case - orphaned licenses)
- `both_licenses`: logins present in both datasets with matching details
- `license_mismatches`: users in both but with conflicting attributes

Primary Output - EMU users without Copilot:
```json
{
  "login": "alice_corp",
  "emu_details": { "name": "Alice Smith", "created_at": "2023-01-15T12:34:56Z" },
  "gap_type": "missing_copilot",
  "recommendation": "candidate_for_copilot_license"
}
```

## 11. Outputs
Directory layout:
```
out/
  emu_users.json              # All EMU users with enterprise licenses
  copilot_users.json          # All users with Copilot licenses  
  license_gaps_emu_only.json  # EMU users missing Copilot (main target)
  license_gaps_copilot_only.json # Copilot users missing EMU (cleanup candidates)
  license_overlaps_both.json  # Users with both licenses
  summary.json               # License utilization summary with counts
  summary.csv                # CSV export for spreadsheet analysis
  summary.md                 # Human-readable report
  request.log               # API request log
  errors.log                # Any API errors
```

Markdown Summary Sections:
- Header (timestamp, enterprise, command)
- License utilization overview table
- EMU users without Copilot (top 20 + count)
- Recommendations for license provisioning
- Cost impact analysis

CSV Format:
```
category,login,name,emu_created_at,copilot_created_at,recommendation
emu_only,alice_corp,Alice Smith,2023-01-15T12:34:56Z,,candidate_for_copilot
both,bob_corp,Bob Jones,2023-01-10T09:15:00Z,2023-03-01T11:30:00Z,properly_licensed
copilot_only,charlie_external,Charlie Brown,,2023-02-01T16:45:00Z,review_license_assignment
```

## 12. Script Structure
Functions:
- `usage()`
- `error()` / `log()` / `debug()`
- `require_tools()` (checks `curl`, `jq`, `gh` optional)
- `parse_args()`
- `resolve_token_spec()`
- `fetch_enterprise_members()` (paginated EMU user collection)
- `fetch_copilot_seats()` (paginated Copilot billing collection, reuse from `inactive_copilot.sh`)
- `normalize_emu_user()` (jq filter)
- `normalize_copilot_user()` (jq filter) 
- `build_license_datasets()`
- `perform_license_gap_analysis()`
- `emit_reports()`

Conventions:
- EMU prefix for enterprise users, COPILOT prefix for Copilot users
- Temporary artifacts in `$OUT_DIR/tmp` (unless `--keep-tmp`)
- Leverage existing patterns from `inactive_copilot.sh` for Copilot API interaction

## 13. Performance Considerations
- Sequential API calls acceptable for typical enterprise sizes (<10k users)
- Copilot billing API typically has smaller dataset than enterprise members
- Future: `--parallel N` for concurrent user detail fetching if needed
- Simple throttle: sleep (configurable via `--sleep-ms` / default 100ms)
- Leverage existing caching from `inactive_copilot.sh` patterns
- Consider rate limits: Copilot billing API may have different limits than standard REST API

## 14. Error Handling
- Missing enterprise access → usage + exit code 2
- HTTP non-200: log to `errors.log`, continue (skip that user/page)
- Rate limit (403 + remaining=0): optionally abort with explanation
- Missing billing access: clear error message about required `manage_billing:copilot` scope
- Empty datasets: warn if either EMU or Copilot returns 0 users
- Partial failures surfaced in summary with counts of successful/failed API calls

## 15. Logging
- `request.log`: `TIMESTAMP ENDPOINT METHOD URL STATUS DURATION`
- Debug flag prints each curl command without tokens
- No tokens written to logs
- License gap analysis results logged with counts
- Summary of API calls made and success/failure rates

## 16. Security
- **Recommend environment variables** (`export GITHUB_TOKEN=token`) over command line parameters
- **Security Warning**: Command line tokens are visible in process lists and shell history
- Redact `Authorization` header in debug output
- Support GitHub CLI token resolution (`gh auth token`) as fallback
- Avoid storing full raw responses unless `--cache-api-responses` specified
- Clear documentation of required token scopes for enterprise and billing access

## 17. Edge Cases
- Private enterprise members (requires proper enterprise access) — documented
- Suspended EMU users (may appear in members but be inactive) — flagged in output
- Recently assigned/removed Copilot licenses (timing differences) — documented in summary
- Enterprise users with external collaborator access vs full seats — differentiated if API provides
- Copilot licenses assigned to users outside the EMU (external collaborators) — flagged as `copilot_only`
- Empty enterprise or no Copilot licenses — clear reporting with 0 counts
- API pagination edge cases — robust page handling and continuation

## 18. Extensibility Backlog
- SCIM integration for richer user attributes (department, manager, active status)
- GraphQL batching for efficient user detail collection
- License cost analysis (pricing per license type)
- Historical tracking (compare current state vs previous runs)
- Automated license provisioning recommendations
- Integration with identity provider data
- Team membership analysis (which teams have low Copilot adoption)
- Usage analytics correlation (identify high-value Copilot candidates)
- Slack/Teams webhook notifications for license gaps
- Dashboard output (HTML report with charts)

## 19. Minimal Success Criteria (Phase 1)
- Command runs with enterprise slug and valid token
- Produces EMU users list and Copilot users list
- Identifies users with enterprise licenses but no Copilot license (primary goal)
- Generates deterministic JSON + Markdown reports  
- Handles ≥1000 EMU users and ≥500 Copilot users without error
- Proper exit codes (0 = success; non-zero when `--fail-on-gaps` and gaps exist)
- Reuses proven patterns from existing `inactive_copilot.sh` and `github_emu_report.sh`

## 20. Example Command
```bash
# Using environment variable for token (recommended secure approach)
export GITHUB_TOKEN=ghp_xxxxxxxxxxxx
./compare_ghe_copilot_licenses.sh \
  --enterprise octodemo \
  --out license_audit_20250922 \
  --markdown --json --csv \
  --fail-on-gaps

# Alternative with explicit token reference (if token stored in different variable)
export MY_GH_TOKEN=ghp_xxxxxxxxxxxx
./compare_ghe_copilot_licenses.sh \
  --enterprise octodemo \
  --token env:MY_GH_TOKEN \
  --out license_audit_20250922 \
  --min-gap-threshold 5 \
  --markdown --json --csv
```

## 21. Acceptance Checklist
- [ ] Usage documented & discoverable via `-h` / `--help`
- [ ] Token prerequisites validated early (enterprise + billing access)
- [ ] Deterministic sorted outputs  
- [ ] No secrets logged
- [ ] JSON schema stable & documented
- [ ] Clear exit behavior documented
- [ ] Integration with existing script patterns (`inactive_copilot.sh`, `github_emu_report.sh`)
- [ ] License gap identification working correctly
- [ ] CSV output compatible with spreadsheet tools

## 22. Key Questions & Considerations
1. **Enterprise Access**: Do you have `admin:enterprise` scope in your GitHub token for accessing enterprise members?
2. **Billing Access**: Do you have `manage_billing:copilot` scope for accessing Copilot billing seats?
3. **Enterprise Slug**: What is your GitHub Enterprise slug/name for the API calls?
4. **Output Focus**: Primary need is EMU users without Copilot licenses (for provisioning planning)?
5. **Reporting Format**: Preference for CSV (spreadsheet analysis) vs JSON (further automation)?
6. **Update Frequency**: One-time audit or recurring license monitoring?
7. **Integration**: Need to integrate with existing license management workflows?

## 23. Timeline (If Implemented Now)
**Phase 1 (Core Implementation)**:
1. License data collection (EMU + Copilot) - reusing existing patterns
2. Gap analysis logic and reporting
3. CSV/JSON/Markdown output generation

**Phase 2 (Enhancements)**:
1. User detail enrichment and advanced filtering
2. Cost analysis and recommendations  
3. Historical tracking and trend analysis

---

### Next Steps
1. **Confirm Requirements**: Validate the assumptions and key questions above
2. **Verify Token Scopes**: Ensure your GitHub token has both enterprise and billing access
3. **Test Enterprise Access**: Verify you can access both `/enterprises/{enterprise}/members` and `/enterprises/{enterprise}/copilot/billing/seats`
4. **Implement Script**: Create `compare_ghe_copilot_licenses.sh` following this plan

**Priority**: This addresses your immediate need to identify EMU users who should get Copilot licenses, which is a common enterprise license optimization scenario.

---

## 24. API Response Examples (For Reference)

### Enterprise Members Response
```json
[
  {
    "login": "alice_corp",
    "id": 12345,
    "node_id": "MDQ6VXNlcjEyMzQ1",
    "avatar_url": "https://github.com/images/error/alice_corp",
    "gravatar_id": "",
    "url": "https://api.github.com/users/alice_corp",
    "html_url": "https://github.com/alice_corp",
    "type": "User",
    "site_admin": false
  }
]
```

### Copilot Billing Seats Response  
```json
{
  "total_seats": 12,
  "seats": [
    {
      "created_at": "2025-03-01T08:15:30Z",
      "updated_at": "2025-09-20T14:22:00Z", 
      "pending_cancellation_date": null,
      "last_activity_at": "2025-09-20T14:22:00Z",
      "last_activity_editor": "vscode",
      "assignee": {
        "login": "alice_corp",
        "id": 12345,
        "node_id": "MDQ6VXNlcjEyMzQ1",
        "avatar_url": "https://github.com/images/error/alice_corp",
        "gravatar_id": "",
        "url": "https://api.github.com/users/alice_corp",
        "html_url": "https://github.com/alice_corp",
        "type": "User",
        "site_admin": false
      }
    }
  ]
}
```

These API responses inform the normalization logic and data extraction patterns.
