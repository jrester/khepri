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

  # Waits until the dependency's container reports healthy. Fails once the dependency's unit
  # stops running, since its container then never turns healthy and the unit has no start timeout.
  mkWaitForHealthy =
    dependencyServiceObject: khepriContext:
    let
      containerName = helpers.mkServiceName dependencyServiceObject;
      unitName = "${helpers.mkSystemdServiceName dependencyServiceObject}.service";
    in
    pkgs.writeShellScript "khepri-wait-healthy-${containerName}" ''
      while true; do
        status=$(${khepriContext.ociExecutable} inspect \
          --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
          ${containerName} 2>/dev/null)
        case "$status" in
          healthy) exit 0 ;;
          unhealthy) echo "${containerName} is unhealthy" >&2; exit 1 ;;
          none) echo "${containerName} has no healthcheck" >&2; exit 1 ;;
        esac
        if ! ${pkgs.systemd}/bin/systemctl is-active --quiet ${unitName}; then
          echo "${unitName} is not running" >&2
          exit 1
        fi
        sleep 1
      done
    '';

  # Waits until the dependency's container exited with 0. Awaited dependencies set
  # `RemainAfterExit`, so a successful exit leaves their unit `active (exited)`. The container
  # itself is removed on exit, so the unit's state is the only record of the exit code.
  mkWaitForCompletion =
    dependencyServiceObject: khepriContext:
    let
      containerName = helpers.mkServiceName dependencyServiceObject;
      unitName = "${helpers.mkSystemdServiceName dependencyServiceObject}.service";
      systemctl = "${pkgs.systemd}/bin/systemctl";
    in
    pkgs.writeShellScript "khepri-wait-completed-${containerName}" ''
      while true; do
        state="$(${systemctl} show -P ActiveState ${unitName})/$(${systemctl} show -P SubState ${unitName})"
        case "$state" in
          active/exited) exit 0 ;;
          failed/*) echo "${containerName} did not complete successfully" >&2; exit 1 ;;
          inactive/*) echo "${unitName} is not running" >&2; exit 1 ;;
        esac
        sleep 1
      done
    '';

  # dependsOn is either compose's short syntax (a list) or its long syntax (an attrset).
  # This transforms both variants into an attr set of serviceName -> condition.
  mkDependencyConditions =
    serviceObject:
    if isList serviceObject.dependsOn then
      genAttrs serviceObject.dependsOn (_: "service_started")
    else
      mapAttrs (_: dependency: dependency.condition) serviceObject.dependsOn;

  mkSystemdServiceForService =
    serviceObject: compositionServiceObjects: khepriContext:
    let
      referencedNetworkObjects = map (
        networkName: helpers.findObjectByNameInObjects networkName serviceObject.networkObjects
      ) serviceObject.networks;
      referencedVolumeObjects = map (
        volumeName: helpers.findObjectByNameInObjects volumeName serviceObject.volumeObjects
      ) (helpers.getOnlyVolumeMounts serviceObject.volumes serviceObject.volumeObjects);
      canonicalDependencyConditions = mkDependencyConditions serviceObject;
      findServiceObjects = map (
        dependencyServiceName:
        helpers.findObjectByNameInObjects dependencyServiceName compositionServiceObjects
      );
      # All services referenced in `depends_on` are added as a dependency.
      dependsOnAllServiceObjects = findServiceObjects (attrNames canonicalDependencyConditions);
      # Services with the condition `service_healthy` or `service_completed_successfully` in
      # `depends_on` need to be added to the later `ExecStartPre` so they are correctly awaited.
      findServiceObjectsWithCondition =
        wantedCondition:
        findServiceObjects (
          attrNames (filterAttrs (_: condition: condition == wantedCondition) canonicalDependencyConditions)
        );
      dependsOnServiceHealthyServiceObjects = findServiceObjectsWithCondition "service_healthy";
      dependsOnServiceCompletedServiceObjects = findServiceObjectsWithCondition "service_completed_successfully";
      # Keeps a completed service `active (exited)`, so a restart of a dependent does not run it again.
      isAwaitedForCompletion = any (
        otherServiceObject:
        (mkDependencyConditions otherServiceObject).${serviceObject.name} or null
        == "service_completed_successfully"
      ) compositionServiceObjects;
      dependencies = flatten [
        (map (
          networkObject: "${helpers.mkSystemdNetworkName networkObject}.service"
        ) referencedNetworkObjects)
        (map (volumeObject: "${helpers.mkSystemdVolumeName volumeObject}.service") referencedVolumeObjects)
        (map (
          serviceObject: "${helpers.mkSystemdServiceName serviceObject}.service"
        ) dependsOnAllServiceObjects)
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
        ExecStartPre =
          map (dependency: mkWaitForHealthy dependency khepriContext) dependsOnServiceHealthyServiceObjects
          ++ map (
            dependency: mkWaitForCompletion dependency khepriContext
          ) dependsOnServiceCompletedServiceObjects;
        RemainAfterExit = mkIf isAwaitedForCompletion true;
      };
      startLimitBurst = 3;
      startLimitIntervalSec = 30;

      after = dependencies;
      # `docker.service` is already part of `after`, however putting it also into `wants` adds a stricter dependency.
      wants = (if khepriContext.ociBackend == "docker" then [ "docker.service" ] else [ ]);
      # Add `docker.socket` explicitly to ensure the docker daemon is available.
      requires =
        dependencies ++ (if khepriContext.ociBackend == "docker" then [ "docker.socket" ] else [ ]);
      partOf = [ "${helpers.mkSystemdCompositionTargetName serviceObject.compositionName}.target" ];
      wantedBy = [ "${helpers.mkSystemdCompositionTargetName serviceObject.compositionName}.target" ];
    };
}
