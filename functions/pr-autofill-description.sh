#!/bin/bash

# Source shared functions
source "$HOME/dotfiles-local/functions/shared/show_spinner.sh"

# Auto-fill PR description using Claude Code
pr-autofill-description() {
  validate_git_environment() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
      echo "Error: Not in a git repository"
      return 1
    fi

    current_branch=$(git branch --show-current)
    if [ -z "$current_branch" ]; then
      echo "Error: Could not determine current branch"
      return 1
    fi
  }

  determine_merge_target() {
    merge_target=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')
    if [ -z "$merge_target" ]; then
      if git show-ref --verify --quiet refs/remotes/origin/main; then
        merge_target="main"
      elif git show-ref --verify --quiet refs/remotes/origin/master; then
        merge_target="master"
      else
        echo "Error: Could not determine merge target branch"
        return 1
      fi
    fi
  }

  generate_description_with_claude() {
    local template_file="$HOME/dotfiles-local/templates/pr_description.md"
    temp_file=$(mktemp)

    # Set up trap to kill Claude process on Ctrl+C
    cleanup_claude() {
      if [ -n "$claude_pid" ] && kill -0 "$claude_pid" 2>/dev/null; then
        echo ""
        echo "Terminating Claude process..."
        kill "$claude_pid" 2>/dev/null
        wait "$claude_pid" 2>/dev/null
      fi
      rm -f "$temp_file"
      tput cnorm  # Restore cursor
      trap - INT  # Clear the trap
      return 1
    }
    trap cleanup_claude INT

    set +m
    (
      echo "Here is my PR description template:"
      echo ""
      cat "$template_file" 2>/dev/null || echo "# Summary\n\n[Brief description of what this PR does]\n\n## Changes\n\n- [List key changes made]\n\n## Testing\n\n- [ ] Tests pass\n\n## Additional Notes\n\n[Any additional context]"
      echo ""
      echo "---"
      echo ""
      echo "Here are the git changes:"
      echo ""
      git diff "$merge_target"...HEAD
    ) | /opt/homebrew/bin/claude -p "Hey! Can you help me fill out this PR description? Look at the changes and fill in the template with what's actually changing. Keep it casual and conversational - imagine you're explaining the changes to a teammate over coffee. No need to be super formal or use fancy words. Just explain what you did and why in a way that makes sense. Skip any corporate-speak or overly professional language. If something's a quick fix or cleanup, just say that. IMPORTANT: Return ONLY the filled template - no markdown code blocks, no 'Based on...' intro, no explanations. Just start with '# Summary' and fill in the template." > "$temp_file" 2>&1 &

    claude_pid=$!
    set -m

    show_spinner $claude_pid "Generating PR description with Claude"
    wait $claude_pid

    # Clear the trap once Claude finishes normally
    trap - INT
  }

  find_current_pr() {
    pr_number=$(gh pr view --json number --jq '.number' 2>/dev/null)
    if [ -z "$pr_number" ]; then
      echo "Error: No PR found for current branch '$current_branch'"
      echo "Make sure you have a PR open for this branch"
      rm "$temp_file"
      return 1
    fi
  }

  review_description_in_editor() {
    echo "Opening generated description in editor for review..."

    local temp_with_comments=$(mktemp)
    echo "// Lines starting with // will be ignored" > "$temp_with_comments"
    echo "// Save and close to update the PR description" >> "$temp_with_comments"
    echo "// Close without saving to cancel" >> "$temp_with_comments"
    echo "" >> "$temp_with_comments"
    cat "$temp_file" >> "$temp_with_comments"
    mv "$temp_with_comments" "$temp_file"

    local mod_time_before=$(stat -f %m "$temp_file")
    ${EDITOR:-vim} "$temp_file"
    local mod_time_after=$(stat -f %m "$temp_file")

    if [ "$mod_time_before" = "$mod_time_after" ]; then
      echo "No changes saved. Cancelling PR update."
      rm "$temp_file"
      return 1
    fi

    grep -v '^//' "$temp_file" > "${temp_file}.clean"
    mv "${temp_file}.clean" "$temp_file"
  }

  update_pr_description() {
    echo "Updating PR #$pr_number description..."
    gh pr edit "$pr_number" --body-file "$temp_file"

    if [ $? -eq 0 ]; then
      echo "✅ Successfully updated PR #$pr_number description"
      echo "🔗 View PR: $(gh pr view --json url --jq '.url')"
    else
      echo "❌ Failed to update PR description"
      echo "Generated description saved to: $temp_file"
      return 1
    fi

    rm "$temp_file"
  }

  # Main execution flow
  validate_git_environment || return 1
  determine_merge_target || return 1

  # Count words in the diff
  local diff_content=$(git diff "$merge_target"...HEAD)
  local word_count=$(echo "$diff_content" | wc -w | xargs)

  echo "Analyzing changes on branch '$current_branch' vs '$merge_target'... $word_count words/tokens changed."

  # Check if there are any changes to process
  if [ "$word_count" -eq 0 ]; then
    echo ""
    echo "❌ No changes found to generate PR description from."
    echo "This could mean:"
    echo "  - No actual changes between '$merge_target' and '$current_branch'"
    echo "  - You're comparing the same branch against itself"
    return 1
  fi

  generate_description_with_claude
  find_current_pr || return 1
  review_description_in_editor || return 0
  update_pr_description
}
