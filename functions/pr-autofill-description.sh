#!/bin/bash

# Source shared functions
source "$HOME/dotfiles-local/functions/shared/show_spinner.sh"

# Auto-fill PR description using Claude Code
pr-autofill-description() {
  # Declare all shared variables as local
  local current_branch merge_target temp_file pr_number claude_pid diff_content char_count
  local interrupted=false
  local retry_file=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --retry)
        if [ -z "$2" ] || [[ "$2" == --* ]]; then
          echo "❌ --retry requires a file path"
          return 1
        fi
        retry_file="$2"
        shift 2
        ;;
      *)
        echo "❌ Unknown argument: $1"
        echo "Usage: pr-autofill-description [--retry <file>]"
        return 1
        ;;
    esac
  done

  # Chunk size for map-reduce (in characters, not words)
  # ~400k chars ≈ 100k tokens, safe for Opus (200k context) with prompt overhead
  local CHUNK_SIZE=400000

  # Check for required dependencies
  check_dependencies() {
    local missing_tools=()
    command -v git >/dev/null || missing_tools+=("git")
    command -v gh >/dev/null || missing_tools+=("gh")
    # Only require claude if not in retry mode
    [ -z "$retry_file" ] && command -v claude >/dev/null || missing_tools+=("claude")
    command -v jq >/dev/null || missing_tools+=("jq")

    # Remove "claude" from missing_tools if in retry mode
    if [ -n "$retry_file" ]; then
      missing_tools=("${missing_tools[@]/claude/}")
    fi

    # Filter out empty elements
    local filtered_tools=()
    for tool in "${missing_tools[@]}"; do
      [ -n "$tool" ] && filtered_tools+=("$tool")
    done

    if [ ${#filtered_tools[@]} -gt 0 ]; then
      echo "❌ Missing required tools: ${filtered_tools[*]}"
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

  # Get claude binary path
  get_claude_path() {
    if command -v claude >/dev/null; then
      echo "claude"
    elif [ -x "/opt/homebrew/bin/claude" ]; then
      echo "/opt/homebrew/bin/claude"
    else
      echo ""
    fi
  }

  # Split a single file's diff at hunk boundaries (@@ ... @@)
  # Used when a single file exceeds CHUNK_SIZE
  # Outputs chunks to output_dir with prefix, starting at start_num
  # Returns the next chunk number to use
  split_file_at_hunks() {
    local file_diff="$1"
    local output_dir="$2"
    local prefix="$3"
    local start_num="$4"

    local file_header=""
    local current_hunk=""
    local current_chunk=""
    local current_char_count=0
    local chunk_num=$start_num
    local in_header=true

    while IFS= read -r line; do
      # Collect file header (everything before first @@)
      if [ "$in_header" = true ]; then
        if [[ "$line" =~ ^@@.*@@ ]]; then
          in_header=false
          current_hunk="$line"
        else
          if [ -n "$file_header" ]; then
            file_header="$file_header"$'\n'"$line"
          else
            file_header="$line"
          fi
        fi
        continue
      fi

      # At a new hunk boundary
      if [[ "$line" =~ ^@@.*@@ ]]; then
        # Add previous hunk to current chunk
        if [ -n "$current_hunk" ]; then
          local hunk_chars=$(echo "$current_hunk" | wc -c | xargs)

          # If adding this hunk would exceed limit, save current chunk first
          if [ $((current_char_count + hunk_chars)) -ge "$CHUNK_SIZE" ] && [ -n "$current_chunk" ]; then
            echo "$file_header"$'\n'"$current_chunk" > "$output_dir/${prefix}_part${chunk_num}.txt"
            chunk_num=$((chunk_num + 1))
            current_chunk=""
            current_char_count=0
          fi

          # Add hunk to current chunk
          if [ -n "$current_chunk" ]; then
            current_chunk="$current_chunk"$'\n'"$current_hunk"
          else
            current_chunk="$current_hunk"
          fi
          current_char_count=$((current_char_count + hunk_chars))
        fi

        current_hunk="$line"
      else
        # Add line to current hunk
        if [ -n "$current_hunk" ]; then
          current_hunk="$current_hunk"$'\n'"$line"
        else
          current_hunk="$line"
        fi
      fi
    done <<< "$file_diff"

    # Handle last hunk
    if [ -n "$current_hunk" ]; then
      local hunk_chars=$(echo "$current_hunk" | wc -c | xargs)

      if [ $((current_char_count + hunk_chars)) -ge "$CHUNK_SIZE" ] && [ -n "$current_chunk" ]; then
        echo "$file_header"$'\n'"$current_chunk" > "$output_dir/${prefix}_part${chunk_num}.txt"
        chunk_num=$((chunk_num + 1))
        current_chunk="$current_hunk"
      else
        if [ -n "$current_chunk" ]; then
          current_chunk="$current_chunk"$'\n'"$current_hunk"
        else
          current_chunk="$current_hunk"
        fi
      fi
    fi

    # Save final chunk
    if [ -n "$current_chunk" ]; then
      echo "$file_header"$'\n'"$current_chunk" > "$output_dir/${prefix}_part${chunk_num}.txt"
      chunk_num=$((chunk_num + 1))
    fi

    # Return next chunk number
    echo "$chunk_num"
  }

  # Split a single diff into sub-chunks of approximately CHUNK_SIZE words
  # Used when a commit diff is too large
  # First splits at file boundaries, then splits large files at hunk boundaries
  split_large_diff() {
    local diff_content="$1"
    local output_dir="$2"
    local prefix="$3"

    local current_file=""
    local current_chunk=""
    local current_chunk_chars=0
    local chunk_num=1

    # Helper to process a completed file
    process_file() {
      local file_content="$1"
      [ -z "$file_content" ] && return

      local file_chars=$(echo "$file_content" | wc -c | xargs)

      # If this single file exceeds chunk size, split it at hunks
      if [ "$file_chars" -ge "$CHUNK_SIZE" ]; then
        # Save current chunk first if we have one
        if [ -n "$current_chunk" ]; then
          echo "$current_chunk" > "$output_dir/${prefix}_part${chunk_num}.txt"
          chunk_num=$((chunk_num + 1))
          current_chunk=""
          current_chunk_chars=0
        fi
        # Split the large file at hunk boundaries
        chunk_num=$(split_file_at_hunks "$file_content" "$output_dir" "$prefix" "$chunk_num")
      # If adding this file would exceed limit, save current chunk first
      elif [ $((current_chunk_chars + file_chars)) -ge "$CHUNK_SIZE" ] && [ -n "$current_chunk" ]; then
        echo "$current_chunk" > "$output_dir/${prefix}_part${chunk_num}.txt"
        chunk_num=$((chunk_num + 1))
        current_chunk="$file_content"
        current_chunk_chars=$file_chars
      else
        # Add file to current chunk
        if [ -n "$current_chunk" ]; then
          current_chunk="$current_chunk"$'\n'"$file_content"
        else
          current_chunk="$file_content"
        fi
        current_chunk_chars=$((current_chunk_chars + file_chars))
      fi
    }

    # Process line by line, accumulating by file
    while IFS= read -r line; do
      # Detect new file header
      if [[ "$line" =~ ^diff\ --git ]]; then
        # Process the previous file
        process_file "$current_file"
        current_file="$line"
      else
        # Add line to current file
        if [ -n "$current_file" ]; then
          current_file="$current_file"$'\n'"$line"
        else
          current_file="$line"
        fi
      fi
    done <<< "$diff_content"

    # Process the last file
    process_file "$current_file"

    # Save any remaining chunk
    if [ -n "$current_chunk" ]; then
      echo "$current_chunk" > "$output_dir/${prefix}_part${chunk_num}.txt"
    fi
  }

  # Split diff by commit boundaries
  # If commits are small enough, use them as chunks
  # If a commit is too large, split it further by file boundaries
  split_diff_into_chunks() {
    local target_branch="$1"
    local full_diff="$2"
    local chunk_dir=$(mktemp -d)
    local chunk_number=1

    # Get list of commits in the branch
    local commits=$(git rev-list --reverse "${target_branch}"..HEAD 2>/dev/null)

    if [ -z "$commits" ]; then
      # Fallback: just use the full diff as one chunk
      echo "$full_diff" > "$chunk_dir/chunk_1.txt"
      echo "$chunk_dir"
      return
    fi

    # Process each commit (use process substitution to avoid subshell)
    while IFS= read -r commit; do
      [ -z "$commit" ] && continue

      local commit_diff=$(git show --format="" "$commit" 2>/dev/null)
      local commit_chars=$(echo "$commit_diff" | wc -c | xargs)
      local commit_msg=$(git log -1 --format="%s" "$commit" 2>/dev/null)

      if [ "$commit_chars" -eq 0 ]; then
        continue
      fi

      if [ "$commit_chars" -le "$CHUNK_SIZE" ]; then
        # Commit is small enough, use as-is
        {
          echo "=== Commit: $commit_msg ==="
          echo ""
          echo "$commit_diff"
        } > "$chunk_dir/chunk_${chunk_number}.txt"
        chunk_number=$((chunk_number + 1))
      else
        # Commit is too large, split by file boundaries
        echo "Commit '$commit_msg' is $commit_chars chars, splitting further..." >&2
        local temp_split_dir=$(mktemp -d)
        split_large_diff "$commit_diff" "$temp_split_dir" "split"
        # Count how many parts were created
        local parts=$(ls "$temp_split_dir"/split_part*.txt 2>/dev/null | wc -l | xargs)
        if [ "$parts" -gt 0 ]; then
          # Move parts to chunk dir with sequential numbers and commit context
          local part_num=1
          for part_file in "$temp_split_dir"/split_part*.txt; do
            {
              echo "=== Commit: $commit_msg (part $part_num of $parts) ==="
              echo ""
              cat "$part_file"
            } > "$chunk_dir/chunk_${chunk_number}.txt"
            chunk_number=$((chunk_number + 1))
            part_num=$((part_num + 1))
          done
        fi
        rm -rf "$temp_split_dir"
      fi
    done <<< "$commits"

    echo "$chunk_dir"
  }

  # Summarize a single chunk of diff
  summarize_chunk() {
    local chunk_file="$1"
    local chunk_num="$2"
    local total_chunks="$3"
    local output_file="$4"
    local claude_path="$5"
    local chunk_label="$6"

    # Debug: log actual file size and character count
    local char_count=$(wc -c < "$chunk_file" | xargs)
    local line_count=$(wc -l < "$chunk_file" | xargs)

    cat "$chunk_file" | "$claude_path" -p "Summarize the key changes in this git diff. Focus on:
- What files were modified
- What functionality was added, changed, or removed
- Any important implementation details

Be concise but comprehensive. This summary will be combined with others to create a PR description.
Return ONLY the summary - no intro text, no markdown code blocks." > "$output_file" 2>&1
    local result=$?

    # On failure, append debug info to output
    if [ $result -ne 0 ]; then
      echo "" >> "$output_file"
      echo "--- Debug Info ---" >> "$output_file"
      echo "Chunk: $chunk_num of $total_chunks" >> "$output_file"
      echo "Characters: $char_count" >> "$output_file"
      echo "Lines: $line_count" >> "$output_file"
      echo "Claude path: $claude_path" >> "$output_file"
      echo "Claude version: $("$claude_path" --version 2>&1 || echo 'unknown')" >> "$output_file"
    fi

    return $result
  }

  # Extract chunk label from chunk file (first line contains === Commit: ... ===)
  get_chunk_label() {
    local chunk_file="$1"
    local first_line=$(head -1 "$chunk_file")
    # Extract text between "=== Commit: " and " ===" using sed
    local label=$(echo "$first_line" | sed -n 's/^=== Commit: \(.*\) ===$/\1/p')
    if [ -n "$label" ]; then
      echo "$label"
    else
      echo "chunk"
    fi
  }

  # Combine chunk summaries into final PR description
  combine_summaries() {
    local summaries_dir="$1"
    local template_file="$2"
    local output_file="$3"
    local claude_path="$4"

    (
      echo "Here is my PR description template:"
      echo ""
      cat "$template_file" 2>/dev/null || echo "# Summary\n\n[Brief description of what this PR does]\n\n## Changes\n\n- [List key changes made]\n\n## Testing\n\n- [ ] Tests pass\n\n## Additional Notes\n\n[Any additional context]"
      echo ""
      echo "---"
      echo ""
      echo "Here are summaries of all the changes in this PR (the diff was too large to process at once):"
      echo ""
      for summary_file in "$summaries_dir"/summary_*.txt; do
        if [ -f "$summary_file" ]; then
          echo "=== Changes Part $(basename "$summary_file" | sed 's/summary_\([0-9]*\)\.txt/\1/') ==="
          cat "$summary_file"
          echo ""
        fi
      done
    ) | "$claude_path" -p "Hey! Can you help me fill out this PR description? I've given you summaries of all the changes (the full diff was too large). Synthesize these summaries into a cohesive PR description using the template.

Keep it casual and conversational - imagine you're explaining the changes to a teammate over coffee. No need to be super formal or use fancy words. Just explain what you did and why in a way that makes sense. Skip any corporate-speak or overly professional language. If something's a quick fix or cleanup, just say that.

IMPORTANT: Return ONLY the filled template - no markdown code blocks, no 'Based on...' intro, no explanations. Just start with '# Summary' and fill in the template." > "$output_file" 2>&1

    return $?
  }

  generate_description_with_claude() {
    # Check if interrupted before starting
    if [ "$interrupted" = true ]; then
      return 1
    fi

    local template_file="$HOME/dotfiles-local/templates/pr_description.md"
    local claude_path=$(get_claude_path)

    if [ -z "$claude_path" ]; then
      echo "❌ Could not find claude binary"
      return 1
    fi

    # Check if we need map-reduce (diff is too large)
    if [ "$char_count" -gt "$CHUNK_SIZE" ]; then
      echo "Large diff detected ($char_count chars). Using map-reduce strategy..."

      # Split diff into chunks
      local chunk_dir=$(split_diff_into_chunks "$merge_target" "$diff_content")
      local num_chunks=$(ls "$chunk_dir"/chunk_*.txt 2>/dev/null | wc -l | xargs)
      echo "Split into $num_chunks chunks"

      if [ "$num_chunks" -eq 0 ]; then
        echo "❌ Failed to split diff into chunks"
        rm -rf "$chunk_dir"
        return 1
      fi

      # Create summaries directory
      local summaries_dir=$(mktemp -d)

      # Process each chunk in parallel (map phase)
      local pids=()
      local chunk_labels=()
      local chunk_files_arr=()
      local chunk_num=1

      echo ""
      echo "📤 Sending chunks to Claude..."
      echo ""

      set +m
      for chunk_file in "$chunk_dir"/chunk_*.txt; do
        local summary_file="$summaries_dir/summary_$chunk_num.txt"
        local label=$(get_chunk_label "$chunk_file")
        local char_count=$(wc -c < "$chunk_file" | xargs)

        echo "  -> [$chunk_num/$num_chunks] $label ($char_count chars)"

        summarize_chunk "$chunk_file" "$chunk_num" "$num_chunks" "$summary_file" "$claude_path" "$label" &
        pids+=($!)
        chunk_labels+=("$label")
        chunk_files_arr+=("$chunk_file")
        chunk_num=$((chunk_num + 1))
      done

      echo ""
      echo "📥 Waiting for responses..."
      echo ""

      # Track which jobs we've already reported as complete
      local reported=()
      local num_pids=${#pids[@]}
      local i=0
      while [ $i -lt $num_pids ]; do
        reported+=("0")
        i=$((i + 1))
      done

      local completed=0
      local failed=false

      while [ $completed -lt $num_pids ]; do
        if [ "$interrupted" = true ]; then
          # Kill all running jobs
          for pid in "${pids[@]}"; do
            kill "$pid" 2>/dev/null
          done
          rm -rf "$chunk_dir" "$summaries_dir"
          set -m
          return 1
        fi

        # Check each job and report newly completed ones
        i=0
        while [ $i -lt $num_pids ]; do
          if [ "${reported[$((i+1))]}" = "0" ] && ! kill -0 "${pids[$((i+1))]}" 2>/dev/null; then
            reported[$((i+1))]="1"
            local job_num=$((i + 1))
            echo "  <- [$job_num/$num_chunks] ${chunk_labels[$((i+1))]}"
          fi
          i=$((i + 1))
        done

        # Count completed
        completed=0
        for r in "${reported[@]}"; do
          [ "$r" = "1" ] && completed=$((completed + 1))
        done

        sleep 0.3
      done

      echo ""
      set -m

      # Check results of all jobs
      i=0
      while [ $i -lt $num_pids ]; do
        local job_num=$((i + 1))
        wait "${pids[$((i+1))]}"
        local exit_code=$?
        local summary_file="$summaries_dir/summary_$job_num.txt"
        local chunk_file="${chunk_files_arr[$((i+1))]}"

        if [ "$exit_code" -ne 0 ] || [ ! -s "$summary_file" ]; then
          echo "  ❌ Failed: ${chunk_labels[$((i+1))]}"
          echo "     Exit code: $exit_code"
          if [ -s "$summary_file" ]; then
            echo "     Error output:"
            sed 's/^/       /' "$summary_file"
          else
            echo "     (no output captured)"
          fi
          if [ -n "$chunk_file" ] && [ -f "$chunk_file" ]; then
            local debug_file="/tmp/pr-autofill-failed-chunk-${job_num}.txt"
            cp "$chunk_file" "$debug_file"
            echo "     Chunk saved to: $debug_file"
          fi
          failed=true
        fi
        i=$((i + 1))
      done

      # Cleanup chunk files
      rm -rf "$chunk_dir"

      if [ "$failed" = true ]; then
        rm -rf "$summaries_dir"
        return 1
      fi

      # Combine summaries (reduce phase)
      echo "🔄 Combining $num_chunks summaries into final PR description..."
      echo ""

      set +m
      combine_summaries "$summaries_dir" "$template_file" "$temp_file" "$claude_path" &
      claude_pid=$!
      show_spinner $claude_pid "Generating final description"
      wait $claude_pid 2>/dev/null
      local claude_exit_code=$?
      set -m

      echo ""

      # Cleanup summaries
      rm -rf "$summaries_dir"

    else
      # Original single-pass logic for smaller diffs
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
        echo "$diff_content"
      ) | "$claude_path" -p "Hey! Can you help me fill out this PR description? Look at the changes and fill in the template with what's actually changing. Keep it casual and conversational - imagine you're explaining the changes to a teammate over coffee. No need to be super formal or use fancy words. Just explain what you did and why in a way that makes sense. Skip any corporate-speak or overly professional language. If something's a quick fix or cleanup, just say that. IMPORTANT: Return ONLY the filled template - no markdown code blocks, no 'Based on...' intro, no explanations. Just start with '# Summary' and fill in the template." > "$temp_file" 2>&1 &

      claude_pid=$!

      show_spinner $claude_pid "Generating PR description with Claude"
      wait $claude_pid 2>/dev/null
      local claude_exit_code=$?
      set -m
    fi

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

    if ! gh pr edit "$pr_number" --body-file "$temp_file"; then
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

  # Retry mode: skip Claude, just re-attempt the PR update
  if [ -n "$retry_file" ]; then
    if [ ! -f "$retry_file" ]; then
      echo "❌ File not found: $retry_file"
      return 1
    fi

    echo "🔄 Retry mode: using saved description from $retry_file"

    # Find the PR
    find_current_pr || return 1

    # Use the provided file as temp_file
    temp_file="$retry_file"

    # Go straight to review and update
    review_description_in_editor || return 0
    update_pr_description
    return $?
  fi

  # Normal mode: generate description with Claude
  determine_merge_target || return 1

  # Count words in the diff
  if ! diff_content=$(git diff "$merge_target"...HEAD 2>/dev/null); then
    echo "❌ Error: Could not generate git diff between '$merge_target' and '$current_branch'"
    return 1
  fi
  char_count=$(echo "$diff_content" | wc -c | xargs)

  echo "Analyzing changes on branch '$current_branch' vs '$merge_target'... $char_count chars changed."

  # Check if there are any changes to process
  if [ "$char_count" -eq 0 ]; then
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

  # Always show the temp file location for --retry
  echo "📄 Description saved to: $temp_file"

  # Check if interrupted after Claude
  if [ "$interrupted" = true ]; then
    return 1
  fi

  review_description_in_editor || return 0
  update_pr_description
}
