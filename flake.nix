{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
    foundry.url = "github:shazow/foundry.nix";
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
            SOLHINT_PATH = ".solhint.json";
            SOLC_VERSION = "0.8.18";
            buildInputs = [
              foundry.defaultPackage.${system}
              nodejs-16_x
              (yarn.override { nodejs = nodejs-16_x; })
              (pkgs.python311.withPackages (p: with p; [ solc-select ]))
            ];
            shellHook = ''
              solc-select use $SOLC_VERSION
            '';
          };
      });
}
