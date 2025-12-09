#!/bin/bash

update_ruby_version() {
  if ! command -v asdf &> /dev/null; then
    echo "Error: asdf is not installed or not in the PATH."
    return 1
  fi

  if [[ ! -f .ruby-version ]]; then
    echo "Error: .ruby-version not found. You're in the wrong directory, dude."
    return 1
  fi

  ruby_version=$(cat .ruby-version | sed 's/^ruby-//')

  echo "running asdf plugin update ruby..."
  asdf plugin update ruby

  echo "running asdf install ruby $ruby_version..."
  if ! asdf install ruby "$ruby_version"; then
    echo "Error: Failed to install Ruby version $ruby_version with asdf."
    return 1
  fi

  # Step 6: Set the local Ruby version
  asdf local ruby "$ruby_version"

  # Step 7: Set the global Ruby version
  asdf global ruby "$ruby_version"

  echo "Ruby version $ruby_version installed and set (local and global)."
}
