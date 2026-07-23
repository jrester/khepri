backend:
(import ./lib.nix) {
  inherit backend;
  name = "test-nextcloud-${backend}";
  nodes = {
    machine1 =
      { self, pkgs, ... }:
      let
        images = import ./images.nix pkgs;
      in
      {
        imports = [ self.nixosModules.khepri ];
        virtualisation.diskSize = 8192;

        # You can choose between 'docker' and 'podman' as backend.
        khepri.ociBackend = backend;

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
                image = images.postgres;
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
                image = images.redis;
                networks = [ "nextcloud" ];
                volumes = [ "redis_data:/data:rw" ];
                restart = "unless-stopped";
              };

              app = {
                # Images can also be derivations created from `dockerTools.pullImage` or `dockerTools.buildImage`.
                # The hash can be obtained through nix-prefetch-docker. See ./images.nix.
                image = images.nextcloud;
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
      # All khepri units are active and the ${backend} resources were created.
      assert_composition(
          machine1,
          "nextcloud",
          networks=["nextcloud"],
          volumes=["nc_data", "pg_data", "redis_data"],
          services=["db", "redis", "app"],
      )
    '';
}
