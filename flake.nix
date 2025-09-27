{
  description = "NixOS native container orchestration";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/25.05";
  };
  outputs =
    { self, nixpkgs, ... }:
    let
      # expose systems for `x86_64-linux` and `aarch64-linux`
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
    {
      nixosModules.khepri = ./src/khepri.nix;
      checks = forAllSystems (
        system:
        let
          checkArgs = {
            # reference to nixpkgs for the current system
            pkgs = nixpkgs.legacyPackages.${system};
            # this gives us a reference to our flake but also all flake inputs
            inherit self;
          };
        in
        {
          test-basic-docker = import ./tests/test-basic-docker.nix checkArgs;
          test-basic-podman = import ./tests/test-basic-podman.nix checkArgs;
        }
      );
    };
}
