---
name: worktree-cleanup
description: Per-project review and cleanup of git branches and Treehouse worktrees left behind after parallel-agent work merges into a target branch (default develop). Reviews every local and remote branch (merged into target? checked out by a worktree?) and every worktree (uncommitted changes?), reports the full state, and cleans up only what the user picks. Use when the user asks to clean up / prune / review worktrees or branches, or invokes /worktree-cleanup.
user-invocable: true
---

# worktree-cleanup

A **per-project**, **report-first** workflow for reclaiming the branches and
[Treehouse](https://github.com/kunchenguid/treehouse) worktrees that pile up
when you run multiple agents in parallel and then merge their work into a
target branch.

The flow is always: **gather full state → report to the user → wait for the
user to choose what to keep vs. remove → then act.** You never
propose-and-delete in one motion. Present the complete picture of every
branch and every worktree first; the user decides disposition per item; only
then do you clean up.

Run this against **one project at a time** - the repo the user is in or names.
This is not a machine-wide sweep.

## The target branch

Work merges back into a **target branch**, which defaults to **`develop`**
(the project's usual default branch). Assume `develop` unless the user says
otherwise. Resolve it concretely before judging anything as merged:

```sh
# Prefer a local target branch; fall back to the remote-tracking one.
git -C <repo> rev-parse --verify --quiet develop \
  || git -C <repo> rev-parse --verify --quiet origin/develop
```

If neither exists, do not guess - ask the user which branch is the
integration target (some projects use `main` or `master`). Everything below
calls the resolved branch `<target>`.

## Phase 1 - Review every branch (local and remote)

For each branch - local and remote - determine two things:

1. **Merged?** Are its changes already in `<target>`?
2. **Checked out?** Is it currently checked out by a worktree, and which one?

### Which branches exist

```sh
git -C <repo> fetch --prune                    # refresh; drop dead remote-tracking refs
git -C <repo> branch                            # local branches
git -C <repo> branch -r                         # remote branches
```

### Is a branch checked out by a worktree, and where

`%(worktreepath)` is empty when the branch is not checked out anywhere:

```sh
git -C <repo> for-each-ref \
  --format='%(refname:short)%09%(worktreepath)' refs/heads
```

Treehouse worktrees frequently run on a **detached HEAD** (no branch), so
also map worktrees to commits directly and reconcile the two:

```sh
git -C <repo> worktree list --porcelain
```

A branch with a non-empty worktree path is **in use** - flag it; do not treat
it as freely deletable even if merged, because a worktree still points at it.

### Is a branch merged into the target

Two cases, because a merged PR is usually **squash-merged**, which
`--merged` does not detect:

```sh
# True/fast-forward merges - branches whose tip is an ancestor of <target>:
git -C <repo> branch --merged <target>
git -C <repo> branch -r --merged <target>
```

For branches **not** listed there, check whether their work was
**squash-merged** (their commits landed as a single squashed commit on
`<target>`, so the branch tip is not an ancestor). `git cherry` marks commits
already present in the target with `-`:

```sh
git -C <repo> cherry <target> <branch>          # all lines start with '-' => already in target
```

If every line is prefixed `-`, the branch's changes are in `<target>` even
though `--merged` did not list it - classify it **merged (squashed)**. If some
lines start with `+`, those commits are not in the target yet - classify it
**not merged** and say so. When squash-merge status is genuinely ambiguous,
report it as "unmerged / needs verification" rather than asserting it is safe.

## Phase 2 - Review every worktree for uncommitted work

For each worktree (from `git worktree list`), check whether it has changes
that were never committed to its checked-out branch - work that would be
**lost** if the worktree were destroyed:

```sh
git -C <worktree-path> status --porcelain       # non-empty => uncommitted changes
git -C <worktree-path> stash list                # stashes are easy to forget
```

Also note worktrees whose HEAD has commits not yet on any remote (unpushed
work), since destroying those loses commits too:

```sh
git -C <worktree-path> log --branches --not --remotes --oneline | head
```

`treehouse status` shows the pool's own view (leased, in-use, running
processes) - fold that in so the report also says whether Treehouse considers
each worktree busy:

```sh
treehouse status                                 # run from inside <repo>
```

## Phase 3 - Report the full state

Present a clear, per-item report the user can act on. Cover **every** branch
and **every** worktree - including the clean, safe-to-remove ones - so the
user sees the whole picture, not just the problems. A table per section works
well:

**Branches**

| branch | local/remote | merged into `<target>`? | checked out by worktree | recommendation |
| ------ | ------------ | ----------------------- | ----------------------- | -------------- |

- merged + not checked out → safe to delete
- merged + checked out → free the worktree first, then delete
- not merged → keep (or flag for the user's attention)

**Worktrees**

| worktree | branch / detached | uncommitted changes | unpushed commits | treehouse state | recommendation |
| -------- | ----------------- | ------------------- | ---------------- | --------------- | -------------- |

- clean, merged, idle, unleased → safe to remove
- dirty / unpushed / leased / in-use → keep, and say exactly why

State recommendations, but do not act on them. End by asking the user which
branches and worktrees to clean up and which to keep.

## Phase 4 - Clean up what the user chose

Act only on the user's explicit selection, one item at a time. Match the tool
to the target.

### Remove a worktree (Treehouse)

Always go through `treehouse`, never `rm -rf` a worktree dir or hand-edit
`.git/worktrees`. Every removal is a dry run until `--yes`:

```sh
treehouse prune                     # dry-run: the safe set (merged, clean, idle, unleased)
treehouse prune --yes               # execute, after the user OK's the previewed list

treehouse destroy <worktree-path>            # dry-run for one specific worktree
treehouse destroy <worktree-path> --yes      # execute
```

For a worktree the safe pass skips, add only the `--include-*` flag matching
the risk the user explicitly accepted for that worktree:

| Skip reason      | Flag                 | Meaning                                     |
| ---------------- | -------------------- | ------------------------------------------- |
| dirty / unmerged | `--include-unlanded` | **DATA LOSS** - uncommitted/unmerged work   |
| running process  | `--include-in-use`   | processes terminated cleanly first          |
| leased           | `--include-leased`   | only with exact path named, never via `--all` |

`--include-unlanded` is the highest-caution flag: name the worktree and what
would be lost, and get explicit confirmation before running it. To release a
leased/idle worktree cleanly instead of destroying it: `treehouse return <path>`.

### Delete a branch

```sh
# Local - safe delete; -d refuses if not merged into the CURRENT branch,
# so this is a real check. Never -D unless the user accepts losing commits.
git -C <repo> branch -d <branch>

# Remote - affects a shared system; confirm exact remote + branch first.
git -C <repo> push <remote> --delete <branch>
```

If `git branch -d` refuses a branch you reported as squash-merged, that is
expected (its tip is not an ancestor of the current branch). Confirm with the
user, then use `-D` for that specific branch - do not silently force it.

Free a worktree before deleting the branch it has checked out (Phase 4
worktree step first, then the branch).

## Phase 5 - Verify and close out

```sh
git -C <repo> worktree list        # only worktrees the user meant to keep remain
git -C <repo> branch -vv           # locals down to target + still-active work
treehouse status
```

Summarize what was removed (branches, worktrees, remote branches) and what was
kept and why (unmerged, dirty, unpushed, leased, in-use), so the next run of
this skill starts from a known state.

## Golden rules

- **Report before you act.** Gather and present full state; the user chooses
  disposition; only then clean up.
- **`develop` is the assumed target** unless the user says otherwise; resolve
  it concretely (local, else `origin/`) and ask if it does not exist.
- **Detect squash-merges**, not just fast-forward merges - a merged PR usually
  leaves a branch that `--merged` will not list.
- **Never destroy work.** A worktree with uncommitted or unpushed changes, or
  a not-merged branch, is kept unless the user explicitly accepts the loss.
- **Worktrees via `treehouse`, branches via `git`** - never `rm -rf` a
  worktree, and free an in-use worktree before deleting its branch.
- **One project at a time**, and every destructive step is confirm-first.
