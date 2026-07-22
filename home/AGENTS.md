# global agent instructions

- Never use the em dash "—". Use plain dash "-" instead
- Never manually modify CHANGELOG.md files or any files that are marked as auto-generated
- When making technical decisions, do not give much weight to development cost.
  Instead, prefer quality, simplicity, robustness, scalability, and long term maintainability.
- When doing bug fixes, always start with reproducing the bug in an E2E setting as closely aligned with how an end user would experience it as possible.
  This makes sure you find the real problem so your fix will actually solve it.
- When end-to-end testing a product, be picky about the UI you see and be obsessed with pixel perfection.
  If something clearly looks off, even if it is not directly related to what you are doing, try to get it fixed along the way.
- Apply that same high standard to engineering excellence: lint, test failures, and test flakiness.
  If you see one, even if it is not caused by what you are working on right now, still get it fixed.

## Local clones of referenced repositories

Documents (ADRs, plans, PR descriptions) reference repositories the way a
human would - a GitHub URL or `org/repo` name - so they stay meaningful
outside this machine. But most of those repos also have a local clone
here, which is faster and doesn't burn API calls: prefer reading the local
clone over `gh`/`WebFetch`/the GitHub API whenever one exists.

- **`~/work/<repo>`** - every `AmwayCommon/<repo>` GitHub repository has (or
  should have) a matching local clone here, same name. Before fetching an
  `AmwayCommon/*` repo remotely, check `~/work/<repo>` first.
- **`~/examples/<repo>`** - open-source or third-party repos cloned for
  reference (e.g. a dependency's source, a tool being evaluated). Before
  fetching a public repo remotely for reference, check here too, and if a
  repo you keep needing isn't there yet, clone it in rather than
  re-fetching it repeatedly.
- Neither directory is guaranteed exhaustive or up to date - if a repo
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

## Generated files - edit the source, not the output

This repo is the personal base and is meant to be extendable by a
separate, work-specific profile repo layered on top (e.g. via `imports`
in that repo's flake) - one that appends its own addendum to files this
repo owns, or merges in its own overlay. Files below plant an unmerged,
personal-only version first specifically so a downstream profile's
activation script (ordered after this repo's) can safely overwrite it
with a merged version:

- `~/.claude/settings.json`, `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`,
  and `~/.config/opencode/AGENTS.md` are all plain live symlinks
  (`home.activation` + `ln -sfn`, not `home.file`) for exactly this
  reason - a `home.file` entry would make home-manager think it owns the
  path and fight a downstream profile's overwrite via its
  `backupFileExtension` logic.
- `~/.agents/instructions/INSTALLATIONS.md` works the same way, wired
  from this repo's `home/instructions/INSTALLATIONS.md`.
- If a symptom looks like "I edited a dotfile in `~/.config` or
  `~/.claude` etc. but it keeps reverting" or "the change isn't taking
  effect", check whether a work-specific profile repo exists on this
  machine and has a `home.activation` script targeting that same path,
  ordered after this repo's - before assuming the edit failed.

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
