# Invocation helper for individual tests.
# The first argument to this function is the test module itself
test:
# These arguments are provided by `flake.nix` on import, see checkArgs
{ pkgs, self }:
let
  inherit (pkgs) lib;
in
(pkgs.testers.runNixOSTest {
  defaults.documentation.enable = lib.mkDefault false;
  node.specialArgs = { inherit self; };
  imports = [ test ];
}).config.result
