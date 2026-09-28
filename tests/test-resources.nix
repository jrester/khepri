backend:
(import ./lib.nix) {
  inherit backend;
  name = "test-resources-${backend}";

  nodes.machine1 =
    { self, pkgs, ... }:
    let
      nginxImage = (import ./images.nix pkgs).nginx;
    in
    {
      imports = [ self.nixosModules.khepri ];

      virtualisation.diskSize = 8192;
      virtualisation.cores = 2;

      khepri = {
        ociBackend = backend;

        compositions.test.services = {
          # Limits given as strings, compose style.
          strings = {
            image = nginxImage;
            cpus = "0.5";
            memory = "256m";
            memoryReservation = "128m";
            pidsLimit = 100;
          };

          # Limits given as numbers.
          numbers = {
            image = nginxImage;
            cpus = 1.5;
            memory = 268435456;
            memoryReservation = 134217728;
          };

          unlimited.image = nginxImage;
        };
      };

      system.stateVersion = "26.05";
    };

  testScript = ''
    start_all()
    machine1.wait_for_unit("multi-user.target")

    assert_composition(machine1, "test", services=["strings", "numbers", "unlimited"])

    def assert_host_config(name, field, expected):
        actual = machine1.succeed(f"{CLI} inspect --format '{{{{.HostConfig.{field}}}}}' {name}").strip()
        assert actual == expected, f"{name} {field}: expected {expected}, got {actual}"

    for name, cpus in [("test_strings", "500000000"), ("test_numbers", "1500000000")]:
        assert_host_config(name, "NanoCpus", cpus)
        assert_host_config(name, "Memory", "268435456")
        assert_host_config(name, "MemoryReservation", "134217728")

    assert_host_config("test_strings", "PidsLimit", "100")
    assert_host_config("test_unlimited", "NanoCpus", "0")
    assert_host_config("test_unlimited", "Memory", "0")
  '';
}
