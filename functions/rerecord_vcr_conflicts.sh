#!/bin/bash

rerecord_vcr_conflicts() {
  # Get all unmerged VCR cassette files
  local unmerged_vcr_files=$(git diff --name-only --diff-filter=U | grep 'spec/vcr_cassettes/.*\.yml$')

  if [ -z "$unmerged_vcr_files" ]; then
    echo "No VCR cassette conflicts found."
    return 0
  fi

  echo "Found VCR cassette conflicts:"
  echo "$unmerged_vcr_files"
  echo ""

  local file_count=$(echo "$unmerged_vcr_files" | wc -l | tr -d ' ')
  echo "Total: $file_count conflicted cassette(s)"
  echo ""

  # Delete the conflicted cassettes
  echo ""
  echo "Deleting conflicted cassettes..."
  while IFS= read -r cassette_file; do
    rm -f "$cassette_file"
    echo "  Deleted: $cassette_file"
  done <<< "$unmerged_vcr_files"

  echo ""
  echo "Running test suite to re-record cassettes..."
  echo "Using: bundle exec rails parallel:spec"
  echo ""

  bundle exec rails parallel:spec

  local exit_code=$?

  if [ $exit_code -eq 0 ]; then
    echo ""
    echo "✅ Successfully re-recorded VCR cassettes!"
    echo ""
    echo "Next steps:"
    echo "  1. Review the changes: git status"
    echo "  2. Stage the cassettes: git add spec/vcr_cassettes/"
    echo "  3. Continue the rebase: git rebase --continue"
  else
    echo ""
    echo "❌ Test suite failed with exit code $exit_code"
    echo "You may need to fix failing tests before continuing the rebase."
  fi

  return $exit_code
}
