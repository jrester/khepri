# This file contains mappers from khepri to the oci-containers interface.
{ helpers, lib, ... }:
with lib;
rec {
  _formatExtraOption = option: value: "--${option}=${value}";

  # Options which are optional (can be null) according to the config definition of khepri.
  _mkExtraOptionsForOptionalOption =
    option: value:
    if value != null then
      [
        (_formatExtraOption option (toString value))
      ]
    else
      [ ];

  # Repeatable options are those options which can be specified multiple times to define a list.
  # E.g., for capabilities to add/remove for a container.
  _mkExtraOptionsForRepeatableOptions =
    option: values: map (value: _formatExtraOption option value) values;

  _mkExtraOptionsForHealthcheck =
    healthcheckOptions:
    [ ]
    ++ (
      # The healthcheck can be empty but other options might still be defined.
      # E.g., to adjust the interval of a healthcheck defined by a service.
      if healthcheckOptions.test != null && builtins.length healthcheckOptions.test > 0 then
        # Healthchecks 'test' may start with different identifiers 'CMD', 'CMD-SHELL' or 'NONE'.
        # When 'NONE' is configured, this means that an existing healthcheck of the container should be disabled.
        # The other two options should be handled directly by the underlying container options.
        if (head healthcheckOptions.test) != "NONE" then
          [
            (_formatExtraOption "health-cmd" (lib.concatStringsSep " " healthcheckOptions.test))
          ]
        else
          [ "--no-healthcheck" ]
      else
        [ ]
    )
    ++ (_mkExtraOptionsForOptionalOption "health-interval" healthcheckOptions.interval)
    ++ (_mkExtraOptionsForOptionalOption "health-timeout" healthcheckOptions.timeout)
    ++ (_mkExtraOptionsForOptionalOption "health-retries" healthcheckOptions.retries)
    ++ (_mkExtraOptionsForOptionalOption "health-start-period" healthcheckOptions.startPeriod)
    ++ (_mkExtraOptionsForOptionalOption "health-start-interval" healthcheckOptions.startInterval);

  _mkCanonicalVolumeMapping =
    volumeMapping: volumeObjects:
    let
      volumeMappingParts = builtins.split ":" volumeMapping;
      volumeNameOrLocalPath = head volumeMappingParts;
      volumeObject = helpers.findObjectByNameInObjects volumeNameOrLocalPath volumeObjects;
      isVolume = volumeObject != null;
    in
    if isVolume then
      strings.concatStringsSep ":" (
        [
          (helpers.mkVolumeName volumeObject)
        ]
        ++ (flatten (tail volumeMappingParts))
      )
    else
      volumeMapping;

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

      environment = attrsets.mapAttrs (name: value: builtins.toString value) serviceObject.environment;

      volumes = map (
        volumeMapping: _mkCanonicalVolumeMapping volumeMapping serviceObject.volumeObjects
      ) serviceObject.volumes;

      # For the network mapping, we need to make sure that the canonical network names are used.
      networks = map (
        networkName:
        helpers.mkNetworkName (helpers.findObjectByNameInObjects networkName serviceObject.networkObjects)
      ) serviceObject.networks;

      extraOptions =
        (_mkExtraOptionsForRepeatableOptions "device" serviceObject.devices)
        ++ (_mkExtraOptionsForRepeatableOptions "cap-add" serviceObject.capAdd)
        ++ (_mkExtraOptionsForRepeatableOptions "cap-drop" serviceObject.capDrop)
        ++ (_mkExtraOptionsForRepeatableOptions "add-host" serviceObject.extraHosts)
        ++ (
          # Hostname might only be set if at least one user-defined network is specified for the container.
          if builtins.length serviceObject.networks > 0 then
            [
              "--network-alias=${hostName}"
            ]
          else
            [ ]
        )
        ++ (
          if serviceObject.healthcheck != null then
            _mkExtraOptionsForHealthcheck serviceObject.healthcheck
          else
            [ ]
        );

      serviceName = helpers.mkSystemdServiceName serviceObject;
    };

}
