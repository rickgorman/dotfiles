#!/bin/bash

cc() {
  for arg in "$@"; do
    if [[ "$arg" == "--list-sessions" ]]; then
      _cc_list_sessions
      return $?
    fi
  done

  local yolo_bin="${HOME}/work/claude-yolo/bin/claude-yolo"
  if [[ -x "$yolo_bin" ]]; then
    "$yolo_bin" "$@"
  else
    claude "$@"
  fi
}

_cc_list_sessions() {
  local projects_dir="${HOME}/.claude/projects"

  if [[ ! -d "$projects_dir" ]]; then
    echo "No sessions found (${projects_dir} does not exist)"
    return 1
  fi

  local -a sorted_files=()
  while IFS= read -r f; do
    sorted_files+=("$f")
  done < <(
    find "$projects_dir" -maxdepth 2 -name "*.jsonl" -type f -print0 \
      | xargs -0 stat -f "%m %N" 2>/dev/null \
      | sort -rn \
      | head -20 \
      | sed 's/^[0-9]* //'
  )

  if [[ ${#sorted_files[@]} -eq 0 ]]; then
    echo "No sessions found"
    return 0
  fi

  local cols
  cols=$(tput cols 2>/dev/null || echo 120)

  # Separator line spanning terminal width
  local sep
  sep=$(python3 -c "print('─' * $cols)")

  local count=0
  for f in "${sorted_files[@]}"; do
    [[ $count -ge 10 ]] && break

    local uuid='' mtime='' cwd='' branch='' first_text='' repo='' linecount=''

    uuid=$(basename "$f" .jsonl)
    mtime=$(stat -f "%Sm" -t "%b %d %H:%M" "$f" 2>/dev/null || echo "?")

    # Use Python to extract cwd, gitBranch, and first user message in one pass.
    # Scans up to 100 lines because newer Claude Code files start with a
    # file-history-snapshot record on line 1 that has no cwd — the real
    # session metadata begins on line 2.  Outputs exactly three lines:
    # cwd, gitBranch, first_text (empty string if not found).
    {
      read -r cwd
      read -r branch
      read -r first_text
    } < <(
      head -100 "$f" | python3 -c "
import json, re, sys

cwd = ''
branch = ''
first_text = ''
candidates = []

for line in sys.stdin:
    try:
        d = json.loads(line)

        # cwd and gitBranch are top-level keys on any non-snapshot line
        if not cwd and 'cwd' in d:
            cwd = d['cwd']
            branch = d.get('gitBranch', '')

        # Collect user message text, cleaned up
        if d.get('type') == 'user' and 'message' in d:
            c = d['message'].get('content', '')
            text = ''
            if isinstance(c, str) and c and not c.startswith('<'):
                text = c
            elif isinstance(c, list):
                for block in c:
                    if isinstance(block, dict) and block.get('type') == 'text':
                        t = block.get('text', '')
                        if t and not t.startswith('<'):
                            text = t
                            break

            if text:
                # Strip markdown heading markers (e.g. '# Title' -> 'Title')
                text = re.sub(r'(?m)^#+\s+', '', text)
                # Collapse all whitespace/newlines to single spaces
                text = re.sub(r'\s+', ' ', text).strip()
                candidates.append(text)
                # Take it immediately if it's long enough to be meaningful
                if len(text) >= 20:
                    first_text = text
                    break
    except Exception:
        pass

# If nothing was long enough, fall back to the longest candidate found
if not first_text and candidates:
    first_text = max(candidates, key=len)

print(cwd)
print(branch)
print(first_text)
" 2>/dev/null
    )

    # Skip noise files (file-history-snapshot, queue-operation, etc.) with no cwd
    [[ -z "$cwd" ]] && continue

    repo=$(basename "$cwd")
    linecount=$(wc -l < "$f" 2>/dev/null | tr -d ' ')

    # Line 1: separator
    echo "$sep"
    # Line 2: date · repo · branch · linecount · hash
    printf "%s  %-16s  %-18s  %5sL  %s\n" \
      "$mtime" "$repo" "$branch" "$linecount" "$uuid"
    # Line 3: preview text, indented, truncated to terminal width
    printf "  %s\n" "${first_text:0:$((cols - 3))}"

    ((count++))
  done

  echo "$sep"
}
