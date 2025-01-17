#!/bin/bash

# Ask whether to calculate for a single user or the entire team
echo "Do you want to calculate for a specific user or the entire team? (Enter 'user' or 'team')"
read CHOICE

# Initialize variables to calculate averages
total_time=0
total_diff_size=0
pr_count=0

# Function to parse human-readable time into seconds
parse_time_to_seconds() {
    local time_str=$1
    local days=0 hours=0 minutes=0
    days=$(echo "$time_str" | grep -o '[0-9]\+d' | sed 's/d//g' || echo 0)
    hours=$(echo "$time_str" | grep -o '[0-9]\+h' | sed 's/h//g' || echo 0)
    minutes=$(echo "$time_str" | grep -o '[0-9]\+m' | sed 's/m//g' || echo 0)
    echo $((days * 86400 + hours * 3600 + minutes * 60))
}

# Function to convert seconds to human-readable format
format_time() {
    local total_seconds=$1
    local days=$((total_seconds / 86400))
    local hours=$(( (total_seconds % 86400) / 3600 ))
    local minutes=$(( (total_seconds % 3600) / 60 ))
    echo "${days}d ${hours}h ${minutes}m"
}

# Ask for the username if calculating for a specific user
if [[ "$CHOICE" == "user" ]]; then
    echo "Enter the username:"
    read USERNAME
fi

# Specify the directory containing the report files
REPORT_DIR="." # Change this to your directory path if different

# Find all report files matching the pattern
REPORT_FILES=$(ls ${REPORT_DIR}/*result_filtered_prs*.json 2>/dev/null)

# Check if report files exist
if [[ -z "$REPORT_FILES" ]]; then
    echo "No report files found in $REPORT_DIR."
    exit 1
fi

# Process each report file
for file in $REPORT_FILES; do
    echo "Processing file: $file"

    if [[ "$CHOICE" == "user" ]]; then
        # Extract PRs for the specified username
        prs=$(jq -c --arg USERNAME "$USERNAME" '.[] | select(.author == $USERNAME)' "$file")
    else
        # Extract all PRs for the team
        prs=$(jq -c '.[]' "$file")
    fi

    # Process the extracted PRs
    while read -r pr; do
        # Extract `time_to_merge` and `diff_size`
        raw_time=$(echo "$pr" | jq -r '.time_to_merge')
        diff_size=$(echo "$pr" | jq -r '.diff_size // 0') # Default to 0 if diff_size is missing

        # Parse human-readable time to seconds
        if [[ "$raw_time" =~ ^[0-9]+[dhm] ]]; then
            time_to_merge=$(parse_time_to_seconds "$raw_time")
            total_time=$((total_time + time_to_merge))
            total_diff_size=$((total_diff_size + diff_size))
            pr_count=$((pr_count + 1))
        else
            echo "Invalid time_to_merge value for PR: $raw_time (skipping)"
        fi
    done <<< "$prs"
done

# Calculate the averages
if [[ $pr_count -gt 0 ]]; then
    average_time=$((total_time / pr_count))
    readable_avg_time=$(format_time $average_time)
    average_diff_size=$((total_diff_size / pr_count))

    if [[ "$CHOICE" == "user" ]]; then
        echo "Average PR lifetime for $USERNAME: $readable_avg_time"
        echo "Average diff size for $USERNAME: $average_diff_size"
    else
        echo "Average PR lifetime for the entire team: $readable_avg_time"
        echo "Average diff size for the entire team: $average_diff_size"
    fi
else
    if [[ "$CHOICE" == "user" ]]; then
        echo "No PRs found for $USERNAME in the report files."
    else
        echo "No PRs found for the team in the report files."
    fi
fi
