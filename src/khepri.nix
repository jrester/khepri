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
          type = types.either (types.listOf types.str) (types.attrsOf (types.submodule dependsOnOptions));
          default = [ ];
          description = ''
            Services of the same composition this service depends on. Either a list of
            service names (compose's short syntax, waits for `service_started`) or an
            attrset of service name to `{ condition; }` (compose's long syntax).
          '';
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
        cpus = mkOption {
          type = types.nullOr (types.either types.str types.number);
          default = null;
          description = "CPU limit, e.g. `\"0.5\"` (compose's `cpus`).";
        };
        memory = mkOption {
          type = types.nullOr (types.either types.str types.ints.positive);
          default = null;
          description = "Hard memory limit, e.g. `\"512m\"` or bytes (compose's `mem_limit`).";
        };
        memoryReservation = mkOption {
          type = types.nullOr (types.either types.str types.ints.positive);
          default = null;
          description = "Soft memory limit, e.g. `\"256m\"` or bytes (compose's `mem_reservation`).";
        };
        pidsLimit = mkOption {
          type = types.nullOr types.int;
          default = null;
          description = "Maximum number of processes, `-1` for unlimited (compose's `pids_limit`).";
        };
      };
    };
  dependsOnOptions = { ... }: {
    options = {
      condition = mkOption {
        type = types.enum [
          "service_started"
          "service_healthy"
          "service_completed_successfully"
        ];
        default = "service_started";
        description = ''
          `service_started` waits until the dependency's unit is active.
          `service_healthy` additionally waits until the dependency's container
          reports `healthy`, and fails if it reports `unhealthy` or has no healthcheck.
          `service_completed_successfully` waits until the dependency's container
          exited with 0, and fails if it exited otherwise.'';
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
        description = "Time between running the check during the start period (ms|s|m|h). On the podman backend this maps to --health-startup-interval and only takes effect together with a startup healthcheck command, so on a plain healthcheck it has no effect.";
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
    ociBackend = mkOption {
      type = types.enum [
        "podman"
        "docker"
      ];
      default = "docker";
      description = "The underlying container runtime implementation to use.";
    };
    ociPackage = mkOption {
      type = types.package;
      default = if cfg.ociBackend == "docker" then pkgs.docker else pkgs.podman;
      defaultText = literalExpression "pkgs.docker or pkgs.podman, depending on `khepri.ociBackend`";
      description = ''
        The package providing the `khepri.ociBackend` implementation. It is used
        both for the container runtime itself and for the CLI khepri calls from
        its systemd units.
      '';
    };
    compositions = mkOption {
      type = types.attrsOf (types.submodule compositionOptions);
      default = { };
    };
  };

  config = mkIf (cfg.compositions != { }) (
    let
      # Setup the khepri context which is used to differentiate between podman and docker.
      khepriContext = {
        ociBackend = cfg.ociBackend;
        ociPackage = cfg.ociPackage;

        # Assumes that ociPackage provides meta.mainProgram.
        ociExecutable = getExe cfg.ociPackage;
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
      virtualisation.oci-containers.backend = cfg.ociBackend;
      # Make the runtime use the same package khepri calls from its units.
      virtualisation.docker.package = mkIf (cfg.ociBackend == "docker") (mkDefault cfg.ociPackage);
      virtualisation.podman.package = mkIf (cfg.ociBackend == "podman") (mkDefault cfg.ociPackage);
      virtualisation.oci-containers.containers = listToAttrs (
        map (
          serviceObject: ociContainersHelpers.mkContainerConfigurationForService cfg.ociBackend serviceObject
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
