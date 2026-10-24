#!/usr/bin/env bash
# Copies one product's reference branch into the workspace, read-only, and writes its facts file.
#
#   snapshot.sh <workspace> <id> <source> [branch] [branch_files_limit] [branch_days_limit]
#
# - <source> is a local repo folder (absolute, ~/..., or relative to the workspace) or a git URL.
#   A URL is kept as the board's own bare clone in <workspace>/.repos/<id>.git, fetched on every run;
#   if the fetch fails, the last fetched state is used and the facts file says so.
# - Reads only from git (git archive, log, for-each-ref): never touches the product's working tree,
#   index or checked-out branch, so sessions working in the product are not affected. The product's
#   git filters (git-crypt, LFS and the like) are switched off, so nothing runs and nothing is decrypted.
# - The snapshot lives in <workspace>/.snap/<id>@<sha12>/ and is reused while the branch head is the same.
# - Media and vendored files are left out; secret-like files are kept by name but their content is replaced;
#   symlinks are replaced by a note naming their target.
# - Prints the path of the facts file: <workspace>/.snap/<id>.facts.md
set -euo pipefail

ws=${1:?workspace}; id=${2:?id}; repo=${3:?repo}; branch=${4:-main}
max_files=${5:-30}; max_days=${6:-14}
case "$ws" in /*) ;; *) ws="$(cd "$ws" && pwd)" ;; esac

# Never prompt for credentials: a prompt would hang the caller.
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}"

source=$repo
fetch_note=""
case "$repo" in
  *://*|git@*:*)
    repo="$ws/.repos/$id.git"
    if [ ! -d "$repo" ]; then
      mkdir -p "$ws/.repos"
      git clone -q --bare "$source" "$repo" || { rm -rf "$repo"; echo "error: cannot clone $source" >&2; exit 2; }
    fi
    if ! git -C "$repo" fetch -q --prune "$source" '+refs/heads/*:refs/heads/*'; then
      echo "warning: cannot fetch $source, using the last fetched state" >&2
      fetch_note="Fetch failed on $(date '+%Y-%m-%d %H:%M'): read as of the last successful fetch."
    fi
    ;;
  /*) ;;
  "~/"*) repo="$HOME/${repo#\~/}" ;;
  *) repo="$ws/$repo" ;;
esac
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { echo "error: $repo is not a git repository" >&2; exit 2; }
sha=$(git -C "$repo" rev-parse --verify -q "refs/heads/$branch^{commit}" || true)
[ -n "$sha" ] || { echo "error: branch '$branch' not found in $repo" >&2; exit 2; }
short=${sha:0:12}

snapdir="$ws/.snap"
dest="$snapdir/$id@$short"
facts="$snapdir/$id.facts.md"
mkdir -p "$snapdir"

excludes=()
for ext in mp3 wav m4a aac caf mp4 mov m4v png jpg jpeg gif heic webp tiff pdf psd sketch ai \
           ttf otf woff woff2 zip gz tgz xz car a dylib framework so jar; do
  excludes+=(":(exclude,glob,icase)**/*.$ext")
done
for dir in Pods node_modules build DerivedData vendor .build Carthage; do
  excludes+=(":(exclude,glob)**/$dir/**")
done
secret_globs='*.p8 *.p12 *.pem *.key *.keystore *.jks *.mobileprovision .env .env.* *.env GoogleService-Info.plist google-services.json credentials*.json .npmrc .netrc id_rsa* *.pfx'

# Switch off every filter driver: user/system config is ignored, and the repo's own drivers are overridden.
nofilter=()
while IFS= read -r key; do
  name=${key#filter.}; name=${name%.*}
  nofilter+=(-c "filter.$name.smudge=cat" -c "filter.$name.process=" -c "filter.$name.required=false")
done < <(git -C "$repo" config --local --name-only --get-regexp '^filter\..*\.(smudge|process|clean)$' 2>/dev/null || true)

if [ -d "$dest" ]; then
  cached=yes
else
  cached=no
  rm -rf "$dest.tmp"; mkdir -p "$dest.tmp"
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    git ${nofilter[@]+"${nofilter[@]}"} -C "$repo" archive "$sha" -- . "${excludes[@]}" | tar -x -C "$dest.tmp"
  mv "$dest.tmp" "$dest"
  for old in "$snapdir/$id@"*; do
    [ -d "$old" ] && [ "$old" != "$dest" ] && rm -rf "$old"
  done
fi

# Symlinks could point outside the snapshot (to live files); replace each with a note naming its target.
while IFS= read -r -d '' l; do
  target=$(readlink "$l" || true)
  rm -f "$l"
  printf 'SYMLINK in the repo, not followed by boardroom: -> %s\n' "$target" > "$l"
done < <(find "$dest" -type l -print0)

# Ignore files from the product would hide snapshot files from the members' search; keep them under another name.
while IFS= read -r -d '' g; do
  mv "$g" "$g.from-repo"
done < <(find "$dest" -type f \( -name .gitignore -o -name .ignore -o -name .rgignore \) -print0)

# Redact secret-like files (kept by name, so the board can still see that one is tracked in git).
redacted=()
while IFS= read -r -d '' f; do
  rel=${f#"$dest/"}
  case "$rel" in *.example|*.sample|*.template) continue ;; esac
  if [ "$(head -c 9 "$f" 2>/dev/null)" != "REDACTED " ]; then
    printf 'REDACTED by boardroom: secret-like file tracked in git at %s. Content removed from the snapshot.\n' "$short" > "$f"
  fi
  redacted+=("$rel")
done < <(set -f; args=(); for g in $secret_globs; do args+=(-o -name "$g"); done; find "$dest" -type f \( "${args[@]:1}" \) -print0)

total=$(git -C "$repo" ls-tree -r --name-only "$sha" | wc -l | tr -d ' ')
kept=$(find "$dest" -type f | wc -l | tr -d ' ')
now=$(date +%s)

version=""
if [ -f "$dest/package.json" ]; then
  version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$dest/package.json" | awk 'NR==1')
fi
if [ -z "$version" ]; then
  # Highest MARKETING_VERSION among the targets: the app's, not a test target's 1.0.
  version=$(find "$dest" -name project.pbxproj -exec sed -n 's/.*MARKETING_VERSION = "*\([0-9.]*\)"*;.*/\1/p' {} + 2>/dev/null \
    | sort -u -t. -k1,1n -k2,2n -k3,3n | awk 'END { print }')
fi

# One table row per branch not merged into the reference branch; a branch that fails to read gets a note, not an abort.
branch_row() {
  local b=$1 ahead files first last days flag base
  ahead=$(git -C "$repo" rev-list --count "$sha..refs/heads/$b" 2>/dev/null) || { echo "| \`$b\` | ? | ? | ? | (could not read) | |"; return; }
  [ "$ahead" -eq 0 ] && return
  if base=$(git -C "$repo" merge-base "$sha" "refs/heads/$b" 2>/dev/null); then
    files=$(git -C "$repo" diff --name-only "$base" "refs/heads/$b" | awk 'END { print NR }')
  else
    files=$(git -C "$repo" diff --name-only "$sha" "refs/heads/$b" 2>/dev/null | awk 'END { print NR }')
  fi
  first=$(git -C "$repo" log --format='%ct' "$sha..refs/heads/$b" | awk 'END { print }')
  last=$(git -C "$repo" log -1 --format='%cs %s' "refs/heads/$b" | cut -c1-70)
  days=$(( (now - ${first:-$now}) / 86400 ))
  flag=""
  if [ "$files" -gt "$max_files" ] || [ "$days" -gt "$max_days" ]; then flag="LARGE"; fi
  echo "| \`$b\` | $ahead | $files | $days days | $last | $flag |"
}

{
  echo "# $id"
  echo
  echo "- Source: \`$source\`"
  echo "- Read from: \`$branch\` @ \`$short\`, $(git -C "$repo" log -1 --format='%cs, "%s"' "$sha")"
  [ -n "$fetch_note" ] && echo "- $fetch_note"
  if git -C "$repo" rev-parse --verify -q "refs/remotes/origin/$branch" >/dev/null; then
    behind=$(git -C "$repo" rev-list --count "$sha..refs/remotes/origin/$branch")
    [ "$behind" -gt 0 ] && echo "- Local \`$branch\` is $behind commits behind \`origin/$branch\` (as of the last fetch in the product folder)."
  fi
  echo "- Snapshot: \`.snap/$id@$short/\` ($kept of $total tracked files; media and vendored files left out)"
  if git -C "$repo" show "$sha:.gitattributes" 2>/dev/null | grep -q export-ignore; then
    echo "- The repo marks some files \`export-ignore\` in \`.gitattributes\`: they are not in the snapshot."
  fi
  echo "- Version: ${version:-unknown}"
  echo "- Cite files as \`$id:<path>:<line>\`, paths relative to the snapshot."
  echo
  echo "## Last 10 commits on $branch"
  echo
  git -C "$repo" log -10 --format='- %cs %s' "$sha"
  echo
  echo "## Work in progress (branches not merged into $branch)"
  echo
  echo "Not read by the board. A branch is flagged LARGE above $max_files changed files or $max_days days open."
  echo
  echo "| Branch | Commits ahead | Files changed | Open since | Last commit | Flag |"
  echo "|---|---|---|---|---|---|"
  rows=$(git -C "$repo" for-each-ref --format='%(refname:lstrip=2)' refs/heads/ | while IFS= read -r b; do
    [ "$b" = "$branch" ] || branch_row "$b"
  done)
  if [ -n "$rows" ]; then echo "$rows"; else echo "| (none) | | | | | |"; fi
  echo
  if [ "$(git -C "$repo" rev-parse --is-bare-repository)" = "true" ]; then
    echo "Read from the remote: branches above are the pushed ones; local unpushed work is not visible."
  else
    current=$(git -C "$repo" branch --show-current)
    # fsmonitor and the untracked cache could run or write something configured in the product repo; switch them off.
    dirty=$(git --no-optional-locks -c core.fsmonitor=false -c core.untrackedCache=false -C "$repo" status --porcelain \
      | awk 'END { print NR }')
    echo "Checked out in the product folder now: \`${current:-detached}\`, $dirty uncommitted files."
  fi
  echo
  echo "## Documents"
  echo
  (cd "$dest" && find . -type f \( -iname '*.md' -o -iname '*.txt' \) | sed 's|^\./||' | sort | awk 'NR<=60 { print "- " $0 }')
  echo
  echo "## Redacted secret-like files"
  echo
  if [ "${#redacted[@]}" -eq 0 ]; then echo "- (none)"; else printf -- '- `%s` (tracked in git)\n' "${redacted[@]}"; fi
} > "$facts.tmp"
mv "$facts.tmp" "$facts"

echo "$facts (snapshot ${short}, cached=$cached)"
