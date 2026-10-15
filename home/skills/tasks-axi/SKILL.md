---
name: tasks-axi
description: "Manage a task backlog through the tasks-axi CLI - add, list, show, start, and complete tasks; track blocked-by dependencies, structured holds, and a ready queue; prune and normalize a hand-editable backlog.md. Use whenever a task touches backlog or task state: filing or dispatching work, recording a PR or report on completion, finding dispatchable or held work, or trimming the Done list."
user-invocable: false
author: Kun Chen (kunchenguid)
metadata:
  hermes:
    tags: [tasks, backlog, planning, dependencies]
    category: productivity
---

# tasks-axi

Agent ergonomic task & backlog manager for the current workspace. Prefer this over hand-editing backlog.md for task state, dependency, or hold changes.

## When to use

Use tasks-axi whenever a task touches the backlog: filing or dispatching work, moving a task through queued -> in flight -> done, recording a PR url or report path on completion, tracking blocked-by dependencies, pausing dispatch with structured holds, finding dispatchable ready work or intentionally held work, or trimming the Done list.

Get every command, flag, and workflow from the live CLI - it is the single source of truth:

- `tasks-axi` - dashboard of the current backlog
- `tasks-axi --help` - global usage
- `tasks-axi <command> --help` - per-command usage

You do not need tasks-axi installed globally. If the CLI prints a follow-up starting with `tasks-axi`, run it as `tasks-axi ...` instead.

## Version pinning on this machine

Do not run `tasks-axi update` - it self-updates via npm and would drift from
the version pinned in dotfiles's `home.nix`, until the next
`./rebuild.sh` silently reinstalls the pinned version over it. To upgrade,
tell the user to bump the pinned version in `home.nix` and run
`./rebuild.sh` - that regenerates this skill file to match automatically.
`tasks-axi update --check` (read-only, does not install) is still fine to run.
