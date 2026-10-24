#!/usr/bin/env bash
# Installs Boardroom into a workspace folder (created if missing).
#
#   ./install.sh <workspace folder>
#
# Then open the workspace in Claude Code, start a new session and run /boardroom:setup.
# The workspace reads Boardroom from this folder, so later edits here apply at the next session start.
set -euo pipefail

ws=${1:?usage: ./install.sh <workspace folder>}
here=$(cd "$(dirname "$0")" && pwd)

# Claude Code CLI: on PATH, or the copy bundled with the Claude desktop app.
claude_bin=$(command -v claude || true)
if [ -z "$claude_bin" ]; then
  claude_bin=$(ls -t "$HOME/Library/Application Support/Claude/claude-code/"*/*/claude.app/Contents/MacOS/claude 2>/dev/null | head -1 || true)
fi
[ -n "$claude_bin" ] || { echo "error: Claude Code CLI not found. Install Claude Code or the Claude desktop app." >&2; exit 1; }

mkdir -p "$ws"
cd "$ws"
case "$(pwd)/" in "$here/"*) echo "error: the workspace must be outside the Boardroom folder" >&2; exit 1 ;; esac

# Both commands are safe to repeat; running again after moving the folders re-registers the path.
"$claude_bin" plugin marketplace add "$here" --scope project
"$claude_bin" plugin install boardroom@boardroom --scope project
echo
echo "Boardroom is installed in $(pwd)."
echo "Next: open this folder in Claude Code, start a new session, and run /boardroom:setup"
