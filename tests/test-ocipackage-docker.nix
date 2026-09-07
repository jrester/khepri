(import ./lib.nix) {
  name = "test-ocipackage-docker";
  nodes = {
    machine1 =
      { self, pkgs, ... }:
      {
        imports = [ self.nixosModules.khepri ];
        khepri.ociBackend = "docker";
        # Same docker, distinct store path. The assertions below can only pass
        # if khepri really uses `khepri.ociPackage` instead of the default.
        khepri.ociPackage = pkgs.docker.overrideAttrs (old: {
          pname = "${old.pname}-khepri-marker";
        });

        khepri.compositions = {
          test = {
            networks = {
              proxy = { };
            };
            volumes = {
              nginx_content = { };
            };
            services = {
              nginx0 = {
                image = pkgs.dockerTools.pullImage {
                  imageName = "nginx";
                  imageDigest = "sha256:0f04e4f646a3f14bf31d8bc8d885b6c951fdcf42589d06845f64d18aec6a3c4d";
                  sha256 = "159z86nw6riirs9ix4zix7qawhfngl5fkx7ypmi6ib0sfayc8pw2";
                  finalImageName = "nginx";
                  finalImageTag = "latest";
                };
                volumes = [ "nginx_content:/usr/share/nginx/html:ro" ];
                networks = [ "proxy" ];
                restart = "unless-stopped";
              };
            };
          };
        };

        system.stateVersion = "25.05";
      };
  };

  testScript =
    { nodes, ... }:
    ''
      oci_package = "${nodes.machine1.khepri.ociPackage}"

      start_all()
      machine1.wait_for_unit("multi-user.target")
      # The composition comes up with the custom package.
      machine1.succeed("systemctl is-active --quiet khepri-network-test_proxy.service")
      machine1.succeed("systemctl is-active --quiet khepri-volume-test_nginx_content.service")
      machine1.succeed("systemctl is-active --quiet khepri-service-test_nginx0.service")
      machine1.succeed("docker inspect test_nginx0")
      # khepri calls the CLI of `khepri.ociPackage` from its own units.
      for unit in [
          "khepri-network-test_proxy",
          "khepri-volume-test_nginx_content",
          "khepri-service-test_nginx0",
      ]:
          machine1.succeed(
              f"systemctl show -p Environment {unit}.service | grep -F {oci_package}/bin"
          )
      # The runtime is the same package: daemon and system-wide CLI.
      machine1.succeed(
          f"systemctl show -p ExecStart docker.service | grep -F {oci_package}/bin/dockerd"
      )
      machine1.succeed(
          f"readlink /run/current-system/sw/bin/docker | grep -F {oci_package}/bin/docker"
      )
    '';
}
