# Writing commit messages

Before writing a commit message, check whether the project defines its own
commit convention - a `CONTRIBUTING.md`, a `docs/`-level rules doc, a section
in the project's own `AGENTS.md`/`CLAUDE.md`, or a `commit-msg` git hook.
Recent `git log` output is also good evidence: if messages already follow a
consistent shape, match it even if it isn't written down anywhere. Follow
whatever the project establishes - it always wins over anything below.

Only when a project has no discoverable convention of its own, use this
default:

## Default convention

Every commit message must follow this exact format:

```
<prefix><risk><risk> - <message>
```

The dash (`-`) is always the 5th character. Pad the prefix+risk field with
spaces to reach that position.

### Prefix

| Prefix | Meaning |
|--------|---------|
| `f` | Feature - new component or functionality added |
| `r` | Refactor - alteration or improvement of existing code, no behavior change |
| `b` | Bugfix - fixing a bug |
| `t` | Test - test creation, update, fix, or removal |
| `d` | Documentation - creation, update, fix, or removal of documentation |
| `c` | Chore - configuration changes (e.g. `.gitignore`, config property values) |
| `a` | Automated - changes made by an automated process (e.g. dependency bumps) |

### Risk escalation

Append risk indicators to the prefix to signal how large or complex the
change is:

| Indicator | Meaning | Example |
|-----------|---------|---------|
| lowercase (`f`) | Minimum risk - small, obvious change | `f   - added login page` |
| UPPERCASE (`R`) | Medium risk - larger or non-trivial change | `R   - refactored auth service` |
| single `!` (`B!`) | High risk - large or complex change | `B!  - fixed null pointer in parser` |
| double `!!` (`R!!`) | Critical risk - very large change or WIP | `R!! - rewriting all e2e tests` |

Most commits should be minimum risk - small, incremental changes are the
goal, and escalation should be the exception, not the norm.

### Dash position

The dash must land at position 5, however many characters the prefix+risk
took:

| Pattern | Dash at | Valid |
|---------|---------|-------|
| `b   - message` | 5 | yes |
| `B   - message` | 5 | yes |
| `B!  - message` | 5 | yes |
| `B!! - message` | 5 | yes |
| `f - message` | 3 | no |
| `f- message` | 2 | no |

## Applying this

Pick one prefix and one risk level per commit - don't combine multiple
prefixes into one message. If a change genuinely mixes concerns (e.g. a
feature plus its tests), either split it into separate commits per concern,
or pick the prefix for whichever concern is primary and note the rest in the
message body.
