# API Scripts

All scripts were generated with the assistance of GitHub Copilot.

> **NOTE:**
> It is highly recommended to use the [GitHub CLI](https://cli.github.com/) for interacting with the API. The Python scripts provided here are primarily to illustrate the complexity differences between using the CLI and writing custom scripts.

## [Copilot](./copilot/)

- [inactive-copilot](./copilot/inactive-copilot.sh) - outputs Copilot users that have been active & inactive within 90 days

## [Repository Data Collection](./repo_data/)

- [get_commits](./repo_data/get_commits.py) - gathers the number of commits to repositories across an organization over the last 3 months

## [Disaster Recovery](./disaster-recovery/)

- [owner-dr](./disaster-recovery/owner-dr.sh) - create text list backups of organization owners in an enterprise and allows an enterprise admin to restore these permissions

## [Teams](./teams/)

- [list-teams](./teams/list-teams.sh) - lists teams in an organization with more than 5 members to show what teams are eligible for Copilot team metrics
