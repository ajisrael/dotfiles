# Treehouse ships its own flake.nix (unlike no-mistakes), so this could be a
# flake input. It is a plain buildGoModule derivation instead, on purpose: a
# flake input's version lives in flake.lock, which the git-subtree vendoring
# into dotfiles-amway does not carry - leaving the two repos' locks to drift.
# Pinning the version here (a file under pkgs/, same as no-mistakes.nix) makes
# dotfiles the single source of truth that propagates to dotfiles-amway
# through `git subtree pull`. See docs/adr for the decision.
#
# Build recipe mirrors upstream's own flake.nix output. Bumping the version is
# a deliberate, reviewed edit: update `version`, then refresh both `hash`
# (nix-prefetch-url --unpack the vX.Y.Z tarball) and `vendorHash` (blank it and
# let the build report the correct value).
{ lib, buildGoModule, fetchFromGitHub, git }:

buildGoModule rec {
  pname = "treehouse";
  version = "2.3.0";

  src = fetchFromGitHub {
    owner = "kunchenguid";
    repo = "treehouse";
    tag = "v${version}";
    hash = "sha256-8C6bg2jfqTSmI3N4tdzyIRuJKN12DA/SjcuL9hBPgEg=";
  };

  vendorHash = "sha256-z8IndcHcZ6nLqhLtAYul3ppddpOA4AHGQWIlfYY/pfI=";

  ldflags = [
    "-X main.version=v${version}"
  ];

  # Upstream's suite includes repo-policy/CI-gating tests (e.g.
  # TestNoMistakesGateDecisions in no_mistakes_gate_test.go) and e2e tests
  # that assume live git fixtures - neither is appropriate for the Nix
  # sandbox and both fail there. Skip checks, same as pkgs/no-mistakes.nix.
  doCheck = false;

  nativeCheckInputs = [ git ];

  meta = {
    description = "Pooled git-worktree manager for parallel AI-agent work";
    homepage = "https://github.com/kunchenguid/treehouse";
    license = lib.licenses.mit;
    mainProgram = "treehouse";
  };
}
