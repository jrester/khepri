# khepri

NixOS container orchestration in native nix similar to docker-compose. 

`khepri` allows you to easily define "container compositions" natively in your NixOS configuration similarly how you would define them in a `docker-compose.yaml`. This enables your NixOS configuration to become the source of truth for your system, without the need for another orchestration layer on top.

The main use-case for `khepri` is to easily run containerized workloads on NixOS, when NixOS modules for an application are not available/applicable and running a large container orchestrator like kubernetes is overkill.

This tool is heavily inspired by [compose2nix](https://github.com/aksiksi/compose2nix). 

# Usage

## Installation

Assuming you are using flakes to configure your NixOS system, you can add the `khepri` module as follows:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/25.05";
    khepri = {
      url = "github:jrester/khepri/v0.1.0";
      inputs.nixpkgs.follows = nixpkgs;
    };
  };
  outputs = { self, nixpkgs, khepri }: {
    nixosConfigurations.yourSystem = nixpkgs.lib.nixosSystem {
      modules = [ ./configuration.nix khepri.nixosModules.khepri ];
    };
  };
}
```

## Example

```nix
{ config, pkgs, lib, ... }: {
  # You can choose between 'docker' and 'podman' as backend.
  khepri.backend = "docker";

  # Define the compositions
  khepri.compositions = {
    # The first composition for running the reverse proxy caddy
    caddy = {
      networks.proxy_net = { external = true;};
      volumes = ["caddy_data"];
      services = {
        caddy = {
          image = "caddy:alpine";
          networks = [ "proxy_net" ];
          volumes = [
            "caddy_data:/data:rw"
            "/etc/caddy/Caddyfile:/etc/caddy/Caddyfile:ro"
          ];
          ports = [ "80:80/tcp" "443:443/tcp" "443:443/udp" ];
          restart = "unless-stopped";
        };
      };
    };
    # The second composition for running paperless-ngx
    paperless = {
      networks = {
        paperless = { };
        proxy_net = { external = true; };
      };
      volumes = {
        data = {};
        pgdata = {};
        redisdata = {};
        documents = {};
      };
      services = {
        broker = {
          image = "docker.io/library/redis:7";
          volumes = [ "redisdata:/data:rw" ];
          networks = [ "paperless" ];
          restart = "unless-stopped";
        };
        db = {
          image = "docker.io/library/postgres:15";
          environment = {
            POSTGRES_DB = "paperless";
            POSTGRES_PASSWORD = "paperless";
            POSTGRES_USER = "paperless";
          };
          volumes = [ "pgdata:/var/lib/postgresql/data:rw" ];
          networks = [ "paperless" ];
          restart = "unless-stopped";
        };
        tika = {
          image = "ghcr.io/paperless-ngx/tika:latest";
          networks = [ "paperless" ];
          restart = "unless-stopped";
        };
        gotenberg = {
          image = "docker.io/gotenberg/gotenberg:7.8";
          cmd = [
            "gotenberg"
            "--chromium-disable-javascript=true"
            "--chromium-allow-list=file:///tmp/.*"
          ];
          networks = [ "paperless" ];
          restart = "unless-stopped";
        };
        webserver = {
          image = "ghcr.io/paperless-ngx/paperless-ngx:latest";
          containerName = "paperless_web";
          environment = {
            PAPERLESS_DBHOST = "db";
            PAPERLESS_OCR_LANGUAGE = "deu";
            PAPERLESS_REDIS = "redis://broker:6379";
            PAPERLESS_SECRET_KEY = "super-secret-key";
            PAPERLESS_TASK_WORKERS = "2";
            PAPERLESS_TIKA_ENABLED = "1";
            PAPERLESS_TIKA_ENDPOINT = "http://tika:9998";
            PAPERLESS_TIKA_GOTENBERG_ENDPOINT = "http://gotenberg:3000";
            PAPERLESS_TIME_ZONE = "Europe/Berlin";
          };
          volumes = [
            "documents:/usr/src/paperless/media:rw"
            "data:/usr/src/paperless/data:rw"
          ];
          ports = [ "8000:8000/tcp" ];
          dependsOn = [ "db" "broker" "tika" "gotenberg" ];
          networks = [ "paperless" "proxy_net" ];
          restart = "unless-stopped";
        };
      };
    };
  };
}
```

### Using dockerTools

When specifying the image as a string, this image will be pulled automatically on boot of the container. Although, this works great, it is not the "nix way". Therefore, khepri also supports docker images as derivations such as those created using `dockerTools.pullImage` or `dockerTools.buildImage`:

```nix
{ config, pkgs, lib, ... }: {
  khepri.compositions = {
    nginx = {
      services = {
        nginx = {          
          image = pkgs.dockerTools.pullImage {
            imageName = "nginx";
            imageDigest =
              "sha256:0f04e4f646a3f14bf31d8bc8d885b6c951fdcf42589d06845f64d18aec6a3c4d";
            sha256 = "159z86nw6riirs9ix4zix7qawhfngl5fkx7ypmi6ib0sfayc8pw2";
            finalImageName = "nginx";
            finalImageTag = "latest";
          };
          restart = "unless-stopped";
        };
      };
    };
  };
};
```


# Features

`khepri` orientates itself at the features of docker-compose. Currently, a subset of the features of docker-compose are supported:


## [`services`](https://docs.docker.com/compose/compose-file/05-services/)

|   |     | Notes |
|---|:---:|-------|
| [`image`](https://docs.docker.com/compose/compose-file/05-services/#image) | ✅ | Supports images from `dockerTools.pullImage` |
| [`container_name`](https://docs.docker.com/compose/compose-file/05-services/#container_name) | ✅ | |
| [`environment`](https://docs.docker.com/compose/compose-file/05-services/#environment) | ✅ | |
| [`volumes`](https://docs.docker.com/compose/compose-file/05-services/#volumes) | ✅ | |
| [`labels`](https://docs.docker.com/compose/compose-file/05-services/#labels) | ✅ | |
| [`ports`](https://docs.docker.com/compose/compose-file/05-services/#ports) | ✅ | |
| [`dns`](https://docs.docker.com/compose/compose-file/05-services/#dns) | ❌ | |
| [`cap_add/cap_drop`](https://docs.docker.com/compose/compose-file/05-services/#cap_add) | ✅ | |
| [`logging`](https://docs.docker.com/compose/compose-file/05-services/#logging) | ❌ | |
| [`depends_on`](https://docs.docker.com/compose/compose-file/05-services/#depends_on) | ⚠️ | Only short syntax is supported. |
| [`restart`](https://docs.docker.com/compose/compose-file/05-services/#restart) | ⚠️ | No 'on-failure:<x>' |
| [`deploy.restart_policy`](https://docs.docker.com/compose/compose-file/deploy/#restart_policy) | ❌ | |
| [`deploy.resources`](https://docs.docker.com/compose/compose-file/deploy/#resources) | ❌ | |
| [`devices`](https://docs.docker.com/compose/compose-file/05-services/#devices) | ✅ | |
| [`networks`](https://docs.docker.com/compose/compose-file/05-services/#networks) | ✅ | |
| [`networks.aliases`](https://docs.docker.com/compose/compose-file/05-services/#aliases) | ❌ | |
| [`networks.ipv*_address`](https://docs.docker.com/compose/compose-file/05-services/#ipv4_address-ipv6_address) | ❌ | |
| [`network_mode`](https://docs.docker.com/compose/compose-file/05-services/#network_mode) | ❌ | |
| [`privileged`](https://docs.docker.com/compose/compose-file/05-services/#privileged) | ❌ | |
| [`extra_hosts`](https://docs.docker.com/compose/compose-file/05-services/#extra_hosts) | ✅ | |
| [`sysctls`](https://docs.docker.com/compose/compose-file/05-services/#sysctls) | ❌ | |
| [`shm_size`](https://docs.docker.com/compose/compose-file/05-services/#shm_size) | ❌ | |
| [`runtime`](https://docs.docker.com/compose/compose-file/05-services/#runtime) | ❌ | |
| [`security_opt`](https://docs.docker.com/compose/compose-file/05-services/#security_opt) | ❌ | |
| [`command`](https://docs.docker.com/compose/compose-file/05-services/#command) | ✅ | |
| [`healthcheck`](https://docs.docker.com/compose/compose-file/05-services/#healthcheck) | ❌ | |
| [`hostname`](https://docs.docker.com/compose/compose-file/05-services/#hostname) | ❌ | |
| [`mac_address`](https://docs.docker.com/compose/compose-file/05-services/#mac_address) | ❌ | |

## [`networks`](https://docs.docker.com/compose/compose-file/06-networks/)

|   |     |
|---|:---:|
| [`basic`](https://docs.docker.com/compose/compose-file/06-networks/#basic-example) | ✅ |
| [`labels`](https://docs.docker.com/compose/compose-file/06-networks/#labels) | ❌ |
| [`name`](https://docs.docker.com/compose/compose-file/06-networks/#name) | ❌ |
| [`driver`](https://docs.docker.com/compose/compose-file/06-networks/#driver) | ❌ |
| [`driver_opts`](https://docs.docker.com/compose/compose-file/06-networks/#driver_opts) | ❌ |
| [`ipam`](https://docs.docker.com/compose/compose-file/06-networks/#ipam) | ❌ |
| [`external`](https://docs.docker.com/compose/compose-file/06-networks/#external) | ✅ |
| [`internal`](https://docs.docker.com/compose/compose-file/06-networks/#internal) | ❌ |

## [`volumes`](https://docs.docker.com/compose/compose-file/07-volumes/)

|   |     |
|---|:---:|
| [`basic`](https://docs.docker.com/compose/compose-file/07-volumes/#example) | ✅ |
| [`driver`](https://docs.docker.com/compose/compose-file/07-volumes/#driver) | ❌ |
| [`driver_opts`](https://docs.docker.com/compose/compose-file/07-volumes/#driver_opts) | ❌ |
| [`labels`](https://docs.docker.com/compose/compose-file/07-volumes/#labels) | ❌ |
| [`name`](https://docs.docker.com/compose/compose-file/07-volumes/#name) | ❌ |
| [`external`](https://docs.docker.com/compose/compose-file/07-volumes/#external) | ✅ |

# Comparison to other tools

## compose2nix

[compose2nix](https://github.com/aksiksi/compose2nix) can be used to automatically generate a NixOS configuration from a docker-compose.yaml file. Although, the results of this conversion can be easily integrated into your NixOS configuration, they are very verbose. Changes to your container setup, can become quite cumbersome. For example, systemd dependencies must be configured manually, instead of "just" adding a new volume to your container.
`khepri` in contrast provides an interface, that is similar to docker-compose and performs the steps done by `compose2nix` automatically under hood. Additionally, all of this happens natively in nix, to provide a streamlined deployment experience.

## arion

[arion](https://github.com/hercules-ci/arion) is a nix wrapper around docker-compose, offering a similar experience to docker-compose. Instead of writing a `docker-compose.yaml` file you would write a `arion-compose.nix` file and control it using `arion <up/down>`. Therefore, `arion` does not provide a native integration with NixOS, like `khepri`.
