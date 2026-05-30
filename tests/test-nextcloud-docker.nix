(import ./lib.nix) {
  name = "test-nextcloud-docker";
  nodes = {
    machine1 =
      { self, pkgs, ... }:
      {
        imports = [ self.nixosModules.khepri ];
        virtualisation.diskSize = 8192;

        # You can choose between 'docker' and 'podman' as backend.
        khepri.backend = "docker";

        # Define your compositions.
        # Each composition would be logically equivialent to a `docker-compose.yml`.
        khepri.compositions = {
          # Composition for running Nextcloud.
          nextcloud = {
            networks = {
              nextcloud = { };
            };
            volumes = {
              nc_data = { };
              pg_data = { };
              redis_data = { };
            };
            services = {
              db = {
                # Images can be referenced by their name, which will be automatically
                # pulled when the service starts up.
                image = pkgs.dockerTools.pullImage {
                  imageName = "postgres";
                  imageDigest = "sha256:7f29c02ba9eeff4de9a9f414d803faa0e6fe5e8d15ebe217e3e418c82e652b35";
                  sha256 = "1zklv6y7xs7l4kcy4bbx8bg7mydrg6hna5g8in382mbjb4fi78gh";
                  finalImageName = "postgres";
                  finalImageTag = "17";
                };
                networks = [ "nextcloud" ];
                volumes = [ "pg_data:/var/lib/postgresql/data:rw" ];
                environment = {
                  POSTGRES_DB = "nextcloud";
                  POSTGRES_USER = "nextcloud";
                  POSTGRES_PASSWORD = "changeme";
                };
                restart = "unless-stopped";
              };

              redis = {
                image = pkgs.dockerTools.pullImage {
                  imageName = "redis";
                  imageDigest = "sha256:bd41d55aae1ecff61b2fafd0d66761223fe94a60373eb6bb781cfbb570a84079";
                  sha256 = "0j8f8yxlqz99j38kb6sm1q7x5723mw6nprdjs5zdha3yki66ac9r";
                  finalImageName = "redis";
                  finalImageTag = "latest";
                };
                networks = [ "nextcloud" ];
                volumes = [ "redis_data:/data:rw" ];
                restart = "unless-stopped";
              };

              app = {
                # Images can also be derivations created from `dockerTools.pullImage` or `dockerTools.buildImage`.
                # The hash can be obtained through nix-prefetch-docker.
                image = pkgs.dockerTools.pullImage {
                  imageName = "nextcloud";
                  imageDigest = "sha256:ff2cbaab14c85e587b5541e3aff4216a8a484e06424ebae661581937c0c8da0c";
                  hash = "sha256-XDbwoTMubzgajpMIiGR5leeQEQYjS3sv0P6Cjkwk4mI=";
                  finalImageName = "nextcloud";
                  finalImageTag = "33.0.0-apache";
                };
                networks = [ "nextcloud" ];
                ports = [ "8080:80/tcp" ];
                volumes = [ "nc_data:/var/www/html:rw" ];
                environment = {
                  POSTGRES_HOST = "db";
                  POSTGRES_DB = "nextcloud";
                  POSTGRES_USER = "nextcloud";
                  POSTGRES_PASSWORD = "changeme";
                  REDIS_HOST = "redis";
                  NEXTCLOUD_TRUSTED_DOMAINS = "nextcloud.example.com";
                };
                dependsOn = [
                  "db"
                  "redis"
                ];
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
      machine1.succeed("systemctl is-active --quiet khepri-network-nextcloud_nextcloud.service")
      machine1.succeed("systemctl is-active --quiet khepri-volume-nextcloud_nc_data.service")
      machine1.succeed("systemctl is-active --quiet khepri-volume-nextcloud_pg_data.service")
      machine1.succeed("systemctl is-active --quiet khepri-volume-nextcloud_redis_data.service")
      machine1.succeed("systemctl is-active --quiet khepri-service-nextcloud_db.service")
      machine1.succeed("systemctl is-active --quiet khepri-service-nextcloud_redis.service")
      machine1.succeed("systemctl is-active --quiet khepri-service-nextcloud_app.service")
      # The relevant docker resources where created.
      machine1.succeed("docker network inspect nextcloud_nextcloud")
      machine1.succeed("docker volume inspect nextcloud_nc_data")
      machine1.succeed("docker volume inspect nextcloud_pg_data")
      machine1.succeed("docker volume inspect nextcloud_redis_data")
      machine1.succeed("docker inspect nextcloud_db")
      machine1.succeed("docker inspect nextcloud_redis")
      machine1.succeed("docker inspect nextcloud_app")
    '';
}
