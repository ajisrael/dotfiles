{ config, pkgs, user, personalDotfilesDir, treehousePackage, ... }:

let
  dotfiles = personalDotfilesDir;

  # No upstream flake exists for no-mistakes (unlike treehouse, consumed
  # directly as a flake input above) - see pkgs/no-mistakes.nix for why.
  no-mistakes = pkgs.callPackage ./pkgs/no-mistakes.nix { };

  # Nix's nodejs package defaults npm's global-install prefix to its own
  # /nix/store path, which is read-only - `npm install -g` fails with EACCES
  # under it unconditionally. Redirect global installs to a writable,
  # stable location instead.
  npmGlobalPrefix = "${config.home.homeDirectory}/.npm-global";
in

{
  home.username = user;
  home.homeDirectory = "/Users/${user}";
  home.stateVersion = "24.11";

  home.packages = with pkgs; [
    bash
    ripgrep
    fd
    fzf
    jq
    lazygit
    lazydocker
    neovim
    tmux
    tree
    wget
    gnupg
    direnv
    nerd-fonts.hack

    # Migrated from Homebrew (tier 1: Nix) - verified available in
    # nixpkgs-26.05-darwin. mongocli is the one confirmed exception with
    # no nixpkgs package; it stays on Homebrew (tier 2).
    ansible
    awscli2
    cloudflared
    cmake
    docker
    gh
    git
    gnused
    go
    kiro-cli
    maven
    mkcert
    pandoc
    sonar-scanner-cli
    stow
    tldr
    yarn
    nodejs

    # Agentic-workflow tooling (kunchenguid's stack) - see
    # ~/.claude/plans/memoized-mixing-quilt.md for the integration plan.
    treehousePackage
    no-mistakes

    # Single source of truth for Python (was 4+ overlapping installs:
    # native python.org 3.8 + 3.13, four Homebrew python@ formulae, plus
    # the Apple/Xcode stub at /usr/bin/python3). `python` -> `python3` via
    # the symlink below.
    python313

    # GUI apps available as real Nix packages (verified against
    # nixpkgs-26.05-darwin - not just name matches; some same-named
    # nixpkgs attrs are unrelated Linux tools, e.g. `alttab`/`flux`).
    # Deliberately not migrated here: Microsoft Edge (removed, no longer
    # wanted) and Qfinder Pro (removed, no longer wanted).
    google-chrome
    mongodb-compass
    postman
    powershell
    rectangle
    slack
    tailscale
    zoom-us
  ];
  fonts.fontconfig.enable = true;
  home.sessionVariables.EDITOR = "nvim";
  home.sessionPath = [ "${dotfiles}/home/tmux-scripts" "${npmGlobalPrefix}/bin" ];

  # `python` -> Nix's python313, so bare `python` works instead of needing
  # `python3`. ~/.local/bin is already on PATH.
  home.file.".local/bin/python" = {
    source = "${pkgs.python313}/bin/python3";
  };

  # Deliberately NOT managing zsh/the prompt through Nix. oh-my-zsh +
  # Powerlevel10k + zsh-autosuggestions/zsh-syntax-highlighting are already
  # installed and working (independent git clones under ~/.oh-my-zsh) -
  # letting home-manager's programs.zsh/programs.starship also try to own
  # .zshrc/the prompt would fight with that instead of preserving it.
  # direnv's shell hook is added via the personal.zsh fragment (Phase 5)
  # using plain `eval "$(direnv hook zsh)"` instead of enableZshIntegration,
  # for the same reason.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Single-owner personal symlinks (nvim, tmux, iTerm2 profile, statusline,
  # zsh/ssh/git fragments) get added here in Phase 4, once the real files
  # move into this repo's home/ tree.

  # sdkman has no Nix or Homebrew package (install-method priority for this
  # machine is Nix, then Homebrew, then curl/native last) - bootstrap it on
  # a fresh machine so a clone + darwin-rebuild switch is one command.
  # Idempotent: no-ops if ~/.sdkman already exists. sdkman's own installer
  # requires bash 4+; macOS ships 3.2, so this uses Nix's bash explicitly.
  home.activation.installSdkman = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "$HOME/.sdkman" ]; then
      $DRY_RUN_CMD /usr/bin/curl -s "https://get.sdkman.io" | $DRY_RUN_CMD ${pkgs.bash}/bin/bash
    fi
  '';

  # Plash has no Homebrew cask and the App Store build has outrun this
  # machine's macOS version (see install-plash.sh) - install-method
  # priority for this machine is Nix, then Homebrew, then curl/native
  # last, same tier as sdkman above.
  home.activation.installPlash = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.bash}/bin/bash "${dotfiles}/home/skills/install-plash.sh"
  '';

  # no-mistakes' own `daemon start` self-registers a transient launchd job
  # via `launchctl bootstrap`/`kickstart` on first use - observed failing
  # silently on this machine ("daemon started but did not become
  # responsive within 5s", no plist ever landing under
  # ~/Library/LaunchAgents), which blocked `no-mistakes init` until an
  # agent worked around it with a manual `nohup no-mistakes daemon run &`.
  # Registering the daemon declaratively here, via home-manager's own
  # launchd.agents module, sidesteps that on-demand bootstrap path
  # entirely - the daemon is already running (KeepAlive, RunAtLoad)
  # before any repo ever calls `no-mistakes init`. `no-mistakes` itself
  # checks for an already-responsive daemon via its socket first and
  # no-ops if one is found, so this doesn't fight the CLI's own daemon
  # management.
  home.activation.ensureNoMistakesLogDir = config.lib.dag.entryBefore [ "setupLaunchAgents" ] ''
    $DRY_RUN_CMD mkdir -p "$HOME/Library/Logs/no-mistakes"
  '';
  launchd.agents.no-mistakes-daemon = {
    enable = true;
    config = {
      ProgramArguments = [
        "${no-mistakes}/bin/no-mistakes"
        "daemon"
        "run"
        "--root"
        "${config.home.homeDirectory}/.no-mistakes"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/no-mistakes/daemon.out.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/no-mistakes/daemon.err.log";
    };
  };

  # Pin the three axi-family CLIs (kunchenguid's agent-ergonomic wrappers)
  # to an exact, reviewed npm version and install them globally, instead of
  # letting their own documented `npx -y <pkg>` skill instructions re-fetch
  # unpinned from the npm registry on every agent invocation. Bumping a
  # version is a deliberate, reviewed edit to home/skills/install-axi-family.sh
  # (kept as a plain shell script, not inlined here, so it can be run and
  # debugged directly - `bash home/skills/install-axi-family.sh <npm> <jq>
  # home/skills` - without going through a full darwin-rebuild switch) -
  # see ~/.claude/plans/memoized-mixing-quilt.md for the rationale.
  # Idempotent: only reinstalls when the installed version doesn't match
  # the pin. Also regenerates each package's local skills/<name>/SKILL.md
  # from its own shipped copy on every run - see that script and
  # sync-axi-skill.sh for details.
  home.activation.installAxiFamily = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    export NPM_CONFIG_PREFIX="${npmGlobalPrefix}"
    $DRY_RUN_CMD ${pkgs.bash}/bin/bash "${dotfiles}/home/skills/install-axi-family.sh" \
      "${pkgs.nodejs}/bin/npm" "${pkgs.jq}/bin/jq" "${dotfiles}/home/skills"
  '';

  # Local skill files, kept in sync with each pinned axi-family package by
  # the installAxiFamily activation block above - symlinked into both
  # Claude Code's and the generic ~/.agents/skills/ convention so other
  # harnesses (Codex, OpenCode, etc.) pick them up too.
  home.file.".claude/skills/gh-axi/SKILL.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/skills/gh-axi/SKILL.md";
  home.file.".agents/skills/gh-axi/SKILL.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/skills/gh-axi/SKILL.md";

  home.file.".claude/skills/chrome-devtools-axi/SKILL.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/skills/chrome-devtools-axi/SKILL.md";
  home.file.".agents/skills/chrome-devtools-axi/SKILL.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/skills/chrome-devtools-axi/SKILL.md";

  home.file.".claude/skills/lavish/SKILL.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/skills/lavish/SKILL.md";
  home.file.".agents/skills/lavish/SKILL.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/skills/lavish/SKILL.md";

  # no-mistakes' skill is normally installed by `no-mistakes init`, which
  # also requires running inside a git repo with an "origin" remote (it
  # sets up that repo's gate at the same time) - not something home.nix
  # should do globally. But the skill install itself is user-level and
  # content-identical regardless of which repo triggers it, so it's
  # vendored here as a static copy pinned to the same v1.37.0 tag as the
  # no-mistakes package above, unlike the three axi-family skills (which
  # regenerate from their own pinned, installed npm package on every
  # activation) - no-mistakes' compiled binary doesn't expose a CLI command
  # to dump its skill markdown, so there's nothing to regenerate from here.
  # Bump this file by hand alongside pkgs/no-mistakes.nix's version pin.
  home.file.".claude/skills/no-mistakes/SKILL.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/skills/no-mistakes/SKILL.md";
  home.file.".agents/skills/no-mistakes/SKILL.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/skills/no-mistakes/SKILL.md";

  # Global agent policy file (kunchenguid's home/AGENTS.md pattern) - one
  # canonical file, symlinked to every harness's expected location.
  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".config/opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";

  # Referenced by home/AGENTS.md's install-instructions pointer - kept out
  # of AGENTS.md's own body so every harness's context window only pays
  # for it when an agent is actually about to install something globally.
  # A plain live symlink (not home.file, unlike the skills/AGENTS.md above)
  # so a downstream config can overwrite this same path with its own merged
  # file without a home.file entry here corrupting the vendored source
  # through the symlink. entryAfter "writeBoundary" only, so any downstream
  # activation that also targets this path can order itself after and win.
  home.activation.installInstallations = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p "$HOME/.agents/instructions"
    $DRY_RUN_CMD ln -sfn "${dotfiles}/home/instructions/INSTALLATIONS.md" "$HOME/.agents/instructions/INSTALLATIONS.md"
  '';
}
