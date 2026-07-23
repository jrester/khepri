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
    CLI = "${backend}"

    def inspect(machine, name):
        return machine.succeed(f"{CLI} inspect {name}")

    def network_inspect(machine, name):
        return machine.succeed(f"{CLI} network inspect {name}")

    def volume_inspect(machine, name):
        return machine.succeed(f"{CLI} volume inspect {name}")

    def assert_healthcheck(machine, name, checks):
        for fmt, expected in checks:
            machine.succeed(f"{CLI} inspect --format '{fmt}' {name} | grep -q '{expected}'")
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
