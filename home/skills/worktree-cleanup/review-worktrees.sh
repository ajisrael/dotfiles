#!/usr/bin/env bash
#
# review-worktrees.sh - read-only state gather for the worktree-cleanup skill.
#
# Reviews every local and remote branch and every git worktree in a project
# and reports, per item, exactly what the agent needs to recommend a cleanup:
#
#   Branches   - merged into the target branch? (true-merge AND squash-merge),
#                and which worktree (if any) currently has it checked out.
#   Worktrees  - uncommitted changes, unpushed commits, and Treehouse's own
#                view (leased / running process / available).
#
# This script NEVER mutates anything (no branch/worktree deletion, no reset).
# `git fetch --prune` is the only network/ref-touching action and is opt-in
# via --fetch. Acting on the report (deleting branches, pruning worktrees) is
# the agent's job, done interactively with the user - not this script's.
#
# Usage:
#   review-worktrees.sh [--repo <path>] [--target <branch>] [--fetch] [--json]
#
#   --repo <path>     Repository to review. Default: current directory.
#   --target <branch> Integration branch to test "merged?" against.
#                     Default: develop (falls back to origin/develop). If
#                     neither resolves, the script exits non-zero and asks
#                     the caller to pass --target explicitly.
#   --fetch           Run `git fetch --prune` first (network; prunes dead
#                     remote-tracking refs). Off by default to stay read-only.
#   --json            Emit machine-readable JSON instead of the text report.
#
# Exit codes: 0 ok, 1 usage/target-resolution error, 2 not a git repo.

set -euo pipefail

repo="."
target=""
do_fetch=0
as_json=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)   repo="${2:?--repo needs a path}"; shift 2 ;;
    --target) target="${2:?--target needs a branch}"; shift 2 ;;
    --fetch)  do_fetch=1; shift ;;
    --json)   as_json=1; shift ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "review-worktrees.sh: unknown argument: $1" >&2; exit 1 ;;
  esac
done

git() { command git -C "$repo" "$@"; }

# --- preconditions ----------------------------------------------------------

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "review-worktrees.sh: '$repo' is not a git repository" >&2
  exit 2
fi

toplevel="$(git rev-parse --show-toplevel)"

if [ "$do_fetch" -eq 1 ]; then
  git fetch --prune >/dev/null 2>&1 || true
fi

# --- resolve the target branch ----------------------------------------------

resolve_target() {
  if [ -n "$target" ]; then
    if git rev-parse --verify --quiet "$target" >/dev/null; then
      echo "$target"; return 0
    fi
    if git rev-parse --verify --quiet "origin/$target" >/dev/null; then
      echo "origin/$target"; return 0
    fi
    return 1
  fi
  # default: develop, then origin/develop
  if git rev-parse --verify --quiet develop >/dev/null; then
    echo develop; return 0
  fi
  if git rev-parse --verify --quiet origin/develop >/dev/null; then
    echo origin/develop; return 0
  fi
  return 1
}

if ! target_ref="$(resolve_target)"; then
  echo "review-worktrees.sh: could not resolve a target branch." >&2
  echo "  Tried: ${target:-develop} and origin/${target:-develop}." >&2
  echo "  Re-run with --target <branch> naming this project's integration branch." >&2
  exit 1
fi
target_sha="$(git rev-parse "$target_ref")"

# --- map: branch -> worktree path (handles attached branches) ---------------
# %(worktreepath) is empty when the branch is not checked out anywhere.

declare -A branch_worktree=()
while IFS=$'\t' read -r br wt; do
  [ -n "$br" ] || continue
  branch_worktree["$br"]="$wt"
done < <(git for-each-ref --format='%(refname:short)%09%(worktreepath)' refs/heads)

# --- gather worktrees (including detached-HEAD Treehouse ones) ---------------
# Parallel arrays indexed together.

wt_paths=(); wt_heads=(); wt_branches=()
cur_path=""; cur_head=""; cur_branch=""
flush_wt() {
  [ -n "$cur_path" ] || return 0
  wt_paths+=("$cur_path"); wt_heads+=("$cur_head"); wt_branches+=("$cur_branch")
  cur_path=""; cur_head=""; cur_branch=""
}
while IFS= read -r line; do
  case "$line" in
    "worktree "*) flush_wt; cur_path="${line#worktree }" ;;
    "HEAD "*)     cur_head="${line#HEAD }" ;;
    "branch "*)   cur_branch="${line#branch refs/heads/}" ;;
    "detached")   cur_branch="(detached)" ;;
    "")           ;;
  esac
done < <(git worktree list --porcelain)
flush_wt

# --- Treehouse per-worktree state (path -> state string) --------------------

declare -A th_state=()
if command -v treehouse >/dev/null 2>&1; then
  th_json="$(cd "$toplevel" && treehouse status --json 2>/dev/null || echo '[]')"
  if command -v jq >/dev/null 2>&1 && [ -n "$th_json" ]; then
    while IFS=$'\t' read -r p s; do
      [ -n "$p" ] && th_state["$p"]="$s"
    done < <(printf '%s' "$th_json" | jq -r '
      .[]? |
      [ .path,
        ( if (.lease_id // "") != "" then "leased(" + (.lease_holder // "?") + ")"
          elif ((.processes // []) | length) > 0 then "in-use"
          else (.status // "available") end )
      ] | @tsv' 2>/dev/null)
  fi
fi

# --- classification helpers -------------------------------------------------

# merged status: "merged" (tip is ancestor of target), "merged(squash)"
# (all commits already in target per git-cherry), or "unmerged".
merged_status() {
  local ref="$1" sha
  sha="$(git rev-parse --verify --quiet "$ref" 2>/dev/null)" || { echo "unknown"; return; }
  [ "$sha" = "$target_sha" ] && { echo "is-target"; return; }
  if git merge-base --is-ancestor "$ref" "$target_ref" 2>/dev/null; then
    echo "merged"; return
  fi
  # squash detection: git cherry marks with '-' commits already in target.
  local cherry plus
  cherry="$(git cherry "$target_ref" "$ref" 2>/dev/null || true)"
  if [ -z "$cherry" ]; then
    # no commits ahead of target at all -> effectively merged
    echo "merged"; return
  fi
  plus="$(printf '%s\n' "$cherry" | grep -c '^+' || true)"
  if [ "$plus" -eq 0 ]; then echo "merged(squash)"; else echo "unmerged"; fi
}

# worktree dirtiness: uncommitted changes + unpushed commits + stashes.
# NOTE: `git stash list` is repo-global, not per-worktree, so the stash count
# is the same for every worktree of the repo - treat it as "the repo has N
# stashes to check", not "this worktree has N stashes".
wt_dirty() { # <path> -> "changes|unpushed|stashes"
  local p="$1" changes unpushed stashes
  changes="$(command git -C "$p" status --porcelain 2>/dev/null | grep -c . || true)"
  unpushed="$(command git -C "$p" log --branches --not --remotes --oneline 2>/dev/null | grep -c . || true)"
  stashes="$(command git -C "$p" stash list 2>/dev/null | grep -c . || true)"
  echo "${changes}|${unpushed}|${stashes}"
}

# --- collect branch rows ----------------------------------------------------
# fields: name | scope | merged | worktree
branch_rows=()
while IFS= read -r br; do
  [ -n "$br" ] || continue
  branch_rows+=("$br"$'\t'"local"$'\t'"$(merged_status "$br")"$'\t'"${branch_worktree[$br]:-}")
done < <(git for-each-ref --format='%(refname:short)' refs/heads)

while IFS= read -r br; do
  [ -n "$br" ] || continue
  case "$br" in
    */HEAD) continue ;;                          # skip origin/HEAD symref
  esac
  # skip a bare remote name (e.g. "origin") that has no branch component
  case "$br" in
    */*) : ;;
    *) continue ;;
  esac
  branch_rows+=("$br"$'\t'"remote"$'\t'"$(merged_status "$br")"$'\t')
done < <(git for-each-ref --format='%(refname:short)' refs/remotes)

# --- output -----------------------------------------------------------------

if [ "$as_json" -eq 1 ]; then
  jstr() { printf '%s' "${1-}" | jq -Rs 'rtrimstr("\n")'; }  # always a valid JSON string
  {
    printf '{\n'
    printf '  "repo": %s,\n' "$(jstr "$toplevel")"
    printf '  "target": %s,\n' "$(jstr "$target_ref")"
    printf '  "branches": [\n'
    first=1
    for row in "${branch_rows[@]}"; do
      IFS=$'\t' read -r name scope merged wt <<<"$row"
      [ $first -eq 1 ] || printf ',\n'; first=0
      printf '    {"name":%s,"scope":%s,"merged":%s,"worktree":%s}' \
        "$(jstr "$name")" "$(jstr "$scope")" "$(jstr "$merged")" "$(jstr "${wt:-}")"
    done
    printf '\n  ],\n  "worktrees": [\n'
    first=1
    for i in "${!wt_paths[@]}"; do
      p="${wt_paths[$i]}"
      IFS='|' read -r ch up st <<<"$(wt_dirty "$p")"
      [ $first -eq 1 ] || printf ',\n'; first=0
      printf '    {"path":%s,"branch":%s,"head":%s,"uncommitted":%s,"unpushed":%s,"stashes":%s,"treehouse":%s}' \
        "$(jstr "$p")" "$(jstr "${wt_branches[$i]}")" "$(jstr "${wt_heads[$i]:0:12}")" \
        "${ch:-0}" "${up:-0}" "${st:-0}" "$(jstr "${th_state[$p]:-unknown}")"
    done
    printf '\n  ]\n}\n'
  }
  exit 0
fi

# text report
printf 'Repo:   %s\n' "$toplevel"
printf 'Target: %s\n\n' "$target_ref"

printf 'BRANCHES\n'
printf '%-32s %-7s %-15s %s\n' "branch" "scope" "merged?" "checked out by worktree"
printf '%-32s %-7s %-15s %s\n' "------" "-----" "-------" "-----------------------"
for row in "${branch_rows[@]}"; do
  IFS=$'\t' read -r name scope merged wt <<<"$row"
  printf '%-32s %-7s %-15s %s\n' "$name" "$scope" "$merged" "${wt:-}"
done

printf '\nWORKTREES\n'
printf '%-48s %-16s %-6s %-6s %-6s %s\n' "path" "branch" "uncmt" "unpsh" "stash" "treehouse"
printf '%-48s %-16s %-6s %-6s %-6s %s\n' "----" "------" "-----" "-----" "-----" "---------"
for i in "${!wt_paths[@]}"; do
  p="${wt_paths[$i]}"
  IFS='|' read -r ch up st <<<"$(wt_dirty "$p")"
  # shorten home dir for readability
  disp="${p/#$HOME/~}"
  printf '%-48s %-16s %-6s %-6s %-6s %s\n' \
    "$disp" "${wt_branches[$i]}" "${ch:-0}" "${up:-0}" "${st:-0}" "${th_state[$p]:-unknown}"
done

printf '\nLegend: merged = tip is ancestor of target; merged(squash) = all commits already in target (git cherry); is-target = the target branch itself.\n'
printf 'uncmt/unpsh/stash = counts of uncommitted changes / unpushed commits / stashes (destroying loses these).\n'
