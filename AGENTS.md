# AGENTS.md

Guidance for coding agents working in this repo. Keep changes small and verified.

## What this is

`khepri` is a NixOS module that runs container "compositions" (docker-compose
style) natively via `virtualisation.oci-containers` + systemd. No extra
orchestration layer. It supports two backends: `docker` and `podman`. Heavily
inspired by [compose2nix](https://github.com/aksiksi/compose2nix).

The flake exposes `nixosModules.khepri` (`src/khepri.nix`) and a set of NixOS VM
tests under `checks`.

## Layout

- `src/khepri.nix` — the module: option definitions (`khepri.ociBackend`,
  `khepri.ociPackage`, `khepri.compositions.*`) and the `config` that turns compositions into
  `virtualisation.oci-containers.containers`, `systemd.services`, and
  `systemd.targets`. Entry point for the whole mapping.
- `src/oci-containers.nix` — maps a khepri service to the oci-containers
  interface (image, volumes, networks, `extraOptions`). Backend-specific CLI
  flags are decided here.
- `src/systemd.nix` — builds the systemd units for services, volumes, networks.
- `src/helpers.nix` — name canonicalization (composition-prefixed names) and
  small lookups.
- `tests/*.nix` — one NixOS VM test per scenario, wired into `checks` in
  `flake.nix`. `tests/lib.nix` is the shared `runNixOSTest` wrapper.

## Data flow

`khepri.compositions` → per-composition objects (`mkObject` / `mkServiceObject`
in `khepri.nix`) carrying `name` + `compositionName` and resolved
volume/network objects → `oci-containers.nix` maps each service to a container
config → `systemd.nix` wraps each in a unit. Names are prefixed with the
composition name unless `containerName`/`external` says otherwise
(`helpers.nix`).

## Backend differences

docker and podman are not flag-compatible. When adding a mapped option, check
whether podman spells it differently and thread `ociBackend` through to decide
the flag, rather than assuming the docker name. Example: `startInterval` emits
`--health-start-interval` on docker but `--health-startup-interval` on podman
(see `_mkExtraOptionsForHealthcheck` in `oci-containers.nix`). Some options that
docker records without a command are a no-op on podman; document such limits on
the option's `description`.

## Build and test

- List checks: `nix flake check --no-build` (evaluation only, fast).
- Cheap eval of one test (catches Nix errors without booting a VM):
  `nix eval .#checks.x86_64-linux.<name>.drvPath`
- Run one VM test (boots a QEMU VM, slow, needs KVM):
  `nix build .#checks.x86_64-linux.<name> -L`
- Test names: see `checks` in `flake.nix` (e.g. `test-healthchecks-podman`).
- `git add` a new file before you build. Flakes only expose git-tracked files
  through `self`, so an untracked file fails as `path '.../<file>' does not
  exist` even though it is on disk. Intent-to-add (`git add`) is enough.

A test asserts on the real runtime via `docker inspect` / `podman inspect` in
its `testScript` — match the inspect command to the test's `ociBackend`.

## Conventions

- Nix files are formatted with `nixfmt` (RFC style). Keep new code formatted the
  same way.
- No new flake inputs / dependencies without a reason; the flake tracks only
  nixpkgs.
- Verify runtime-affecting changes by building the relevant VM test, not just by
  eval. A change to a mapped flag isn't done until an `inspect` assertion or a
  green test proves the container gets it.
- Follow conventional-commit-ish messages. Don't commit or push unless asked.
