#!/bin/bash

newpr () {
  local BASE_BRANCH="${MASTER_BRANCH_NAME}"

  if [ -n "$1" ]; then
    BASE_BRANCH=$1
  else
    # Check if current branch has a different upstream branch
    local git_status_output=$(git status 2>/dev/null)
    local upstream_match=$(echo "$git_status_output" | grep -o "Your branch is ahead of '[^']*'" | sed "s/Your branch is ahead of '\([^']*\)'.*/\1/")

    if [ -n "$upstream_match" ]; then
      BASE_BRANCH="$upstream_match"
      echo "Detected upstream branch: $BASE_BRANCH"
    fi
  fi

  # Create a temporary file to hold the commit log in Markdown format.
  local TEMP_FILE=$(mktemp)

  # Capture commit logs into the temporary file with Markdown formatting.
  git log "${BASE_BRANCH}..HEAD" --pretty=format:"%s%n---%n%b%n%n" > "${TEMP_FILE}"

  # Create the PR using the temporary file as the body, formatted in Markdown.
  gh pr create --fill -B "${BASE_BRANCH}" --body-file "${TEMP_FILE}" && gh pr ready --undo && gh pr view --web

  # Clean up the temporary file.
  rm "${TEMP_FILE}"
}