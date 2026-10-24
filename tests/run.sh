#!/usr/bin/env bash
# Tests for the boardroom scripts. Builds a throwaway product repo and workspace, then checks:
# snapshot from the reference branch only, redaction, media exclusion, work-in-progress detection,
# caching, refresh on a new commit, product repo untouched, notes copy and the citation checker.
#
#   tests/run.sh            (needs only bash, git, rsync)
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
scripts="$here/../scripts"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

# Fixture: a product repo with a planted issue, a secret, a media file and two branches.
# The "private key" and the premium-header bug below are fake test data, written to a temp dir.
repo="$tmp/shop"
git init -q -b main "$repo"
git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
mkdir -p "$repo/src" "$repo/assets" "$repo/keys"
printf '# Shop\nSells things.\n' > "$repo/README.md"
printf 'line1\nif (req.header("x-premium") === "yes") { premium = true }\nline3\n' > "$repo/src/auth.js"
printf -- '-----BEGIN PRIVATE KEY-----\nsecret\n' > "$repo/keys/AuthKey_TEST.p8"
printf 'API_KEY=example\n' > "$repo/.env.example"
printf 'binary' > "$repo/assets/logo.png"
printf '{ "name": "shop", "version": "1.2.3" }\n' > "$repo/package.json"
git -C "$repo" add -A; git -C "$repo" commit -qm "initial"
git -C "$repo" checkout -q -b small-fix
echo "fix" > "$repo/src/fix.js"; git -C "$repo" add -A; git -C "$repo" commit -qm "small fix"
git -C "$repo" checkout -q -b big-feature main
for i in $(seq 1 35); do echo "$i" > "$repo/src/f$i.js"; done
git -C "$repo" add -A; git -C "$repo" commit -qm "big feature"
# Leave the repo on a side branch with uncommitted work, like a live dev session.
echo "dirty" >> "$repo/README.md"
before=$(git -C "$repo" status --porcelain; git -C "$repo" branch --show-current)

ws="$tmp/hq"; mkdir -p "$ws"
out=$("$scripts/snapshot.sh" "$ws" shop "$repo" main)
snap=$(find "$ws/.snap" -maxdepth 1 -type d -name 'shop@*')
facts="$ws/.snap/shop.facts.md"

check "snapshot created from main" '[ -n "$snap" ] && [ -f "$snap/src/auth.js" ]'
check "side-branch files not in snapshot" '[ ! -f "$snap/src/f1.js" ] && [ ! -f "$snap/src/fix.js" ]'
check "uncommitted work not in snapshot" '! grep -q dirty "$snap/README.md"'
check "media left out" '[ ! -f "$snap/assets/logo.png" ]'
check "secret kept by name, content redacted" 'grep -q "^REDACTED by boardroom" "$snap/keys/AuthKey_TEST.p8" && ! grep -q "PRIVATE KEY" "$snap/keys/AuthKey_TEST.p8"'
check "example env file not redacted" 'grep -q API_KEY "$snap/.env.example"'
check "facts list the redacted file" 'grep -q "keys/AuthKey_TEST.p8" "$facts"'
check "facts read the version" 'grep -q "Version: 1.2.3" "$facts"'
check "large branch flagged" 'grep "big-feature" "$facts" | grep -q LARGE'
check "small branch listed, not flagged" 'grep "small-fix" "$facts" | grep -vq LARGE'
check "first run not cached" 'echo "$out" | grep -q "cached=no"'
check "second run cached" '"$scripts/snapshot.sh" "$ws" shop "$repo" main | grep -q "cached=yes"'
check "product repo untouched" '[ "$before" = "$(git -C "$repo" status --porcelain; git -C "$repo" branch --show-current)" ]'

# A new commit on main gives a new snapshot and removes the old one.
git -C "$repo" stash -q; git -C "$repo" checkout -q main
echo "v2" >> "$repo/README.md"; git -C "$repo" commit -qam "v2"
"$scripts/snapshot.sh" "$ws" shop "$repo" main >/dev/null
check "refresh on new commit, old snapshot removed" '[ "$(find "$ws/.snap" -maxdepth 1 -type d -name "shop@*" | wc -l | tr -d " ")" = 1 ] && grep -q v2 "$ws"/.snap/shop@*/README.md'
check "missing branch is an error" '! "$scripts/snapshot.sh" "$ws" shop "$repo" nope 2>/dev/null'

# Git URL source: the board keeps its own bare clone and fetches it on every run.
url="file://$repo"
"$scripts/snapshot.sh" "$ws" shopurl "$url" main >/dev/null
check "URL source cloned into .repos" '[ "$(git -C "$ws/.repos/shopurl.git" rev-parse --is-bare-repository)" = true ]'
check "URL source snapshot from main" 'grep -q v2 "$ws"/.snap/shopurl@*/README.md && [ ! -f "$ws"/.snap/shopurl@*/src/f1.js ]'
check "URL source lists pushed branches" 'grep "big-feature" "$ws/.snap/shopurl.facts.md" | grep -q LARGE'
git -C "$repo" checkout -q main; echo "v3" >> "$repo/README.md"; git -C "$repo" commit -qam "v3"
"$scripts/snapshot.sh" "$ws" shopurl "$url" main >/dev/null
check "URL source fetches new commits" 'grep -q v3 "$ws"/.snap/shopurl@*/README.md'
check "bad URL is an error" '! "$scripts/snapshot.sh" "$ws" nope "file:///nonexistent/repo.git" main 2>/dev/null'
mkdir -p "$tmp/home"; git clone -q "$repo" "$tmp/home/shop"
check "~/ path source works" 'HOME="$tmp/home" "$scripts/snapshot.sh" "$ws" shophome "~/shop" main >/dev/null'
mv "$tmp/shop" "$tmp/shop-moved"
check "unreachable URL uses the last fetch" '"$scripts/snapshot.sh" "$ws" shopurl "$url" main 2>/dev/null >/dev/null && grep -q "Fetch failed" "$ws/.snap/shopurl.facts.md"'
mv "$tmp/shop-moved" "$tmp/shop"

# Hard cases: orphan branch, branch and tag with the same name, a branch far ahead, a git filter, a symlink.
hard="$tmp/hard"
git init -q -b main "$hard"; git -C "$hard" config user.email t@t; git -C "$hard" config user.name t
mkdir -p "$hard/src"; printf 'secret value\n' > "$tmp/live-secret.env"
printf 'plain\n' > "$hard/src/app.js"; printf 'enc\n' > "$hard/src/vault.txt"
printf 'src/vault.txt filter=crypt\n' > "$hard/.gitattributes"
printf 'node_modules\nbuild/\n' > "$hard/.gitignore"
ln -s "$tmp/live-secret.env" "$hard/link.txt"
git -C "$hard" add -A; git -C "$hard" commit -qm "initial"
git -C "$hard" checkout -q --orphan gh-pages; git -C "$hard" rm -rqf .; echo page > "$hard/index.html"
git -C "$hard" add -A; git -C "$hard" commit -qm "pages"
git -C "$hard" checkout -q -f -b release/1.0 main; mkdir -p "$hard/src"; echo r > "$hard/src/r.js"; git -C "$hard" add -A; git -C "$hard" commit -qm "release"
git -C "$hard" tag release/1.0 main
git -C "$hard" checkout -q -b long main
for i in $(seq 1 900); do git -C "$hard" commit -q --allow-empty -m "c$i"; done
git -C "$hard" checkout -q main
# The filter is configured only now, so it could run only if the snapshot ran it.
git -C "$hard" config filter.crypt.smudge "sh -c 'touch $tmp/filter-ran; echo DECRYPTED'"
touch "$tmp/marker"; sleep 1
hfacts=$("$scripts/snapshot.sh" "$ws" hard "$hard" main | cut -d' ' -f1)
hsnap=$(find "$ws/.snap" -maxdepth 1 -type d -name 'hard@*')
check "orphan, same-name tag and long branch do not abort" 'grep -q "gh-pages" "$hfacts" && grep "release/1.0" "$hfacts" | grep -q "| 1 |" && grep "long" "$hfacts" | grep -q "| 900 |"'
check "facts file complete" 'grep -q "## Redacted secret-like files" "$hfacts"'
check "git filter not run, content raw" '[ ! -e "$tmp/filter-ran" ] && grep -q "^enc" "$hsnap/src/vault.txt"'
check "symlink replaced by a note" '[ ! -L "$hsnap/link.txt" ] && grep -q "^SYMLINK" "$hsnap/link.txt" && ! grep -q "secret value" "$hsnap/link.txt"'
check "product ignore file renamed" '[ ! -f "$hsnap/.gitignore" ] && [ -f "$hsnap/.gitignore.from-repo" ]'
check "nothing written in the product .git" '[ -z "$(find "$hard/.git" -newer "$tmp/marker" -print)" ]'

# Notes.
mkdir -p "$tmp/reports"; printf 'a\nb\n' > "$tmp/reports/growth plan.md"; printf 'x' > "$tmp/reports/chart.png"
"$scripts/notes.sh" "$ws" ../reports >/dev/null
check "notes copied, text only" '[ -f "$ws/.snap/notes/reports/growth plan.md" ] && [ ! -f "$ws/.snap/notes/reports/chart.png" ]'
mkdir -p "$tmp/other/reports"
check "two notes folders with the same name are an error" '! "$scripts/notes.sh" "$ws" ../reports ../other/reports >/dev/null 2>&1'
"$scripts/notes.sh" "$ws" ../reports >/dev/null

# Citation checker.
printf 'Good: `shop:src/auth.js:2` and `shop:src/auth.js:1-3` and `notes:reports/growth plan.md:2`.\n' > "$tmp/good.md"
printf 'Bad: `shop:src/auth.js:99` and `shop:src/missing.js:1`.\n' > "$tmp/bad.md"
printf 'Not citations: `http://localhost:3000` `redis://cache:6379` `12:30:00`, but `shop:src/auth.js:2` is.\n' > "$tmp/lookalike.md"
printf 'Nothing cited.\n' > "$tmp/none.md"
check "valid citations pass" '"$scripts/check-citations.sh" "$ws" "$tmp/good.md" >/dev/null'
check "broken citations fail" '! "$scripts/check-citations.sh" "$ws" "$tmp/bad.md" >/dev/null && [ "$("$scripts/check-citations.sh" "$ws" "$tmp/bad.md" | grep -c BROKEN)" = 2 ]'
check "look-alikes are not citations" '"$scripts/check-citations.sh" "$ws" "$tmp/lookalike.md" | grep -q "1 ok, 0 broken"'
set +e; "$scripts/check-citations.sh" "$ws" "$tmp/none.md" >/dev/null; rc=$?; set -e
check "no citations is reported" '[ "$rc" = 2 ]'

echo
[ "$fails" -eq 0 ] && echo "all tests passed" || { echo "$fails failed"; exit 1; }
