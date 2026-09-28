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
      ];
    in
    {
      nixosModules.khepri = ./src/khepri.nix;
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          inherit (pkgs) lib;
          checkArgs = { inherit pkgs self; };
          backends = [
            "docker"
            "podman"
          ];
          # Run a backend-parameterized test against every backend, producing
          # `test-<name>-<backend>` checks.
          matrix =
            name: testFn:
            lib.listToAttrs (
              map (backend: {
                name = "test-${name}-${backend}";
                value = testFn backend checkArgs;
              }) backends
            );
        in
        (matrix "nginx" (import ./tests/test-nginx.nix))
        // (matrix "healthchecks" (import ./tests/test-healthchecks.nix))
        // (matrix "nextcloud" (import ./tests/test-nextcloud.nix))
        // (matrix "ocipackage" (import ./tests/test-ocipackage.nix))
        // (matrix "resources" (import ./tests/test-resources.nix))
      );
    };
}
