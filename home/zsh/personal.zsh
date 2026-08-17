# Nix/home-manager's per-user profile and session vars (PATH additions
# declared in home.nix, EDITOR, etc). Not sourced automatically because
# programs.zsh is deliberately disabled in home.nix (preserving the
# existing oh-my-zsh + Powerlevel10k setup instead of letting
# home-manager also try to own .zshrc) - that means this sourcing has
# to happen here instead of the usual home-manager-generated hook.
export PATH="/etc/profiles/per-user/$USER/bin:$PATH"
[ -f "$HOME/.local/state/home-manager/gcroots/current-home/home-path/etc/profile.d/hm-session-vars.sh" ] && \
  source "$HOME/.local/state/home-manager/gcroots/current-home/home-path/etc/profile.d/hm-session-vars.sh"

# nix-darwin's system-wide profile (darwin-rebuild, etc), separate from
# the per-user profile above.
export PATH="/run/current-system/sw/bin:$PATH"

# direnv's shell hook. home.nix's programs.direnv only installs the
# binary + enables nix-direnv - it doesn't wire the hook into .zshrc,
# since programs.zsh is deliberately off here (see the "Deliberately NOT
# managing zsh" comment there), so this has to happen by hand, same as
# the home-manager session vars sourced above.
eval "$(direnv hook zsh)"

# Preferred editor for local and remote sessions
export EDITOR='nvim'

alias vim="nvim"

# Keybindings
bindkey -s ^f "tmux-sessionizer\n"

# opencode: load the MCP server secrets (home/config/opencode/mcp.env,
# decrypted by home/config/opencode/bin/decrypt-mcp-env.sh) into the
# session env, then launch. Uses `command opencode` so the alias doesn't
# recurse; the source is guarded because mcp.env won't exist on a fresh
# clone until the vault has been decrypted once.
alias opencode='if [[ -f "$HOME/dotfiles/home/config/opencode/mcp.env" ]]; then set -a; source "$HOME/dotfiles/home/config/opencode/mcp.env"; set +a; fi; command opencode'

export NVM_DIR="$HOME/.nvm"

# Lazy-load nvm: sourcing nvm.sh eagerly on every shell adds several
# seconds (nvm_auto version resolution, plus a duplicate compinit pass
# triggered by nvm's bash-completion shim running before oh-my-zsh's own).
# Load it for real only the first time nvm/node/npm/npx is actually invoked.
#
# Defined here (not zprofile) so the shims exist in every interactive
# shell, not just login ones - __nvmrc_hook below calls `nvm use` on every
# cd regardless of shell type (e.g. treehouse's worktree subshell is
# non-login), and needs the shim to already be defined when it does.
#
# IMPORTANT: the loader helper's name MUST keep its double-underscore
# prefix. Claude Code (and other agent harnesses) snapshot shell functions
# for non-interactive tool calls and filter out single-underscore-prefixed
# names (treated as zsh completion functions, e.g. `_git`) while
# explicitly keeping double-underscore names (the same carve-out
# mise/pyenv rely on for helpers like `__pyenv_init`). A single-underscore
# `_load_nvm` gets silently dropped from the snapshot while the
# `node`/`npm`/`npx`/`nvm` shims below (kept - no leading underscore)
# still call it, so at snapshot time the helper is "command not found"
# and each shim falls through to calling itself: infinite recursion until
# zsh's FUNCNEST limit aborts it. Renaming back to a single underscore
# reintroduces that bug in every agent shell.
__load_nvm() {
  unset -f nvm node npm npx __load_nvm
  [ -s "/usr/local/opt/nvm/nvm.sh" ] && \. "/usr/local/opt/nvm/nvm.sh"  # This loads nvm
  [ -s "/usr/local/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/usr/local/opt/nvm/etc/bash_completion.d/nvm"  # This loads nvm bash_completion
}
nvm() { __load_nvm; nvm "$@"; }
node() { __load_nvm; node "$@"; }
npm() { __load_nvm; npm "$@"; }
npx() { __load_nvm; npx "$@"; }

# Auto-switch node version on cd, like the oh-my-zsh nvm plugin's
# load-nvmrc, but without eagerly sourcing nvm.sh: the shims above lazy-load
# nvm.sh on first real use to keep shell startup fast, and calling
# `nvm use` unconditionally on every cd would defeat that. So walk up from
# a directory looking for a .nvmrc in plain shell first (no nvm call, so
# no forced load), and only invoke the (lazy-loading) `nvm` shim - which
# pays the one-time load cost - when we actually need to switch/revert.
__find_nvmrc() {
  local dir="$1"
  # Loop on dir != "" (matching nvm's own nvm_find_up), not dir != "/":
  # `${dir%/*}` on a single-segment path like "/Users" collapses straight
  # to "" rather than "/", so terminating on "/" never triggers and this
  # spins forever - hanging every `cd ..` once it walks above such a path.
  while [[ -n "$dir" ]]; do
    [[ -f "$dir/.nvmrc" ]] && return 0
    dir="${dir%/*}"
  done
  return 1
}
__nvmrc_hook() {
  if __find_nvmrc "$PWD"; then
    nvm use --silent
  elif __find_nvmrc "${OLDPWD:-}"; then
    # Leaving a directory (tree) that had its own .nvmrc for one that
    # doesn't: revert to the default version, same as the oh-my-zsh
    # plugin does. Only bother if nvm has already been loaded in this
    # shell - if it hasn't, the version was never switched away from
    # default in the first place, so there's nothing to revert and no
    # reason to force the lazy load just to check.
    (( $+functions[__load_nvm] )) && return
    [[ "$(nvm version)" != "$(nvm version default)" ]] && nvm use default --silent
  fi
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd __nvmrc_hook
__nvmrc_hook

# Custom P10k segment: java version from the nearest .sdkmanrc walking up
# from $PWD, shown only when it differs from sdkman's global default -
# same "only show when switched" spirit as the nvm segment above. Reads
# .sdkmanrc directly (the actual file sdkman_auto_env parses) rather than
# a .java-version file or $SDKMAN_ENV, so there's exactly one source of
# truth for "what java does this project want" - see p10k.zsh's own
# comment on why the built-in java_version segment doesn't work here
# (no Ant/build.xml support, and no non-default-only gate to begin with).
# Prefixed my_ per Powerlevel10k's own convention for custom segments
# (avoids clashing with future built-in segment names).
function prompt_my_java_version_sdkman() {
  local dir="$PWD" pinned=""
  while true; do
    if [[ -f "$dir/.sdkmanrc" ]]; then
      pinned="$(sed -nE 's/^[[:space:]]*java[[:space:]]*=[[:space:]]*([^[:space:]]+).*/\1/p' "$dir/.sdkmanrc" | head -n1)"
      break
    fi
    [[ "$dir" == "/" ]] && break
    dir="${dir:h}"
  done
  [[ -n "$pinned" ]] || return

  local default=""
  [[ -n "$SDKMAN_DIR" ]] && default="$(readlink "$SDKMAN_DIR/candidates/java/current" 2>/dev/null)"
  default="${default:t}"
  [[ "$pinned" == "$default" ]] && return

  p10k segment -f 3 -b 0 -i JAVA_ICON -r -t "$pinned"
}

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# tmux-sessionizer lives in dotfiles; home.nix wires this onto
# PATH via home.sessionPath once darwin-rebuild switch has run, but this
# line keeps it working in the meantime (harmless duplicate afterward).
export PATH="$HOME/dotfiles/home/tmux-scripts:$PATH"

# Generated for envman. Do not edit.
[ -s "$HOME/.config/envman/load.sh" ] && source "$HOME/.config/envman/load.sh"

# For learning-linux class from boot.dev
export PATH="$PATH:$HOME/learning/boot-dev/learning-linux/worldbanc/private/bin"

# Remove claude alias from websearch plugin
unalias claude 2>/dev/null

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# Podman replacement for Docker Desktop (see home.nix/configuration.nix
# for the package/launchd side). Points anything that talks to the Docker
# Engine API directly (Testcontainers, CDK's local emulation, etc.) at the
# rootless podman machine's socket - the docker/docker-compose CLI shims
# in home.nix don't need this, they just exec podman directly.
if command -v podman >/dev/null 2>&1; then
  _podman_socket="$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}' 2>/dev/null)"
  [ -n "$_podman_socket" ] && export DOCKER_HOST="unix://$_podman_socket"
  unset _podman_socket
fi

# firstmate (github.com/kunchenguid/firstmate) - a cloned "agent distro"
# you launch a harness inside of, which then becomes a supervisor spawning
# sub-agents ("crewmates") to ship PRs. Not a package - there's nothing for
# Nix to install here, so this just gets you into the personal clone and
# launches the harness; the clone itself is manual, per firstmate's own
# README:
#   git clone https://github.com/kunchenguid/firstmate ~/firstmate
# dotfiles-amway defines the matching `fm-work` for the separate
# ~/firstmate-amway clone, kept out of this repo since it must stay
# employer-agnostic.
#
# `gh auth switch` first: gh has one global active account, not a
# per-directory one, so anything firstmate shells out to gh-axi/gh for
# (PRs, issues) would otherwise run as whichever account was last active -
# possibly the work one. ~/firstmate/'s own commit identity is handled
# separately by gitconfig's includeIf on gitdir.
fm-personal() {
  if [[ ! -d "$HOME/firstmate" ]]; then
    echo "fm-personal: ~/firstmate not found - clone it first:" >&2
    echo "  git clone https://github.com/kunchenguid/firstmate ~/firstmate" >&2
    return 1
  fi
  gh auth switch --user ajisrael || return 1
  (cd "$HOME/firstmate" && claude)
}
