#!/bin/bash

# Combined newpr and pr-autofill-description function
newpra() {
    echo "Creating PR..."

    # Run newpr with any passed arguments
    if ! newpr "$@"; then
        echo "❌ Failed to create PR"
        return 1
    fi

    echo "Waiting for PR to be available..."

    # Wait for PR to exist with a timeout
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if gh pr view --json number --jq '.number' >/dev/null 2>&1; then
            echo "✅ PR is available"
            break
        fi

        attempt=$((attempt + 1))
        echo "Waiting for PR... (attempt $attempt/$max_attempts)"
        sleep 1
    done

    # Check if we timed out
    if [ $attempt -eq $max_attempts ]; then
        echo "❌ Timeout waiting for PR to be available"
        return 1
    fi

    echo "Auto-filling PR description..."

    # Run pr-autofill-description
    if pr-autofill-description; then
        echo "✅ PR created and description auto-filled!"
    else
        echo "❌ Failed to auto-fill description, but PR was created successfully"
        return 1
    fi
}