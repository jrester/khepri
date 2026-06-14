{
  lib,
  pkgs,
  config,
  ...
}:
with lib;
let
  cfg = config.khepri;
  compositionNetworkOptions =
    { ... }:
    {
      options = {
        external = mkOption {
          type = types.bool;
          default = false;
        };
      };
    };
  compositionVolumeOptions =
    { ... }:
    {
      options = {
        external = mkOption {
          type = types.bool;
          default = false;
        };
      };
    };
  compositionOptions =
    { ... }:
    {
      options = {
        services = mkOption {
          type = types.attrsOf (types.submodule serviceOptions);
          default = { };
        };
        volumes = mkOption {
          type = types.attrsOf (types.submodule compositionVolumeOptions);
          default = { };
        };
        networks = mkOption {
          type = types.attrsOf (types.submodule compositionNetworkOptions);
          default = { };
        };
      };
    };
  serviceOptions =
    { ... }:
    {
      options = {
        enable = lib.mkOption {
          type = types.bool;
          default = true;
        };
        image = mkOption { type = types.either types.str types.package; };
        restart = mkOption {
          type = types.enum [
            "no"
            "always"
            "on-failure"
            "unless-stopped"
          ];
          default = "no";
        };
        environment = mkOption {
          type = types.attrsOf types.anything;
          default = { };
        };
        environmentFiles = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
        containerName = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        volumes = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
        cmd = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
        networks = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
        ports = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
        dependsOn = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
        devices = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
        capAdd = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
        capDrop = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
        extraHosts = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
        labels = mkOption {
          type = types.attrsOf types.str;
          default = { };
        };
        entrypoint = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        healthcheck = mkOption {
          type = types.nullOr (types.submodule serviceHealthcheckOptions);
          default = null;
        };
      };
    };
  serviceHealthcheckOptions = { ... }: {
    options = {
      test = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        description = "Command to run to check health";
      };
      interval = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Time between running the check (ms|s|m|h)";
      };
      timeout = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Maximum time to allow one check to run (ms|s|m|h)";
      };
      retries = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Consecutive failures needed to report unhealthy";
      };
      startPeriod = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Start period for the container to initialize before starting health-retries countdown (ms|s|m|h)";
      };
      startInterval = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Time between running the check during the start period (ms|s|m|h)";
      };
    };
  };
  helpers = import ./helpers.nix { inherit lib; };
  systemdHelpers = import ./systemd.nix { inherit helpers pkgs lib; };
  ociContainersHelpers = import ./oci-containers.nix { inherit helpers pkgs lib; };

  mkObject =
    compositionName: objectName: objectOptions:
    objectOptions
    // {
      name = objectName;
      compositionName = compositionName;
    };

  mkServiceObject =
    compositionName: serviceName: serviceOptions: volumeObjects: networkObjects:
    (mkObject compositionName serviceName serviceOptions)
    // {
      volumeObjects = helpers.findObjectsOfComposition compositionName volumeObjects;
      networkObjects = helpers.findObjectsOfComposition compositionName networkObjects;
    };
in
{
  options.khepri = {
    backend = mkOption {
      type = types.enum [
        "podman"
        "docker"
      ];
      default = "docker";
      description = "The underlying Docker implementation to use.";
    };
    compositions = mkOption {
      type = types.attrsOf (types.submodule compositionOptions);
      default = { };
    };
  };

  config = mkIf (cfg.compositions != { }) (
    let
      # Setup the khepri context which is used to differentiate between podman and docker.
      ociPackage = (if cfg.backend == "docker" then pkgs.docker else pkgs.podman);
      ociExecutable = (
        if cfg.backend == "docker" then "${pkgs.docker}/bin/docker" else "${pkgs.podman}/bin/podman"
      );
      khepriContext = {
        inherit ociPackage ociExecutable;
        backend = cfg.backend;
      };

      networkObjects = flatten (
        mapAttrsToList (
          compositionName: compositionOptions:
          (mapAttrsToList (
            networkName: networkOptions: (mkObject compositionName networkName networkOptions)
          ) compositionOptions.networks)
        ) cfg.compositions
      );
      volumeObjects = flatten (
        mapAttrsToList (
          compositionName: compositionOptions:
          (mapAttrsToList (
            volumeName: volumeOptions: (mkObject compositionName volumeName volumeOptions)
          ) compositionOptions.volumes)
        ) cfg.compositions
      );

      serviceObjects = flatten (
        mapAttrsToList (
          compositionName: compositionOptions:
          (mapAttrsToList (
            serviceName: serviceOptions:
            (mkServiceObject compositionName serviceName serviceOptions volumeObjects networkObjects)
          ) compositionOptions.services)
        ) cfg.compositions
      );
      targets = lists.unique (
        mapAttrsToList (
          compositionName: compositionOptions: helpers.mkSystemdCompositionTargetName compositionName
        ) cfg.compositions
      );
    in
    {
      # Set the oci-containers backend. oci-containers will automatically enable the required virtualization backend.
      virtualisation.oci-containers.backend = cfg.backend;
      virtualisation.oci-containers.containers = listToAttrs (
        map (
          serviceObject: ociContainersHelpers.mkContainerConfigurationForService serviceObject
        ) serviceObjects
      );
      systemd.services =
        let
          services = listToAttrs (systemdHelpers.mkSystemdServicesForServices serviceObjects khepriContext);
          volumes = listToAttrs (
            systemdHelpers.mkSystemdServicesForVolumes (filter (
              volumeObject: !volumeObject.external
            ) volumeObjects) khepriContext
          );
          networks = listToAttrs (
            systemdHelpers.mkSystemdServicesForNetworks (filter (
              networkObject: !networkObject.external
            ) networkObjects) khepriContext
          );
        in
        mkMerge [
          services
          volumes
          networks
        ];
      systemd.targets = listToAttrs (
        map (target: nameValuePair target ({ wantedBy = [ "multi-user.target" ]; })) targets
      );
    }
  );
}
