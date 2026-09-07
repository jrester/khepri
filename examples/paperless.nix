{
  pkgs,
  ...
}:
let
  paperlessImage = pkgs.dockerTools.pullImage {
    imageName = "ghcr.io/paperless-ngx/paperless-ngx";
    imageDigest = "sha256:6c86cad803970ea782683a8e80e7403444c5bf3cf70de63b4d3c8e87500db92f";
    hash = "sha256-tpQPDJSuipl5or/GgyommFvUoUmy9gcPs5C/TlfP8sY=";
    finalImageName = "ghcr.io/paperless-ngx/paperless-ngx";
    finalImageTag = "2.20.15";
  };
  postgresImage = pkgs.dockerTools.pullImage {
    imageName = "postgres";
    imageDigest = "sha256:822f8795764a670160640888508b2a68ea5c4b045012c2de17e1d0447bdbdc99";
    hash = "sha256-4Ig3mcKYLgtgy59yum8pQSR+yLX0Wu9FpKKmLH3RTeQ=";
    finalImageName = "postgres";
    finalImageTag = "15";
  };
  redisImage = pkgs.dockerTools.pullImage {
    imageName = "redis";
    imageDigest = "sha256:5c7c0445ed86918cb9efb96d95a6bfc03ed2059fe2c5f02b4d74f477ffe47915";
    hash = "sha256-WRPJvp56TQ7dgxeLmSOkyzvLkigUrliN0lqLfMZLn9w=";
    finalImageName = "redis";
    finalImageTag = "8";
  };
in
{
  khepri.backend = "docker";

  khepri.compositions.paperless = {
    networks = {
      paperless = { };
    };
    volumes = {
      data = { };
      pgdata = { };
      redisdata = { };
      documents = { };
    };
    services = {
      broker = {
        image = redisImage;
        volumes = [ "redisdata:/data:rw" ];
        networks = [ "paperless" ];
        restart = "unless-stopped";
      };

      db = {
        image = postgresImage;
        environment = {
          POSTGRES_DB = "paperless";
          POSTGRES_PASSWORD = "paperless";
          POSTGRES_USER = "paperless";
        };
        volumes = [ "pgdata:/var/lib/postgresql/data:rw" ];
        networks = [ "paperless" ];
        restart = "unless-stopped";
      };

      webserver = {
        image = paperlessImage;
        containerName = "paperless_web";
        environment = {
          PAPERLESS_DBHOST = "db";
          PAPERLESS_OCR_LANGUAGE = "deu";
          PAPERLESS_REDIS = "redis://broker:6379";
          PAPERLESS_SECRET_KEY = "changeme";
          PAPERLESS_TASK_WORKERS = "2";
          PAPERLESS_TIME_ZONE = "Europe/Berlin";
        };
        volumes = [
          "documents:/usr/src/paperless/media:rw"
          "data:/usr/src/paperless/data:rw"
        ];
        ports = [ "8000:8000/tcp" ];
        dependsOn = [
          "db"
          "broker"
        ];
        networks = [
          "paperless"
        ];
        restart = "unless-stopped";
      };
    };
  };
}
