#!/usr/bin/env bash
# Checks that every citation in a meeting file points at a real line in the snapshot.
#
#   check-citations.sh <workspace> <meeting.md>
#
# A citation is `<id>:<path>:<line>` or `<id>:<path>:<from>-<to>` in backticks, where <id> is a product id
# with a snapshot in .snap/ or `notes`. Backticked text that looks similar but names no snapshot
# (`http://localhost:3000`, `12:30:00`) is not a citation and is ignored.
# Prints one line per broken citation and a summary.
# Exit 0 when all citations resolve, 1 when any is broken, 2 when the meeting cites nothing.
set -euo pipefail

ws=${1:?workspace}; file=${2:?meeting file}
snap="$ws/.snap"
[ -d "$snap" ] || { echo "citations: no snapshots in $snap, nothing to check"; exit 2; }
ok=0; bad=0

while IFS= read -r cite; do
  c=${cite#\`}; c=${c%\`}
  id=${c%%:*}; rest=${c#*:}
  lines=${rest##*:}; path=${rest%:*}
  from=${lines%%-*}; to=${lines##*-}
  if [ "$id" = "notes" ]; then
    root="$snap/notes"
  else
    root=$(find "$snap" -maxdepth 1 -type d -name "$id@*" | awk 'NR==1')
  fi
  [ -n "$root" ] && [ -d "$root" ] || continue
  if [ ! -f "$root/$path" ]; then
    echo "BROKEN $cite: file not in snapshot"; bad=$((bad + 1)); continue
  fi
  n=$(wc -l < "$root/$path" | tr -d ' ')
  [ -n "$(tail -c 1 "$root/$path")" ] && n=$((n + 1))
  if [ "$from" -lt 1 ] || [ "$to" -gt "$n" ] || [ "$from" -gt "$to" ]; then
    echo "BROKEN $cite: file has $n lines"; bad=$((bad + 1)); continue
  fi
  ok=$((ok + 1))
done < <(grep -oE '`[A-Za-z0-9_.-]+:[^`:]+:[0-9]+(-[0-9]+)?`' "$file" | sort -u || true)

echo "citations: $ok ok, $bad broken"
[ "$bad" -gt 0 ] && exit 1
[ "$ok" -eq 0 ] && exit 2
exit 0
