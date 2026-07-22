{ user, ... }:

{
  # nix-darwin does NOT manage the Nix install/daemon here. nixpkgs-26.05's
  # own `nix` package (2.34.7) is compiled against a macOS 14 SDK baseline
  # and crashes on launch on Ventura (13.7.8) with a dyld symbol error -
  # "built for macOS 14.0 which is newer than running OS". Letting
  # nix.enable = true install/manage that package broke the nix-daemon
  # LaunchDaemon during the first darwin-rebuild switch. Nix itself stays
  # the classic-installer 2.24.10 build (see ~/dev-env-followups.md for
  # why: Determinate Nix dropped Intel Mac support, and the generic
  # nixos.org installer's *latest* release also requires macOS 14+ - only
  # the pinned 2.24.10 release works on this OS). Same logic as the
  # reference repo's `nix.enable = false` for Determinate: whichever tool
  # actually manages the daemon, nix-darwin shouldn't also try to.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "x86_64-darwin";

  system.primaryUser = user;
  users.users.${user} = {
    home = "/Users/${user}";
  };
  system.stateVersion = 6;

  system.defaults = {
    dock.autohide = true;
  };

  # nix-darwin has no module for pmset (it's not a `defaults` domain, so
  # system.defaults can't express it) - shell out directly instead.
  # AC: displaysleep=60 keeps the screensaver/background visible for an
  # hour before the display sleeps; sleep=0 means the system itself never
  # suspends while plugged in. Battery: displaysleep=2 blanks the screen
  # quickly to save power, but sleep=0 keeps the system awake so any
  # running background/agent work isn't paused just because it's unplugged.
  system.activationScripts.postActivation.text = ''
    /usr/bin/pmset -c displaysleep 60 sleep 0
    /usr/bin/pmset -b displaysleep 2 sleep 0
  '';

  nix-homebrew = {
    enable = true;
    inherit user;
    # This machine already had an Intel Homebrew install at /usr/local
    # before nix-homebrew existed. Without this, the first switch stops
    # and asks how to proceed (uninstall Homebrew entirely, or let
    # nix-homebrew adopt the existing install). autoMigrate takes over
    # management of the existing installation in place, replacing its own
    # bookkeeping while keeping already-installed casks/formulae/taps.
    autoMigrate = true;
  };

  # Install-method priority for everything on this machine: Nix first,
  # Homebrew second, curl/native installers last.
  #   nvm: no nixpkgs package (it's a shell function/script managing
  #        ~/.nvm, not a typical binary - a known nixpkgs gap).
  #   mongocli: confirmed absent from nixpkgs-26.05-darwin.
  # Everything else previously on Homebrew was verified available in
  # nixpkgs and moved to home.packages instead - see home.nix.
  homebrew = {
    enable = true;
    onActivation.cleanup = "none";
    onActivation.autoUpdate = true;
    brews = [ "nvm" "mongocli" ];
    # GUI .app bundles stay on Homebrew casks (tier 2) for proper
    # /Applications integration, Spotlight visibility, and auto-update
    # behavior, even where a same-named nixpkgs package exists (e.g.
    # iterm2) - Nix's nixpkgs alt-tab is an unrelated Linux X11 tool
    # despite the matching name, not the macOS AltTab.app.
    casks = [
      "alt-tab"
      "iterm2"

      # Menu-bar toggle + hotkey for keeping the machine awake with the
      # lid closed (see home/hammerspoon/init.lua) - macOS >= 13 required,
      # this machine is on Ventura (13.7.8).
      "hammerspoon"

      # No nixpkgs equivalent, or GUI .app convention (deep system
      # integration like Docker Desktop's privileged helper/VM, or a
      # different product from any similarly-named nixpkgs package).
      "dbeaver-community"
      "flux-app"
      "intellij-idea"
      "intellij-idea-ce"
      "open-design"

      # Local whisper.cpp-based dictation replacement (Intel-Mac-confirmed,
      # unlike OpenSuperWhisper - see ~/.claude/plans/memoized-mixing-quilt.md).
      # Custom vocabulary lives in the app's own Settings ->
      # Advanced -> Custom Words, not here. update_checks_enabled must be
      # turned off in-app (Settings) to satisfy the fully-local requirement -
      # that's a runtime setting, not something this cask declaration can set.
      "handy"

      # windows-app hard-requires macOS >= 14 (Sonoma); this machine is on
      # Ventura (13.7.8) and failed during the first switch attempt with
      # "This cask does not run on macOS versions older than Sonoma."
      # Re-add once the OS is upgraded - see ~/dev-env-followups.md.
      #
      # docker-desktop is deliberately NOT here - podman replaces it entirely
      # (CLI, VM, and socket) without Docker Desktop's commercial-use
      # subscription requirement. podman itself isn't declared here either:
      # its current (6.x) Homebrew formula requires arm64 (Intel Mac support
      # was dropped upstream), so it's pinned to the last Intel-compatible
      # version via home.nix's installPodman activation script instead - see
      # home/skills/install-podman.sh for the detail.
    ];
  };
}
