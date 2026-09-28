# Invocation helper for individual tests.
# The first argument is the test module itself. When `backend` is set, a small
# backend-aware python prelude is injected into the testScript so tests express
# container operations once instead of hardcoding `docker`/`podman`.
test@{
  backend ? null,
  testScript,
  ...
}:
# These arguments are provided by `flake.nix` on import, see checkArgs
{ pkgs, self }:
let
  inherit (pkgs) lib;

  # Backend-aware helpers, available to every testScript. `machine` is the test
  # driver node object; `name` a container/network/volume name.
  prelude = lib.optionalString (backend != null) ''
    import re

    CLI = "${backend}"

    def assert_container_exists(machine, name):
        return machine.succeed(f"{CLI} inspect {name}")

    def assert_network_exists(machine, name):
        return machine.succeed(f"{CLI} network inspect {name}")

    def assert_volume_exists(machine, name):
        return machine.succeed(f"{CLI} volume inspect {name}")

    def assert_inspect(machine, name, checks):
        # Each check is a (format, regex) pair; anchor the regex for an exact match.
        for fmt, pattern in checks:
            actual = machine.succeed(f"{CLI} inspect --format '{fmt}' {name}").strip()
            assert re.search(pattern, actual), f"{name} {fmt}: expected /{pattern}/, got {actual}"

    def assert_active(machine, unit):
        machine.succeed(f"systemctl is-active --quiet {unit}")

    def assert_composition(machine, comp, services=[], networks=[], volumes=[]):
        # Assert each resource's khepri unit is active and the backend resource
        # exists. Names follow `{comp}_{name}` and `khepri-{kind}-{comp}_{name}`.
        # A service entry may instead be a ("name", "containerName") tuple, for a
        # service that overrides containerName and so escapes the `{comp}_` prefix.
        for name in networks:
            assert_active(machine, f"khepri-network-{comp}_{name}.service")
            assert_network_exists(machine, f"{comp}_{name}")
        for name in volumes:
            assert_active(machine, f"khepri-volume-{comp}_{name}.service")
            assert_volume_exists(machine, f"{comp}_{name}")
        for entry in services:
            resource = entry[1] if isinstance(entry, tuple) else f"{comp}_{entry}"
            assert_active(machine, f"khepri-service-{resource}.service")
            assert_container_exists(machine, resource)
  '';

  # The test driver autocalls a function-valued testScript, passing only the
  # arguments it declares. Declare `nodes` so the driver supplies it, and forward
  # the whole set on to the wrapped script.
  withPrelude =
    if lib.isFunction testScript then
      { nodes, ... }@args: prelude + "\n" + testScript args
    else
      prelude + "\n" + testScript;

  module = builtins.removeAttrs test [ "backend" ] // {
    testScript = withPrelude;
  };
in
(pkgs.testers.runNixOSTest {
  defaults.documentation.enable = lib.mkDefault false;
  node.specialArgs = { inherit self; };
  imports = [ module ];
}).config.result
