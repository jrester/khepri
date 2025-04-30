{ lib, ... }:
with lib;
rec {
  # Similar to the default behaviour of docker-compose, the names of containers, volumes and networks
  # are automatically prefixed with the composition name, unless specified otherwise.
  mkServiceName =
    serviceObject:
    if serviceObject.containerName != null then
      serviceObject.containerName
    else
      "${serviceObject.compositionName}_${serviceObject.name}";
  mkNetworkName =
    networkObject:
    if networkObject.external then
      networkObject.name
    else
      "${networkObject.compositionName}_${networkObject.name}";
  mkVolumeName =
    volumeObject:
    if volumeObject.external then
      volumeObject.name
    else
      "${volumeObject.compositionName}_${volumeObject.name}";

  mkSystemdVolumeName = volumeObject: "khepri-volume-${mkVolumeName volumeObject}";
  mkSystemdNetworkName = networkObject: "khepri-network-${mkNetworkName networkObject}";
  mkSystemdServiceName = serviceObject: "khepri-service-${mkServiceName serviceObject}";
  mkSystemdCompositionTargetName = compositionName: "khepri-compose-${compositionName}-root";

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

  findObjectsOfComposition =
    compositionName: objects: filter (object: object.compositionName == compositionName) objects;
  findObjectByNameInObjects =
    name: objects:
    let
      results = filter (object: object.name == name) objects;
    in
    if results == [ ] then null else head results;

  getOnlyVolumeMounts =
    volumes: volumeObjects:
    filter (volumeName: (findObjectByNameInObjects volumeName volumeObjects) != null) (
      map (volumeMapping: head (builtins.split ":" volumeMapping)) volumes
    );
}
