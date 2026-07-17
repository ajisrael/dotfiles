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

