import os
import requests
import pandas as pd
from datetime import datetime
import tempfile
import logging
import sys
import traceback

# Configure logging - more verbose for debugging
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Prerequisites:
# - Install pandas: pip install pandas requests
# - Export GITHUB_TOKEN in your environment: export GITHUB_TOKEN=your_token_here

# Get the GitHub token from environment
github_token = os.getenv("GITHUB_TOKEN")
if not github_token:
    logger.error("GITHUB_TOKEN environment variable is not set.")
    sys.exit(1)

# Log that we found the token (without revealing it)
logger.info("GitHub token found in environment.")

# Fetch Copilot Direct Data Access usage data
EMU = "fabrikam"  # Replace with your actual enterprise name
SINCE_DATE = "2025-03-20"  # Replace with a date in the past (not future date)
UNTIL_DATE = "2025-03-31"  # Replace with a date in the past (not future date)

logger.info(f"Enterprise: {EMU}")
logger.info(f"Date range: {SINCE_DATE} to {UNTIL_DATE}")

# Validate the date range does not exceed 14 days
try:
    since_date_epoch = datetime.strptime(SINCE_DATE, "%Y-%m-%d").timestamp()
    until_date_epoch = datetime.strptime(UNTIL_DATE, "%Y-%m-%d").timestamp()

    if since_date_epoch > until_date_epoch:
        logger.error("Error: SINCE_DATE cannot be after UNTIL_DATE. Please adjust the date values.")
        sys.exit(1)
    date_diff = (until_date_epoch - since_date_epoch) / 86400

    if date_diff > 14:
        logger.error("Error: The date range cannot exceed 14 days. Please adjust SINCE_DATE and UNTIL_DATE.")
        sys.exit(1)
        
    logger.info(f"Date range is valid: {date_diff} days")
except ValueError as e:
    logger.error(f"Date parsing error: {e}")
    sys.exit(1)

# Set up headers for the API request
headers = {
    "Accept": "application/vnd.github+json",
    "Authorization": f"token {github_token}",
    "X-GitHub-Api-Version": "2022-11-28"
}

# Construct the URL for the API request
url = f"https://api.github.com/enterprises/{EMU}/copilot/direct-data?since={SINCE_DATE}&until={UNTIL_DATE}"
logger.info(f"API URL: {url}")

# Test the API connection first
try:
    logger.info("Testing GitHub API connection...")
    test_response = requests.get("https://api.github.com/rate_limit", headers=headers, timeout=10)
    test_response.raise_for_status()
    rate_limit_info = test_response.json()
    logger.info(f"GitHub API connection successful. Rate limit: {rate_limit_info.get('resources', {}).get('core', {}).get('remaining', 'unknown')} remaining.")
except requests.exceptions.RequestException as e:
    logger.error(f"GitHub API connection test failed: {e}")
    if hasattr(e, 'response') and e.response is not None:
        logger.error(f"Response status code: {e.response.status_code}")
        logger.error(f"Response text: {e.response.text}")
    sys.exit(1)

# Fetch JSON data using the GitHub API
try:
    logger.info(f"Fetching data from GitHub API for enterprise: {EMU}")
    response = requests.get(url, headers=headers)
    response.raise_for_status()
    json_data = response.json()
    logger.info(f"API response received. Data entries: {len(json_data)}")
except requests.exceptions.HTTPError as http_err:
    logger.error(f"HTTP error occurred: {http_err}")
    if hasattr(http_err, 'response') and http_err.response is not None:
        logger.error(f"Response status code: {http_err.response.status_code}")
        logger.error(f"Response text: {http_err.response.text}")
    sys.exit(1)
except Exception as err:
    logger.error(f"An error occurred: {err}")
    sys.exit(1)

# Process each entry in the JSON data
for entry in json_data:
    date = entry.get("date")
    blob_uris = entry.get("blob_uris", [])

    logger.info(f"Processing data for date: {date}")
    logger.info(f"Found {len(blob_uris)} blob URIs")

    for blob_uri in blob_uris:
        logger.info(f"Fetching data from: {blob_uri}")
        try:
            response = requests.get(blob_uri)
            response.raise_for_status()
            
            logger.info(f"Received blob data ({len(response.content)} bytes)")

            # Read the Parquet file into a Pandas DataFrame
            with tempfile.NamedTemporaryFile(suffix=".parquet") as temp_file:
                temp_file.write(response.content)
                temp_file.flush()
                logger.info(f"Wrote blob data to temporary file: {temp_file.name}")
                
                logger.info("Reading Parquet file with pandas...")
                df = pd.read_parquet(temp_file.name)
                
                logger.info(f"DataFrame shape: {df.shape}")
                logger.info(f"DataFrame columns: {df.columns.tolist()}")

            # Display the DataFrame
            print("\nDataFrame contents:")
            print(df)
            
        except requests.exceptions.HTTPError as http_err:
            logger.error(f"HTTP error occurred while fetching blob: {http_err}")
            if hasattr(http_err, 'response') and http_err.response is not None:
                logger.error(f"Response status code: {http_err.response.status_code}")
                logger.error(f"Response text: {http_err.response.text}")
        except Exception as err:
            logger.error(f"An error occurred while processing blob: {err}")
            logger.error(f"Traceback: {traceback.format_exc()}")

    logger.info("----------------------------------------")

logger.info("Data processing complete.")