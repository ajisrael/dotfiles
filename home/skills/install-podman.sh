#!/usr/bin/env bash
# Podman 6.0.0 dropped Intel Mac support at the Go source level (upstream
# SUPPORT.md: "code for Intel Macs was removed and will no longer compile for
# that platform") and Homebrew's formula gained a matching `depends_on arch:
# :arm64` guard the same release - this is a hard wall, not something a macOS
# upgrade lifts, since the gate is the CPU architecture, not the OS version.
# homebrew-core's last commit with a working Intel (x86_64) bottle is
# a9b2821f51 ("podman: update 5.8.3 bottle").
#
# `homebrew.brews` can't express "this exact old commit" (it always resolves
# against the tap's current formula, i.e. 6.0.1/arm64-only), and current
# Homebrew (6.0.9, confirmed on this machine) refuses `brew install` on a
# bare local formula file ("Homebrew requires formulae to be in a tap") - so
# this vendors that pinned formula into a throwaway local tap
# (local/podman-pin) and installs from there instead. Same imperative-script
# pattern as install-plash.sh, for the same reason: doesn't fit the
# declarative homebrew.brews list.
#
# Run via home.nix's installPodman activation block. Idempotent: no-ops once
# the installed version already matches PODMAN_VERSION. `brew pin` keeps
# `brew update`/`brew upgrade`/`brew bundle` from ever bumping this back to
# the tap's current arm64-only formula.
set -euo pipefail

PODMAN_VERSION="5.8.3"
PODMAN_FORMULA_COMMIT="a9b2821f51"
PODMAN_FORMULA_URL="https://raw.githubusercontent.com/Homebrew/homebrew-core/${PODMAN_FORMULA_COMMIT}/Formula/p/podman.rb"

brew_bin="/usr/local/bin/brew"
tap_name="local/podman-pin"
tap_dir="$("$brew_bin" --repository)/Library/Taps/local/homebrew-podman-pin"

installed_version="$("$brew_bin" list --versions podman 2>/dev/null | /usr/bin/awk '{print $2}')"

if [ "$installed_version" = "$PODMAN_VERSION" ]; then
  exit 0
fi

if [ ! -d "$tap_dir" ]; then
  "$brew_bin" tap-new local/podman-pin
fi

/usr/bin/curl -sL "$PODMAN_FORMULA_URL" -o "$tap_dir/Formula/podman.rb"
"$brew_bin" install "$tap_name/podman"
"$brew_bin" pin podman
