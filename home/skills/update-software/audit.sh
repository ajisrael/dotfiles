#!/usr/bin/env bash
# audit.sh - itemize every version-pinned piece of software this repo manages
# and compare the pinned version against the latest available upstream.
#
# Read-only: it never edits a file, bumps a version, or runs a rebuild. It
# only reads the pins out of this repo's own files and queries upstream
# (npm/GitHub/Homebrew) for the latest version. Network lookups are
# best-effort - any failure prints "?" for that item's latest column rather
# than aborting, so a flaky network degrades the report instead of breaking
# it. The update-software SKILL.md drives the actual per-item bump workflow
# off this report.
#
# Agnostic by design (this repo is public and must not reference any employer
# or downstream repo): it audits only the pins that live HERE. The pins a
# superset/work repo adds on top (vendoring this one) are audited by that
# repo's own skill - see its SKILL.md. Resolves this repo's root from the
# script location so it works both in ~/dotfiles and when vendored elsewhere.
set -uo pipefail

# Repo root = two levels up from home/skills/update-software/audit.sh.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# ---- column helpers --------------------------------------------------------
# A row is: <name> <pinned> <latest> <where> <how-to-bump-pointer>
# Collected into arrays, printed as an aligned table at the end so the
# (slow, networked) latest-version lookups can run without the output
# interleaving mid-fetch.
names=(); pinneds=(); latests=(); wheres=()

add_row() { names+=("$1"); pinneds+=("$2"); latests+=("${3:-?}"); wheres+=("$4"); }

# npm_latest <pkg> -> latest published version, or empty on failure.
npm_latest() { command -v npm >/dev/null 2>&1 && npm view "$1" version 2>/dev/null || true; }

# gh_latest_tag <owner/repo> -> highest semver tag (strips a leading v), or
# empty. Uses git ls-remote so it needs no gh auth and no API token.
gh_latest_tag() {
  git ls-remote --tags --refs "https://github.com/$1" 2>/dev/null \
    | awk -F/ '{print $NF}' | sed 's/^v//' | sort -V | tail -1
}

# brew_latest_cask / brew_latest_formula <name> -> version string from brew's
# json, or empty. Reads the already-fetched local tap (no forced update).
BREW="/usr/local/bin/brew"
brew_latest_cask() {
  [ -x "$BREW" ] || return 0
  "$BREW" info --cask --json=v2 "$1" 2>/dev/null | jq -r '.casks[0].version // empty' 2>/dev/null || true
}
brew_latest_formula() {
  [ -x "$BREW" ] || return 0
  "$BREW" info --formula --json=v2 "$1" 2>/dev/null \
    | jq -r '.formulae[0].versions.stable // empty' 2>/dev/null || true
}

# first_capture <file> <regex-with-one-group> -> the captured group of the
# first match, or empty. Used to read a pinned version straight out of a repo
# file so the "pinned" column can never drift from the real source.
first_capture() {
  local file="$1" re="$2"
  [ -f "$file" ] || return 0
  sed -nE "s/.*${re}.*/\1/p" "$file" 2>/dev/null | head -1
}

echo "Auditing pinned software in: $REPO_ROOT"
echo "(looking up latest upstream versions - this takes a few seconds)"
echo

# ---- Nix flake inputs ------------------------------------------------------
# These are pinned to the 26.05 RELEASE BRANCHES in flake.nix, and to exact
# revisions in flake.lock. "Latest" here is intentionally NOT "the newest
# nixpkgs release" - moving off 26.05 drops x86_64-darwin support (see
# flake.nix's own comment). So the meaningful update is "newer commit on the
# SAME 26.05 branch", obtained with `nix flake update`. The audit flags the
# three inputs as a group and defers the real check to the SKILL workflow,
# which runs `nix flake update --dry-run`-style diffing. We surface the
# locked branch so the report is self-explanatory.
flake_lock="$REPO_ROOT/flake.lock"
if [ -f "$flake_lock" ] && command -v jq >/dev/null 2>&1; then
  for inp in nixpkgs nix-darwin home-manager; do
    rev="$(jq -r --arg i "$inp" '.nodes[$i].locked.rev // empty' "$flake_lock" 2>/dev/null | cut -c1-7)"
    add_row "$inp" "${rev:-?} (26.05)" "run: nix flake update" "flake.lock"
  done
fi

# ---- treehouse (pinned buildGoModule) --------------------------------------
th_pin="$(first_capture "$REPO_ROOT/pkgs/treehouse.nix" 'version = "([0-9][^"]*)"')"
add_row "treehouse" "${th_pin:-?}" "$(gh_latest_tag kunchenguid/treehouse)" "pkgs/treehouse.nix"

# ---- pinned npm globals in home.nix (opencode-ai, acpx) --------------------
home_nix="$REPO_ROOT/home.nix"
oc_pin="$(first_capture "$home_nix" 'opencode-ai@([0-9][^"'"'"' ]*)')"
add_row "opencode-ai" "${oc_pin:-?}" "$(npm_latest opencode-ai)" "home.nix installOpencode"
acpx_pin="$(first_capture "$home_nix" 'acpx@([0-9][^"'"'"' ]*)')"
add_row "acpx" "${acpx_pin:-?}" "$(npm_latest acpx)" "home.nix installAcpx"

# ---- axi-family pinned npm globals (install-axi-family.sh) ------------------
axi_file="$REPO_ROOT/home/skills/install-axi-family.sh"
if [ -f "$axi_file" ]; then
  # Each line is: installAxiPkg <pkg> <version> <skillName>
  while read -r pkg ver; do
    [ -n "$pkg" ] || continue
    add_row "$pkg" "$ver" "$(npm_latest "$pkg")" "install-axi-family.sh"
  done < <(sed -nE 's/^installAxiPkg[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+).*/\1 \2/p' "$axi_file")
fi

# ---- podman (pinned brew formula @ commit) ---------------------------------
# Deliberately Intel-pinned (upstream dropped x86_64 at 6.0). "Latest" from
# brew will be the arm64-only version and is NOT installable here - surface
# it for information but the SKILL marks podman as a special, usually-frozen
# case.
pod_pin="$(first_capture "$REPO_ROOT/home/skills/install-podman.sh" 'PODMAN_VERSION="([^"]*)"')"
add_row "podman" "${pod_pin:-?}" "$(brew_latest_formula podman) (arm64-only)" "install-podman.sh"

# ---- intellij (pinned casks @ commit) --------------------------------------
# Pinned to pre-command_wrapper recipes until nix-homebrew's brew engine
# catches up (see the script's header). "Latest" from brew is informational.
idea_pin="$(first_capture "$REPO_ROOT/home/skills/install-intellij-pin.sh" 'IDEA_VERSION="([^",]*)')"
add_row "intellij-idea" "${idea_pin:-?}" "$(brew_latest_cask intellij-idea)" "install-intellij-pin.sh"
ideace_pin="$(first_capture "$REPO_ROOT/home/skills/install-intellij-pin.sh" 'IDEA_CE_VERSION="([^",]*)')"
add_row "intellij-idea-ce" "${ideace_pin:-?}" "$(brew_latest_cask intellij-idea-ce)" "install-intellij-pin.sh"

# ---- Homebrew brews/casks declared in configuration.nix --------------------
# These are NOT version-pinned in the repo (the repo just names them; their
# version floats with the tap on `brew upgrade`). Only the packages THIS repo
# explicitly declares are reported - not brew's full outdated dependency
# closure (transitive deps like libpng/cairo/nspr are noise the user never
# chose). The declared names are parsed straight out of configuration.nix's
# `brews = [ ... ]` and `casks = [ ... ]` lists so the audit scope can't
# drift from what the repo actually manages. The SKILL explains these upgrade
# through plain `brew upgrade <name>`, not a repo edit.
config_nix="$REPO_ROOT/configuration.nix"
# declared_names <brews|casks> -> the quoted entries of that list in
# configuration.nix. Grabs the "brews = [ ... ]" / "casks = [ ... ]" block
# (possibly multi-line) and pulls each "quoted" token out of it. Comments in
# the Nix file are "# ..." and carry no quotes, so they're naturally skipped.
declared_names() {
  [ -f "$config_nix" ] || return 0
  awk -v key="$1" '
    $0 ~ (key " = \\[") { inblk=1 }
    inblk {
      while (match($0, /"[^"]+"/)) {
        tok=substr($0, RSTART+1, RLENGTH-2); print tok
        $0=substr($0, RSTART+RLENGTH)
      }
    }
    inblk && /\]/ { inblk=0 }
  ' "$config_nix"
}
if [ -x "$BREW" ]; then
  outdated_casks="$("$BREW" outdated --cask --greedy --quiet 2>/dev/null)"
  outdated_brews="$("$BREW" outdated --formula --quiet 2>/dev/null)"
  while read -r c; do
    [ -n "$c" ] || continue
    # Only report a declared cask when brew says it's actually outdated.
    grep -qx "$c" <<<"$outdated_casks" || continue
    installed="$("$BREW" list --cask --versions "$c" 2>/dev/null | awk '{print $2}')"
    add_row "$c (cask)" "${installed:-?}" "$(brew_latest_cask "$c")" "configuration.nix casks / brew upgrade"
  done < <(declared_names casks)
  while read -r f; do
    [ -n "$f" ] || continue
    grep -qx "$f" <<<"$outdated_brews" || continue
    installed="$("$BREW" list --formula --versions "$f" 2>/dev/null | awk '{print $2}')"
    add_row "$f (brew)" "${installed:-?}" "$(brew_latest_formula "$f")" "configuration.nix brews / brew upgrade"
  done < <(declared_names brews)
fi

# ---- aligned output + outdated summary -------------------------------------
printf '%-22s %-26s %-26s %s\n' "SOFTWARE" "PINNED/INSTALLED" "LATEST UPSTREAM" "WHERE / HOW"
printf '%-22s %-26s %-26s %s\n' "--------" "----------------" "---------------" "-----------"
outdated=0
for i in "${!names[@]}"; do
  n="${names[$i]}"; p="${pinneds[$i]}"; l="${latests[$i]}"; w="${wheres[$i]}"
  # Mark a row with "*" when a bare pinned-vs-latest semver comparison says
  # upstream is newer. Only meaningful for the plain-version rows (npm/github
  # /brew), not the flake rows whose "latest" is a run-this instruction - so
  # only compare when both look like versions.
  mark=" "
  if [[ "$p" =~ ^[0-9] ]] && [[ "$l" =~ ^[0-9] ]]; then
    pbase="${p%% *}"; lbase="${l%% *}"
    if [ "$pbase" != "$lbase" ] && [ "$(printf '%s\n%s\n' "$pbase" "$lbase" | sort -V | tail -1)" = "$lbase" ]; then
      mark="*"; outdated=$((outdated+1))
    fi
  fi
  printf '%s%-21s %-26s %-26s %s\n' "$mark" "$n" "$p" "$l" "$w"
done
echo
echo "Rows marked * have a newer upstream version. $outdated updatable item(s)."
echo "Pick which to update; the update-software SKILL has the per-item bump steps."
