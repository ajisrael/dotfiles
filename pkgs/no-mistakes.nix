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
  version = "1.77.0";

  src = fetchFromGitHub {
    owner = "kunchenguid";
    repo = "no-mistakes";
    tag = "v${version}";
    hash = "sha256-A86AqF0MDqn4qw9xvMjfucgNoetUWd4wb3+4OxNk46Q=";
  };

  vendorHash = "sha256-maAVBptEtdrGanJHwAPAmuGBorzIMUgK6T+NmIz1kS0=";

  subPackages = [ "cmd/no-mistakes" ];

  # Upstream moved its version variable to internal/buildinfo (was main.version
  # in older releases); the package's own version.go documents this exact
  # ldflags path. Without it the binary reports "dev" instead of the tag.
  ldflags = [
    "-X github.com/kunchenguid/no-mistakes/internal/buildinfo.Version=v${version}"
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
