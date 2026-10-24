# Boardroom workspace

This folder is the board of a company that runs several products. The products live in their own repos;
`board.yml` says which, and what the company is optimizing. The board studies them read-only and proposes;
the human co-CEO decides.

- `board.yml`: the input. If it is missing, empty or incomplete, run `/boardroom:setup` before anything else.
- `/boardroom:meeting [product] [topic]`: a board meeting. Minutes go to `meetings/`.
- `DECISIONS.md`: decisions of the human co-CEO only, newest first. Add a line only when they state a decision.
- `meetings/`: minutes, one file per meeting.
- `.snap/`: read-only copies of the products' reference branches, rebuilt by the scripts. Never edit; not in git.
- `.repos/`: the board's own clones of products given by git URL. Never edit; not in git.
- To add, remove or change products: `/boardroom:setup` with the change, or edit `board.yml`.

Never write, commit, build or deploy in a product repo from here. Product work happens in a session in that repo.
