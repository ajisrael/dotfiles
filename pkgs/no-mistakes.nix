# No upstream flake exists for no-mistakes (unlike treehouse, which ships
# its own flake.nix consumed directly as an input - see flake.nix). This
# derivation is modeled on treehouse's own flake output: same buildGoModule
# shape, same Go toolchain, just a different repo/vendorHash. Pinned to a
# tagged release (not `main`) so updates are a deliberate, reviewed edit
# here rather than following upstream automatically.
#
# If kunchenguid ever adds a flake.nix to no-mistakes, prefer switching to
# consuming it as a flake input (like treehouse) and delete this file.
{ lib, buildGoModule, fetchFromGitHub, git }:

buildGoModule rec {
  pname = "no-mistakes";
  version = "1.37.0";

  src = fetchFromGitHub {
    owner = "kunchenguid";
    repo = "no-mistakes";
    tag = "v${version}";
    hash = "sha256-gNxnW73qGIdO4j8P6gkpvW1WOtUO2gpFgNf9Dhhx6BA=";
  };

  vendorHash = "sha256-NZOYxNYvt4192uqKBdKRxdgrKFvWx3585psdCnRdPSM=";

  subPackages = [ "cmd/no-mistakes" ];

  ldflags = [
    "-X main.version=v${version}"
  ];

  # Upstream's own test suite expects network access and live git-fixture
  # setup (recorded agent sessions, real repos in temp dirs) that isn't
  # appropriate for a Nix sandbox build. The e2e suite is already gated
  # behind a separate `e2e` build tag upstream and excluded from `go test`
  # by default; skip the remaining unit tests here too rather than fight
  # sandbox network isolation.
  doCheck = false;

  nativeCheckInputs = [ git ];

  meta = {
    description = "Local git-push-triggered verification pipeline for AI coding agents";
    homepage = "https://github.com/kunchenguid/no-mistakes";
    license = lib.licenses.mit;
    mainProgram = "no-mistakes";
  };
}
