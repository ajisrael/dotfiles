#!/usr/bin/env bash
# Prunes old nix-darwin (system) and home-manager generations down to the
# last KEEP, then garbage-collects the store paths that were only kept
# alive by the generations just removed.
#
# Deleting a generation just drops it as a GC root - the disk space isn't
# reclaimed until nix-collect-garbage actually runs, which is why both
# steps happen here together.
#
# Must run as root (via sudo, or as root's own cron job/LaunchDaemon) -
# /nix/var/nix/profiles/system is root-owned on this machine's classic
# multi-user Nix install (see configuration.nix's `nix.enable = false`
# comment for why nix-darwin doesn't manage the daemon here). Resolves the
# invoking user's home via $SUDO_USER so it still finds the right
# ~/.local/state/nix/profiles/home-manager when run with `sudo prune.sh`
# interactively, not just from a root cron job.
set -euo pipefail

KEEP=10

if [ "$(id -u)" -ne 0 ]; then
  echo "prune.sh: must run as root (sudo ./prune.sh)" >&2
  exit 1
fi

target_user="${SUDO_USER:-$(stat -f '%Su' /dev/console)}"
target_home="$(dscl . -read "/Users/${target_user}" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"

if [ -z "$target_home" ] || [ ! -d "$target_home" ]; then
  echo "prune.sh: couldn't resolve a home directory for user '${target_user}'" >&2
  exit 1
fi

home_manager_profile="${target_home}/.local/state/nix/profiles/home-manager"

echo "==> Pruning system generations (keeping last ${KEEP})"
nix-env --profile /nix/var/nix/profiles/system --delete-generations "+${KEEP}"

if [ -e "$home_manager_profile" ]; then
  echo "==> Pruning home-manager generations for ${target_user} (keeping last ${KEEP})"
  nix-env --profile "$home_manager_profile" --delete-generations "+${KEEP}"
else
  echo "==> No home-manager profile found at ${home_manager_profile}, skipping"
fi

echo "==> Collecting garbage"
nix-collect-garbage

echo "Done."
