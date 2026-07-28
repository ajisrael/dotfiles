# Agent instructions for dotfiles

Personal Mac dotfiles managed with nix-darwin and home-manager. See
`README.md` for full setup/usage docs - this file covers agent-specific
operating notes only.

## The user always runs ./rebuild.sh themselves

Never run `./rebuild.sh` or `sudo darwin-rebuild switch` on the user's
behalf - applying a system config change is the user's call, not an agent's.
Validate changes instead with:

```sh
nix flake check --no-build
nix build .#darwinConfigurations.mac.system --dry-run
```

then tell the user the change is ready to apply.

## home/config/nvim is a submodule, not a subtree

`home/config/nvim` (ajisrael's kickstart.nvim fork) is a real git submodule
with its own independent history - it is not vendored via `git subtree`.
Commits made in that repo don't appear here until the submodule pointer is
bumped. To pull its latest work into this repo:

```sh
cd home/config/nvim
git pull origin master
cd ../../..
git add home/config/nvim
git commit -m "Update nvim submodule pointer"
```

That second commit only records which submodule commit this repo points
at - it never rewrites the submodule's own history.

## Herdr is pinned to Homebrew, not nixpkgs, until the next branch bump

nixpkgs has `pkgs/by-name/he/herdr/package.nix` and home-manager has a
`programs.herdr` module, but both landed on `master`/`unstable` only
(2026-05/06) - confirmed 404 on the `nixpkgs-26.05-darwin`/`release-26.05`
branches this flake pins to, as of 2026-07-28. Installed via
`homebrew.brews` (tier 2) in the meantime; config is a plain symlinked
`home/herdr/config.toml`, not `programs.herdr.settings`. Re-check
availability on the pinned branches next time flake.nix's inputs are
bumped, and migrate to tier 1 (`home.packages` + `programs.herdr`) once
it's there.

