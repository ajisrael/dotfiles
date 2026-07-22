#!/usr/bin/env bash
# Plash (https://github.com/sindresorhus/Plash) has no Homebrew cask - Sindre
# Sorhus ships it App Store-only via `mas`, and the current App Store build
# requires macOS 26.4, far past this machine's Ventura 13.7.8. Sorhus tags a
# matching older build per macOS version under the "older-releases" GitHub
# release; 2.14.1 is the one built against macOS 13. Pinned to that exact
# asset URL + checksum (not "latest") so a fresh machine gets a build that
# actually launches - bumping the version below is a deliberate, reviewed
# edit, same pattern as install-axi-family.sh.
#
# Run via home.nix's installPlash activation block. Idempotent: no-ops once
# the installed /Applications/Plash.app already matches PLASH_VERSION.
set -euo pipefail

PLASH_VERSION="2.14.1"
PLASH_URL="https://github.com/sindresorhus/Plash/releases/download/older-releases/Plash.${PLASH_VERSION}.-.macOS.13.zip"
PLASH_SHA256="56ab1bf6b4d8fcec826d2a4f726666e7b0021480c15ccd0567c6a928142ae2ad"

app_path="/Applications/Plash.app"
installed_version=""
if [ -d "$app_path" ]; then
  installed_version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app_path/Contents/Info.plist" 2>/dev/null || true)"
fi

if [ "$installed_version" = "$PLASH_VERSION" ]; then
  exit 0
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

zip_path="$work_dir/Plash.zip"
/usr/bin/curl -sL "$PLASH_URL" -o "$zip_path"

actual_sha256="$(/usr/bin/shasum -a 256 "$zip_path" | /usr/bin/cut -d' ' -f1)"
if [ "$actual_sha256" != "$PLASH_SHA256" ]; then
  echo "install-plash.sh: checksum mismatch for $PLASH_URL (expected $PLASH_SHA256, got $actual_sha256)" >&2
  exit 1
fi

/usr/bin/unzip -q "$zip_path" -d "$work_dir"

rm -rf "$app_path"
cp -R "$work_dir/Plash.app" "$app_path"
