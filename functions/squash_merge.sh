#!/bin/bash

squash_merge() {
  local BASE_BRANCH="${MASTER_BRANCH_NAME:-main}"

  # Auto-detect upstream branch if not provided
  if [ -n "$1" ]; then
    BASE_BRANCH=$1
  else
    # Try to detect from git status
    local upstream_match=$(git status 2>/dev/null | grep -o "Your branch is ahead of '[^']*'" | sed "s/Your branch is ahead of '\([^']*\)'.*/\1/")
    if [ -n "$upstream_match" ]; then
      BASE_BRANCH=$(echo "$upstream_match" | sed "s|origin/||")
    elif git rev-parse --verify develop >/dev/null 2>&1; then
      BASE_BRANCH="develop"
    elif git rev-parse --verify main >/dev/null 2>&1; then
      BASE_BRANCH="main"
    elif git rev-parse --verify master >/dev/null 2>&1; then
      BASE_BRANCH="master"
    fi
  fi

  echo "Using base branch: $BASE_BRANCH"

  # Capture commit messages with full body BEFORE reset
  local TEMP_FILE=$(mktemp)
  git log --reverse --format='- %s%n%b' $(git merge-base HEAD "$BASE_BRANCH")..HEAD | sed '/^$/d' > "$TEMP_FILE"

  # Reset and commit with editor
  git reset --soft $(git merge-base HEAD "$BASE_BRANCH") && \
  git commit -eF "$TEMP_FILE" && \
  git rebase "$BASE_BRANCH"

  # Clean up
  rm "$TEMP_FILE"
}