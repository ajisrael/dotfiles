# dotfiles

Personal Mac setup, managed with nix-darwin and home-manager. Covers shell,
tmux, neovim, iTerm2, and general-purpose dev tooling.

## Fresh-machine setup

```sh
git clone <this repo> dotfiles
cd dotfiles
./bootstrap.sh
```

`bootstrap.sh` installs Nix if it isn't already present, checks the `user`
configured in `flake.nix` against your actual macOS username (offers to fix
it if they differ), then runs the first `darwin-rebuild switch`.

After that, `darwin-rebuild` exists on `PATH` and you're on the normal
workflow below.

## Daily use

Edit the config files in place, then apply:

```sh
./rebuild.sh
```

## Validate without applying

```sh
nix flake check --no-build
nix build .#darwinConfigurations.mac.system --dry-run
```

## Repo tour

- `flake.nix` - entry point. Wires up nixpkgs, nix-darwin, home-manager.
- `configuration.nix` - system-level config: macOS defaults, Homebrew.
- `home.nix` - user-level config: packages, PATH, activation scripts.
- `home/` - the actual config files that get symlinked into place (nvim,
  tmux, iTerm2 profile, Claude statusline, zsh fragment, etc).

## Updating the neovim config

`home/config/nvim` (ajisrael's kickstart.nvim fork) is a git submodule with
its own independent history, not vendored content - commits made in that
repo don't show up here until the submodule pointer is bumped. To pull its
latest work into this repo:

```sh
cd home/config/nvim
git pull origin master
cd ../../..
git add home/config/nvim
git commit -m "Update nvim submodule pointer"
```

The second commit only records which submodule commit this repo points at -
it never rewrites the submodule's own history.

## Notes on this machine

- This machine is Intel (`x86_64-darwin`) on macOS Ventura (13.7.8).
  `flake.nix` pins `nixpkgs`/`nix-darwin`/`home-manager` to their `26.05`
  branches - the last release confirmed to support `x86_64-darwin`.
- `configuration.nix` sets `nix.enable = false` on purpose. nixpkgs-26.05's
  own `nix` package requires macOS 14+ and will crash the nix-daemon
  LaunchDaemon with a dyld error if nix-darwin is allowed to install/manage
  it on this OS. A separately-installed classic Nix (2.24.10, which
  supports macOS 10.12.6+) manages the daemon instead. Don't flip
  `nix.enable` back to `true` until this Mac is on macOS 14+.
- Nix itself needs installing before `bootstrap.sh` can do anything.
  Determinate Nix and the latest generic `nixos.org` installer both
  require macOS 14+. On Ventura or older, use the classic multi-user
  installer pinned to an older release instead:
  ```sh
  curl -sL https://releases.nixos.org/nix/nix-2.24.10/install | sh -s -- --daemon
  ```
