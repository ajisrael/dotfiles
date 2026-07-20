---
name: adr
description: Record architecture decisions (ADRs) - a durable log of why the codebase looks the way it does, separate from AGENTS.md/CLAUDE.md's how-to-work-here rules. Use when a decision was genuinely contested (multiple real options), came out of a planning session, changes a system boundary or a hard-to-reverse choice, or the user asks to log/record/write up a decision.
user-invocable: true
---

# adr

`adr` (npryce/adr-tools) manages a numbered log of Architecture Decision
Records - one markdown file per decision, in `docs/adr/` by default. It is
project-scoped, not machine-global: each repo gets its own log the first
time this skill is used in it.

## Is this an ADR, or just an AGENTS.md/CLAUDE.md entry?

These two mechanisms solve different problems - use both, not one instead
of the other:

- **AGENTS.md / CLAUDE.md** - *how to work here*: conventions, gotchas,
  "don't do X because Y broke last time." Small, read in full every
  session. See that file's own "Maintaining this file" section.
- **ADR** - *why the system looks the way it does*: a considered,
  hard-to-reverse choice about architecture, a dependency, a data model, an
  API boundary. Immutable once accepted; referenced by number, not reloaded
  wholesale.

Write an ADR when the decision meaningfully changes the system's structure
or a dependency, and reversing it later would be costly - not for routine
implementation choices. When in doubt, ask the user rather than guessing.
If a decision is genuinely small (a one-line default, a naming choice),
log it in AGENTS.md/CLAUDE.md instead, or skip logging entirely.

## Setup (once per repo)

Check for an existing ADR log first - a `.adr-dir` file, or a `doc/adr/`
or `docs/adr/` directory already in the repo - and use that location
instead if one exists. Only when none exists:

```sh
adr init docs/adr
```

Creates `docs/adr/0001-record-architecture-decisions.md` (the standard
first ADR explaining that ADRs are in use) and remembers the directory in
`.adr-dir`.

Then drop the Nygard template in as the repo's *default* - `adr new` uses
`<adr-dir>/templates/template.md` automatically when present, without any
flag:

```sh
mkdir -p docs/adr/templates
cp ~/.claude/skills/adr/templates/nygard.md docs/adr/templates/template.md
```

(The MADR template lives alongside it at
`~/.claude/skills/adr/templates/madr.md` - not copied in by default, since
it's the exception, invoked explicitly per decision below.)

## Default: Nygard format

Use this for most decisions - anything with an obvious answer, or where
the reasoning fits in a paragraph:

```sh
EDITOR=true adr new Use Postgres for the events table
```

`EDITOR=true` is required in an agent session - `adr new` opens the new
file in `$VISUAL`/`$EDITOR` by default (interactive-editor tooling assumes
a human is at the keyboard), and `true` is a no-op editor that just exits
immediately so the file is left for you to edit programmatically instead.
It prints the created file's path to stdout - edit that file's Context,
Decision, and Consequences sections directly with your file-editing tool.

## When the decision was contested: MADR format

Use this when a planning session (or the conversation) surfaced multiple
real options and you weighed tradeoffs between them - not just "we did the
obvious thing." Pass the MADR template explicitly for this one ADR via
`ADR_TEMPLATE`, without changing the repo's default:

```sh
EDITOR=true ADR_TEMPLATE=~/.claude/skills/adr/templates/madr.md \
  adr new Choose a queue for order events
```

Fill in Decision Drivers, Considered Options, and Pros/Cons for each
option genuinely considered - this is the point of using MADR over Nygard,
so don't skip it. Be concise per bullet; this is a record of *why*, not a
design document.

## Superseding or linking decisions

```sh
# ADR 12 becomes superseded by this new one (both files updated automatically)
EDITOR=true adr new -s 12 Move to a hosted queue instead of self-managed

# Link two ADRs without one replacing the other
EDITOR=true adr new -l "5:Amends:Amended by" Extend the auth boundary from ADR 5
```

Never hand-edit an old ADR's Status line to mark it superseded - use `-s`
so both files stay consistent (it inserts the cross-links and flips the
old one's status automatically). ADRs are otherwise append-only: don't
edit or delete an accepted ADR's Decision/Consequences after the fact, even
if it turns out wrong - supersede it with a new one that explains why.

## Other commands

```sh
adr list              # every ADR in the log
adr generate toc       # table of contents (pipe to docs/adr/README.md if wanted)
```
