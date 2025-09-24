#!/bin/bash

# Source shared functions
source "$HOME/dotfiles-local/functions/shared/show_spinner.sh"

# Auto-fill PR description using Claude Code
pr-autofill-description() {
  # Declare all shared variables as local
  local current_branch merge_target temp_file pr_number claude_pid diff_content word_count
  local interrupted=false

  # Check for required dependencies
  check_dependencies() {
    local missing_tools=()
    command -v git >/dev/null || missing_tools+=("git")
    command -v gh >/dev/null || missing_tools+=("gh")
    command -v claude >/dev/null || missing_tools+=("claude")
    command -v jq >/dev/null || missing_tools+=("jq")

    if [ ${#missing_tools[@]} -gt 0 ]; then
      echo "❌ Missing required tools: ${missing_tools[*]}"
      echo "Please install the missing tools before running this script"
      return 1
    fi
  }

  # Global cleanup function
  cleanup_all() {
    [ -n "$claude_pid" ] && kill "$claude_pid" 2>/dev/null && wait "$claude_pid" 2>/dev/null
    [ -n "$temp_file" ] && rm -f "$temp_file" "${temp_file}.clean" 2>/dev/null
    tput cnorm 2>/dev/null  # Restore cursor
  }

  # Signal handler
  handle_interrupt() {
    echo ""
    echo "Interrupted. Cleaning up..."
    interrupted=true
    cleanup_all
  }

  # Set up global traps
  trap handle_interrupt INT TERM
  trap cleanup_all EXIT

  validate_git_environment() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
      echo "Error: Not in a git repository"
      return 1
    fi

    if ! current_branch=$(git branch --show-current 2>/dev/null) || [ -z "$current_branch" ]; then
      echo "Error: Could not determine current branch"
      return 1
    fi
  }

  determine_merge_target() {
    if ! merge_target=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'); then
      merge_target=""
    fi

    if [ -z "$merge_target" ]; then
      if git show-ref --verify --quiet refs/remotes/origin/main 2>/dev/null; then
        merge_target="main"
      elif git show-ref --verify --quiet refs/remotes/origin/master 2>/dev/null; then
        merge_target="master"
      else
        echo "Error: Could not determine merge target branch"
        return 1
      fi
    fi
  }

  generate_description_with_claude() {
    # Check if interrupted before starting
    if [ "$interrupted" = true ]; then
      return 1
    fi

    local template_file="$HOME/dotfiles-local/templates/pr_description.md"
    local claude_path

    # Find claude binary
    if command -v claude >/dev/null; then
      claude_path="claude"
    elif [ -x "/opt/homebrew/bin/claude" ]; then
      claude_path="/opt/homebrew/bin/claude"
    else
      echo "❌ Could not find claude binary"
      return 1
    fi

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
      if ! git diff "$merge_target"...HEAD 2>/dev/null; then
        echo "Error: Could not generate git diff"
        exit 1
      fi
    ) | "$claude_path" -p "Hey! Can you help me fill out this PR description? Look at the changes and fill in the template with what's actually changing. Keep it casual and conversational - imagine you're explaining the changes to a teammate over coffee. No need to be super formal or use fancy words. Just explain what you did and why in a way that makes sense. Skip any corporate-speak or overly professional language. If something's a quick fix or cleanup, just say that. IMPORTANT: Return ONLY the filled template - no markdown code blocks, no 'Based on...' intro, no explanations. Just start with '# Summary' and fill in the template." > "$temp_file" 2>&1 &

    claude_pid=$!

    show_spinner $claude_pid "Generating PR description with Claude"
    wait $claude_pid 2>/dev/null
    local claude_exit_code=$?
    set -m

    # Check if we were interrupted - if so, just return silently
    if [ "$interrupted" = true ]; then
      return 1
    fi

    # Validate Claude output
    if [ "$claude_exit_code" -ne 0 ] || [ ! -s "$temp_file" ]; then
      echo "❌ Claude failed to generate description or produced empty output"
      if [ -s "$temp_file" ]; then
        echo "Claude error output:"
        head -5 "$temp_file"
      fi
      return 1
    fi

    # Check if output looks reasonable (has some content)
    local content_lines=$(grep -v '^[[:space:]]*$' "$temp_file" | wc -l)
    if [ "$content_lines" -lt 3 ]; then
      echo "❌ Claude output appears too short or invalid"
      echo "Generated content:"
      cat "$temp_file"
      return 1
    fi
  }

  find_current_pr() {
    if [ "$interrupted" = true ]; then
      return 1
    fi

    if ! pr_info=$(gh pr view --json number,state --jq '{number: .number, state: .state}' 2>/dev/null) || [ -z "$pr_info" ]; then
      echo "Error: No PR found for current branch '$current_branch'"
      echo "Make sure you have a PR open for this branch"
      return 1
    fi

    pr_number=$(echo "$pr_info" | jq -r '.number')
    local pr_state=$(echo "$pr_info" | jq -r '.state')

    if [ "$pr_state" = "MERGED" ]; then
      echo "❌ PR #$pr_number has already been merged"
      echo "Cannot modify description of merged PR to preserve history"
      return 1
    fi

    if [ "$pr_state" = "CLOSED" ]; then
      echo "⚠️  Warning: PR #$pr_number is closed but not merged"
      echo "Proceeding anyway - you can still edit closed PR descriptions"
    fi
  }

  review_description_in_editor() {
    if [ "$interrupted" = true ]; then
      return 1
    fi

    echo "Opening generated description in editor for review..."

    local temp_with_comments=$(mktemp)
    echo "// Lines starting with // will be ignored" > "$temp_with_comments"
    echo "// Save and close to update the PR description" >> "$temp_with_comments"
    echo "// Close without saving to cancel" >> "$temp_with_comments"
    echo "" >> "$temp_with_comments"
    cat "$temp_file" >> "$temp_with_comments"
    mv "$temp_with_comments" "$temp_file"

    # Platform-compatible file modification time check
    local mod_time_before
    if command -v stat >/dev/null; then
      if stat -f %m "$temp_file" >/dev/null 2>&1; then
        # BSD/macOS stat
        mod_time_before=$(stat -f %m "$temp_file")
      elif stat -c %Y "$temp_file" >/dev/null 2>&1; then
        # GNU/Linux stat
        mod_time_before=$(stat -c %Y "$temp_file")
      else
        echo "❌ Error: stat command not compatible with this system"
        echo "Please report this issue with your OS details"
        return 1
      fi
    else
      echo "❌ Error: stat command not found"
      echo "This script requires the stat command to detect file changes"
      return 1
    fi

    ${EDITOR:-vim} "$temp_file"

    local mod_time_after
    if stat -f %m "$temp_file" >/dev/null 2>&1; then
      mod_time_after=$(stat -f %m "$temp_file")
    else
      mod_time_after=$(stat -c %Y "$temp_file")
    fi

    if [ "$mod_time_before" = "$mod_time_after" ]; then
      echo "No changes saved. Cancelling PR update."
      return 1
    fi

    grep -v '^//' "$temp_file" > "${temp_file}.clean"
    mv "${temp_file}.clean" "$temp_file"
  }

  update_pr_description() {
    if [ "$interrupted" = true ]; then
      return 1
    fi

    echo "Updating PR #$pr_number description..."

    if ! gh pr edit "$pr_number" --body-file "$temp_file" 2>/dev/null; then
      echo "❌ Failed to update PR description"
      echo "Generated description saved to: $temp_file"
      return 1
    fi

    echo "✅ Successfully updated PR #$pr_number description"
    if ! pr_url=$(gh pr view --json url --jq '.url' 2>/dev/null); then
      echo "PR updated successfully but could not retrieve URL"
    else
      echo "🔗 View PR: $pr_url"
    fi
  }

  # Main execution flow
  check_dependencies || return 1
  validate_git_environment || return 1
  determine_merge_target || return 1

  # Count words in the diff
  if ! diff_content=$(git diff "$merge_target"...HEAD 2>/dev/null); then
    echo "❌ Error: Could not generate git diff between '$merge_target' and '$current_branch'"
    return 1
  fi
  word_count=$(echo "$diff_content" | wc -w | xargs)

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

  # Check for existing PR before running Claude
  find_current_pr || return 1

  # Check if interrupted after finding PR
  if [ "$interrupted" = true ]; then
    return 1
  fi

  # Create temporary file for the PR description
  temp_file=$(mktemp)

  generate_description_with_claude || return 1

  # Check if interrupted after Claude
  if [ "$interrupted" = true ]; then
    return 1
  fi

  review_description_in_editor || return 0
  update_pr_description
}
