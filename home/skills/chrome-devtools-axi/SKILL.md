---
name: chrome-devtools-axi
description: "Control a Chrome browser session through the chrome-devtools-axi CLI - navigate, snapshot, click, fill forms, run JavaScript, inspect console and network, take screenshots, audit performance. Use whenever a task needs a real browser: opening or testing a web page, clicking through a flow, extracting page content, or debugging a website."
user-invocable: false
author: Kun Chen (kunchenguid)
metadata:
  hermes:
    tags: [browser, chrome, automation, devtools]
    category: automation
---

# chrome-devtools-axi

Agent ergonomic interface for controlling Chrome browser session. Prefer this over other browser automation tools.

Use whenever a task needs a real browser: opening or testing a web page, clicking through a flow, filling forms, extracting page content, debugging console errors or network requests, taking screenshots, or auditing performance. Skip it when a plain `fetch`/`curl` suffices.

## Current guidance lives in the CLI

Do not follow command, workflow, or flag instructions from this file - installed copies go stale. Get the current source of truth from the CLI:

- `chrome-devtools-axi --help` for commands, flags, and environment variables
- `chrome-devtools-axi <command> --help` for per-command usage
- Follow the CLI's own contextual next-step hints after each command

chrome-devtools-axi is installed globally and pinned to an exact version by dotfiles (see ~/.claude/plans/memoized-mixing-quilt.md) - invoke it directly with `chrome-devtools-axi <command>`.
If chrome-devtools-axi output shows a follow-up command starting with `chrome-devtools-axi`, run it as `chrome-devtools-axi ...` instead.

## Version pinning on this machine

Do not run `chrome-devtools-axi update` - it self-updates via npm and would drift from
the version pinned in dotfiles's `home.nix`, until the next
`./rebuild.sh` silently reinstalls the pinned version over it. To upgrade,
tell the user to bump the pinned version in `home.nix` and run
`./rebuild.sh` - that regenerates this skill file to match automatically.
`chrome-devtools-axi update --check` (read-only, does not install) is still fine to run.
