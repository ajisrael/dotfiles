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

  # `docker`/`docker-compose` shims onto `podman`/`podman-compose` - podman
  # itself lives on the Homebrew tier (see configuration.nix) rather than
  # here, but this keeps anything that shells out to a literal `docker`
  # binary (CDK's asset bundling, scripts, muscle memory) working
  # unchanged. Podman's CLI is Docker-API-compatible, so this is a
  # transparent rename rather than a behavior shim.
  #
  # The compose shim must exec the standalone `podman-compose` (also in
  # home.packages below), NOT `podman compose` (the built-in subcommand,
  # no hyphen) - that subcommand resolves an external compose provider by
  # searching PATH, finds this very `docker-compose` shim, and re-execs it,
  # forking itself without bound until the machine is killed by hand.
  dockerShim = pkgs.writeShellScriptBin "docker" ''
    exec podman "$@"
  '';
  dockerComposeShim = pkgs.writeShellScriptBin "docker-compose" ''
    exec podman-compose "$@"
  '';
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
    podman-compose
    dockerShim
    dockerComposeShim
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
    gh
    git
    gnused
    go
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

    # OpenAI's Codex CLI - AI coding agent that runs in your terminal.
    # Available as a nixpkgs package (tier 1) in nixpkgs-26.05-darwin.
    codex

    # CLI for Architecture Decision Records (numbering, status/supersede
    # links, TOC generation) - paired with the `adr` skill below.
    adr-tools

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

  # zsh/tmux/git/ssh - tracked here so a fresh clone + darwin-rebuild switch
  # reproduces them exactly, instead of relying on hand-edits that silently
  # go stale (as happened to all four across a prior repo rename). Still
  # deliberately NOT using home-manager's own
  # programs.zsh/programs.git/programs.ssh modules - same reasoning as the
  # comment below about not fighting the existing oh-my-zsh + Powerlevel10k
  # setup.
  #
  # .zshrc/.tmux.conf/.gitconfig/.ssh/config specifically are plain live
  # symlinks via home.activation (not home.file), same reasoning as
  # installAgentsFile above: a downstream work-specific profile repo may
  # regenerate these same paths with its own merged content on every
  # rebuild, and a home.file entry here would make home-manager think it
  # owns the path, triggering its backupFileExtension logic against content
  # it didn't actually write - which fails outright once a stale .backup
  # from a prior rebuild is already sitting there. entryAfter
  # "writeBoundary" only, so any downstream activation targeting the same
  # path can order itself after and win.
  home.activation.installShellConfigFiles = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p "$HOME/.ssh"
    $DRY_RUN_CMD ln -sfn "${dotfiles}/home/zsh/zshrc" "$HOME/.zshrc"
    $DRY_RUN_CMD ln -sfn "${dotfiles}/home/tmux.conf" "$HOME/.tmux.conf"
    $DRY_RUN_CMD ln -sfn "${dotfiles}/home/git/gitconfig" "$HOME/.gitconfig"
    $DRY_RUN_CMD ln -sfn "${dotfiles}/home/ssh/rootconfig" "$HOME/.ssh/config"
  '';
  # Was a plain untracked file (not a symlink) until the nvm lazy-load
  # helper's naming bug (see home/zsh/zprofile's own comment) surfaced that
  # a fresh machine would silently not get this lazy-load at all.
  home.file.".zprofile".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/zsh/zprofile";
  home.file.".hammerspoon/init.lua".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/hammerspoon/init.lua";

  # Was dangling at the deleted dotfiles-personal path after the rename -
  # not previously declared here at all, just a manually-created symlink.
  home.file.".claude/statusline-command.sh".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/claude/statusline-command.sh";

  # Custom theme matching the Tokyo Night palette already used by the
  # statusline/tmux/iTerm2/nvim setup - referenced by settings.json's
  # "theme": "custom:tokyo-night". Claude Code reads *.json files directly
  # from ~/.claude/themes/, keyed by filename (minus .json).
  home.file.".claude/themes/tokyo-night.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/claude/themes/tokyo-night.json";

  # Same dangling-after-rename problem as statusline-command.sh above -
  # ~/.config/nvim was a manually-created symlink still pointing at the
  # deleted dotfiles-personal path.
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/config/nvim";

  # Same dangling-after-rename problem again - iTerm2's DynamicProfiles
  # symlink still pointed at the deleted dotfiles-personal path.
  home.file."Library/Application Support/iTerm2/DynamicProfiles/tokyonight-pkmn.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/iterm2/tokyonight-pkmn.json";

  # opencode's TUI prefs (vim keybinds, theme, plugin) - generic and
  # personal, unlike opencode.json which holds machine/employer-specific
  # provider and MCP config and is deliberately not managed here.
  home.file.".config/opencode/tui.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/config/opencode/tui.json";

  # Herdr - trying it out alongside tmux, not replacing it (see
  # configuration.nix's homebrew.brews comment for the install-tier
  # reasoning). Only vim-style pane nav + the Tokyo Night theme are here;
  # tmux-sessionizer has no Herdr equivalent, so that stays tmux-only.
  home.file.".config/herdr/config.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/herdr/config.toml";

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

  # podman itself isn't in configuration.nix's homebrew.brews - the current
  # (6.x) tap formula requires arm64, a hard wall on this Intel machine (see
  # that file's comment). Installs and pins the last Intel-compatible
  # version instead, same tier-3 (curl/imperative) pattern as
  # installSdkman/installPlash above.
  home.activation.installPodman = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.bash}/bin/bash "${dotfiles}/home/skills/install-podman.sh"
  '';

  # intellij-idea/intellij-idea-ce aren't in configuration.nix's
  # homebrew.casks - the current homebrew-cask recipes use a
  # `command_wrapper` stanza nix-homebrew's pinned brew engine doesn't
  # implement yet (see that file's comment). Installs and pins the last
  # pre-migration recipe instead, same tier-3 (curl/imperative) local-tap
  # pattern as installPodman above.
  home.activation.installIntellijPin = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.bash}/bin/bash "${dotfiles}/home/skills/install-intellij-pin.sh"
  '';

  # Starts the rootless podman machine VM on login, replacing Docker
  # Desktop's auto-launched VM. `podman machine start` exits nonzero if the
  # machine is already running (e.g. after a fast logout/login or a second
  # activation) - `|| true` swallows that so this activation step, and any
  # later home-manager switch, stays idempotent. No KeepAlive: unlike
  # no-mistakes-daemon below, this launches a VM process that supervises
  # itself, it isn't a long-running foreground process for launchd to
  # restart. Requires `podman machine init` to have been run once by hand
  # first (creates the VM/downloads its image) - not declarative-friendly,
  # so it isn't done here. Hardcoded /usr/local/bin (not
  # config.homebrew.brewPrefix - that option lives on the nix-darwin
  # config, not this home-manager one) matching this machine's pre-existing
  # Intel Homebrew prefix - see configuration.nix's nix-homebrew.autoMigrate
  # comment.
  launchd.agents.podman-machine-start = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.bash}/bin/bash"
        "-c"
        "/usr/local/bin/podman machine start || true"
      ];
      RunAtLoad = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/podman-machine-start.out.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/podman-machine-start.err.log";
    };
  };

  # Pin the axi-family CLIs (kunchenguid's agent-ergonomic wrappers) to an
  # exact, reviewed npm version and install them globally, instead of
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

  # opencode CLI - pinned-version npm global install, same idempotency
  # shape as installAxiFamily above (reinstall only when the installed
  # version doesn't match the pin). Neither Nix nor Homebrew tier fit: see
  # configuration.nix's homebrew comment for why Homebrew was rejected
  # (Tier-3 macOS forces a multi-hour from-source rust build via
  # ripgrep's build dependency). npm installs opencode-ai's prebuilt
  # binary instead - no compilation, and npmGlobalPrefix already puts it
  # on PATH with no separate PATH export needed. Was previously
  # self-installed/self-updating into ~/.opencode/bin via `opencode
  # upgrade`; bump the version below by hand instead of relying on that
  # self-updater, so this activation block stays the single source of
  # truth for the installed version.
  home.activation.installOpencode = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    export NPM_CONFIG_PREFIX="${npmGlobalPrefix}"
    # opencode-ai's postinstall script shells out to a bare `node` - needs
    # nodejs on PATH, not just invoked via its absolute store path below.
    export PATH="${pkgs.nodejs}/bin:$PATH"
    installed="$( ("${pkgs.nodejs}/bin/npm" ls -g --depth=0 --json opencode-ai 2>/dev/null || true) \
      | "${pkgs.jq}/bin/jq" -r '.dependencies."opencode-ai".version // ""')"
    if [ "$installed" != "1.18.7" ]; then
      $DRY_RUN_CMD "${pkgs.nodejs}/bin/npm" install -g opencode-ai@1.18.7
    fi
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

  # tasks-axi/quota-axi - firstmate's backlog-mutation and quota-aware
  # dispatch helpers, pinned/synced the same way as the three axi-family
  # skills above (see docs/configuration.md's "Toolchain" section in the
  # firstmate repo for why these two are required alongside gh-axi/
  # chrome-devtools-axi/lavish-axi).
  home.file.".claude/skills/tasks-axi/SKILL.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/skills/tasks-axi/SKILL.md";
  home.file.".agents/skills/tasks-axi/SKILL.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/skills/tasks-axi/SKILL.md";

  home.file.".claude/skills/quota-axi/SKILL.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/skills/quota-axi/SKILL.md";
  home.file.".agents/skills/quota-axi/SKILL.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/skills/quota-axi/SKILL.md";

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

  # Architecture Decision Records - hand-authored skill (not synced from an
  # npm package like the axi family above), paired with the adr-tools
  # package. Templates live alongside SKILL.md and are referenced by path
  # from within it, so symlink the whole skill directory rather than just
  # the one file.
  home.file.".claude/skills/adr".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/skills/adr";
  home.file.".agents/skills/adr".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/skills/adr";

  # mentor - hand-authored skill, same pattern as adr above.
  home.file.".claude/skills/mentor".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/skills/mentor";
  home.file.".agents/skills/mentor".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/skills/mentor";

  # Global agent policy file (kunchenguid's home/AGENTS.md pattern) - one
  # canonical file, symlinked to every harness's expected location. A
  # plain live symlink via home.activation (not home.file) - same
  # reasoning as installInstallations below: a downstream work-specific
  # profile repo may overwrite these same three paths with its own merged
  # file on every rebuild, and a home.file entry here would make
  # home-manager think it owns that path, triggering its
  # backupFileExtension logic against content it didn't actually write -
  # which fails outright once a stale .backup from a prior rebuild is
  # already sitting there. entryAfter "writeBoundary" only, so any
  # downstream activation targeting the same path can order itself after
  # and win.
  home.activation.installAgentsFile = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.config/opencode"
    $DRY_RUN_CMD ln -sfn "${dotfiles}/home/AGENTS.md" "$HOME/.claude/CLAUDE.md"
    $DRY_RUN_CMD ln -sfn "${dotfiles}/home/AGENTS.md" "$HOME/.codex/AGENTS.md"
    $DRY_RUN_CMD ln -sfn "${dotfiles}/home/AGENTS.md" "$HOME/.config/opencode/AGENTS.md"
  '';

  # Referenced by home/AGENTS.md's install-instructions pointer - kept out
  # of AGENTS.md's own body so every harness's context window only pays
  # for it when an agent is actually about to install something globally.
  # A plain live symlink (not home.file) - see installAgentsFile above for
  # why. entryAfter "writeBoundary" only, so any downstream activation
  # that also targets this path can order itself after and win.
  home.activation.installInstallations = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p "$HOME/.agents/instructions"
    $DRY_RUN_CMD ln -sfn "${dotfiles}/home/instructions/INSTALLATIONS.md" "$HOME/.agents/instructions/INSTALLATIONS.md"
  '';

  # Referenced by home/AGENTS.md's commit-conventions pointer - same
  # load-on-demand reasoning as installInstallations above: only paid for
  # when an agent is actually about to write a commit message.
  home.activation.installCommitConventions = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p "$HOME/.agents/instructions"
    $DRY_RUN_CMD ln -sfn "${dotfiles}/home/instructions/COMMITS.md" "$HOME/.agents/instructions/COMMITS.md"
  '';
}
