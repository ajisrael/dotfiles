#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
sudo darwin-rebuild switch --flake "$DIR#mac"
echo "Rebuild successful!"
