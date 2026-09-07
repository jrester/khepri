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
