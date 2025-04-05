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
  compositionOptions =
    { ... }:
    {
      options = {
        services = mkOption {
          default = { };
          type = types.attrsOf (types.submodule serviceOptions);
        };
        volumes = mkOption {
          type = types.listOf types.str;
          default = [ ];
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
          type = types.attrsOf types.str;
          default = { };
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
      };
    };
  # Helper functions to enable consistent name generation
  mkContainerName =
    compositionName: serviceName: serviceConfiguration:
    if serviceConfiguration.containerName != null then
      serviceConfiguration.containerName
    else
      "${compositionName}_${serviceName}";
  mkNetworkName =
    compositionName: networkName: networkConfiguration:
    if networkConfiguration.external then networkName else "${compositionName}_${networkName}";
  mkSystemdTargetName = compositionName: "khepri-compose-${compositionName}-root";
  mkSystemdVolumeName = compositionName: volumeName: "docker-volume-${compositionName}_${volumeName}";
  mkSystemdNetworkName =
    compositionName: networkName: "docker-network-${compositionName}_${networkName}";

  getImageNameFromDerivation =
    drv:
    let
      attrNames = lib.attrNames drv;
    in
    if builtins.elem "destNameTag" attrNames then
      # image comming from dockerTools.pullImage
      drv.destNameTag
    else
    # image comming from dockerTools.buildImage
    if builtins.elem "imageName" attrNames && builtins.elem "imageTag" attrNames then
      "${drv.imageName}:${drv.imageTag}"
    else
      throw (
        "Image '${drv}' is missing the attribute 'destNameTag'. Available attributes: ${lib.strings.concatStringsSep "," (attrNames)}"
      );

  composeRestartToSystemdRestart =
    restartStr: if restartStr == "unless-stopped" then "always" else restartStr;

  mkCanonicalServiceConfiguration =
    compositionName: compositionConfiguration: serviceName: serviceConfiguration: networkConfigurations:
    let
      mappedVolumes = map (
        volumeMapping: head (builtins.split ":" volumeMapping)
      ) serviceConfiguration.volumes;
      # Cross reference those mapped volumes with the volumes definied in the compoistion, so that we only link docker volumes and not direct file mounts
      # TODO: Additionally, some sanity checks might be usefull here
      serviceVolumes = filter (volume: elem volume compositionConfiguration.volumes) mappedVolumes;
      # Construct the resulting mappings. For serviceVolumes, the mapping must be updated with the canonical name of that volume
      volumeMappings = map (
        mapping:
        let
          volumeMappingParts = (builtins.split ":" mapping);
          volumeName = head volumeMappingParts;
        in
        if elem volumeName serviceVolumes then
          strings.concatStringsSep ":" (flatten [
            "${compositionName}_${volumeName}"
            (tail volumeMappingParts)
          ])
        else
          mapping
      ) serviceConfiguration.volumes;
      # Map all attached networks to their final name
      attachedNetworksConfigurations = map (
        networkName:
        (lists.findSingle
          (
            networkConfiguration:
            networkConfiguration.name == networkName && networkConfiguration.composition == compositionName
          )
          (throw "error: network '${networkName}' is referenced by service '${serviceName}' in composition '${compositionName}' but definition on composition level could not be found")
          (throw "error: multiple network configurations for '${networkName}' found")
          networkConfigurations
        )
      ) serviceConfiguration.networks;
      containerName = mkContainerName compositionName serviceName serviceConfiguration;
      imageName =
        if builtins.isString serviceConfiguration.image then
          serviceConfiguration.image
        else
          getImageNameFromDerivation serviceConfiguration.image;
    in
    {
      serviceName = serviceName;
      containerName = containerName;
      hostName =
        if serviceConfiguration.containerName != null then
          serviceConfiguration.containerName
        else
          serviceName;
      # Concrete mappings e.g. '/data:/var/data:rw'
      volumeMappings = volumeMappings;
      # Canonical name of each volume as definied in a compositions 'volumes' section
      volumes = serviceVolumes;
      primaryNetwork =
        if attachedNetworksConfigurations == [ ] then
          ""
        else
          (head attachedNetworksConfigurations).canonicalName;
      additionalNetworks =
        if attachedNetworksConfigurations == [ ] then
          [ ]
        else
          map (networkConfiguration: networkConfiguration.canonicalName) (
            tail attachedNetworksConfigurations
          );
      dependsOn = map (
        dependencyServiceName:
        mkContainerName compositionName dependencyServiceName (
          getAttr dependencyServiceName compositionConfiguration.services
        )
      ) serviceConfiguration.dependsOn;
      image = imageName;
      imageFile =
        if builtins.isAttrs serviceConfiguration.image then serviceConfiguration.image else null;
      # Some extra parameters that are passed as is
      environment = serviceConfiguration.environment;
      cmd = serviceConfiguration.cmd;
      ports = serviceConfiguration.ports;
      devices = serviceConfiguration.devices;
      capAdd = serviceConfiguration.capAdd;
      labels = serviceConfiguration.labels;
      capDrop = serviceConfiguration.capDrop;
      extraHosts = serviceConfiguration.extraHosts;
      restart = serviceConfiguration.restart;

      # Additional information for systemd
      systemdTarget = mkSystemdTargetName compositionName;
      systemdVolumeDependencies = map (
        volumeName: "${mkSystemdVolumeName compositionName volumeName}.service"
      ) serviceVolumes;
      # Create the dependencies to the systemd services for each non-external service
      systemdNetworkDependencies = map (
        networkConfiguration: "${networkConfiguration.systemdService}.service"
      ) (filter (networkConfiguration: !networkConfiguration.external) attachedNetworksConfigurations);
    };
  mkCanonicalNetworkConfiguration = compositionName: networkName: networkConfiguration: {
    name = networkName;
    canonicalName = mkNetworkName compositionName networkName networkConfiguration;
    external = networkConfiguration.external;

    composition = compositionName;

    # Additional information for systemd
    systemdTarget = mkSystemdTargetName compositionName;
    systemdService = mkSystemdNetworkName compositionName networkName;
  };

  mkContainerConfiguration =
    serviceConfiguration:
    nameValuePair serviceConfiguration.containerName {
      image = serviceConfiguration.image;
      imageFile = serviceConfiguration.imageFile;
      environment = serviceConfiguration.environment;
      volumes = serviceConfiguration.volumeMappings;
      cmd = serviceConfiguration.cmd;
      ports = serviceConfiguration.ports;
      dependsOn = serviceConfiguration.dependsOn;
      labels = serviceConfiguration.labels;
      extraOptions =
        let
          networkOption =
            if serviceConfiguration.primaryNetwork != "" then
              [ "--network=${serviceConfiguration.primaryNetwork}" ]
            else
              [ ];
          deviceOptions = map (device: "--device=${device}") serviceConfiguration.devices;
          capAddOptions = map (cap: "--cap-add=${cap}") serviceConfiguration.capAdd;
          capDropOptions = map (cap: "--cap-drop=${cap}") serviceConfiguration.capDrop;
          extraHostsOptions = map (host: "--add-host=${host}") serviceConfiguration.extraHosts;
        in
        networkOption
        ++ deviceOptions
        ++ capAddOptions
        ++ extraHostsOptions
        ++ capDropOptions
        ++ [ "--network-alias=${serviceConfiguration.hostName}" ];
    };

  mkSystemdServicesForContainers =
    serviceConfigurations:
    (map (
      serviceConfiguration: mkSystemdServiceForContainer serviceConfiguration
    ) serviceConfigurations);
  mkSystemdServiceForContainer =
    serviceConfiguration:
    let
      dependencies = flatten [
        serviceConfiguration.systemdVolumeDependencies
        serviceConfiguration.systemdNetworkDependencies
      ];
      networkConnectCmds = strings.concatStringsSep "&&" (
        map (
          networkName:
          "${pkgs.docker}/bin/docker network connect ${networkName} ${serviceConfiguration.containerName}"
        ) (serviceConfiguration.additionalNetworks)
      );
    in
    nameValuePair "docker-${serviceConfiguration.containerName}" {
      path = [
        pkgs.docker
        pkgs.gnugrep
      ];
      serviceConfig = {
        Restart = mkForce (composeRestartToSystemdRestart serviceConfiguration.restart);
        RestartMaxDelaySec = mkOverride 500 "1m";
        RestartSec = mkOverride 500 "100ms";
        RestartSteps = mkOverride 500 9;
      };
      after = dependencies;
      requires = dependencies;
      partOf = [ "${serviceConfiguration.systemdTarget}.target" ];
      wantedBy = [ "${serviceConfiguration.systemdTarget}.target" ];
      postStart =
        if length serviceConfiguration.additionalNetworks > 0 then
          ''
            until [ `${pkgs.docker}/bin/docker container ls --format 'table {{.Names}}' | tail -n +2 | ${pkgs.gnugrep}/bin/grep -w "${serviceConfiguration.containerName}" -c` == 1 ]; do
              sleep 1;
            done;

            ${networkConnectCmds}
          ''
        else
          "";
    };

  mkSystemdServicesForVolumes =
    compositionName: serviceConfiguration:
    (map (
      volumeName:
      nameValuePair (mkSystemdVolumeName compositionName volumeName) (
        mkSystemdServiceForVolume compositionName volumeName
      )
    ) serviceConfiguration.volumes);
  mkSystemdServiceForVolume =
    compositionName: volumeName:
    let
      fullVolumeName = "${compositionName}_${volumeName}";
    in
    {
      path = [ pkgs.docker ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        docker volume inspect ${fullVolumeName} || docker volume create ${fullVolumeName}
      '';
      partOf = [ "${mkSystemdTargetName compositionName}.target" ];
      wantedBy = [ "${mkSystemdTargetName compositionName}.target" ];
    };

  mkSystemdServicesForNetworks =
    networkConfigurations:
    map (
      networkConfiguration:
      (nameValuePair "docker-network-${networkConfiguration.canonicalName}" (
        mkSystemdServiceForNetwork networkConfiguration
      ))
    ) networkConfigurations;
  mkSystemdServiceForNetwork =
    networkConfiguration:
    let
      fullTargetName = "${networkConfiguration.systemdTarget}.target";
    in
    {
      path = [ pkgs.docker ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStop = "${pkgs.docker}/bin/docker network rm -f ${networkConfiguration.canonicalName}";
      };
      script = ''
        docker network inspect ${networkConfiguration.canonicalName} || docker network create ${networkConfiguration.canonicalName}
      '';
      partOf = [ fullTargetName ];
      wantedBy = [ fullTargetName ];
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
      networkConfigurations = flatten (
        mapAttrsToList (
          compositionName: compositionConfiguration:
          (mapAttrsToList (
            networkName: networkConfiguration:
            (mkCanonicalNetworkConfiguration compositionName networkName networkConfiguration)
          ) compositionConfiguration.networks)
        ) cfg.compositions
      );
      serviceConfigurations = flatten (
        mapAttrsToList (
          compositionName: compositionConfiguration:
          (mapAttrsToList (
            serviceName: serviceConfiguration:
            (mkCanonicalServiceConfiguration compositionName compositionConfiguration serviceName
              serviceConfiguration
              networkConfigurations
            )
          ) compositionConfiguration.services)
        ) cfg.compositions
      );
      targets = lists.unique (
        map (serviceConfiguration: serviceConfiguration.systemdTarget) serviceConfigurations
      );
    in
    {
      virtualisation.oci-containers.containers = listToAttrs (
        map (serviceConfiguration: mkContainerConfiguration serviceConfiguration) serviceConfigurations
      );
      systemd.services =
        let
          containers = listToAttrs (mkSystemdServicesForContainers serviceConfigurations);
          volumes = listToAttrs (
            flatten (mapAttrsToList (n: v: mkSystemdServicesForVolumes n v) cfg.compositions)
          );
          networks = listToAttrs (
            mkSystemdServicesForNetworks (
              filter (networkConfiguration: !networkConfiguration.external) networkConfigurations
            )
          );
        in
        mkMerge [
          containers
          volumes
          networks
        ];
      systemd.targets = listToAttrs (
        map (target: nameValuePair target ({ wantedBy = [ "multi-user.target" ]; })) targets
      );
    }
  );
}
