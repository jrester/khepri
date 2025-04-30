# This file contains mappers from khepri to the oci-containers interface.
{ helpers, lib, ... }:
with lib;
rec {
  _mkExtraOptionsFor = option: values: map (value: "--${option}=${value}") values;
  _mkCanonicalVolumeMapping =
    volumeMapping: volumeObjects:
    let
      volumeMappingParts = builtins.split ":" volumeMapping;
      volumeNameOrLocalPath = head volumeMappingParts;
      volumeObject = helpers.findObjectByNameInObjects volumeNameOrLocalPath volumeObjects;
      canonicalVolumeNameOrLocalPath =
        if volumeObject != null then helpers.mkVolumeName volumeObject else volumeNameOrLocalPath;
    in
    strings.concatStringsSep ":" (
      [
        canonicalVolumeNameOrLocalPath
      ]
      ++ (flatten (tail volumeMappingParts))
    );

  mkContainerConfigurationForService =
    serviceObject:
    let
      hostName =
        if serviceObject.containerName != null then serviceObject.containerName else serviceObject.name;
      isPlainImageName = builtins.isString serviceObject.image;
    in
    nameValuePair (helpers.mkServiceName serviceObject) {
      # Some options can be mapped one-to-one.
      inherit (serviceObject)
        environment
        environmentFiles
        cmd
        ports
        entrypoint
        labels
        ;

      # Distinguish images based on whether they are provided only with their name (e.g. traefik)
      # or if they are provided as a package (e.g. with dockerTools.pullImage).
      image =
        if isPlainImageName then
          serviceObject.image
        else
          helpers.getImageNameFromDerivation serviceObject.image;
      imageFile = if isPlainImageName then null else serviceObject.image;

      # Upstream dependsOn is broken, since it does not respect the different service names.
      dependsOn = [ ];

      volumes = map (
        volumeMapping: _mkCanonicalVolumeMapping volumeMapping serviceObject.volumeObjects
      ) serviceObject.volumes;

      # For the network mapping, we need to make sure that the canonical network names are used.
      networks = map (
        networkName:
        helpers.mkNetworkName (helpers.findObjectByNameInObjects networkName serviceObject.networkObjects)
      ) serviceObject.networks;

      extraOptions =
        (_mkExtraOptionsFor "device" serviceObject.devices)
        ++ (_mkExtraOptionsFor "cap-add" serviceObject.capAdd)
        ++ (_mkExtraOptionsFor "cap-drop" serviceObject.capDrop)
        ++ (_mkExtraOptionsFor "add-host" serviceObject.extraHosts)
        ++ [
          "--network-alias=${hostName}"
        ];

      serviceName = helpers.mkSystemdServiceName serviceObject;
    };

}
