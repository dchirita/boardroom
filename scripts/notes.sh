#!/usr/bin/env bash
# Copies notes folders (reports, research; not code) into the workspace, read-only.
#
#   notes.sh <workspace> <dir> [<dir> ...]
#
# Each folder lands in <workspace>/.snap/notes/<folder name>/ and is cited as `notes:<folder name>/<path>:<line>`.
# Only text files are copied; secret-like files are skipped. Two folders with the same name are an error.
set -euo pipefail

ws=${1:?workspace}; shift
case "$ws" in /*) ;; *) ws="$(cd "$ws" && pwd)" ;; esac
dest="$ws/.snap/notes"
rm -rf "$dest"; mkdir -p "$dest"

seen=" "
for dir in "$@"; do
  case "$dir" in /*) src="$dir" ;; "~/"*) src="$HOME/${dir#\~/}" ;; *) src="$ws/$dir" ;; esac
  [ -d "$src" ] || { echo "warning: notes folder $dir not found, skipped" >&2; continue; }
  src=$(cd "$src" && pwd)
  name=$(basename "$src")
  case "$src/" in "$ws/"*) echo "error: notes folder $dir is inside the workspace" >&2; exit 2 ;; esac
  case "$seen" in *" $name "*) echo "error: two notes folders are named '$name'; rename one" >&2; exit 2 ;; esac
  seen="$seen$name "
  rsync -a --prune-empty-dirs \
    --exclude '.git/' --exclude '*.p8' --exclude '*.pem' --exclude '*.key' --exclude '.env*' \
    --include '*/' --include '*.md' --include '*.txt' --include '*.csv' --include '*.json' --exclude '*' \
    "$src/" "$dest/$name/"
  echo "notes: $dir -> .snap/notes/$name ($(find "$dest/$name" -type f | awk 'END { print NR }') files)"
done
