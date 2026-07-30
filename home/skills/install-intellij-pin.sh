#!/usr/bin/env bash
# homebrew-cask's intellij-idea/intellij-idea-ce recipes migrated to a
# `command_wrapper` cask stanza (upstream commits 88edf0d7de/dc76406554,
# 2026-07-20) that nix-homebrew's pinned brew engine (brew-src ref 6.0.12,
# confirmed as of 2026-07-29 - the latest nix-homebrew release still pins
# this far) doesn't implement yet - `brew bundle` fails outright reading
# either recipe with "undefined method 'command_wrapper'". configuration.nix's
# `onActivation.autoUpdate = true` means this isn't a one-time break: every
# `./rebuild.sh` re-pulls the incompatible recipe from the tap.
#
# Vendors the last known-good recipe (pinned to a specific homebrew-cask
# commit, from before the migration) into a throwaway local tap and installs
# from there instead - same pattern as install-podman.sh, for the same
# reason (`homebrew.brews`/`casks` can't express "this exact old commit",
# and current Homebrew refuses `brew install` on a bare local formula/cask
# file outside a tap). `brew pin --cask` then keeps `brew
# update`/`upgrade`/`bundle` from ever re-fetching the broken recipe.
#
# Re-check whether nix-homebrew's brew-src pin has caught up to
# command_wrapper support next time flake.nix's inputs are bumped, and
# migrate intellij-idea/intellij-idea-ce back to configuration.nix's
# `homebrew.casks` once it has.
#
# Run via home.nix's installIntellijPin activation block. Idempotent:
# no-ops once both casks are already pinned at their target version.
set -euo pipefail

# Matches what was already installed on this machine (confirmed via each
# cask's Caskroom directory name) rather than the latest pre-migration
# recipe, so this pin doesn't also trigger an unrelated up/downgrade.
IDEA_VERSION="2026.1.4,261.26222.65"
IDEA_FORMULA_COMMIT="2cbe54ba75"
IDEA_CE_VERSION="2025.2.5,252.28238.7"
IDEA_CE_FORMULA_COMMIT="4a8173137a"

brew_bin="/usr/local/bin/brew"
tap_name="local/intellij-pin"
# `brew --repository <tap>` (with an argument) reliably predicts this tap's
# path even before it exists. Bare `brew --repository` (no argument, as
# install-podman.sh uses) is NOT equivalent here - on this machine it
# resolves to nix-homebrew's `.homebrew-is-managed-by-nix` marker directory
# instead of the real Homebrew prefix, silently pointing every curl/mkdir
# below at a path Homebrew never reads from.
tap_dir="$("$brew_bin" --repository "$tap_name")"
caskroom="$("$brew_bin" --prefix)/Caskroom"

# `brew list --pinned --cask` (unlike `brew list --cask`/`--versions`)
# doesn't need to load either cask's current definition, so it stays
# reliable even while the upstream recipe is still broken - and it verifies
# the pin actually happened, not just that the app is installed.
already_pinned="$("$brew_bin" list --pinned --cask 2>/dev/null)"
if grep -qx "intellij-idea" <<<"$already_pinned" \
  && grep -qx "intellij-idea-ce" <<<"$already_pinned" \
  && [ -d "${caskroom}/intellij-idea/${IDEA_VERSION}" ] \
  && [ -d "${caskroom}/intellij-idea-ce/${IDEA_CE_VERSION}" ]; then
  exit 0
fi

if [ ! -d "$tap_dir" ]; then
  "$brew_bin" tap-new --no-git "$tap_name"
fi
mkdir -p "$tap_dir/Casks"

# Local taps expect a flat Casks/ directory, unlike homebrew-cask's own
# upstream repo (which shards by first letter, e.g. Casks/i/) - the URLs
# below fetch from that sharded upstream layout but write to this tap's
# flat one.
/usr/bin/curl -sL \
  "https://raw.githubusercontent.com/Homebrew/homebrew-cask/${IDEA_FORMULA_COMMIT}/Casks/i/intellij-idea.rb" \
  -o "$tap_dir/Casks/intellij-idea.rb"
/usr/bin/curl -sL \
  "https://raw.githubusercontent.com/Homebrew/homebrew-cask/${IDEA_CE_FORMULA_COMMIT}/Casks/i/intellij-idea-ce.rb" \
  -o "$tap_dir/Casks/intellij-idea-ce.rb"

"$brew_bin" install --cask "$tap_name/intellij-idea"
"$brew_bin" install --cask "$tap_name/intellij-idea-ce"
# `brew pin --cask` needs the fully-qualified tap-scoped name here - a bare
# `intellij-idea` still resolves against homebrew/cask's broken definition
# for this lookup and fails with the same command_wrapper error.
"$brew_bin" pin --cask "$tap_name/intellij-idea" "$tap_name/intellij-idea-ce"
