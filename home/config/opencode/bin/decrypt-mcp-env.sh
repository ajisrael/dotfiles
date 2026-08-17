#!/usr/bin/env bash
# Decrypt the opencode MCP server secrets for this machine.
#
# mcp.env.vault (committed, ansible-vault AES256 encrypted) is decrypted
# into mcp.env (gitignored) using the vault password in ~/.vault_pass
# (gitignored). The vault password file must exist on this machine - it is
# the single secret that unlocks everything.
#
# opencode does not auto-load mcp.env, so after decrypting, source it in
# your shell before launching opencode:
#
#   home/config/opencode/bin/decrypt-mcp-env.sh
#   set -a && source ~/dotfiles/home/config/opencode/mcp.env && set +a && opencode
#
# Usage:
#   decrypt-mcp-env.sh    # decrypt mcp.env.vault -> mcp.env
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
vault_pass_file="$HOME/.vault_pass"
source_file="$script_dir/../mcp.env.vault"
dest_file="$script_dir/../mcp.env"

if [ ! -f "$vault_pass_file" ]; then
  echo "error: $vault_pass_file not found." >&2
  echo "It holds the ansible-vault password and is never committed - copy it from" >&2
  echo "another machine or recreate it, then rerun this script." >&2
  exit 1
fi

if [ ! -f "$source_file" ]; then
  echo "error: $source_file not found (is the repo on the latest commit?)" >&2
  exit 1
fi

ansible-vault decrypt --vault-password-file "$vault_pass_file" --output "$dest_file" "$source_file"
chmod 600 "$dest_file"
echo "==> Secrets decrypted to $dest_file"
echo "    Source it before running opencode:  set -a && source $dest_file && set +a"
