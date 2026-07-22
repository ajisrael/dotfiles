#!/usr/bin/env bash
# Pins and installs the axi-family CLIs (kunchenguid's agent-ergonomic
# GitHub/browser/HTML-review wrappers) to exact, reviewed npm versions,
# instead of relying on their documented unpinned `npx -y <pkg>` skill
# invocation - a real supply-chain exposure once paired with no-mistakes'
# elevated pipeline-agent invocations. Bumping a version below is a
# deliberate, reviewed edit - see
# ~/.claude/plans/memoized-mixing-quilt.md for the rationale.
#
# Run via home.nix's installAxiFamily activation block, which sets
# NPM_CONFIG_PREFIX before calling this (Nix's nodejs defaults npm's
# global-install prefix to its own read-only /nix/store path, so this
# script never overrides the prefix itself - it just inherits it).
#
# Also regenerates each package's local SKILL.md via sync-axi-skill.sh on
# every run (not only when the version changes), so bumping a version here
# and running ./rebuild.sh updates both the binary and its matching skill
# together with no manual re-copy/re-diff.
#
# Usage: install-axi-family.sh <npm-bin> <jq-bin> <skills-dir>
set -euo pipefail

npm_bin="$1"
jq_bin="$2"
skills_dir="$3"
sync_script="$(dirname "${BASH_SOURCE[0]}")/sync-axi-skill.sh"

installAxiPkg() {
  local pkg="$1" version="$2" skillName="$3"
  local installed
  # npm ls -g exits non-zero when the package isn't installed yet (or the
  # prefix dir doesn't exist yet on a fresh machine) - under this script's
  # `set -e -o pipefail`, that would otherwise kill the whole activation
  # silently before ever reaching the install step below.
  installed="$( ("$npm_bin" ls -g --depth=0 --json "$pkg" 2>/dev/null || true) \
    | "$jq_bin" -r --arg pkg "$pkg" '.dependencies[$pkg].version // ""')"
  if [ "$installed" != "$version" ]; then
    "$npm_bin" install -g "$pkg@$version"
  fi
  bash "$sync_script" "$npm_bin" "$pkg" "$skillName" "${skills_dir}/${skillName}"
}

installAxiPkg gh-axi 0.1.27 gh-axi
installAxiPkg chrome-devtools-axi 0.1.26 chrome-devtools-axi
installAxiPkg lavish-axi 0.1.42 lavish
