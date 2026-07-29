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

IDEA_VERSION="2026.2,262.8665.258"
IDEA_FORMULA_COMMIT="b8934104c1"
IDEA_CE_VERSION="2025.2.5,252.28238.7"
IDEA_CE_FORMULA_COMMIT="4a8173137a"

brew_bin="/usr/local/bin/brew"
tap_name="local/intellij-pin"
tap_dir="$("$brew_bin" --repository)/Library/Taps/local/homebrew-intellij-pin"

installed_idea_version="$("$brew_bin" list --cask --versions intellij-idea 2>/dev/null | /usr/bin/awk '{print $2}')"
installed_idea_ce_version="$("$brew_bin" list --cask --versions intellij-idea-ce 2>/dev/null | /usr/bin/awk '{print $2}')"

if [ "$installed_idea_version" = "${IDEA_VERSION%%,*}" ] && [ "$installed_idea_ce_version" = "${IDEA_CE_VERSION%%,*}" ]; then
  exit 0
fi

if [ ! -d "$tap_dir" ]; then
  "$brew_bin" tap-new --no-git "$tap_name"
fi
mkdir -p "$tap_dir/Casks/i"

/usr/bin/curl -sL \
  "https://raw.githubusercontent.com/Homebrew/homebrew-cask/${IDEA_FORMULA_COMMIT}/Casks/i/intellij-idea.rb" \
  -o "$tap_dir/Casks/i/intellij-idea.rb"
/usr/bin/curl -sL \
  "https://raw.githubusercontent.com/Homebrew/homebrew-cask/${IDEA_CE_FORMULA_COMMIT}/Casks/i/intellij-idea-ce.rb" \
  -o "$tap_dir/Casks/i/intellij-idea-ce.rb"

"$brew_bin" install --cask "$tap_name/intellij-idea"
"$brew_bin" install --cask "$tap_name/intellij-idea-ce"
"$brew_bin" pin --cask intellij-idea intellij-idea-ce
