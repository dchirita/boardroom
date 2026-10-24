---
name: setup
description: Set up or update a Boardroom workspace - find the product repos, ask the founder what the board needs to know, and write board.yml. Use when board.yml is missing, empty or incomplete, or when the user wants to add, remove or change products (paths, git URLs, branches), data commands, notes or company context.
allowed-tools:
  - Bash(${CLAUDE_PLUGIN_ROOT}/scripts/snapshot.sh *)
---

# Boardroom setup

You are setting up the current folder as a Boardroom workspace, or changing it. Keep it short: the founder should
be done in a few minutes. Ask only what you cannot find out yourself. Plugin scripts are in
`${CLAUDE_PLUGIN_ROOT}/scripts/`, templates in `${CLAUDE_PLUGIN_ROOT}/templates/`.

## Editing an existing workspace

If `board.yml` exists and the user asked for a specific change ("add git@github.com:org/app.git", "remove X",
"read shop from branch release", "switch app-1 to its git URL"), do just that: for a new product, look it up as in
step 1 (README, branch, classification) and confirm in one question; edit only the affected entry (section 3); run
the check (section 4) for that product only. Otherwise list what is filled in and what is missing, and ask only about
the missing parts or what the user wants to change.

## 1. Look before asking

- Where the products are: ask first (section 2, question 2) unless the user already said. Default candidates: the
  parent folder and this folder. The user may give other folders (any path, several) and/or git URLs.
- In each folder, find git repos one level down (`<folder>/*/.git`). For each: its reference branch (`main`, else
  `master`, else the default branch), last commit date and subject on that branch, the first lines of its README on
  that branch (`git -C <repo> show <branch>:README.md`), and its `origin` URL if any (`git -C <repo> remote get-url
  origin`). Read only from git; never check out, fetch or change anything in those repos.
- For a git URL the user gives: `git ls-remote --symref <url> HEAD` for the default branch; the README comes from the
  check in section 4.
- Classify each repo yourself as a likely product, shared infrastructure (servers, packages used by other repos) or
  not a product (archives, test data, scratch), and draft a one-sentence `about` from its README.
- Find candidate notes folders: non-git folders next to the repos that hold mostly Markdown (reports, research).
- Find candidate data commands: scripts in the repos that print metrics (for example a `metrics` script in a
  `package.json`). Read the script to confirm it only reads; never propose a command that writes or deploys.

## 2. Ask

Use the AskUserQuestion tool, at most four questions per call, recommended option first. Typically:
1. Company: name, stage, north star (offer drafts based on what you found; the user can type their own).
2. Where the products are: the folders you found repos in (default), other folders, git URLs, or a mix.
3. Products: which repos the board studies, with your classification as the default (multi-select).
4. Source per product: `repo:` (git URL, recommended when the repo has a remote: the board reads what is pushed and
   needs nothing on this disk) or `path:` (local folder: also sees commits not pushed yet). Ask once for all, with
   exceptions named.
Then, if you found any: data commands to run before each meeting, and notes folders.
Ask for minutes language only if it is not obvious from how the user writes. `context` stays empty unless the user
volunteers it.

## 3. Write

- `board.yml`: if it does not exist, start from `${CLAUDE_PLUGIN_ROOT}/templates/board.yml`, keep its comments,
  fill in the answers. If it exists, never rewrite it: edit only the fields that changed, and keep everything else
  (comments, hand-written values, fields you did not ask about) exactly as it is.
- Each product has exactly one of `repo:` (git URL) or `path:` (absolute or `~/` path, so the workspace can live
  anywhere). When a product is removed, also delete `.repos/<id>.git`, the folders `.snap/<id>@*` and the file
  `.snap/<id>.facts.md` (exactly these names: another product's id may start with the same letters).
- If missing: `CLAUDE.md` and `DECISIONS.md` from the templates, an empty `meetings/` folder, a `.gitignore`
  containing `.snap/` and `.repos/`, and an `.ignore` containing `!.snap/` (so the members' search still sees the
  snapshots that git ignores). If the folder is not a git repo, run `git init` in it (this folder only).

## Board members

New workspaces get the four default members in `board.yml` (`members`); do not ask about them during first setup
beyond one line saying they can be changed. When the user asks to change the board:
- **Add a seat** ("add a Legal member who checks GDPR and App Store terms"): create `.claude/agents/<name>.md` in this
  workspace from `${CLAUDE_PLUGIN_ROOT}/templates/member.md`, filling in the seat and its lens from what the user
  said (ask one question if the lens is unclear). Keep `tools: Read, Grep, Glob` (add `WebSearch, WebFetch` only if
  the user wants the seat to research the web). Do not put rules or formats in it: the meeting brief carries them.
  Add `<name>` to `members`.
- **Remove a seat**: take it out of `members` (and delete its file if it is the workspace's own).
  `boardroom:ceo` cannot be removed: say it writes the synthesis.
- **Split a seat** (e.g. `cto` and `ciso` instead of `boardroom:tech-risk`): create the new seats, replace the old one
  in `members`.
- More than 7 members: warn that each member costs two agent runs per meeting and seats start to repeat each other;
  do it only if the user confirms.
New or changed seats take effect in the next session (agents load at session start); say so.

## 4. Check

Run `${CLAUDE_PLUGIN_ROOT}/scripts/snapshot.sh <ws> <id> <repo or path> <branch> <max_files> <max_days>` for every
product (only the changed ones when editing), with `<ws>` the absolute path of this folder, and each data command
once, in a subshell: `(cd <ws> && <run>)`. A URL is cloned into `.repos/` on first
use; if cloning fails, say that git access to that URL is missing and leave the entry for the user to fix. Report in
a few lines: products and the commit each will be read at, work in progress flagged LARGE, redacted secret-like
files, which data commands worked. Then say the workspace is ready for `/boardroom:meeting`, and that products can
be changed any time by running `/boardroom:setup` again with the change, or by editing `board.yml`.
