{
  description = "Nix native docker container orchestration";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        packages.nixos-tests = pkgs.testers.runNixOSTest ./test.nix;
      }
    )
    // {
      nixosModules.default = ./src/khepri.nix;
    };
}
