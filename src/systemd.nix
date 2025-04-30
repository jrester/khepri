# This file contains mappers from khepri configuration to systemd services.
{
  pkgs,
  lib,
  helpers,
  ...
}:
with lib;
rec {
  # Creation of systemd units for volumes.
  # Volumes are only created, but never destroyed.
  mkSystemdServicesForVolumes =
    volumeObjects:
    (map (
      volumeObject:
      nameValuePair (helpers.mkSystemdVolumeName volumeObject) (mkSystemdServiceForVolume volumeObject)
    ) volumeObjects);
  mkSystemdServiceForVolume = volumeObject: {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      docker volume inspect ${helpers.mkVolumeName volumeObject} || docker volume create ${helpers.mkVolumeName volumeObject}
    '';
    partOf = [ "${helpers.mkSystemdCompositionTargetName volumeObject.compositionName}.target" ];
    wantedBy = [ "${helpers.mkSystemdCompositionTargetName volumeObject.compositionName}.target" ];
  };

  # Creation of systemd units for networks.
  # Networks are created and destroyed with the lifecycle of a composition.
  mkSystemdServicesForNetworks =
    networkObjects:
    map (
      networkObject:
      (nameValuePair (helpers.mkSystemdNetworkName networkObject) (
        mkSystemdServiceForNetwork networkObject
      ))
    ) networkObjects;
  mkSystemdServiceForNetwork = networkObject: {
    path = [
      pkgs.docker
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "${pkgs.docker}/bin/docker network rm -f ${helpers.mkNetworkName networkObject}";
    };
    script = ''
      docker network inspect ${helpers.mkNetworkName networkObject} || docker network create ${helpers.mkNetworkName networkObject}
    '';
    partOf = [ "${helpers.mkSystemdCompositionTargetName networkObject.compositionName}.target" ];
    wantedBy = [ "${helpers.mkSystemdCompositionTargetName networkObject.compositionName}.target" ];
  };

  mkSystemdServicesForServices =
    serviceObjects:
    map (
      serviceObject:
      (nameValuePair (helpers.mkSystemdServiceName serviceObject) (
        mkSystemdServiceForService serviceObject (
          helpers.findObjectsOfComposition serviceObject.compositionName serviceObjects
        )
      ))
    ) serviceObjects;

  mkSystemdServiceForService =
    serviceObject: compositionServiceObjects:
    let
      referencedNetworkObjects = map (
        networkName: helpers.findObjectByNameInObjects networkName serviceObject.networkObjects
      ) serviceObject.networks;
      referencedVolumeObjects = map (
        volumeName: helpers.findObjectByNameInObjects volumeName serviceObject.volumeObjects
      ) (helpers.getOnlyVolumeMounts serviceObject.volumes serviceObject.volumeObjects);
      referencedServiceObjects = map (
        dependencyServiceName:
        helpers.findObjectByNameInObjects dependencyServiceName compositionServiceObjects
      ) serviceObject.dependsOn;
      dependencies = flatten [
        (map (
          networkObject: "${helpers.mkSystemdNetworkName networkObject}.service"
        ) referencedNetworkObjects)
        (map (volumeObject: "${helpers.mkSystemdVolumeName volumeObject}.service") referencedVolumeObjects)
        (map (
          serviceObject: "${helpers.mkSystemdServiceName serviceObject}.service"
        ) referencedServiceObjects)
      ];
    in
    {
      path = [
        pkgs.docker
        pkgs.gnugrep
      ];
      serviceConfig = {
        Restart = mkForce (helpers.composeRestartToSystemdRestart serviceObject.restart);
        RestartMaxDelaySec = mkOverride 500 "1m";
        RestartSec = mkOverride 500 "100ms";
        RestartSteps = mkOverride 500 9;
      };
      after = dependencies;
      requires = dependencies;
      partOf = [ "${helpers.mkSystemdCompositionTargetName serviceObject.compositionName}.target" ];
      wantedBy = [ "${helpers.mkSystemdCompositionTargetName serviceObject.compositionName}.target" ];
    };
}
