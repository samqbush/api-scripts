# API Scripts

All scripts were generated with the assistance of GitHub Copilot.

> **NOTE:**
> It is highly recommended to use the [GitHub CLI](https://cli.github.com/) for interacting with the API. The Python scripts provided here are primarily to illustrate the complexity differences between using the CLI and writing custom scripts.

## [Copilot](./copilot/)

- [inactive_copilot](./copilot/inactive_copilot.sh) - outputs Copilot users that have been active & inactive within 90 days
- [user level engagement metrics](./copilot/copilot_ule.sh) - outputs a summary of user level engagement metrics using the private preview api

## [Disaster Recovery](./disaster_recovery/)

- [owner_dr](./disaster_recovery/owner_dr.sh) - create text list backups of organization owners in an enterprise and allows an enterprise admin to restore these permissions

## [GHAS](./ghas/)

- [ignore_secrets](./ghas/ignore_secrets.sh) - fetches secret scanning alerts from a GitHub repository and filters them based on commit dates to identify when secrets were first introduced to the codebase and resolves them as false_positives

## [Repository Data Collection](./repo_data/)

- [get_commits](./repo_data/get_commits.sh) - gathers the number of commits to repositories across an organization over the last 3 months

## [Teams](./teams/)

- [list_teams](./teams/list_teams.sh) - lists teams in an organization with more than 5 members to show what teams are eligible for Copilot team metrics
