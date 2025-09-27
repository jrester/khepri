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
    volumeObjects: khepriContext:
    (map (
      volumeObject:
      nameValuePair (helpers.mkSystemdVolumeName volumeObject) (
        mkSystemdServiceForVolume volumeObject khepriContext
      )
    ) volumeObjects);
  mkSystemdServiceForVolume = volumeObject: khepriContext: {
    path = [ khepriContext.ociPackage ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${khepriContext.ociExecutable} volume inspect ${helpers.mkVolumeName volumeObject} || ${khepriContext.ociExecutable} volume create ${helpers.mkVolumeName volumeObject}
    '';
    partOf = [ "${helpers.mkSystemdCompositionTargetName volumeObject.compositionName}.target" ];
    wantedBy = [ "${helpers.mkSystemdCompositionTargetName volumeObject.compositionName}.target" ];
  };

  # Creation of systemd units for networks.
  # Networks are created and destroyed with the lifecycle of a composition.
  mkSystemdServicesForNetworks =
    networkObjects: khepriContext:
    map (
      networkObject:
      (nameValuePair (helpers.mkSystemdNetworkName networkObject) (
        mkSystemdServiceForNetwork networkObject khepriContext
      ))
    ) networkObjects;
  mkSystemdServiceForNetwork = networkObject: khepriContext: {
    path = [
      khepriContext.ociPackage
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "${khepriContext.ociExecutable} network rm -f ${helpers.mkNetworkName networkObject}";
    };
    script = ''
      ${khepriContext.ociExecutable} network inspect ${helpers.mkNetworkName networkObject} || ${khepriContext.ociExecutable} network create ${helpers.mkNetworkName networkObject}
    '';
    partOf = [ "${helpers.mkSystemdCompositionTargetName networkObject.compositionName}.target" ];
    wantedBy = [ "${helpers.mkSystemdCompositionTargetName networkObject.compositionName}.target" ];
  };

  # Creation of system units for services.
  mkSystemdServicesForServices =
    serviceObjects: khepriContext:
    map (
      serviceObject:
      (nameValuePair (helpers.mkSystemdServiceName serviceObject) (
        mkSystemdServiceForService serviceObject
          (helpers.findObjectsOfComposition serviceObject.compositionName serviceObjects)
          khepriContext
      ))
    ) serviceObjects;

  mkSystemdServiceForService =
    serviceObject: compositionServiceObjects: khepriContext:
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
        khepriContext.ociPackage
        pkgs.gnugrep
      ];
      serviceConfig = {
        Restart = mkForce (helpers.composeRestartToSystemdRestart serviceObject.restart);
        RestartMaxDelaySec = mkOverride 500 "1m";
        RestartSec = mkOverride 500 "100ms";
        RestartSteps = mkOverride 500 9;
      };
      startLimitBurst = 3;
      startLimitIntervalSec = 30;

      after = dependencies;
      # `docker.service` is already part of `after`, however putting it also into `wants` adds a stricter dependency.
      wants = (if khepriContext.backend == "docker" then [ "docker.service" ] else [ ]);
      # Add `docker.socket` explicitly to ensure the docker daemon is available.
      requires = dependencies ++ (if khepriContext.backend == "docker" then [ "docker.socket" ] else [ ]);
      partOf = [ "${helpers.mkSystemdCompositionTargetName serviceObject.compositionName}.target" ];
      wantedBy = [ "${helpers.mkSystemdCompositionTargetName serviceObject.compositionName}.target" ];
    };
}
