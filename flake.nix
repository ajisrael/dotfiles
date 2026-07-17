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

    # Pooled git-worktree manager for parallel agent work
    # (https://github.com/kunchenguid/treehouse). Ships its own flake output
    # rather than a nixpkgs package, so it's consumed as an input, same
    # pattern as nix-homebrew above - gives flake.lock-pinned, content-
    # addressed installs with no runtime fetch.
    treehouse.url = "github:kunchenguid/treehouse";
    treehouse.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nix-darwin, nix-homebrew, home-manager, nixpkgs, treehouse }:
    let
      user = "changeme";
      # Must be a plain string, not a Nix path literal - a path literal
      # gets copied into an immutable /nix/store path at build time,
      # breaking the live-editable-symlink model these dotfiles rely on.
      personalDotfilesDir = "/Users/${user}/dotfiles";
      system = "x86_64-darwin";
    in
    {
      darwinConfigurations."mac" = nix-darwin.lib.darwinSystem {
        specialArgs = {
          inherit user personalDotfilesDir;
          treehousePackage = treehouse.packages.${system}.default;
        };
        modules = [
          ./configuration.nix
          nix-homebrew.darwinModules.nix-homebrew
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = {
              inherit user personalDotfilesDir;
              treehousePackage = treehouse.packages.${system}.default;
            };
            home-manager.users.${user} = import ./home.nix;
          }
        ];
      };
    };
}
