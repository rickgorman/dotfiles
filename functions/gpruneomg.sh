#!/bin/bash

# prune stale local branches in a rather destructive way
gpruneomg () {
  git fetch -p

  echo "# WARNING: CLOSING THIS EDITOR WILL FORCEFULLY REMOVE THESE LOCAL BRANCHES" >  /tmp/branches_to_prune.txt
  echo "#"                                                                          >> /tmp/branches_to_prune.txt
  echo "# Please be sure to remove entries that you do not wish to prune. "         >> /tmp/branches_to_prune.txt
  echo "# Recovery will be full of pain and regret."                                >> /tmp/branches_to_prune.txt
  echo "\n"                                                                         >> /tmp/branches_to_prune.txt

  branches=`git for-each-ref --format '%(refname) %(upstream:track)' refs/heads | awk '$2 == "[gone]" {sub("refs/heads/", "", $1); print $1}'`

  echo $branches | while read -r branch
  do
    echo "branch -D $branch" >> /tmp/branches_to_prune.txt
  done

  $VISUAL /tmp/branches_to_prune.txt --wait

  cat /tmp/branches_to_prune.txt | grep -v "#" | xargs -L 1 git
}