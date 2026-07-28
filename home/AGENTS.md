# global agent instructions

- Never use the em dash "—". Use plain dash "-" instead
- Never manually modify CHANGELOG.md files or any files that are marked as auto-generated
- Never run `tmux kill-server` (or any command that tears down the whole tmux
  server, e.g. `killall tmux`).
- When working in a project that has a remote repository, unless specified otherwise never write full system paths.
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

## Large file writes (4096 output-token cap)

A single model turn can only emit ~4096 output tokens, so one `Write` (or
one giant `Edit`) call can silently truncate a large file (a big HTML
artifact, a long generated doc, a large source file). When the content
you're producing is large:

- Write a minimal skeleton first (structure/containers only), then add the
  rest with a sequence of smaller `Edit` calls, each well under the cap.
- Prefer many small, targeted edits over one large rewrite, even when
  targeting the same file repeatedly.
- This applies regardless of tool (Write, Edit, MultiEdit, or a subagent
  producing file content) - the cap is on the model's output per turn, not
  on the tool itself.

## Local clones of referenced repositories

Documents (ADRs, plans, PR descriptions) reference repositories the way a
human would - a GitHub URL or `org/repo` name - so they stay meaningful
outside this machine. But most of those repos also have a local clone
here, which is faster and doesn't burn API calls: prefer reading the local
clone over `gh`/`WebFetch`/the GitHub API whenever one exists.

- **`~/examples/<repo>`** - open-source or third-party repos cloned for
  reference (e.g. a dependency's source, a tool being evaluated). Before
  fetching a public repo remotely for reference, check here too, and if a
  repo you keep needing isn't there yet, clone it in rather than
  re-fetching it repeatedly.
- This directory is not guaranteed exhaustive or up to date - if a repo
  isn't present, or the local clone looks stale for what you need, fall
  back to `gh`/the GitHub API/`WebFetch` normally.

## Installation

- Before installing anything globally on this machine (a CLI tool, GUI app, or
  language runtime available system-wide - not a project-local install like
  `npm install` inside a repo), read `~/.agents/instructions/INSTALLATIONS.md`
  and follow its install-method priority order.

## Commits

- NEVER auto-add your agent name as co-author.
- Before writing a commit message, read
  `~/.agents/instructions/COMMITS.md` and follow it: use the project's own
  commit convention if it has one, otherwise fall back to the default
  format described there.

## Maintaining this file and project-level agent context files

- Whenever you get course-corrected, made an incorrect assumption, or
  discover something non-obvious (a gotcha, a hidden constraint, a
  convention that isn't derivable from the code), add an entry to the
  relevant agent context file - this one for machine-wide/cross-project
  lessons, the project's own AGENTS.md/CLAUDE.md for project-specific ones.
  The goal is so the next agent doesn't repeat the same mistake or have to
  rediscover how this developer works.
- Keep entries short. Concise enough to keep token overhead low,
  but specific enough to still carry the "why", not just the
  "what".
- Every time you add an entry, re-skim the whole file and check whether it
  has grown enough that a topic should be split into its own doc (like
  `~/.agents/instructions/INSTALLATIONS.md`) and linked from here instead of
  inlined.
- Not every discovery belongs here, though. A decision that's architectural
  (a hard-to-reverse choice about structure, a dependency, a data model, an
  API boundary) - especially one that came out of weighing real
  alternatives - belongs in that repo's ADR log instead of this file. See
  the `adr` skill for when and how.
