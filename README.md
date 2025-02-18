# api-scripts
All scripts were generated with the assistance of GitHub Copilot.

> **NOTE:** 
> It is highly recommended to use the [GitHub CLI](https://cli.github.com/) for interacting with the API. The Python scripts provided here are primarily to illustrate the complexity differences between using the CLI and writing custom scripts.

## [Repository Data Collection](./repo_data/)
- [get_commits](./repo_data/get_commits.py) - gathers the number of commits to repositories across an organization over the last 3 months

## [Disaster Recovery](./disaster-recovery/)
- [owner-dr](./disaster-recovery/owner-dr.sh) - create text list backups of organization owners in an enterprise and allows an enterprise admin to restore these permissions