---
name: quota-axi
description: "Report local Claude, Codex, Cursor, GitHub Copilot, Grok, Kimi, Z.AI, Alibaba, OpenCode Go, and Antigravity quota windows via the quota-axi CLI - remaining effective usable runway, percentages, reset times, cycle-average pace vs the reset clock, a per-scope selection signal, and provider status read from local auth sources, with no routing, no credential minting, and no default ordering preference. Use before deciding whether it is safe to keep spending a provider's quota, when the user asks about usage, rate limits, pace, or remaining quota, or when comparing local provider headroom."
user-invocable: false
author: Kun Chen (kunchenguid)
metadata:
  hermes:
    tags:
      - quota
      - rate-limits
      - pace
      - claude
      - codex
      - cursor
      - copilot
      - grok
      - kimi
      - zai
      - agy
      - alibaba
      - opencode-go
      - antigravity
      - cli
    category: observability
---

# quota-axi

Report local Claude, Codex, Cursor, GitHub Copilot, Grok, Kimi, Z.AI, Alibaba, OpenCode Go, and Antigravity quota windows.
quota-axi is data only: it never routes, recommends, ranks, or mints credentials. When the same stored
access token is expired, refreshable, and definitively rejected, it may delegate renewal to the vendor's
own CLI and re-read the result.

Use it when you need local quota headroom before deciding whether it is safe to keep spending a
provider, when the user asks about usage, rate limits, pace, or remaining quota, or when comparing
local provider headroom.

For current instructions, output shape, and field semantics, run the CLI (no global install required):

- `quota-axi` - default TOON report
- `quota-axi --help` - commands and flags
- `quota-axi --json` / `quota-axi --full` - current output shape and field semantics

## Version pinning on this machine

Do not run `quota-axi update` - it self-updates via npm and would drift from
the version pinned in dotfiles's `home.nix`, until the next
`./rebuild.sh` silently reinstalls the pinned version over it. To upgrade,
tell the user to bump the pinned version in `home.nix` and run
`./rebuild.sh` - that regenerates this skill file to match automatically.
`quota-axi update --check` (read-only, does not install) is still fine to run.
