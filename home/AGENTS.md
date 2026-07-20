# global agent instructions

- Never use the em dash "—". Use plain dash "-" instead
- When writing commit messages, NEVER auto-add your agent name as co-author
- Never manually modify CHANGELOG.md files or any files that are marked as auto-generated
- When making technical decisions, do not give much weight to development cost.
  Instead, prefer quality, simplicity, robustness, scalability, and long term maintainability.
- When doing bug fixes, always start with reproducing the bug in an E2E setting as closely aligned with how an end user would experience it as possible.
  This makes sure you find the real problem so your fix will actually solve it.
- When end-to-end testing a product, be picky about the UI you see and be obsessed with pixel perfection.
  If something clearly looks off, even if it is not directly related to what you are doing, try to get it fixed along the way.
- Apply that same high standard to engineering excellence: lint, test failures, and test flakiness.
  If you see one, even if it is not caused by what you are working on right now, still get it fixed.

## Installation

- Before installing anything globally on this machine (a CLI tool, GUI app, or
  language runtime available system-wide - not a project-local install like
  `npm install` inside a repo), read `~/.agents/instructions/INSTALLATIONS.md`
  and follow its install-method priority order.

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
