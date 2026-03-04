#!/usr/bin/env bash

_worktree_resolve() {
  local name="$1"

  local results
  results=$(git worktree list --porcelain | awk -v pattern="$name" '
    /^worktree / { path = substr($0, 10) }
    /^branch /   { branch = substr($0, 8)
                   if (index(branch, pattern) || index(path, pattern)) {
                     print path "|" branch
                   } }
  ')

  if [[ -z "$results" ]]; then
    echo "Error: no worktree matching '$name'" >&2
    echo "" >&2
    git worktree list >&2
    return 1
  fi

  local count
  count=$(echo "$results" | wc -l | tr -d ' ')

  if [[ "$count" -gt 1 ]]; then
    echo "Error: '$name' matches multiple worktrees:" >&2
    echo "" >&2
    echo "$results" | while IFS='|' read -r path _; do
      git worktree list | grep "$path"
    done >&2
    return 1
  fi

  echo "$results"
}

worktree() {
  local cmd="${1:-status}"

  case "$cmd" in
    help|-h|--help)
      echo "Usage: worktree [command]"
      echo ""
      echo "Commands:"
      echo "  new <branch>      Create a worktree + branch in one step"
      echo "  yolo <name>       Launch cc --yolo in a worktree"
      echo "  done <name>       Push + create PR (post-yolo one-shot)"
      echo "  status            Dashboard of all worktrees"
      echo "  list              List all worktrees (default)"
      echo "  -- <name>         Switch to the named worktree"
      echo "  top               Go back to the main (non-worktree) repo root"
      echo "  teleport          Relocate container worktrees to the host"
      echo "  pr <name>         Open or create a PR for the worktree"
      echo "  pr push <name>    Push the worktree branch to remote"
      echo "  help              Show this help message"
      return 0
      ;;

    list)
      git worktree list
      ;;

    new)
      local branch_name="$2"
      if [[ -z "$branch_name" ]]; then
        echo "Error: branch name required"
        echo "Usage: worktree new <branch-name>"
        return 1
      fi

      local repo_root
      repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
      if [[ -z "$repo_root" ]]; then
        echo "Error: not in a git repository"
        return 1
      fi

      local default_branch
      default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
      if [[ -z "$default_branch" ]]; then
        echo "Error: could not detect default branch. Try 'git fetch origin' first."
        return 1
      fi

      local wt_path="$repo_root/.claude/worktrees/$branch_name"

      # Check if branch is already checked out in an existing worktree
      local existing_wt
      existing_wt=$(git worktree list --porcelain \
        | grep -B2 "branch refs/heads/${branch_name}$" \
        | head -1 | sed 's/^worktree //')

      if [[ -n "$existing_wt" ]]; then
        echo "Worktree already exists at $existing_wt, switching to it..."
        cd "$existing_wt" || return 1
        return 0
      fi

      if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
        echo "Creating worktree with existing branch $branch_name..."
        git worktree add "$wt_path" "$branch_name"
      else
        echo "Creating worktree with new branch $branch_name from $default_branch..."
        git worktree add -b "$branch_name" "$wt_path" "$default_branch"
      fi

      if [[ $? -ne 0 ]]; then
        echo "Error: failed to create worktree"
        return 1
      fi

      # Copy .env files from repo root into worktree
      for env_file in "$repo_root"/.env "$repo_root"/.env.*; do
        if [[ -f "$env_file" ]]; then
          cp "$env_file" "$wt_path/"
          echo "Copied $(basename "$env_file") to worktree"
        fi
      done

      cd "$wt_path" || return 1
      echo "Switched to worktree: $wt_path"
      ;;

    yolo)
      local name="$2"
      if [[ -z "$name" ]]; then
        echo "Error: worktree name required"
        echo "Usage: worktree yolo <name>"
        return 1
      fi

      local result
      result=$(_worktree_resolve "$name") || return 1

      local wt_path
      wt_path=$(echo "$result" | cut -d'|' -f1)

      cd "$wt_path" || return 1
      echo "Switched to worktree: $wt_path"
      cc --yolo
      ;;

    status)
      local main_path
      main_path=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')

      echo ""
      printf "%-30s  %-7s  %-7s  %s\n" "BRANCH" "DIRTY" "AHEAD" "PR"
      printf "%-30s  %-7s  %-7s  %s\n" "------" "-----" "-----" "--"

      git worktree list --porcelain | awk '
        /^worktree / { path = substr($0, 10) }
        /^branch /   { branch = substr($0, 8); print path "|" branch }
      ' | while IFS='|' read -r wt_path wt_branch; do
        # Skip main worktree
        [[ "$wt_path" == "$main_path" ]] && continue

        wt_branch=${wt_branch#refs/heads/}

        # Dirty/clean
        local dirty="clean"
        if [[ -n $(git -C "$wt_path" status --porcelain 2>/dev/null) ]]; then
          dirty="dirty"
        fi

        # Commits ahead of origin
        local ahead="--"
        if git rev-parse --verify "origin/$wt_branch" &>/dev/null; then
          ahead=$(git rev-list --count "origin/$wt_branch..$wt_branch" 2>/dev/null || echo "--")
        else
          ahead="new"
        fi

        # PR status
        local pr_status="none"
        local pr_info
        pr_info=$(gh pr view "$wt_branch" --json state,isDraft --jq '
          if .isDraft then "draft"
          elif .state == "MERGED" then "merged"
          elif .state == "OPEN" then "open"
          elif .state == "CLOSED" then "closed"
          else "none"
          end
        ' 2>/dev/null)
        if [[ -n "$pr_info" ]]; then
          pr_status="$pr_info"
        fi

        printf "%-30s  %-7s  %-7s  %s\n" "$wt_branch" "$dirty" "$ahead" "$pr_status"
      done

      echo ""
      ;;

    done)
      local name="$2"
      if [[ -z "$name" ]]; then
        echo "Error: worktree name required"
        echo "Usage: worktree done <name>"
        return 1
      fi

      local result
      result=$(_worktree_resolve "$name") || return 1

      local wt_path wt_branch
      wt_path=$(echo "$result" | cut -d'|' -f1)
      wt_branch=$(echo "$result" | cut -d'|' -f2)
      wt_branch=${wt_branch#refs/heads/}

      # Teleport if the worktree path doesn't exist on host
      if [[ ! -d "$wt_path" ]]; then
        echo "Worktree path not found on host, teleporting..."
        worktree teleport
        # Re-resolve after teleport
        result=$(_worktree_resolve "$name") || return 1
        wt_path=$(echo "$result" | cut -d'|' -f1)
      fi

      # Push
      echo "Pushing $wt_branch..."
      git push -u origin "$wt_branch"

      # Check for existing PR
      local pr_url
      pr_url=$(gh pr view "$wt_branch" --json url --jq '.url' 2>/dev/null)

      if [[ -n "$pr_url" ]]; then
        echo "PR exists: $pr_url"
      else
        echo "Creating PR..."
        (cd "$wt_path" && newpra)
      fi
      ;;

    --)
      local name="$2"
      if [[ -z "$name" ]]; then
        echo "Error: worktree name required"
        echo "Usage: worktree -- <name>"
        return 1
      fi

      local result
      result=$(_worktree_resolve "$name") || return 1

      local wt_path
      wt_path=$(echo "$result" | cut -d'|' -f1)

      cd "$wt_path" || return 1
      echo "Switched to worktree: $wt_path"
      ;;

    top)
      local main_path
      main_path=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')

      if [[ -z "$main_path" ]]; then
        echo "Error: could not determine main worktree path"
        return 1
      fi

      cd "$main_path" || return 1
      echo "Switched to main worktree: $main_path"
      ;;

    teleport)
      local repo_root
      repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
      if [[ -z "$repo_root" ]]; then
        echo "Error: not in a git repository"
        return 1
      fi

      local git_dir
      git_dir=$(cd "$repo_root" && git rev-parse --absolute-git-dir 2>/dev/null)

      local found=0
      for wt_dir in "$git_dir"/worktrees/*/; do
        [[ -d "$wt_dir" ]] || continue

        local wt_name
        wt_name=$(basename "$wt_dir")

        local old_path
        old_path=$(sed 's|/\.git$||' "$wt_dir/gitdir")

        # skip worktrees that already exist on the host
        [[ -d "$old_path" ]] && continue

        local branch
        branch=$(cat "$wt_dir/HEAD")
        branch=${branch#ref: refs/heads/}

        local new_path="$repo_root/.claude/worktrees/$wt_name"

        echo "Teleporting: $wt_name"
        echo "  branch: $branch"
        echo "  from:   $old_path"
        echo "  to:     $new_path"

        # create the worktree checkout
        mkdir -p "$new_path"
        git --work-tree="$new_path" checkout "$branch" -- . 2>/dev/null

        # write the .git file pointing back to the worktree metadata
        echo "gitdir: $git_dir/worktrees/$wt_name" > "$new_path/.git"

        # update the gitdir in worktree metadata to point to new location
        echo "$new_path/.git" > "$wt_dir/gitdir"

        echo "  done."
        echo ""
        found=1
      done

      if [[ "$found" -eq 0 ]]; then
        echo "No container worktrees to teleport."
      fi
      ;;

    pr)
      local subcmd="$2"
      local name

      if [[ "$subcmd" == "push" ]]; then
        name="$3"
      else
        name="$2"
      fi

      if [[ -z "$name" ]]; then
        echo "Error: worktree name required"
        echo "Usage: worktree pr [push] <name>"
        return 1
      fi

      local result
      result=$(_worktree_resolve "$name") || return 1

      local wt_path wt_branch
      wt_path=$(echo "$result" | cut -d'|' -f1)
      wt_branch=$(echo "$result" | cut -d'|' -f2)
      wt_branch=${wt_branch#refs/heads/}

      if [[ "$subcmd" == "push" ]]; then
        echo "Pushing $wt_branch..."
        git push origin "$wt_branch"
        return $?
      fi

      # check if a PR already exists for this branch
      local pr_url
      pr_url=$(gh pr view "$wt_branch" --json url --jq '.url' 2>/dev/null)

      if [[ -n "$pr_url" ]]; then
        echo "PR exists: $pr_url"
        open "$pr_url"
      else
        echo "No PR found for $wt_branch, creating one..."
        git push -u origin "$wt_branch" 2>/dev/null

        (cd "$wt_path" && newpra)
      fi
      ;;

    *)
      echo "Error: unknown command '$cmd'"
      echo "Run 'worktree help' for usage"
      return 1
      ;;
  esac
}
