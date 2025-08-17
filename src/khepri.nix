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
          default = false;
          type = types.bool;
        };
      };
    };
  compositionVolumeOptions =
    { ... }:
    {
      options = {
        external = mkOption {
          default = false;
          type = types.bool;
        };
      };
    };
  compositionOptions =
    { ... }:
    {
      options = {
        services = mkOption {
          default = { };
          type = types.attrsOf (types.submodule serviceOptions);
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
    compositions = mkOption {
      type = types.attrsOf (types.submodule compositionOptions);
      default = { };
    };
  };

  config = mkIf (cfg.compositions != { }) (
    let
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
      virtualisation.oci-containers.containers = listToAttrs (
        map (
          serviceObject: ociContainersHelpers.mkContainerConfigurationForService serviceObject
        ) serviceObjects
      );
      systemd.services =
        let
          services = listToAttrs (systemdHelpers.mkSystemdServicesForServices serviceObjects);
          volumes = listToAttrs (
            systemdHelpers.mkSystemdServicesForVolumes (
              filter (volumeObject: !volumeObject.external) volumeObjects
            )
          );
          networks = listToAttrs (
            systemdHelpers.mkSystemdServicesForNetworks (
              filter (networkObject: !networkObject.external) networkObjects
            )
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
