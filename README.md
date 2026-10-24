# Boardroom

**This folder is the product**: a reusable Claude Code plugin. It contains no data about any company.
You install it into a separate workspace folder (your board), which holds your company's input and minutes.
For example: `boardroom/` (this plugin) next to `board/` (your workspace), next to your product repos.

A board of AI agents for a company that runs several products, each in its own git repo.
You open a workspace folder in Claude Code, call a meeting, and four board members study the products from
their code and docs, propose, challenge each other once, and a co-CEO agent writes the synthesis.
You are the other co-CEO: you decide.

## Quick start

1. Pick a workspace folder for your board, anywhere (for example `~/board`), and install:

   ```bash
   ./install.sh ~/board
   ```

2. Open the workspace in Claude Code, start a **new** session, and run `/boardroom:setup`. It asks where your
   products are (folders and/or git URLs), finds the repos, asks a few questions and writes the workspace files.
3. Call a meeting: `/boardroom:meeting` (all products) or `/boardroom:meeting <product> <topic>`.

The workspace reads Boardroom from this folder: after changing it, start a new session in the workspace
(or run `/reload-plugins`). No reinstall needed.

A workspace after setup:

```
hq/
  board.yml        the input: company, products, data commands, notes
  CLAUDE.md        tells Claude this folder is a board
  DECISIONS.md     your decisions
  meetings/        minutes
  .snap/           read-only copies of the products (not in git)
  .repos/          the board's own clones of products given by git URL (not in git)
  .claude/settings.json   Boardroom installed for this folder
```

| Member | Seat | Lens |
|---|---|---|
| `ceo` | co-CEO | Focus: what moves the north star most, what to stop. Chairs and writes the synthesis. |
| `growth` | CMO + Sales | Cheapest path to revenue: users, channels, pricing, B2B pilots. Can search the web. |
| `tech-risk` | CTO + CISO | Feasibility, effort, shared infrastructure, security, privacy, compliance. |
| `cfo` | CFO + skeptic | Numbers, cost, return, kill criteria. |

## Products: git URL or local folder

Each product in `board.yml` has one source:

```yaml
products:
  - id: shop
    repo: git@github.com:org/shop.git   # git URL: the board keeps its own clone in .repos/, fetched every meeting
    branch: main
    kind: product                        # product | infra
    about: Online shop app
  - id: server
    path: ~/work/server                  # local repo folder, anywhere
    branch: main
    kind: infra
    about: Shared backend
```

- `repo:` needs nothing on this disk and reads what is pushed. It needs git access to the URL.
- `path:` also sees commits on the branch that are not pushed yet. It needs the folder on this machine.

**Changing products later**, either way:
- run `/boardroom:setup` and say the change ("add git@github.com:org/app.git", "remove server",
  "read shop from branch release"): it edits only that entry and checks it;
- or edit `board.yml` by hand. The next meeting picks it up; a broken entry is reported and skipped.

## The board and your own seats

`members` in `board.yml` lists the board. The default is the four seats above; `boardroom:ceo` always takes part.
To change it, run `/boardroom:setup` and say what you want: "add a Legal seat that checks GDPR and store terms",
"remove cfo", "split tech-risk into cto and ciso". Your own seats are files in the workspace,
`.claude/agents/<name>.md`, made from `templates/member.md`: a seat only describes its lens. The rules and formats
come from the meeting, so every seat follows them. Keep the board at 7 or fewer: each seat costs two agent runs.

## What every proposal must say

- **Who does each step**: `OM` (only a human can or may: talking to people, money, signing, legal, account access,
  approving deploys, sending or publishing) or `AI`. Each OM step has what, time and a deadline. The synthesis opens
  with **what you must do**, and the next meeting checks OM steps still not done.
- **Compatibility** (compatible / breaks what exactly / n/a) and **reversibility** (easy / costly / irreversible).
  A proposal that breaks something or cannot be undone needs a migration or exit plan, or it cannot be recommended.

`DECISIONS.md` records the same for every decision you take.

## How a meeting works

1. **Snapshot.** For each product in scope, `scripts/snapshot.sh` copies the reference branch (usually `main`) into
   `.snap/<id>@<sha>/` with `git archive`. It never touches the product's working tree or branch, so sessions working
   in the product are not affected. Media and vendored files are left out, secret-like files are redacted.
   It also writes `.snap/<id>.facts.md`: commit, version, last commits, documents, redacted files, and the
   branches in progress with their size (flagged LARGE above the limits in `board.yml`). The snapshot is reused
   until the branch moves.
2. **Data and notes.** The `data` commands from `board.yml` run, after you approve any that are new or changed,
   and their output goes to `.snap/data.md`; `notes` folders are copied to `.snap/notes/`.
3. **Reports.** The members work in parallel: observations with citations, up to three proposals each
   (impact, cost, metric, target, date), concerns, unknowns.
4. **Challenge.** One round: each member reads all reports and supports, objects to or amends others' proposals,
   with reasons, and checks the OM/AI and compatibility labels. Agreement is allowed.
5. **Synthesis.** The co-CEO agent: what you must do, follow-up on past decisions, surviving proposals ranked, recommendation,
   what to stop, the weakest proposal, what nobody proposed, questions for you.
6. **Minutes** go to `meetings/<date>-<topic>.md`. `scripts/scan-secrets.sh` looks for secret-like strings and
   they are replaced with `[REDACTED]`; `scripts/check-citations.sh` checks that every cited `<id>:<path>:<line>`
   exists in the snapshot.

## Why the board reads copies, not the product folders

Board members can only read files (Read, Grep, Glob); they cannot run commands, so they cannot change anything.
The product folders themselves are the wrong thing to read: they show whatever branch a developer has checked out,
with unsaved changes. So each meeting reads a copy of the reference branch, made with `git archive`:

- it is exactly the reference branch at one commit, so every member and every citation refers to the same code;
- making it touches nothing in the product repo: no checkout, no worktree, no lock on the branch;
- it is small (media and vendored files are left out) and reused until the branch moves.

The alternatives were worse: a `git worktree` writes into the product's `.git`, runs its checkout hooks and filters
and copies everything unredacted (and, unless detached, stops anyone else from checking out `main`); letting members
run `git show` gives them a shell, which cannot be kept read-only.

## What install.sh does

It runs, from the workspace folder, with the Claude Code CLI (or the one bundled with the Claude desktop app):

```bash
claude plugin marketplace add <path to this folder> --scope project
claude plugin install boardroom@boardroom --scope project
```

This registers Boardroom and writes it to the workspace's `.claude/settings.json`. Writing that file by hand is
not enough: the plugin is only registered by these commands. Running `install.sh` again is safe; after moving the
folders it registers the new path.

## Safety

What Boardroom does to protect your repos and secrets:

- **Read-only on your products.** Members can only read files (Read, Grep, Glob; the growth seat can also search
  the web). The scripts read products through git (`git archive`, `log`, `for-each-ref`) without touching their
  working folders, index or branches; the products' git filters, fsmonitor and hooks are switched off or never run.
  A product given by URL is cloned, bare, into the workspace's `.repos/`, never into your folders.
- **Secrets stay out of the copies.** Secret-like files (`*.p8`, `*.pem`, `.env*`, `GoogleService-Info.plist`, …) are
  kept by name with their content replaced; symlinks are replaced by a note, so nothing points outside the copy.
- **Secrets stay out of the minutes.** Members are told never to quote a secret, only to name where it is; the
  minutes are then scanned for secret-like strings and any hit is replaced with `[REDACTED]`.
- **Commands run only with your approval.** The `data` commands in `board.yml` run on your machine, as you. A
  meeting asks you before running any command that is new or changed since the last approved run.

What it cannot do for you:

- Pattern matching does not catch every secret. A key hard-coded in a file with an ordinary name is in the copy and
  may be read by a member; read minutes before you share or commit them.
- Members read code, notes and web pages that may contain text written to manipulate an AI. They are told to treat
  it as data and they cannot write or run anything, but the growth seat can search the web. Remove that seat
  (`members` in `board.yml`) if you do not want any web access.
- Everything the members read is sent to the model provider by Claude Code, under your account and its terms.

## Terms of use

Boardroom is provided "as is", without warranty of any kind, under the [MIT License](LICENSE). By using it you
accept the [disclaimer](DISCLAIMER.md). In short: you alone are responsible for your repositories, keys,
credentials and data, for the commands you put in `board.yml`, for the costs of running it (tokens, API usage), and
for any decision you take. The board's output is not legal, financial, security or investment advice.

No support is promised; issues and pull requests are welcome.

## Tests

```bash
tests/run.sh
```

Builds throwaway product repos (with a planted security issue, a fake secret, media, side branches, an orphan
branch, a same-name tag, a git filter and a symlink) and checks the snapshot, redaction, work-in-progress
detection, caching, URL sources, that nothing is written in the product's `.git`, notes, the citation checker and
the secret scanner. Needs bash, git and rsync.
For an end-to-end check, run a meeting on a workspace and look for: every section present, citations passing,
product repos unchanged (`git status`), and the board finding known issues by itself.
