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

# Preferred editor for local and remote sessions
export EDITOR='nvim'

alias vim="nvim"

# Keybindings
bindkey -s ^f "tmux-sessionizer\n"

# Rename the tmux window to the running program (mapped to a friendlier
# name), then back to "zsh" once it exits. Uses $TMUX_PANE (not plain
# `tmux rename-window`) because a terminal wrapper in front of this shell
# puts it on a pty tmux isn't directly watching, so pane_current_command
# and automatic-rename can't see through it.
if [[ -n "$TMUX" ]]; then
  _tmux_window_name_for_cmd() {
    local cmd="${1%% *}"
    case "$cmd" in
      claude) echo "claude-code" ;;
      nvim|vim) echo "vim" ;;
      *) echo "$cmd" ;;
    esac
  }
  _tmux_rename_preexec() {
    tmux rename-window -t "$TMUX_PANE" "$(_tmux_window_name_for_cmd "$1")"
  }
  _tmux_rename_precmd() {
    tmux rename-window -t "$TMUX_PANE" "zsh"
  }
  autoload -Uz add-zsh-hook
  add-zsh-hook preexec _tmux_rename_preexec
  add-zsh-hook precmd _tmux_rename_precmd
fi

# Auto-switch node version on cd, like the oh-my-zsh nvm plugin's
# load-nvmrc, but without eagerly sourcing nvm.sh: nvm/zprofile lazy-loads
# nvm.sh on first real use to keep shell startup fast, and calling
# `nvm use` unconditionally on every cd would defeat that. So walk up from
# $PWD looking for a .nvmrc in plain shell first, and only invoke the
# (lazy-loading) `nvm` shim - which pays the one-time load cost - when one
# is actually found.
__nvmrc_hook() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.nvmrc" ]]; then
      nvm use --silent
      return
    fi
    dir="${dir%/*}"
  done
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd __nvmrc_hook
__nvmrc_hook

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
export PATH="$HOME/learning/claude-code-playground:$PATH"

# opencode
export PATH="$HOME/.opencode/bin:$PATH"

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
