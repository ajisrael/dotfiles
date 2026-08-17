#!/usr/bin/env bash
# Smoke-tests the environment ./rebuild.sh is supposed to produce: PATH
# binaries, symlinked config files, and a couple of functional checks
# (tmux config actually loads, darwin-rebuild actually runs). Entirely
# read-only - safe to run in a brand new terminal before closing the one
# you rebuilt from, so a broken rebuild is caught while the last-known-good
# shell is still open.
#
# Not a replacement for `nix flake check`/`--dry-run` (those validate the
# Nix build before you apply it); this validates the result after you did.
#
# dotfiles-amway's own verify.sh runs this first (checking here, falling
# back to its vendored vendor/personal/verify.sh copy - same pattern as
# prune.sh), then layers its work-only checks on top.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

red=$'\e[1;31m'; grn=$'\e[1;32m'; yel=$'\e[1;33m'; end=$'\e[0m'

pass_count=0
fail_count=0
warn_count=0

pass() { printf "${grn}PASS${end}  %s\n" "$1"; pass_count=$((pass_count + 1)); }
fail() { printf "${red}FAIL${end}  %s\n" "$1"; fail_count=$((fail_count + 1)); }
warn() { printf "${yel}WARN${end}  %s\n" "$1"; warn_count=$((warn_count + 1)); }

section() { printf "\n${grn}== %s ==${end}\n" "$1"; }

section "PATH binaries"

# gnupg/maven are the nixpkgs package names, not the binaries they ship
# (gpg, mvn) - check the binaries actually on PATH instead.
for bin in darwin-rebuild nix tmux git rg fd fzf jq lazygit lazydocker nvim tree wget gpg direnv ansible ansible-vault aws cloudflared cmake gh go mvn mkcert pandoc stow tldr yarn node npm tmux-sessionizer claude; do
  if command -v "$bin" >/dev/null 2>&1; then
    pass "'$bin' on PATH ($(command -v "$bin"))"
  else
    fail "'$bin' not found on PATH"
  fi
done

# nvm is a lazy-load zsh *function* (home/zsh/zprofile), not a binary on
# PATH - `command -v` for it would always fail under this script's bash
# shebang even in a working zsh shell, so check the file it sources.
if [ -s "/usr/local/opt/nvm/nvm.sh" ]; then
  pass "nvm.sh present at /usr/local/opt/nvm/nvm.sh (lazy-loaded by zprofile)"
else
  fail "/usr/local/opt/nvm/nvm.sh missing - nvm lazy-load will silently no-op"
fi

section "Pinned npm-global CLIs (~/.npm-global, installAxiFamily/installOpencode)"

npm_global_bin="$HOME/.npm-global/bin"
for bin in gh-axi chrome-devtools-axi lavish-axi tasks-axi quota-axi opencode; do
  if [ -x "$npm_global_bin/$bin" ]; then
    pass "$npm_global_bin/$bin present"
  else
    fail "$npm_global_bin/$bin missing"
  fi
done

section "Functional smoke tests"

if command -v darwin-rebuild >/dev/null 2>&1; then
  # darwin-rebuild --help exits 1 even on success (it's not an error exit,
  # just how the tool is written) - check output content, not exit code.
  dr_help="$(darwin-rebuild --help 2>&1)"
  if grep -q '^darwin-rebuild ' <<< "$dr_help"; then
    pass "'darwin-rebuild --help' runs"
  else
    fail "'darwin-rebuild --help' produced unexpected output: $dr_help"
  fi
else
  fail "'darwin-rebuild' not on PATH, skipping check"
fi

if command -v claude >/dev/null 2>&1; then
  if claude_version="$(claude --version 2>&1)"; then
    pass "'claude --version' -> $claude_version"
  else
    fail "'claude --version' failed: $claude_version"
  fi
else
  fail "'claude' not on PATH, skipping --version check"
fi

if command -v tmux >/dev/null 2>&1; then
  tmux_socket="verify-$$"
  if tmux -L "$tmux_socket" new-session -d -s smoke 2>/tmp/verify-tmux-err.$$; then
    if tmux -L "$tmux_socket" show-options -g >/dev/null 2>&1; then
      pass "tmux config loads cleanly in a throwaway detached session"
    else
      fail "tmux started but 'show-options' failed - config may be broken"
    fi
    tmux -L "$tmux_socket" kill-server 2>/dev/null || true
  else
    fail "tmux failed to start a detached session: $(cat /tmp/verify-tmux-err.$$ 2>/dev/null)"
  fi
  rm -f /tmp/verify-tmux-err.$$
else
  fail "'tmux' not on PATH, skipping functional check"
fi

section "Symlinked config files"

# home-manager's mkOutOfStoreSymlink/home.file entries resolve through an
# intermediate ~/-files store path before reaching their real target, so a
# single readlink() only shows that intermediate hop - readlink -f resolves
# the full chain.
check_symlink() {
  local path="$1" expected_glob="$2"
  path="${path/#\~/$HOME}"
  if [ ! -L "$path" ]; then
    if [ -e "$path" ]; then
      fail "$path exists but is not a symlink"
    else
      fail "$path missing"
    fi
    return
  fi
  local target
  target="$(readlink -f "$path")"
  case "$target" in
    $expected_glob) pass "$path -> $target" ;;
    *) fail "$path -> $target (expected to match $expected_glob)" ;;
  esac
}

# dotfiles-amway's mergeConfigs activation overwrites .zshrc/.tmux.conf/
# .gitconfig/.ssh/config/CLAUDE.md/AGENTS.md/INSTALLATIONS.md with merged
# (personal+work) plain files right after this repo's own activation plants
# them as live symlinks - so this repo's own verify.sh can't assert those
# five stay symlinks on a machine with dotfiles-amway installed. Only
# assert the ones no downstream repo overwrites.
check_symlink "~/.zprofile" "*home/zsh/zprofile"
check_symlink "~/.hammerspoon/init.lua" "*home/hammerspoon/init.lua"
# home.file's source is pkgs.python313 directly (not this repo's own
# file), so the fully-resolved target is nixpkgs' pinned interpreter
# binary, not a path under dotfiles - just confirm it resolves to *some*
# python3.x binary rather than a stale/broken link.
check_symlink "~/.local/bin/python" "*/bin/python3.*"

section "opencode MCP secrets"

mcp_vault="$DIR/home/config/opencode/mcp.env.vault"
if [ ! -f "$mcp_vault" ]; then
  fail "$mcp_vault missing"
elif [ -f "$HOME/.vault_pass" ] && ansible-vault view --vault-password-file "$HOME/.vault_pass" "$mcp_vault" >/dev/null 2>&1; then
  pass "home/config/opencode/mcp.env.vault present and decrypts with ~/.vault_pass"
else
  fail "home/config/opencode/mcp.env.vault present but does not decrypt with ~/.vault_pass"
fi

mcp_env="$DIR/home/config/opencode/mcp.env"
if [ ! -f "$mcp_env" ]; then
  warn "home/config/opencode/mcp.env missing - run home/config/opencode/bin/decrypt-mcp-env.sh before launching opencode with MCP servers"
fi

section "Podman machine (home.nix's podman-machine-start LaunchAgent)"

if command -v podman >/dev/null 2>&1; then
  if podman machine list --format '{{.Name}}' 2>/dev/null | grep -q .; then
    pass "'podman machine list' shows a machine"
  else
    fail "no podman machine found - run 'podman machine init' once by hand"
  fi

  if [ -S "/var/run/docker.sock" ]; then
    pass "/var/run/docker.sock present and forwarding to podman"
  else
    fail "/var/run/docker.sock missing - run 'sudo \$(brew --prefix podman)/bin/podman-mac-helper install' once by hand"
  fi
else
  fail "'podman' not on PATH, skipping podman machine checks"
fi

section "Homebrew packages (vendor/personal's own tier-2 list)"

if command -v brew >/dev/null 2>&1; then
  installed_formulae="$(brew list --formula 2>/dev/null)"
  installed_casks="$(brew list --cask 2>/dev/null)"
  for f in nvm mongocli herdr; do
    if grep -qx "$f" <<< "$installed_formulae"; then
      pass "brew formula '$f' installed"
    else
      fail "brew formula '$f' missing"
    fi
  done
  for c in alt-tab iterm2 hammerspoon claude-code antigravity-cli dbeaver-community flux-app open-design handy; do
    if grep -qx "$c" <<< "$installed_casks"; then
      pass "brew cask '$c' installed"
    else
      fail "brew cask '$c' missing"
    fi
  done
else
  fail "'brew' not on PATH, skipping Homebrew checks"
fi

# CHECK_SECTIONS_MARKER

printf "\n${grn}%d passed${end}, ${yel}%d warned${end}, ${red}%d failed${end}\n" "$pass_count" "$warn_count" "$fail_count"

if [ "$fail_count" -gt 0 ]; then
  printf "${red}Environment looks broken - keep the old terminal open.${end}\n"
  exit 1
fi
printf "${grn}Environment looks good.${end}\n"
