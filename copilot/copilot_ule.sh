#!/bin/bash

# Usage:
# ./copilot_ule.sh
# This script outputs a summary of user-level engagement metrics using the private preview API.

# Fetch JSON data using the gh api command
EMU="fabrikam" # Replace with your enterprise name
JSON_DATA=$(gh api "/enterprises/$EMU/copilot/user-engagement")

# Initialize counters for summary
total_users=0
total_code_completion=0
total_panel_chat=0
total_inline_chat=0
total_dotcom_chat=0
total_cli=0
total_kb_chat=0
total_mobile_chat=0
total_pr_summary=0
total_code_review=0

# Count days with data
days_with_data=0

# Create a temporary file to store the JSON entries
TEMP_FILE=$(mktemp)
echo "$JSON_DATA" | jq -c '.[]' > "$TEMP_FILE"

# Loop through each entry in the JSON data
while IFS= read -r entry; do
  # Extract the date
  date=$(echo "$entry" | jq -r '.date')
  
  # Extract the blob_uri (if it exists)
  blob_uri=$(echo "$entry" | jq -r '.blob_uri // empty')
  
  # Print the date
  echo "Date: $date"
  
  # Check if blob_uri exists
  if [ -n "$blob_uri" ]; then
    
    # Use curl to download the blob data directly into a variable
    BLOB_DATA=$(curl -s "$blob_uri")
    
    if [ -n "$BLOB_DATA" ]; then
      # Increment days with data counter
      days_with_data=$((days_with_data + 1))
      
      # Count unique users and engagement metrics directly from memory
      unique_users=$(echo "$BLOB_DATA" | jq -s 'map(.user_id) | unique | length')
      
      # Extract engagement counts
      code_completion=$(echo "$BLOB_DATA" | jq -s 'map(.code_completion_engagement) | add // 0')
      panel_chat=$(echo "$BLOB_DATA" | jq -s 'map(.panel_chat_engagement) | add // 0')
      inline_chat=$(echo "$BLOB_DATA" | jq -s 'map(.inline_chat_engagement) | add // 0')
      dotcom_chat=$(echo "$BLOB_DATA" | jq -s 'map(.dotcom_chat_engagement) | add // 0')
      cli=$(echo "$BLOB_DATA" | jq -s 'map(.cli_engagement) | add // 0')
      kb_chat=$(echo "$BLOB_DATA" | jq -s 'map(.knowledge_base_chat_engagement) | add // 0')
      mobile_chat=$(echo "$BLOB_DATA" | jq -s 'map(.mobile_chat_engagement) | add // 0')
      pr_summary=$(echo "$BLOB_DATA" | jq -s 'map(.pull_request_summary_engagement) | add // 0')
      code_review=$(echo "$BLOB_DATA" | jq -s 'map(.code_review_engagement) | add // 0')
      
      # Add to totals
      total_users=$((total_users + unique_users))
      total_code_completion=$((total_code_completion + code_completion))
      total_panel_chat=$((total_panel_chat + panel_chat))
      total_inline_chat=$((total_inline_chat + inline_chat))
      total_dotcom_chat=$((total_dotcom_chat + dotcom_chat))
      total_cli=$((total_cli + cli))
      total_kb_chat=$((total_kb_chat + kb_chat))
      total_mobile_chat=$((total_mobile_chat + mobile_chat))
      total_pr_summary=$((total_pr_summary + pr_summary))
      total_code_review=$((total_code_review + code_review))
      
      # Display metrics
      echo "  - Unique Users: $unique_users"
      echo "  - Code Completion: $code_completion"
      echo "  - Panel Chat: $panel_chat"
      echo "  - Inline Chat: $inline_chat"
      echo "  - Dotcom Chat: $dotcom_chat"
      echo "  - CLI: $cli"
      echo "  - Knowledge Base Chat: $kb_chat"
      echo "  - Mobile Chat: $mobile_chat"
      echo "  - PR Summary: $pr_summary"
      echo "  - Code Review: $code_review"
      
      # Get the top 5 users by code completion engagement
      echo -e "\nTop 5 Users by Code Completion:"
      echo "$BLOB_DATA" | jq -s 'sort_by(.code_completion_engagement) | reverse | .[0:5] | .[] | "  - " + .login + ": " + (.code_completion_engagement | tostring)'
      
    else
      echo "Failed to download blob data."
    fi
  else
    echo "Blob URI: Not available"
  fi
  
  echo "----------------------------------------"
done < "$TEMP_FILE"

# Clean up temporary file
rm "$TEMP_FILE"

# Display summary report directly in terminal with nice formatting
echo ""
echo "=============================================="
echo "        COPILOT USAGE OVERALL SUMMARY         "
echo "=============================================="
echo "Days with data: $days_with_data"
echo "--------------------------------------------"
echo "ENGAGEMENT METRICS"
echo "--------------------------------------------"
echo "Total unique users: $total_users"
echo "Total code completion engagements: $total_code_completion"
echo "Total panel chat engagements: $total_panel_chat"
echo "Total inline chat engagements: $total_inline_chat"
echo "Total dotcom chat engagements: $total_dotcom_chat"
echo "Total CLI engagements: $total_cli"
echo "Total knowledge base chat engagements: $total_kb_chat"
echo "Total mobile chat engagements: $total_mobile_chat"
echo "Total PR summary engagements: $total_pr_summary"
echo "Total code review engagements: $total_code_review"
echo "=============================================="