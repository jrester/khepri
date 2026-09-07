# khepri

`khepri` allows you to easily define "container compositions" natively in your NixOS configuration similar to how you would define them in a `docker-compose.yaml`. This enables your NixOS configuration to become the source of truth for your system, without the need for another orchestration layer on top.

The main use-case for `khepri` is to easily run containerized workloads on NixOS, when NixOS modules for an application are not available/applicable and running a large container orchestrator like Kubernetes is overkill.

This tool is heavily inspired by [compose2nix](https://github.com/aksiksi/compose2nix). 

# Usage

## Installation

Assuming you are using flakes to configure your NixOS system, you can add the `khepri` module as follows:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    khepri = {
      url = "github:jrester/khepri/v0.1.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = { self, nixpkgs, khepri }: {
    nixosConfigurations.yourSystem = nixpkgs.lib.nixosSystem {
      modules = [ khepri.nixosModules.khepri ];
    };
  };
}
```

## Example


```nix
{ pkgs, ... }:
{
  # You can choose between 'docker' and 'podman' as backend.
  khepri.ociBackend = "docker";

  # Optional: pin the package providing the backend. Defaults to `pkgs.docker`
  # or `pkgs.podman`, matching `khepri.ociBackend`.
  # khepri.ociPackage = pkgs.docker_25;

  # Define your compositions.
  # Each composition would be logically equivialent to a `docker-compose.yml`.
  khepri.compositions = {
    # Composition for running Nextcloud.
    nextcloud = {
      networks = {
        nextcloud = { };
      };
      volumes = {
        nc_data = {};
        pg_data = {};
        redis_data = {};
      };
      services = {
        db = {
          # Images can be referenced by their name, which will be automatically
          # pulled when the service starts up.
          image = "postgres:15";
          networks = [ "nextcloud" ];
          volumes = [ "pg_data:/var/lib/postgresql/data:rw" ];
          environment = {
            POSTGRES_DB       = "nextcloud";
            POSTGRES_USER     = "nextcloud";
            POSTGRES_PASSWORD = "changeme";
          };
          restart = "unless-stopped";
        };

        redis = {
          image = "redis:7-alpine";
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
          ports   = [ "8080:80/tcp" ];
          volumes = [ "nc_data:/var/www/html:rw" ];
          environment = {
            POSTGRES_HOST     = "db";
            POSTGRES_DB       = "nextcloud";
            POSTGRES_USER     = "nextcloud";
            POSTGRES_PASSWORD = "changeme";
            REDIS_HOST        = "redis";
            NEXTCLOUD_TRUSTED_DOMAINS = "nextcloud.example.com";
          };
          dependsOn = [ "db" "redis" ];
          restart   = "unless-stopped";
        };       
      };
    };
  };
}
```

# Features

## Name Mangling

Similar to `docker-compose`, `khepri` performs name mangling of service, volume and network names based on the composition name by default. This means that the service named `db` in the `nextcloud` composition will be assigned the canonical name of `nextcloud_db` unless otherwise configured. However, inside a composition, it can still be referenced by its `db` name, e.g., in `depends_on`.

## Systemd Integration

Similar to the NixOS built-in `virtualization.oci-containers`, `khepri` makes heavy use of `systemd` to manage the composition and its services, volumes and networks.

For this purpose all services are grouped under a `systemd` target unit `khepri-compose-<composition name>-root.target` (e.g., `khepri-compose-nextcloud-root.target`). This enables orchestration of the whole composition, e.g., to restart the composition as a whole.

### Volume Management

Each volume is translated to a `systemd` service unit `khepri-volume-<canonical volume name>.service` (e.g., `khepri-volume-nextcloud_pgdata.service`), which creates the volume on demand. This service unit will be automatically pulled in by each service that references the volume in a composition.

### Network Management

Each network is translated to a `systemd` service unit `khepri-network-<canonical network name>.service` (e.g., `khepri-network-nextcloud_nextcloud.service`), which creates the network on demand. This service unit will be automatically pulled in by each service that references the network in a composition.

### Service Management

Each service is translated to a `systemd` service unit `khepri-service-<canonical service name>.service` (e.g., `khepri-service-nextcloud_app.service`), which creates the container. The service will automatically pull in the required volume, network and service units it requires to ensure that everything is ready, before the container is started.

## Docker-Compose Feature Parity

`khepri` orientates itself at the features of `docker-compose`. Currently, a subset of the features of `docker-compose` are supported:


### [`services`](https://docs.docker.com/compose/compose-file/05-services/)

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

### [`networks`](https://docs.docker.com/compose/compose-file/06-networks/)

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

### [`volumes`](https://docs.docker.com/compose/compose-file/07-volumes/)

|   |     |
|---|:---:|
| [`basic`](https://docs.docker.com/compose/compose-file/07-volumes/#example) | ✅ |
| [`driver`](https://docs.docker.com/compose/compose-file/07-volumes/#driver) | ❌ |
| [`driver_opts`](https://docs.docker.com/compose/compose-file/07-volumes/#driver_opts) | ❌ |
| [`labels`](https://docs.docker.com/compose/compose-file/07-volumes/#labels) | ❌ |
| [`name`](https://docs.docker.com/compose/compose-file/07-volumes/#name) | ❌ |
| [`external`](https://docs.docker.com/compose/compose-file/07-volumes/#external) | ✅ |

# Comparison to other tools

## oci-containers

With the NixOS built-in `virtualization.oci-containers` option it is already possible to manage containers natively inside the NixOS configuration. In fact, `khepri` translates to `oci-containers` natively but adds additional logic around the management of networks, volumes, as well as name mangling and a more sophisticated systemd integration. So, `khepri` can be seen as an extension of `oci-containers`, and it is possible to easily plug into the underlying `oci-containers` definitions.

## compose2nix

[compose2nix](https://github.com/aksiksi/compose2nix) can be used to automatically generate a NixOS configuration from a docker-compose.yaml file. Although, the results of this conversion can be easily integrated into your NixOS configuration, they are very verbose. Changes to your container setup can become quite cumbersome. For example, systemd dependencies must be configured manually, instead of "just" adding a new volume to your container.
In contrast, `khepri` provides an interface which is syntactically similar to `docker-compose` and performs the steps done by `compose2nix` automatically under the hood. Additionally, all of this happens natively in nix, so users do not need to re-run `compose2nix` when their compose definition changes.

## arion

[arion](https://github.com/hercules-ci/arion) is a Nix wrapper around `docker-compose`, offering a similar experience to docker-compose. Instead of writing a `docker-compose.yaml` file you would write a `arion-compose.nix` file and control it using `arion <up/down>`. Therefore, `arion` does not provide a native integration with NixOS like `khepri` does.
