{
  description = "dotfiles";

  inputs = {
    # x86_64-darwin support ends with the 26.05 branch on all three of these
    # inputs (nixpkgs, nix-darwin, home-manager) - do not move to unstable or
    # a later release branch without re-checking Intel Mac support first.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
  };

  outputs = inputs@{ self, nix-darwin, nix-homebrew, home-manager, nixpkgs }:
    let
      user = "changeme";
      # Must be a plain string, not a Nix path literal - a path literal
      # gets copied into an immutable /nix/store path at build time,
      # breaking the live-editable-symlink model these dotfiles rely on.
      personalDotfilesDir = "/Users/${user}/dotfiles";
      system = "x86_64-darwin";
      # Pooled git-worktree manager for parallel agent work
      # (https://github.com/kunchenguid/treehouse). A pinned buildGoModule
      # derivation, not a flake input - so its version lives in dotfiles and
      # propagates to dotfiles-amway via git subtree. See pkgs/treehouse.nix
      # and docs/adr for why.
      treehousePackage =
        nixpkgs.legacyPackages.${system}.callPackage ./pkgs/treehouse.nix { };
    in
    {
      darwinConfigurations."mac" = nix-darwin.lib.darwinSystem {
        specialArgs = {
          inherit user personalDotfilesDir treehousePackage;
        };
        modules = [
          ./configuration.nix
          nix-homebrew.darwinModules.nix-homebrew
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            # A file newly brought under home.file (e.g. .zshrc, .gitconfig)
            # collides with the real, pre-existing plain file on the first
            # switch that manages it - back it up instead of hard-failing
            # the whole activation.
            home-manager.backupFileExtension = "backup";
            home-manager.extraSpecialArgs = {
              inherit user personalDotfilesDir treehousePackage;
            };
            home-manager.users.${user} = import ./home.nix;
          }
        ];
      };
    };
}
