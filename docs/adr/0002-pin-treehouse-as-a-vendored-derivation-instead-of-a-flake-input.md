# 2. Pin treehouse as a vendored derivation instead of a flake input

Date: 2026-09-16

## Status

Accepted

## Context

Treehouse was a flake input. A flake input's version lives in that flake's
`flake.lock`, which a `git subtree` vendoring of this repo into another flake
does not carry - so a consuming repo's lock drifts independently of this one.

## Decision

Consume treehouse as a pinned `buildGoModule` derivation
(`pkgs/treehouse.nix`, mirroring `pkgs/no-mistakes.nix`) instead of a flake
input. The version lives in a tracked file here and propagates through any
`git subtree pull` of this repo, matching how no-mistakes is already handled.

## Consequences

One source of truth for the version; no lock drift for subtree consumers.
We give up `nix flake update treehouse` - bumping now means editing the
version and refreshing `hash` + `vendorHash` by hand. We prioritized version
consistency and maintainability over that flake-update convenience.
