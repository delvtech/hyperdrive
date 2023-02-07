{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-21.11";
    utils.url = "github:numtide/flake-utils";
    foundry.url = "github:shazow/foundry.nix/monthly";
  };
  outputs = inputs@{ self, nixpkgs, foundry, utils }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ foundry.overlay ];
        };
      in {
        devShell = with pkgs;
          mkShell {
            SOLC_VERSION = "0.8.15";
            buildInputs =
              [ foundry.defaultPackage.${system} solc-select yarn nodejs-14_x ];
            shellHook = ''
              solc-select install $SOLC_VERSION
            '';
          };
      });
}
