# 2. Pin treehouse as a vendored derivation instead of a flake input

Date: 2026-09-16

## Status

Accepted

## Context

Treehouse was a flake input in both `dotfiles` and `dotfiles-amway`. A flake
input's version lives in that flake's `flake.lock`, which the `git subtree`
vendoring of `dotfiles` into `dotfiles-amway/vendor/personal` does not carry -
so the two repos' locks drifted independently.

## Decision

Consume treehouse as a pinned `buildGoModule` derivation
(`pkgs/treehouse.nix`, mirroring `pkgs/no-mistakes.nix`) instead of a flake
input. The version lives in `dotfiles` and propagates to `dotfiles-amway`
through `git subtree pull`, matching how no-mistakes is already handled.

## Consequences

One source of truth for the version; no more lock drift between the two repos.
We give up `nix flake update treehouse` - bumping now means editing the
version and refreshing `hash` + `vendorHash` by hand. We prioritized version
consistency and maintainability over that flake-update convenience.
