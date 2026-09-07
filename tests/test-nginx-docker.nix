(import ./lib.nix) {
  name = "test-nginx-docker";
  nodes = {
    machine1 =
      { self, pkgs, ... }:
      {
        imports = [ self.nixosModules.khepri ];
        khepri.ociBackend = "docker";

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
              whoami0 = {
                image = pkgs.dockerTools.pullImage {
                  imageName = "traefik/whoami";
                  imageDigest = "sha256:200689790a0a0ea48ca45992e0450bc26ccab5307375b41c84dfc4f2475937ab";
                  hash = "sha256-Y6ZZJ9vgg8slPYe84kv46/VcbsrzD/UFVHcdmLMNrb4=";
                  finalImageName = "traefik/whoami";
                  finalImageTag = "v1.11";
                };
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
      # All relevant systemd units were successfully started.
      machine1.succeed("systemctl is-active --quiet khepri-network-test_proxy.service")
      machine1.succeed("systemctl is-active --quiet khepri-volume-test_nginx_content.service")
      machine1.succeed("systemctl is-active --quiet khepri-service-test_nginx0.service")
      machine1.succeed("systemctl is-active --quiet khepri-service-whoami0.service")
      # The relevant docker resources where created.
      machine1.succeed("docker network inspect test_proxy")
      machine1.succeed("docker volume inspect test_nginx_content")
      machine1.succeed("docker inspect test_nginx0")
      machine1.succeed("docker inspect whoami0")
    '';
}
