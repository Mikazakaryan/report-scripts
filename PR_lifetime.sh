#!/bin/bash

# Specify the usernames to filter
TARGET_USERNAMES="<username>,<username>"
EXCLUDED_USER="<username>,<username>"  # User to exclude from team average

# Repositories to process
REPOS=("<REPO>")

# Determine the date 7 days ago (cross-platform handling)
if [[ "$OSTYPE" == "darwin"* ]]; then
    SEVEN_DAYS_AGO=$(date -v-7d +%Y-%m-%d)
    CURRENT_DATE=$(date +%d_%m_%Y) # macOS: Current date as DD_MM_YYYY
else
    SEVEN_DAYS_AGO=$(date -d '7 days ago' +%Y-%m-%d)
    CURRENT_DATE=$(date +%d_%m_%Y) # Linux: Current date as DD_MM_YYYY
fi

# Filenames including the current date at the beginning
FILTERED_REPORT="./${CURRENT_DATE}_result_filtered_prs.json"
AVERAGES_REPORT="./${CURRENT_DATE}_result_averages.json"

# Start the JSON output
echo "[" > "$FILTERED_REPORT"

# Initialize arrays for tracking times, counts, and diff sizes
usernames=()
user_times=()
user_counts=()
user_diffs=()
team_time=0
team_count=0
team_diff=0

# Function to convert seconds to human-readable format
format_time() {
    local total_seconds=$1
    local days=$((total_seconds / 86400))
    local hours=$(( (total_seconds % 86400) / 3600 ))
    local minutes=$(( (total_seconds % 3600) / 60 ))
    echo "${days}d ${hours}h ${minutes}m"
}

# Helper function to add time and diff size to a user
add_time_and_diff_to_user() {
    local user=$1
    local time=$2
    local diff_size=$3
    for i in "${!usernames[@]}"; do
        if [[ "${usernames[$i]}" == "$user" ]]; then
            user_times[$i]=$(( ${user_times[$i]} + time ))
            user_counts[$i]=$(( ${user_counts[$i]} + 1 ))
            user_diffs[$i]=$(( ${user_diffs[$i]} + diff_size ))
            return
        fi
    done

    # Add a new user if not found
    usernames+=("$user")
    user_times+=("$time")
    user_counts+=(1)
    user_diffs+=("$diff_size")
}

# Loop through each repository
for REPO in "${REPOS[@]}"; do
    echo "Processing repository: $REPO"  # Debugging
    pr_list=$(gh pr list --repo "$REPO" --state merged --search "merged:>=$SEVEN_DAYS_AGO" --json number,mergedAt,url,author,createdAt,additions,deletions,changedFiles --limit 10000 | jq -c '.[]')
    while read -r pr; do
        # Extract details from the PR JSON
        merged_at=$(echo "$pr" | jq -r '.mergedAt')
        author=$(echo "$pr" | jq -r '.author.login')
        url=$(echo "$pr" | jq -r '.url')
        pr_number=$(echo "$pr" | jq -r '.number')
        additions=$(echo "$pr" | jq -r '.additions')
        deletions=$(echo "$pr" | jq -r '.deletions')
        diff_size=$((additions + deletions))

        # Filter by username
        if echo "$TARGET_USERNAMES" | grep -q -w "$author"; then
            # Fetch the ReadyForReviewEvent timestamp for this PR
            ready_for_review=$(gh api "/repos/$REPO/issues/$pr_number/timeline" --jq '.[] | select(.event == "ready_for_review") | .created_at' | head -n 1)
            ready_for_review=${ready_for_review:-$(echo "$pr" | jq -r '.createdAt')}

            # Calculate time to merge in seconds
            if [ -n "$ready_for_review" ] && [ -n "$merged_at" ]; then
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    time_to_merge=$(( $(gdate -d "$merged_at" +%s) - $(gdate -d "$ready_for_review" +%s) ))
                else
                    time_to_merge=$(( $(date -d "$merged_at" +%s) - $(date -d "$ready_for_review" +%s) ))
                fi
            else
                time_to_merge=0
            fi

            # Convert time_to_merge to human-readable format
            readable_time=$(format_time $time_to_merge)

            echo "Adding time and diff size for $author: $readable_time, diff size: $diff_size"  # Debugging

            # Add time and diff size to the user
            add_time_and_diff_to_user "$author" "$time_to_merge" "$diff_size"

            # Update team totals (excluding excluded user)
            if [ "$author" != "$EXCLUDED_USER" ]; then
                team_time=$((team_time + time_to_merge))
                team_count=$((team_count + 1))
                team_diff=$((team_diff + diff_size))
            fi

            # Append PR details to the JSON output
            echo "{
                \"repository\": \"$REPO\",
                \"mergedAt\": \"$merged_at\",
                \"author\": \"$author\",
                \"url\": \"$url\",
                \"readyForReviewAt\": \"$ready_for_review\",
                \"time_to_merge\": \"$readable_time\",
                \"diff_size\": \"$diff_size\"
            }," >> "$FILTERED_REPORT"
        fi
    done <<< "$pr_list"
done

# Remove the trailing comma and close the JSON array
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' '$ s/,$//' "$FILTERED_REPORT"
else
    sed -i '$ s/,$//' "$FILTERED_REPORT"
fi
echo "]" >> "$FILTERED_REPORT"

# Start the averages JSON output
echo "{" > "$AVERAGES_REPORT"

# Calculate per-person averages
echo "\"per_person\": {" >> "$AVERAGES_REPORT"
for i in "${!usernames[@]}"; do
    if [[ ${user_counts[$i]} -gt 0 ]]; then
        avg_time=$(( ${user_times[$i]} / ${user_counts[$i]} ))
        avg_diff=$(( ${user_diffs[$i]} / ${user_counts[$i]} ))
        readable_avg_time=$(format_time $avg_time)
    else
        readable_avg_time="0d 0h 0m"
        avg_diff=0
    fi
    echo "    \"${usernames[$i]}\": {\"avg_time\": \"$readable_avg_time\", \"avg_diff_size\": $avg_diff}," >> "$AVERAGES_REPORT"
done

# Remove the trailing comma from the per_person block
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' '$ s/,$//' "$AVERAGES_REPORT"
else
    sed -i '$ s/,$//' "$AVERAGES_REPORT"
fi

# Close the per_person block
echo "}," >> "$AVERAGES_REPORT"

# Calculate team averages
if [ $team_count -gt 0 ]; then
    team_avg_time=$((team_time / team_count))
    team_avg_diff=$((team_diff / team_count))
    readable_team_avg_time=$(format_time $team_avg_time)
else
    readable_team_avg_time="0d 0h 0m"
    team_avg_diff=0
fi

# Add team averages to the JSON
echo "\"team_average\": {\"avg_time\": \"$readable_team_avg_time\", \"avg_diff_size\": $team_avg_diff}" >> "$AVERAGES_REPORT"

# Close the JSON object
echo "}" >> "$AVERAGES_REPORT"
