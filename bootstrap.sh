#!/usr/bin/env bash
# Takes a fresh Mac from nothing to a built nix-darwin config.
# Run this once. After it finishes, use ./rebuild.sh for every later change.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

echo "==> Step 1: Nix"
if command -v nix >/dev/null 2>&1; then
  echo "    nix already installed, skipping"
else
  # Determinate Nix and the generic nixos.org installer's *latest*
  # release both require macOS 14+ (Sonoma). On Ventura (13.x) or older,
  # use the classic multi-user installer pinned to an older release that
  # still supports macOS 10.12.6+ instead:
  #   curl -sL https://releases.nixos.org/nix/nix-2.24.10/install | sh -s -- --daemon
  # On macOS 14+, the standard installer works:
  #   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm
  echo "    No 'nix' found. Install it first (see the comment in this script for the right"
  echo "    installer for your macOS version), open a new terminal, then re-run ./bootstrap.sh."
  exit 1
fi
# shellcheck disable=SC1091
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null || true

echo "==> Step 2: personalize the configured username"
# Do this before any sudo call: sudo resets $USER to root, so whoami has to
# run as the real interactive user first.
REAL_USER="$(whoami)"
FLAKE_USER="$(sed -nE 's/^[[:space:]]*user = "([^"]+)";.*/\1/p' "$DIR/flake.nix" | head -n1)"
if [ -z "$FLAKE_USER" ]; then
  echo "    Could not find the single \"user = \" line in flake.nix."
  echo "    Edit flake.nix yourself before continuing."
  exit 1
elif [ "$FLAKE_USER" != "$REAL_USER" ]; then
  echo "    flake.nix is configured for user \"$FLAKE_USER\", but you are \"$REAL_USER\"."
  read -r -p "    Rewrite flake.nix's \"user = \" line to \"$REAL_USER\"? [y/N] " REPLY
  if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
    sed -i '' -E "s/^([[:space:]]*user = \")[^\"]+(\";.*)/\1${REAL_USER}\2/" "$DIR/flake.nix"
    echo "    Updated. Review the change with: git diff flake.nix"
  else
    echo "    Skipped. Edit the single \"user = \" line in flake.nix yourself before continuing."
    exit 1
  fi
else
  echo "    flake.nix already matches \"$REAL_USER\", nothing to do."
fi

echo "==> Step 3: first darwin-rebuild switch (pinned to nix-darwin-26.05)"
# darwin-rebuild doesn't exist yet on a fresh machine, so run it straight
# from the flake this once. After this, rebuild.sh works normally.
#
# On Ventura (13.x) or older: configuration.nix sets nix.enable = false
# on purpose. nixpkgs-26.05's own `nix` package requires macOS 14+ and
# will crash the nix-daemon LaunchDaemon with a dyld error if nix-darwin
# is allowed to install/manage it. Leave nix.enable = false until this
# Mac is on macOS 14+, or the daemon breaks and needs manual repair
# (see ~/dev-env-followups.md for the exact recovery steps).
# sudo resets PATH to a secure default that excludes /nix/.../bin, so a
# freshly installed `nix` would not be found under sudo even though it's
# on PATH here. Resolve the absolute path first and invoke that instead.
NIX_BIN="$(command -v nix)"
# "mac" is this flake's host label - if you renamed it, change
# it in flake.nix and rebuild.sh too.
sudo "$NIX_BIN" --extra-experimental-features "nix-command flakes" run \
  github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- \
  switch --flake "$DIR#mac"
# If this still fails with "nix: command not found", open a new terminal
# and re-run ./bootstrap.sh.

echo "==> Done. Use ./rebuild.sh for future changes."
