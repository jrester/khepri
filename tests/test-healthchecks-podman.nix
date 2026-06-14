(import ./lib.nix) {
  name = "test-healthchecks-podman";

  nodes.machine1 =
    {
      self,
      pkgs,
      lib,
      ...
    }:
    let
      nginxImage = pkgs.dockerTools.pullImage {
        imageName = "nginx";
        imageDigest = "sha256:0f04e4f646a3f14bf31d8bc8d885b6c951fdcf42589d06845f64d18aec6a3c4d";
        sha256 = "159z86nw6riirs9ix4zix7qawhfngl5fkx7ypmi6ib0sfayc8pw2";
        finalImageName = "nginx";
        finalImageTag = "latest";
      };

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
        backend = "podman";

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

      units = [
          "khepri-service-test_nginx_full.service",
          "khepri-service-test_nginx_timing.service",
          "khepri-service-test_nginx_disabled.service",
          "khepri-service-test_nginx_none.service",
      ]

      cases = {
          "test_nginx_full": [
              ("{{json .Config.Healthcheck.Test}}", "CMD-SHELL"),
              ("{{json .Config.Healthcheck.Test}}", "curl -f http://localhost"),
              ("{{.Config.Healthcheck.Interval}}", "^30s$"),
              ("{{.Config.Healthcheck.Timeout}}", "^10s$"),
              ("{{.Config.Healthcheck.Retries}}", "^3$"),
              ("{{.Config.Healthcheck.StartPeriod}}", "^5s$"),
              ("{{.Config.Healthcheck.StartInterval}}", "^2s$"),
          ],

          "test_nginx_timing": [
              ("{{.Config.Healthcheck.Interval}}", "^15s$"),
              ("{{.Config.Healthcheck.Timeout}}", "^5s$"),
          ],

          "test_nginx_disabled": [
              ("{{json .Config.Healthcheck.Test}}", "NONE"),
          ],

          "test_nginx_none": [
              ("{{json .Config.Healthcheck}}", "^null$"),
          ],
      }

      def assert_healthcheck(container, checks):
          for fmt, expected in checks:
              machine1.succeed(
                  f"podman inspect --format '{fmt}' {container}"
                  f" | grep -q '{expected}'"
              )

      for unit in units:
          machine1.succeed(f"systemctl is-active --quiet {unit}")

      for container in cases:
          machine1.succeed(f"docker inspect {container}")

      for container, checks in cases.items():
          assert_healthcheck(container, checks)
    '';
}
