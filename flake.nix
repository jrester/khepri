{
  description = "NixOS native container orchestration";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
  };
  outputs =
    { self, nixpkgs, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
    in
    {
      nixosModules.khepri = ./src/khepri.nix;
      checks = forAllSystems (
        system:
        let
          checkArgs = {
            pkgs = nixpkgs.legacyPackages.${system};
            inherit self;
          };
        in
        {
          test-nginx-docker = import ./tests/test-nginx-docker.nix checkArgs;
          test-nginx-podman = import ./tests/test-nginx-podman.nix checkArgs;
          test-nextcloud-docker = import ./tests/test-nextcloud-docker.nix checkArgs;
          test-ocipackage-docker = import ./tests/test-ocipackage-docker.nix checkArgs;
          test-ocipackage-podman = import ./tests/test-ocipackage-podman.nix checkArgs;
        }
      );
    };
}
