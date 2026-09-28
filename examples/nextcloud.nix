{
  config,
  pkgs,
  lib,
  ...
}:
let
  serviceName = "nextcloud";
  commonService = import ./common.nix {
    inherit
      config
      pkgs
      lib
      serviceName
      ;
  };

  nextcloudImage = pkgs.dockerTools.pullImage {
    imageName = "nextcloud";
    imageDigest = "sha256:ff2cbaab14c85e587b5541e3aff4216a8a484e06424ebae661581937c0c8da0c";
    hash = "sha256-XDbwoTMubzgajpMIiGR5leeQEQYjS3sv0P6Cjkwk4mI=";
    finalImageName = "nextcloud";
    finalImageTag = "33.0.0-apache";
  };
  nextcloudVolumes = [
    "nc_html:/var/www/html"
    "nc_apps:/var/www/html/custom_apps"
    "nc_config:/var/www/html/config"
    "nc_data:/var/www/html/data"
  ];

  postgres = commonService.mkPostgres { };
  redis = commonService.mkRedis { };
in
{
  khepri.compositions.nextcloud = {
    networks = {
      traefik_proxy_net.external = true;
      "${serviceName}" = { };
    };
    volumes = {
      postgres_data = { };
      redis_data = { };
      nc_config = { };
      nc_data = { };
      nc_apps = { };
      nc_html = { };
    };
    services = {
      inherit postgres redis;
      app = {
        image = nextcloudImage;
        networks = [
          serviceName
          "traefik_proxy_net"
        ];
        volumes = nextcloudVolumes;
        environment = {
          NEXTCLOUD_ADMIN_USER = "admin";

          POSTGRES_DB = serviceName;
          POSTGRES_USER = serviceName;
          POSTGRES_HOST = postgres.containerName;

          REDIS_HOST = redis.containerName;

          OVERWRITEPROTOCOL = "https";
          TRUSTED_PROXIES = "172.0.0.0/8";
          NEXTCLOUD_TRUSTED_DOMAINS = commonService.domainName;

          SMTP_HOST = config.oecis.smtp.host;
          SMTP_SECURE = if config.oecis.smtp.tls then "ssl" else "";
          SMTP_PORT = builtins.toString config.oecis.smtp.port;
          SMTP_NAME = config.oecis.smtp.user;
          MAIL_FROM_ADDRESS = "nextcloud";
          MAIL_DOMAIN = config.oecis.domain;

          # Fix some complaints about missing configuration.
          NC_maintenance_window_start = "1";
          NC_default_phone_region = "DE";
        };
        environmentFiles = [
          # Contains:
          # * POSTGRES_PASSWORD
          # * SMTP_PASSWORD
          commonService.secretsEnvFile
        ];
        labels = commonService.traefikServiceLabels // {
          "traefik.http.routers.nextcloud.middlewares" =
            "nextcloud-headers@docker, nextcloud-redirectregex@docker";
          "traefik.http.middlewares.nextcloud-headers.headers.stsPreload" = "true";
          "traefik.http.middlewares.nextcloud-headers.headers.stsSeconds" = "15552000";
          "traefik.http.middlewares.nextcloud-redirectregex.redirectregex.regex" =
            "^https://(.*)/.well-known/(card|cal)dav";
          "traefik.http.middlewares.nextcloud-redirectregex.redirectregex.replacement" =
            "https:///$${1}/remote.php/dav";
        };
        restart = "unless-stopped";
      };
      cron = {
        image = nextcloudImage;
        volumes = nextcloudVolumes;
        networks = [
          "nextcloud"
        ];
        restart = "unless-stopped";
        entrypoint = "/cron.sh";
      };
    };
  };
}
