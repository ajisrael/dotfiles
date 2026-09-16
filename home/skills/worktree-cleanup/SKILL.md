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

## Phase 1-3 - Gather and report state (use the companion script)

A companion script does all the state gathering in one pass so you do not
have to orchestrate the git/treehouse plumbing by hand. It never deletes or
resets anything. Its one ref-touching action is `git fetch --prune`, which
**runs by default** - the whole point of a cleanup pass is to reconcile local
state against the real remote, so stale remote-tracking refs get pruned up
front before anything is judged "merged". Pass `--no-fetch` to skip it and
stay fully read-only/offline.

```sh
# The script lives next to this SKILL.md. Depending on the harness that is:
#   ~/.kiro/skills/worktree-cleanup/review-worktrees.sh   (Kiro)
#   ~/.claude/skills/worktree-cleanup/review-worktrees.sh (Claude Code)
#   ~/.agents/skills/worktree-cleanup/review-worktrees.sh (generic)
review-worktrees.sh --repo <repo> [--target develop] [--no-fetch]
```

- `--repo <repo>` - the project to review (defaults to the current directory).
- `--target <branch>` - integration branch to test "merged?" against.
  Defaults to `develop`, falling back to `origin/develop`. If neither
  resolves the script exits non-zero and asks you to pass `--target`; relay
  that to the user and ask which branch is the integration target.
- `--no-fetch` - skip the default `git fetch --prune` and stay offline. Use
  when there is no network, or you just fetched and want to avoid the round
  trip. Warn that "merged?" may then reflect stale remote-tracking refs.
  (`--fetch` still exists as an explicit no-op alias for the default.)
- `--json` - machine-readable output if you would rather parse it than read
  the text tables.

The script prints two tables. **Branches**: each local and remote branch with
its merged status (`merged`, `merged(squash)`, `unmerged`, or `is-target`)
and which worktree, if any, has it checked out. **Worktrees**: each worktree
with counts of uncommitted changes, unpushed commits, and stashes, plus
Treehouse's own state (`available`, `leased`, `in-use`).

It detects **squash-merges** (via `git cherry`), not just fast-forward
merges - important because a merged PR usually leaves a branch whose tip is
not an ancestor of the target, which a plain `git branch --merged` would
wrongly call unmerged.

Caveats to keep in mind when reading the output:

- The stash count is **repo-global** (git stashes are not per-worktree), so
  every worktree row shows the same number - read it as "the repo has N
  stashes to check", not "this worktree has N".
- `unmerged` is the safe default when squash status is ambiguous. Do not
  assert an `unmerged` branch is disposable.

**Report to the user**: relay the two tables (or a tidied version), covering
every branch and every worktree - including the clean, safe-to-remove ones -
so they see the whole picture. Add a recommendation column based on the
signals:

- branch merged + not checked out → safe to delete
- branch merged + checked out by a worktree → free that worktree first
- branch unmerged → keep (flag for attention)
- worktree clean + idle + unleased (and on a merged/detached branch) → safe to remove
- worktree with uncommitted / unpushed / leased / in-use → keep, say why

State recommendations but **do not act**. End by asking the user which
branches and worktrees to clean up and which to keep.

### Doing it by hand (fallback)

If the script is unavailable, the underlying commands are:

```sh
git -C <repo> fetch --prune                                                           # default: sync + prune dead remotes (skip only if offline)
git -C <repo> for-each-ref --format='%(refname:short)%09%(worktreepath)' refs/heads   # branch -> worktree
git -C <repo> worktree list --porcelain                                               # incl. detached
git -C <repo> branch --merged <target>; git -C <repo> branch -r --merged <target>     # true merges
git -C <repo> cherry <target> <branch>          # all '-' lines => squash-merged
git -C <wt> status --porcelain; git -C <wt> log --branches --not --remotes --oneline  # dirty / unpushed
treehouse status                                 # pool state (run in <repo>)
```

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
- **Sync before you judge.** The review script runs `git fetch --prune` by
  default so "merged?" reflects the real remote, not stale tracking refs;
  only `--no-fetch` (offline) skips it, and then say the state may be stale.
- **`develop` is the assumed target** unless the user says otherwise; resolve
  it concretely (local, else `origin/`) and ask if it does not exist.
- **Detect squash-merges**, not just fast-forward merges - a merged PR usually
  leaves a branch that `--merged` will not list.
- **Never destroy work.** A worktree with uncommitted or unpushed changes, or
  a not-merged branch, is kept unless the user explicitly accepts the loss.
- **Worktrees via `treehouse`, branches via `git`** - never `rm -rf` a
  worktree, and free an in-use worktree before deleting its branch.
- **One project at a time**, and every destructive step is confirm-first.
