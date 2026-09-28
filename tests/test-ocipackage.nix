backend:
let
  # The runtime is the same package as khepri's CLI. docker has a daemon, so
  # both the daemon and the system-wide CLI come straight from the package.
  # podman has no daemon: the system-wide CLI is the runtime. The podman module
  # re-wraps its `package` (an `apply` adds extraPackages), so the runtime is
  # derived from `khepri.ociPackage` and keeps its name, but not its store path.
  runtimeChecks =
    if backend == "docker" then
      ''
        machine1.succeed(
            f"systemctl show -p ExecStart docker.service | grep -F {oci_package}/bin/dockerd"
        )
        machine1.succeed(
            f"readlink /run/current-system/sw/bin/docker | grep -F {oci_package}/bin/docker"
        )
      ''
    else
      ''
        machine1.succeed(
            "readlink /run/current-system/sw/bin/podman | grep -F podman-khepri-marker"
        )
      '';
in
(import ./lib.nix) {
  inherit backend;
  name = "test-ocipackage-${backend}";
  nodes = {
    machine1 =
      { self, pkgs, ... }:
      let
        images = import ./images.nix pkgs;
      in
      {
        imports = [ self.nixosModules.khepri ];
        khepri.ociBackend = backend;
        # Same backend package, distinct store path. The assertions below can
        # only pass if khepri really uses `khepri.ociPackage` over the default.
        khepri.ociPackage = pkgs.${backend}.overrideAttrs (old: {
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
                image = images.nginx;
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
      assert_composition(
          machine1,
          "test",
          networks=["proxy"],
          volumes=["nginx_content"],
          services=["nginx0"],
      )
      # khepri calls the CLI of `khepri.ociPackage` from its own units.
      for unit in [
          "khepri-network-test_proxy",
          "khepri-volume-test_nginx_content",
          "khepri-service-test_nginx0",
      ]:
          machine1.succeed(
              f"systemctl show -p Environment {unit}.service | grep -F {oci_package}/bin"
          )
      ${runtimeChecks}
    '';
}
