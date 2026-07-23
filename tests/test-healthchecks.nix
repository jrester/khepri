backend:
let
  # podman maps startInterval to --health-startup-interval (docker's
  # --health-start-interval does not exist on podman), so it is not reflected in
  # Config.Healthcheck.StartInterval. The is-active check still asserts the flag
  # does not break startup.
  fullStartInterval =
    if backend == "docker" then ''("{{.Config.Healthcheck.StartInterval}}", "^2s$"),'' else "";

  # Unlike docker, podman does not persist timing overrides when no health
  # command is given and the image defines no probe, so Config.Healthcheck stays
  # null. The is-active check still asserts the timing-only config works.
  timingChecks =
    if backend == "docker" then
      ''
        ("{{.Config.Healthcheck.Interval}}", "^15s$"),
                ("{{.Config.Healthcheck.Timeout}}", "^5s$"),''
    else
      ''("{{json .Config.Healthcheck}}", "^null$"),'';
in
(import ./lib.nix) {
  inherit backend;
  name = "test-healthchecks-${backend}";

  nodes.machine1 =
    {
      self,
      pkgs,
      lib,
      ...
    }:
    let
      nginxImage = (import ./images.nix pkgs).nginx;

      mkNginxService =
        healthcheck:
        {
          image = nginxImage;
          restart = "unless-stopped";
        }
        // lib.optionalAttrs (healthcheck != null) {
          inherit healthcheck;
        };
    in
    {
      imports = [ self.nixosModules.khepri ];

      virtualisation.diskSize = 8192;

      khepri = {
        ociBackend = backend;

        compositions.test.services = {
          # Fully-specified healthcheck.
          nginx_full = mkNginxService {
            test = [
              "CMD-SHELL"
              "curl -f http://localhost || exit 1"
            ];
            interval = "30s";
            timeout = "10s";
            retries = 3;
            startPeriod = "5s";
            startInterval = "2s";
          };

          # Override timings while preserving the image-defined probe.
          # Since nginx has no built-in healthcheck this is mostly done to validate
          # that the healthcheck mapping works even without a defined test command.
          nginx_timing = mkNginxService {
            interval = "15s";
            timeout = "5s";
          };

          # Disable healthchecks entirely.
          nginx_disabled = mkNginxService {
            test = [ "NONE" ];
          };

          # No healthcheck configuration.
          nginx_none = mkNginxService null;
        };
      };

      system.stateVersion = "26.05";
    };

  testScript =
    { ... }:
    ''
      start_all()
      machine1.wait_for_unit("multi-user.target")

      cases = {
          "test_nginx_full": [
              ("{{json .Config.Healthcheck.Test}}", "CMD-SHELL"),
              ("{{json .Config.Healthcheck.Test}}", "curl -f http://localhost"),
              ("{{.Config.Healthcheck.Interval}}", "^30s$"),
              ("{{.Config.Healthcheck.Timeout}}", "^10s$"),
              ("{{.Config.Healthcheck.Retries}}", "^3$"),
              ("{{.Config.Healthcheck.StartPeriod}}", "^5s$"),
              ${fullStartInterval}
          ],

          "test_nginx_timing": [
              ${timingChecks}
          ],

          "test_nginx_disabled": [
              ("{{json .Config.Healthcheck.Test}}", "NONE"),
          ],

          "test_nginx_none": [
              ("{{json .Config.Healthcheck}}", "^null$"),
          ],
      }

      assert_composition(
          machine1,
          "test",
          services=["nginx_full", "nginx_timing", "nginx_disabled", "nginx_none"],
      )

      for container, checks in cases.items():
          assert_healthcheck(machine1, container, checks)
    '';
}
