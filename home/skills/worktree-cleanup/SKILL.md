---
name: worktree-cleanup
description: Iteratively clean up Treehouse pool worktrees and the local/remote git branches left behind after parallel-agent work merges back into a mainline (develop/main/master). Use when the user asks to clean up / prune / tidy worktrees or branches, says the repo has accumulated stale worktrees or merged branches after running agents in parallel, or invokes /worktree-cleanup.
user-invocable: true
---

# worktree-cleanup

A safe, confirm-first playbook for reclaiming the two things that pile up
when you run multiple agents in parallel with
[Treehouse](https://github.com/kunchenguid/treehouse) worktrees and then merge their work back into a mainline branch:

1. **Treehouse pool worktrees** - the numbered, pre-warmed worktrees under
   `~/.treehouse/<repo>-<hash>/<n>/<repo>`, managed by the `treehouse` CLI.
2. **Git branches** - the local branches (and their remote counterparts)
   the agents pushed, now merged and dead weight.

These are *separate* cleanup targets with separate tools. A Treehouse
worktree usually runs on a **detached HEAD**, so destroying the worktree
does **not** delete the branch, and deleting the branch does **not** free
the worktree. This skill walks both, in order, one repo at a time.

Treehouse is the source of truth for worktree state; plain `git` is the
source of truth for branch state. Never `rm -rf` a worktree directory or
hand-edit `.git/worktrees` - always go through `treehouse` so the pool
metadata stays consistent.

## Golden rules

- **Dry-run first, always.** `treehouse prune` and `treehouse destroy` are
  dry runs by default and print a risk-revealing preview. Show the user
  that preview and get an explicit go-ahead before re-running with `--yes`.
- **Never force past a safety class without naming it.** The `--include-*`
  flags each opt into a specific risk (unlanded work, in-use worktrees,
  leased worktrees). Only add the exact flag the user approved for the
  exact worktree in question - never a blanket override.
- **Merged-ness is judged against the mainline the user names**, not
  assumed. Confirm which branch is the integration target
  (`develop`, `main`, `master`, ...) before deleting anything as "merged."
- **One repo at a time.** Run the loop in the repo the user means. Only
  reach for the global sweep (`treehouse prune --all`) when the user
  explicitly asks to clean every pool on the machine.
- **Iterate, don't bulldoze.** Work through candidates in passes, letting
  the user veto individual items, rather than clearing everything at once.

## Step 0 - Orient

Confirm the repo and its integration branch before touching anything.

```sh
git -C <repo> rev-parse --show-toplevel        # confirm which repo
git -C <repo> branch -vv                        # local branches + tracking
treehouse status                                # pool worktrees (run in repo)
```

Ask the user which branch work merges back into if it is not obvious from
`git branch -vv` (a repo with `develop` tracked and several feature
branches merged into it, for example). That branch is the `<mainline>`
referenced throughout.

## Step 1 - Return anything you still hold, then prune the safe set

`treehouse prune` removes only genuinely stale worktrees: treehouse-managed,
no owner reservation or running process, clean working tree, and HEAD
already merged into the default branch. It is the low-risk first pass.

```sh
treehouse prune                 # dry run - prints candidates, deletes nothing
```

Review the printed candidates with the user, then execute:

```sh
treehouse prune --yes           # delete the listed candidates
```

If a worktree you want gone is skipped, the dry-run output says *why*
(in use, leased, dirty, unmerged). Do not immediately escalate - surface
the reason to the user first. Common resolutions:

- **In use / lingering process** - if the work is truly done, return it:
  `treehouse return <path>` (add `--force` only with the user's OK; it
  terminates processes and resets the worktree).
- **Leased** - a durable reservation from `treehouse get --lease`. Release
  it with `treehouse return <path>` when the user confirms it is finished.
- **Orphaned** (backing repo gone) - include with
  `treehouse prune --prune-orphans --yes` once confirmed.

## Step 2 - Destroy specific stubborn worktrees (opt-in risk)

When a *specific* worktree needs to go even though prune skipped it, use
`destroy`. It targets one worktree path (or `--all` within one named pool)
and is also a dry run until `--yes`.

```sh
treehouse destroy <worktree-path>          # dry-run preview for one worktree
```

Then add only the flag matching the risk the user accepted, plus `--yes`:

| Skip reason         | Flag to add            | What it means                                   |
| ------------------- | ---------------------- | ----------------------------------------------- |
| dirty / unmerged    | `--include-unlanded`   | **DATA LOSS** - uncommitted or unmerged work    |
| running process     | `--include-in-use`     | processes are terminated cleanly first          |
| leased              | `--include-leased`     | only with the exact path named, never via `--all` |

```sh
treehouse destroy <worktree-path> --include-unlanded --yes   # only if user OK'd data loss
```

Treat `--include-unlanded` as the highest-caution flag: name what would be
lost (which worktree, that it has uncommitted or unmerged commits) and get
explicit confirmation before running it.

## Step 3 - Delete merged local branches

With worktrees handled, clean the branches. First list what has actually
merged into the integration branch, excluding the mainlines themselves:

```sh
git -C <repo> branch --merged <mainline> \
  | grep -vE '^\*|(^|\s)(main|master|develop)$'
```

Show that list to the user. Delete the approved ones with the safe flag
(`-d` refuses to delete an unmerged branch; never reach for `-D` unless the
user explicitly accepts losing unmerged commits):

```sh
git -C <repo> branch -d <branch> [<branch> ...]
```

A branch that `-d` refuses is not actually merged into `<mainline>` - stop
and tell the user rather than forcing it. It may have merged into a
*different* mainline, or its work may still be live.

## Step 4 - Prune remote-tracking refs and delete remote branches

After branches merge and are deleted on the remote (e.g. by a merged PR),
your local remote-tracking refs go stale. Prune them, then find any
still-live remote branches that are now redundant.

```sh
git -C <repo> fetch --prune                     # drop stale remote-tracking refs
git -C <repo> branch -vv | grep ': gone]'       # locals whose upstream is gone
```

Branches marked `: gone]` had their remote deleted already - their local
counterpart is safe to remove once merged (Step 3 handles that; a `gone`
local that is also merged is a clear delete candidate).

To delete a remote branch that is still present but merged, confirm the
remote and branch with the user, then:

```sh
git -C <repo> push <remote> --delete <branch>   # deletes the branch on the remote
```

Deleting a remote branch affects a shared system. Always confirm the exact
remote and branch names with the user first, and never batch-delete remote
branches without showing the full list and getting a go-ahead.

## Step 5 - Verify and report

```sh
treehouse status              # pool should show only worktrees you meant to keep
git -C <repo> branch -vv      # locals should be down to mainlines + active work
```

Summarize what was removed (worktrees, local branches, remote branches) and
what was intentionally kept and why (leased, dirty, still active), so the
next pass starts from a known state.

## Doing it again next time

This is meant to be run regularly. Each pass:

1. `treehouse status` + `git branch -vv` to see the accumulation.
2. `treehouse prune` (dry run) → review → `--yes`.
3. Named `treehouse destroy` for stubborn ones the user approves.
4. `git branch --merged <mainline>` → review → `git branch -d`.
5. `git fetch --prune`, then delete redundant remote branches with the
   user's OK.

Keep every destructive step confirm-first. The whole point is to reclaim
space without ever losing work the user still wanted.
