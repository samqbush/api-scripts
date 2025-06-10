# GitHub API Scripts

All scripts were generated with the assistance of GitHub Copilot.

## Script Types & Usage Philosophy

> **Bash First:** These scripts prioritize Bash whenever possible for simplicity and portability. Python is only used when advanced data processing (pandas, numpy) or complex analysis is required.

> **GitHub CLI Recommended:** For most GitHub API interactions, consider using the [GitHub CLI](https://cli.github.com/) instead of custom scripts. The scripts here demonstrate API usage patterns and handle specific use cases not covered by the CLI.

## 📊 [Copilot Analytics](./copilot/)

### Bash Scripts (Recommended)
- [`inactive_copilot.sh`](./copilot/inactive_copilot.sh) - Identifies Copilot users active and inactive within 90 days
- [`copilot_ule.sh`](./copilot/copilot_ule.sh) - Generates user-level engagement metrics using the private preview API

### Python Scripts (Advanced Analysis)
- [`copilot_dda_complete.py`](./copilot/copilot_dda_complete.py) - Complete Direct Data Access analysis with visualizations and comprehensive reporting (requires pandas, matplotlib, seaborn)
- [`data_explorer.py`](./copilot/data_explorer.py) - Interactive tool for exploring Copilot usage data

## 🔄 [Disaster Recovery](./disaster_recovery/)

- [`owner_dr.sh`](./disaster_recovery/owner_dr.sh) - Creates text-based backups of organization owners in an enterprise and allows restoration of these permissions

## 🔒 [GitHub Advanced Security (GHAS)](./ghas/)

- [`ignore_secrets.sh`](./ghas/ignore_secrets.sh) - Fetches secret scanning alerts, filters by commit dates to identify when secrets were introduced, and resolves them as false positives

## 📈 [Repository Data Collection](./repo_data/)

### Bash Scripts (Recommended)
- [`get_commits.sh`](./repo_data/get_commits.sh) - Gathers commit counts for repositories across an organization over the last 3 months
- [`github_emu_report.sh`](./repo_data/github_emu_report.sh) - Generates EMU (Enterprise Managed User) reports

### Python Scripts (Data Processing)
- [`get_commits.py`](./repo_data/get_commits.py) - Advanced commit analysis with data processing capabilities

## 👥 [Teams Management](./teams/)

- [`list_teams.sh`](./teams/list_teams.sh) - Lists teams in an organization with more than 5 members (useful for identifying teams eligible for Copilot team metrics)

## Prerequisites

### All Scripts
- GitHub CLI installed and authenticated (`gh auth login`)
- `GITHUB_TOKEN` environment variable set with appropriate scopes

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

   # Python script example  
   python copilot/copilot_dda_complete.py your-enterprise --since 2025-06-01
   ```

## Development Notes

- **Bash Compatibility:** Scripts use `#!/usr/bin/env bash` shebang for portability
- **Shell Version:** Compatible with Bash < 4.0 (no associative arrays)
- **Error Handling:** All scripts include comprehensive error checking and usage documentation
- **Output:** Most scripts provide both human-readable output and CSV/JSON for further processing
