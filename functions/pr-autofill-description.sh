#!/bin/bash

# Auto-fill PR description using Claude Code
// Lines starting with // will be ignored
// Save and close to update the PR description
// Close without saving to cancel
pr-autofill-description() {
    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    # Get current branch
    current_branch=$(git branch --show-current)
    if [ -z "$current_branch" ]; then
        echo "Error: Could not determine current branch"
        return 1
    fi

    # Get the merge target (usually main or master)
    merge_target=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')
    if [ -z "$merge_target" ]; then
        # Fallback to common branch names
        if git show-ref --verify --quiet refs/remotes/origin/main; then
            merge_target="main"
        elif git show-ref --verify --quiet refs/remotes/origin/master; then
            merge_target="master"
        else
            echo "Error: Could not determine merge target branch"
            return 1
        fi
    fi

    echo "Analyzing changes on branch '$current_branch' vs '$merge_target'..."

    # Create a temporary file for the PR description
    temp_file=$(mktemp)

    # Use Claude Code to analyze the git diff and generate PR description
    template_file="$HOME/dotfiles-local/templates/pr_description.md"

    # Function to show spinner
    show_spinner() {
        local pid=$1
        local delay=0.05
        local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        local colors=(196 202 208 214 220 226 190 154 118 82 46 47 48 49 50 51 45 39 33 27 21 57 93 129 165 201)
        local color_idx=0
        local iterations=0

        # Hide cursor
        tput civis

        printf "Generating PR description with Claude  "
        while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
            # Calculate color index based on iterations (cycles through colors every ~1.3 seconds)
            # With 0.05s delay and 26 colors, full cycle = 1.3 seconds
            color_idx=$((iterations % ${#colors[@]}))

            local temp=${spinstr#?}
            printf "\b\b\033[38;5;${colors[$color_idx]}m %s\033[0m" "${spinstr:0:1}"
            spinstr=$temp${spinstr:0:1}
            sleep $delay
            ((iterations++))
        done
        printf "\b\b ✓\n"

        # Show cursor again
        tput cnorm
    }

    # Run Claude in background and capture PID
    {
        echo "Here is my PR description template:"
        echo ""
        cat "$template_file" 2>/dev/null || echo "# Summary\n\n[Brief description of what this PR does]\n\n## Changes\n\n- [List key changes made]\n\n## Testing\n\n- [ ] Tests pass\n\n## Additional Notes\n\n[Any additional context]"
        echo ""
        echo "---"
        echo ""
        echo "Here are the git changes:"
        echo ""
        git diff "$merge_target"...HEAD
    } | /opt/homebrew/bin/claude -p "Hey! Can you help me fill out this PR description? Look at the changes and fill in the template with what's actually changing. Keep it casual and conversational - imagine you're explaining the changes to a teammate over coffee. No need to be super formal or use fancy words. Just explain what you did and why in a way that makes sense. Skip any corporate-speak or overly professional language. If something's a quick fix or cleanup, just say that. IMPORTANT: Return ONLY the filled template - no markdown code blocks, no 'Based on...' intro, no explanations. Just start with '# Summary' and fill in the template." > "$temp_file" 2>&1 &

    # Get the PID of the Claude process
    claude_pid=$!

    # Show spinner while Claude is running
    show_spinner $claude_pid

    # Wait for Claude to finish
    wait $claude_pid

    # Get current PR number for this branch
    pr_number=$(gh pr view --json number --jq '.number' 2>/dev/null)

    if [ -z "$pr_number" ]; then
        echo "Error: No PR found for current branch '$current_branch'"
        echo "Make sure you have a PR open for this branch"
        rm "$temp_file"
        return 1
    fi

    echo "Updating PR #$pr_number description..."

    # Open the description in editor for review/editing
    echo "Opening generated description in editor for review..."

    # Prepend comment lines to the top of the file
    temp_with_comments=$(mktemp)
    echo "// Lines starting with // will be ignored" > "$temp_with_comments"
    echo "// Save and close to update the PR description" >> "$temp_with_comments"
    echo "// Close without saving to cancel" >> "$temp_with_comments"
    echo "" >> "$temp_with_comments"
    cat "$temp_file" >> "$temp_with_comments"
    mv "$temp_with_comments" "$temp_file"

    # Get file modification time before editing (macOS)
    mod_time_before=$(stat -f %m "$temp_file")

    # Open in editor
    ${EDITOR:-vim} "$temp_file"

    # Get file modification time after editing (macOS)
    mod_time_after=$(stat -f %m "$temp_file")

    # Check if file was saved (modification time changed)
    if [ "$mod_time_before" = "$mod_time_after" ]; then
        echo "No changes saved. Cancelling PR update."
        rm "$temp_file"
        return 0
    fi

    # Remove comment lines before updating PR
    grep -v '^//' "$temp_file" > "${temp_file}.clean"
    mv "${temp_file}.clean" "$temp_file"

    echo "Updating PR #$pr_number description..."

    # Update the PR description
    gh pr edit "$pr_number" --body-file "$temp_file"

    if [ $? -eq 0 ]; then
        echo "✅ Successfully updated PR #$pr_number description"
        echo "🔗 View PR: $(gh pr view --json url --jq '.url')"
    else
        echo "❌ Failed to update PR description"
        echo "Generated description saved to: $temp_file"
        return 1
    fi

    # Clean up
    rm "$temp_file"
}
