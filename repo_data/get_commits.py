# Add the following permissions to the GitHub fine-grained token:

# Repository Permissions:
    # Contents: Read-only
    # Metadata: Read-only
    # Commit statuses: Read-only
# Organization Permissions:
    # Email addresses: Read-only (if you need to access organization member information)

# Make sure to: pip install requests
import requests
from datetime import datetime, timedelta
import os
import logging

# Configure logger
logging.basicConfig(level=logging.ERROR)
logger = logging.getLogger(__name__)

# GitHub organization and token
organization = "octodemo"
token = os.getenv("GITHUB_TOKEN")
if not token:
    logger.error("GITHUB_TOKEN environment variable not set")
    raise EnvironmentError("GITHUB_TOKEN environment variable not set")

# Calculate date three months ago
three_months_ago = datetime.utcnow() - timedelta(days=90)
since_date = three_months_ago.isoformat() + "Z"

# Headers for authentication
headers = {
    "Authorization": f"token {token}",
    "Accept": "application/vnd.github.v3+json"
}

# Get list of repositories in the organization
repos_url = f"https://api.github.com/orgs/{organization}/repos"
repos_response = requests.get(repos_url, headers=headers)
repos = repos_response.json()

# Iterate over repositories and get the number of commits in the last 3 months
for repo in repos:
    repo_name = repo["name"]
    commits_url = f"https://api.github.com/repos/{organization}/{repo_name}/commits"
    commits_params = {"since": since_date}
    commits_response = requests.get(commits_url, headers=headers, params=commits_params)
    commits = commits_response.json()
    num_commits = len(commits)
    print(f"Repository: {repo_name}, Commits in last 3 months: {num_commits}")