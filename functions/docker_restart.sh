#!/bin/bash

docker_restart() {
  echo "Fetching running container IDs..."
  # Get an array of running container IDs
  ids=($(docker ps -q))

  if [ ${#ids[@]} -gt 0 ]; then
    echo "Found running containers: ${ids[*]}"
    # Iterate over each container ID and handle in parallel
    for id in "${ids[@]}"; do
      {
        echo "Stopping container $id..."
        docker stop "$id"
        if [ $? -eq 0 ]; then
          echo "Container $id stopped successfully."
        else
          echo "Failed to stop container $id."
          continue
        fi

        # Adding a short delay to ensure the container stops properly
        sleep 2

        echo "Starting container $id..."
        docker start "$id"
        if [ $? -eq 0 ]; then
          echo "Container $id started successfully."
        else
          echo "Failed to start container $id."
        fi
      } & # Run each block in the background
    done

    # Wait for all background jobs to finish
    wait
    echo "All containers have been restarted."
  else
    echo "No running containers to restart."
  fi
}