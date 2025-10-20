{
  description = "NixOS Nextcloud server with flake-based deployment and installer ISO";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    nixos-generators.url = "github:nix-community/nixos-generators";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = inputs@{ self, nixpkgs, nixos-generators, flake-utils, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
    in
    flake-utils.lib.eachSystem systems (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      in
      {
        formatter = pkgs.nixpkgs-fmt;

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            nixpkgs-fmt
            git
          ];
        };

        packages = {
          nextcloud-installer-iso = nixos-generators.nixosGenerate {
            inherit system;
            format = "iso";
            modules = [
              ./hosts/nextcloud-server/iso.nix
            ];
          };
        };
      })
    // {
      nixosConfigurations.nextcloud-server = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/nextcloud-server
        ];
        specialArgs = {
          inherit inputs;
        };
      };
    };
}
