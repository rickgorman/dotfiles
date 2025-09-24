#!/bin/bash

# Auto-fill PR description using Claude Code
pr-autofill-description() {
  # Default exclusion patterns for non-code files
  local default_excludes=(
  '*.png'
  '*.jpg'
  '*.jpeg'
  '*.gif'
  '*.svg'
  '*.ico'
  '*.pdf'
  '*.zip'
  '*.tar'
  '*.gz'
  '*.bz2'
  '*.7z'
  '*.exe'
  '*.dll'
  '*.so'
  '*.dylib'
  '*.bin'
  '*.dat'
  '*.db'
  '*.sqlite'
  '*.mp3'
  '*.mp4'
  '*.mov'
  '*.avi'
  '*.mkv'
  '*.ttf'
  '*.woff'
  '*.woff2'
  '*.eot'
  '*.otf'
  'spec/vcr*'
  'spec/fixtures/vcr_cassettes/*'
  'test/vcr*'
  'test/fixtures/vcr_cassettes/*'
  '*.cassette'
  '*.yml.cassette'
  'vendor/*'
  'node_modules/*'
  '.git/*'
  'tmp/*'
  'log/*'
  'public/assets/*'
  'public/packs/*'
  'coverage/*'
  '*.min.js'
  '*.min.css'
  'yarn.lock'
  'package-lock.json'
  'Gemfile.lock'
  )

  local custom_excludes=()
  local exclude_flag_found=false

  # Parse command line arguments
  while [[ $# -gt 0 ]]; do
  case $1 in
  --exclude)
      exclude_flag_found=true
      if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
          # Split comma-separated values and add to custom_excludes
          local IFS=','
          local excludes_list=($2)
          for exclude in "${excludes_list[@]}"; do
              # Trim whitespace
              exclude=$(echo "$exclude" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
              custom_excludes+=("$exclude")
          done
          shift 2
      else
          echo "Error: --exclude requires a value (e.g., --exclude '*.yml,spec/long_file.rb')"
          return 1
      fi
      ;;
  *)
      echo "Unknown option: $1"
      echo "Usage: pr-autofill-description [--exclude 'pattern1,pattern2,pattern3']"
      return 1
      ;;
  esac
  done

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

  # Try to get the merge target from existing PR first
  merge_target=$(gh pr view --json baseRefName --jq '.baseRefName' 2>/dev/null)

  if [ -z "$merge_target" ]; then
  # If no PR exists, detect the upstream branch like newpr does
  local git_status_output=$(git status 2>/dev/null)
  local upstream_match=$(echo "$git_status_output" | grep -o "Your branch is ahead of '[^']*'" | sed "s/Your branch is ahead of '\([^']*\)'.*/\1/")

  if [ -n "$upstream_match" ]; then
  merge_target="$upstream_match"
  # Strip origin/ prefix if present
  merge_target=$(echo "$merge_target" | sed 's|^origin/||')
  else
  # Fallback to default branch
  merge_target=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@' 2>/dev/null)
  if [ -z "$merge_target" ]; then
      # Final fallback to common branch names
      if git show-ref --verify --quiet refs/remotes/origin/main; then
          merge_target="main"
      elif git show-ref --verify --quiet refs/remotes/origin/master; then
          merge_target="master"
      else
          echo "Error: Could not determine merge target branch"
          return 1
      fi
  fi
  fi
  fi

  echo "Analyzing changes on branch '$current_branch' vs '$merge_target'..."

  # Build git pathspec exclusions as an array
  local git_excludes=()
  for pattern in "${default_excludes[@]}"; do
  git_excludes+=(":(exclude)$pattern")
  done
  for pattern in "${custom_excludes[@]}"; do
  git_excludes+=(":(exclude)$pattern")
  done

  # Get the diff and count words
  echo "Checking diff size..."
  local diff_content=$(git diff "$merge_target"...HEAD -- "${git_excludes[@]}")
  local word_count=$(echo "$diff_content" | wc -w | xargs)

  echo "Total word count: $word_count (excluding non-code files)"

  # Check if word count is 0
  if [ "$word_count" -eq 0 ]; then
  echo ""
  echo "❌ Error: No changes found in diff"
  echo ""
  echo "This could mean:"
  echo "  - No actual changes between '$merge_target' and '$current_branch'"
  echo "  - All changes are excluded by your exclusion patterns"
  echo "  - You're comparing the same branch against itself"
  echo ""
  echo "Current exclusions are excluding all files. Try with fewer exclusions."
  return 1
  fi

  # Check if word count exceeds 15K
  if [ "$word_count" -gt 20000 ]; then
  echo ""
  echo "❌ Error: The PR diff is too large ($word_count words, limit is 20,000)"
  echo ""
  echo "Files with most changes:"
  echo "------------------------"

  # Show files sorted by lines changed
  git diff "$merge_target"...HEAD --stat --stat-width=120 -- "${git_excludes[@]}" | head -20

  echo ""
  echo "To see word counts by file:"
  echo "  git diff $merge_target...HEAD --name-only -- ${git_excludes[*]} | while read f; do echo \"\$(git diff $merge_target...HEAD -- \"\$f\" | wc -w) \$f\"; done | sort -rn | head -20"

  echo ""
  echo "You can exclude specific files or patterns using the --exclude flag:"
  echo "  pr-autofill-description --exclude 'path/to/large_file.rb,*.generated.rb,spec/fixtures/*'"
  echo ""
  echo "Current exclusions include: VCR cassettes, images, binaries, vendor/, node_modules/, etc."

  return 1
  fi

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
  cat "$template_file" 2>/dev/null
  echo ""
  echo "---"
  echo ""
  echo "Here are the git changes:"
  echo ""
  echo "$diff_content"
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
