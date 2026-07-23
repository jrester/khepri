backend:
(import ./lib.nix) {
  inherit backend;
  name = "test-nginx-${backend}";
  nodes = {
    machine1 =
      { self, pkgs, ... }:
      let
        images = import ./images.nix pkgs;
      in
      {
        imports = [ self.nixosModules.khepri ];
        khepri.ociBackend = backend;

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
              whoami0 = {
                image = images.whoami;
                containerName = "whoami0";
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
      start_all()
      machine1.wait_for_unit("multi-user.target")
      # All khepri units are active and the ${backend} resources were created.
      assert_composition(
          machine1,
          "test",
          networks=["proxy"],
          volumes=["nginx_content"],
          services=["nginx0", ("whoami0", "whoami0")],
      )
    '';
}
