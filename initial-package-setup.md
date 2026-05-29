# Initial Package Setup

## Project layout

The project is a standard multi-package `bdep` workspace. `packages.manifest`
lists the packages in the order they are registered:

```
lockfile/
libhello/
libworld/
libhello-tests/
libworld-tests/
```

The root `buildfile` reads that manifest at build time and pulls all packages
in as build targets.

---

## Packages and their dependencies

### lockfile

- Type: `other` (no compiled output)
- Project: `qme`
- Purpose: enforce pinned external dependency versions on every build via
  `bdep.lock`. See `lockfile/README.md` for the full workflow.
- Depends on: `build2 >= 0.18.0`, `bpkg >= 0.18.0`
- No dependencies on other packages in this workspace.

### libhello

- Type: C++ library
- Project: `hello`
- Purpose: core hello library.
- Depends on: `build2 >= 0.18.0`, `bpkg >= 0.18.0`
- No dependencies on other packages in this workspace.
- Test package: `libhello-tests == $` (same version).

### libworld

- Type: C++ library
- Project: `hello`
- Purpose: world library, built on top of libhello.
- Depends on: `build2 >= 0.18.0`, `bpkg >= 0.18.0`, `libhello == $`
- Test package: `libworld-tests == $` (same version).

### libhello-tests

- Type: executable
- Project: `hello`
- Purpose: test driver for libhello.
- Depends on: `build2 >= 0.18.0`, `bpkg >= 0.18.0`
- Note: the explicit `depends: libhello ^1.0.0` line is currently commented
  out, so bpkg does not enforce the version constraint.

### libworld-tests

- Type: executable
- Project: `hello`
- Purpose: test driver for libworld.
- Depends on: `build2 >= 0.18.0`, `bpkg >= 0.18.0`
- Note: the explicit `depends:` line is commented out and reads `libhello`
  instead of `libworld`, which looks like a copy-paste artifact from the
  scaffold.

---

## Dependency graph

```
libhello  <--(== $)--  libworld
    |                      |
  tests: ==             tests: ==
    |                      |
    v                      v
libhello-tests        libworld-tests

lockfile  (standalone)
```

---

## Build configurations

Three linked `bpkg` configurations are used (see `config-setup.md` for the
exact setup commands):

| Name | Type | Purpose |
|------|------|---------|
| `@host` | host | Build-time tools compiled for the build machine. Skipped by the lockfile enforcer. |
| `@<cfg>` | target | Main configuration where project packages are initialized. |
| `@<cfg>-external` | target | Third-party/external dependencies. Linked to `@<cfg>` so it can resolve them. |

The main configuration is linked to the external one via `bpkg cfg-link`, so
dependency resolution flows: main -> external.

---

## Version pinning

`lockfile/bdep.lock` records the exact versions of external packages in the
external configuration. On every `b` invocation, `lockfile/build/lockfile.build`
(sourced at bootstrap) checks all pinned packages and, if any version drifts,
runs `bpkg pkg-build` on the affected configuration and then `bdep sync`.

To regenerate the lockfile from the current configuration state:

```
b config.lockfile.gen=true lockfile/
```

To bypass enforcement for a single build:

```
BDEP_SYNC=false b
```
