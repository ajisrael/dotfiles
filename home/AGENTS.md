# global agent instructions

- Never use the em dash "—". Use plain dash "-" instead
- Never manually modify CHANGELOG.md files or any files that are marked as auto-generated
- Never run `tmux kill-server` (or any command that tears down the whole tmux
  server, e.g. `killall tmux`).
- When working in a project that has a remote repository, unless specified otherwise, never write full system paths.
  Especially ones that contain the username. Paths should be relative to the project to allow
  for consistency when being used by others.
- When making technical decisions, do not give much weight to development cost.
  Instead, prefer quality, simplicity, robustness, scalability, and long term maintainability.
- When doing bug fixes, always start with reproducing the bug in an E2E setting as closely aligned with how an end user would experience it as possible.
  This makes sure you find the real problem so your fix will actually solve it.
- When end-to-end testing a product, be picky about the UI you see and be obsessed with pixel perfection.
  If something clearly looks off, even if it is not directly related to what you are doing, try to get it fixed along the way.
- Apply that same high standard to engineering excellence: lint, test failures, and test flakiness.
  If you see one, even if it is not caused by what you are working on right now, still get it fixed.
- Some projects will be designed to work with multiple work trees simultaneously and will dynamically update ports for locally running servers. Make sure
  you check that you are calling the correct local server when verifying changes and making calls.

## Local clones of referenced repositories

Documents (ADRs, plans, PR descriptions) reference repositories the way a
human would - a GitHub URL or `org/repo` name - so they stay meaningful
outside this machine.

Most of those repos also have a local clone: `~/examples/<repo>` is used for public repositories.
Other private repos the user has access to would be found inside the parent directory of a project.

Instead of using `gh`, or `WebFetch` by default, prefer to analyze the local clone to save on api calls.
If a local clone doesn't exist ask the user for the preference to clone or not.

## Installation

- Before installing anything globally on this machine read `~/.agents/instructions/INSTALLATIONS.md`.

## Commits

- NEVER auto-add your agent name as co-author.
- Before writing a commit message, read
  `~/.agents/instructions/COMMITS.md` and follow it: use the project's own
  commit convention if it has one, otherwise fall back to the default
  format described there.

## Maintaining this file and project-level agent context files

Keep this file for knowledge useful to almost every future agent session.
Do not repeat what the codebase already shows; point to the authoritative file, skill, command, or doc.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve every safety boundary and keep the always-loaded contract concise.

Additionally:

- Whenever you get course-corrected, made an incorrect assumption, or
  discover something non-obvious, add an entry to the relevant agent context file:
    - this one for machine-wide/cross-project lessons
    - the project's own AGENTS.md/CLAUDE.md for project-specific ones.
  The goal is so the next agent doesn't repeat the same mistake or have to rediscover things already figured out.
- Expand entries to a reference document (like `~/.agents/instructions/INSTALLATIONS.md`) when a
  topic has grown in complexity for the notation or only needs to be considered under certain conditions.
- Not every discovery belongs here, reference architectural decisions following the `adr` skill.
