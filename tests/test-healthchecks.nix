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

          # No healthcheck configuration. Also covers dependsOn's short (list) syntax.
          nginx_none = mkNginxService null // {
            dependsOn = [ "nginx_disabled" ];
          };

          # Healthy only once the test script creates /tmp/ready. The long start
          # period keeps it `starting` instead of `unhealthy` until then.
          # The CMD arguments only work if each is passed through as one shell word.
          gate = mkNginxService {
            test = [
              "CMD"
              "sh"
              "-c"
              "test -f /tmp/ready"
            ];
            interval = "1s";
            startPeriod = "10m";
          };
          gated = mkNginxService null // {
            dependsOn.gate.condition = "service_healthy";
          };

          # Unhealthy after the first probe.
          sick = mkNginxService {
            test = [
              "CMD"
              "false"
            ];
            interval = "1s";
            retries = 1;
          };
          sick_dependent = mkNginxService null // {
            restart = "no";
            dependsOn.sick.condition = "service_healthy";
          };

          # service_healthy on a dependency without a healthcheck fails instead of waiting.
          unchecked_dependent = mkNginxService null // {
            restart = "no";
            dependsOn.nginx_disabled.condition = "service_healthy";
          };

          # Exits right away, so it never turns healthy.
          crashing =
            mkNginxService {
              test = [
                "CMD-SHELL"
                "true"
              ];
              interval = "1s";
            }
            // {
              cmd = [ "false" ];
              restart = "no";
            };
          crashing_dependent = mkNginxService null // {
            restart = "no";
            dependsOn.crashing.condition = "service_healthy";
          };

          # Runs until the test script creates /tmp/done, then exits with 0.
          job = mkNginxService null // {
            cmd = [
              "sh"
              "-c"
              "until test -f /tmp/done; do sleep 1; done"
            ];
            restart = "no";
          };
          job_dependent = mkNginxService null // {
            dependsOn.job.condition = "service_completed_successfully";
          };

          # Exits non-zero. The sleep keeps the exit after the unit's start job, so the dependent
          # fails in its wait instead of being cancelled by systemd.
          failing_job = mkNginxService null // {
            cmd = [
              "sh"
              "-c"
              "sleep 3; exit 1"
            ];
            restart = "no";
          };
          failing_job_dependent = mkNginxService null // {
            restart = "no";
            dependsOn.failing_job.condition = "service_completed_successfully";
          };
        };
      };

      system.stateVersion = "26.05";
    };

  testScript =
    { ... }:
    ''
      start_all()

      def unit_log_contains(unit, text):
          machine1.succeed(f"journalctl -u {unit} | grep -qF '{text}'")

      # dependsOn becomes Requires= for both the short and the long syntax.
      for unit, dependency in [("test_gated", "test_gate"), ("test_nginx_none", "test_nginx_disabled")]:
          machine1.succeed(
              f"systemctl show -P Requires khepri-service-{unit}.service"
              f" | grep -qw khepri-service-{dependency}.service"
          )

      # service_healthy: the dependent stays in ExecStartPre while its dependency is starting ...
      gated_state = "systemctl show -P SubState khepri-service-test_gated.service | grep -qx start-pre"
      machine1.wait_for_unit("khepri-service-test_gate.service")
      machine1.wait_until_succeeds(gated_state)
      machine1.sleep(5)
      machine1.succeed(gated_state)
      machine1.fail(f"{CLI} inspect test_gated")
      # ... starts once it turns healthy ...
      machine1.succeed(f"{CLI} exec test_gate touch /tmp/ready")
      machine1.wait_for_unit("khepri-service-test_gated.service")
      # ... and fails once it turns unhealthy.
      machine1.wait_until_succeeds("systemctl is-failed --quiet khepri-service-test_sick_dependent.service")
      machine1.fail(f"{CLI} inspect test_sick_dependent")
      unit_log_contains("khepri-service-test_sick_dependent", "test_sick is unhealthy")

      # A dependency without a healthcheck fails the dependent.
      machine1.wait_until_succeeds("systemctl is-failed --quiet khepri-service-test_unchecked_dependent.service")
      machine1.fail(f"{CLI} inspect test_unchecked_dependent")
      unit_log_contains("khepri-service-test_unchecked_dependent", "test_nginx_disabled has no healthcheck")

      # A dependency that stops running never turns healthy. Depending on timing the dependent's
      # start either fails in ExecStartPre or is cancelled by systemd, but it must not keep waiting.
      machine1.wait_until_succeeds(
          "! systemctl is-active --quiet khepri-service-test_crashing_dependent.service"
          " && ! systemctl list-jobs --no-legend | grep -q khepri-service-test_crashing_dependent.service",
          timeout=120,
      )
      machine1.fail(f"{CLI} inspect test_crashing_dependent")

      def unit_property(unit, prop):
          return machine1.succeed(f"systemctl show -P {prop} khepri-service-{unit}.service").strip()

      # service_completed_successfully: the dependent stays in ExecStartPre while its dependency runs ...
      job_dependent_state = "systemctl show -P SubState khepri-service-test_job_dependent.service | grep -qx start-pre"
      machine1.wait_for_unit("khepri-service-test_job.service")
      machine1.wait_until_succeeds(job_dependent_state, timeout=120)
      machine1.sleep(5)
      machine1.succeed(job_dependent_state)
      machine1.fail(f"{CLI} inspect test_job_dependent")
      # ... starts once it exited with 0 ...
      machine1.succeed(f"{CLI} exec test_job touch /tmp/done")
      machine1.wait_for_unit("khepri-service-test_job_dependent.service")
      # ... the dependency stays active (exited), so restarting the dependent does not run it again ...
      assert unit_property("test_job", "SubState") == "exited"
      job_invocation = unit_property("test_job", "InvocationID")
      machine1.succeed("systemctl restart khepri-service-test_job_dependent.service")
      machine1.wait_for_unit("khepri-service-test_job_dependent.service")
      assert unit_property("test_job", "InvocationID") == job_invocation
      # ... and a non-zero exit fails the dependent.
      machine1.wait_until_succeeds(
          "systemctl is-failed --quiet khepri-service-test_failing_job_dependent.service", timeout=120
      )
      machine1.fail(f"{CLI} inspect test_failing_job_dependent")
      unit_log_contains("khepri-service-test_failing_job_dependent", "test_failing_job did not complete successfully")

      machine1.wait_for_unit("multi-user.target")

      cases = {
          "test_nginx_full": [
              ("{{json .Config.Healthcheck.Test}}", '"CMD-SHELL","curl -f http://localhost'),
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
