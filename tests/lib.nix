# The first argument to this function is the test module itself
test:
# These arguments are provided by `flake.nix` on import, see checkArgs
{ pkgs, self }:
let
  inherit (pkgs) lib;
in
(pkgs.testers.runNixOSTest {
  # This speeds up the evaluation by skipping evaluating documentation (optional)
  defaults.documentation.enable = lib.mkDefault false;
  # This makes `self` available in the NixOS configuration of our virtual machines.
  # This is useful for referencing modules or packages from your own flake
  # as well as importing from other flakes.
  node.specialArgs = { inherit self; };
  imports = [ test ];
}).config.result
