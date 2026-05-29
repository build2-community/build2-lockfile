# Add Third-Party Dependencies

Packages are available from:
- `https://pkg.cppget.org/1/stable`
- `https://pkg.cppget.org/1/testing`

---

## Chosen dependencies

| Package | Third-party dep | Rationale |
|---------|----------------|-----------|
| libhello | `fmt` | String formatting (interface dep -- exported to consumers) |
| libhello | `xxd` | Build-time tool (host dep -- exercises the host-skip path in lockfile) |
| libworld | `spdlog` | Logging (implementation-only, private); depends on `fmt` transitively |
| libhello-tests | `catch2` | Test framework |
| libhello-tests | `entt` | Header-only ECS library (exercises testing-repo version pinning, case 19) |
| libworld-tests | `catch2` | Test framework |
| lockfile | -- | No change needed |

`fmt` is an interface dependency of `libhello` (`intf_libs`) -- it is exported
to consumers, so `libworld` picks it up transitively through `libhello`. This
creates a transitive chain (`libworld` -> `libhello` -> `fmt`) that exercises
the lockfile machinery more thoroughly. `spdlog` is implementation-only
(`impl_libs`). `catch2` is linked directly into the test executables.
`xxd` is a build-time tool (`depends: * xxd`) and is installed in the host
configuration. The lockfile enforcer must skip host configs, and xxd provides
a real package there to pin incorrectly for that test. `entt` is a header-only
library with no deps and versions that span both stable (3.14.0) and testing
(3.15.0, 3.16.0), making it ideal for case 19 (testing-repo version round-trip).

---

## Available versions (for lockfile pin testing)

All versions listed are from the stable repository unless noted.

### fmt

| Version | Repository |
|---------|-----------|
| 11.1.4 | testing |
| 11.0.2 | testing |
| 10.2.1 | stable |
| 10.1.1 | stable |
| 10.0.0 | stable |
| 9.1.0 | stable |

Use `>= 10.0.0` as the manifest constraint. Lockfile tests can cycle among any
combination of the above; the testing versions are accessible because
`https://pkg.cppget.org/1/testing` is already a prerequisite repository in
`repositories.manifest`.

### spdlog

`spdlog` depends on `fmt`. Pinning `spdlog` to a specific version implicitly
constrains which `fmt` versions are compatible within the same configuration.

| Version | Notes |
|---------|-------|
| 1.14.1+2 | latest stable |
| 1.12.0 | |
| 1.11.0+1 | |

Use `>= 1.11.0` as the manifest constraint. Lockfile tests can cycle among
1.14.1+2, 1.12.0, and 1.11.0+1.

### catch2

| Version | Notes |
|---------|-------|
| 3.7.1 | latest stable |
| 3.5.1+1 | |
| 3.3.2 | |

Use `>= 3.3.0` as the manifest constraint. Lockfile tests can cycle among
3.7.1, 3.5.1+1, and 3.3.2.

### xxd

Build-time tool. Only one version is available in the stable repo: `8.2.3075+2`.
For case 11 (host-config skip), pin xxd at any other version string (e.g.
`xxd/1.0.0`) in `bdep.lock`. Enforcement must fire the diagnostic but not
call `bpkg pkg-build` on the host config.

### entt

Header-only ECS library, no deps, no version constraints from other packages.

| Version | Repository |
|---------|-----------|
| 3.15.0 | testing |
| 3.16.0 | testing |
| 3.14.0 | stable |
| 3.13.2 | stable |
| 3.13.0 | stable |

Use `>= 3.14.0` as the manifest constraint. Lockfile tests for case 19 cycle
between a stable version (3.14.0) and a testing version (3.15.0 or 3.16.0).

---

## Changes per file

### libhello

**`libhello/manifest`** -- add after the existing `depends:` lines:
```
depends: * xxd >= 8.0.0
depends: fmt >= 10.0.0
```

**`libhello/libhello/buildfile`** -- add fmt import and xxd as a build-time
prerequisite:
```
# before
intf_libs = # Interface dependencies.
impl_libs = # Implementation dependencies.

# after
intf_libs = # Interface dependencies.
impl_libs = # Implementation dependencies.
import intf_libs += fmt%lib{fmt}

import! xxd = xxd%exe{xxd}

lib{hello}: {hxx ixx txx cxx}{** -version} hxx{version} $impl_libs $intf_libs $xxd
```

---

### libworld

**`libworld/manifest`** -- add after the existing `depends:` lines:
```
depends: spdlog >= 1.11.0
```

**`libworld/libworld/buildfile`** -- replace the empty `impl_libs` line:
```
# before
impl_libs = # Implementation dependencies.

# after
impl_libs =
import impl_libs += spdlog%lib{spdlog}
```

---

### libhello-tests

**`libhello-tests/manifest`** -- add after the existing `depends:` lines:
```
depends: catch2 >= 3.3.0
depends: entt >= 3.14.0
```

**`libhello-tests/tests/buildfile`** -- add imports alongside the existing one:
```
# before
libs =
import libs += libhello%lib{hello}

# after
libs =
import libs += libhello%lib{hello}
import libs += catch2%lib{catch2}
import libs += entt%lib{entt}
```

---

### libworld-tests

**`libworld-tests/manifest`** -- add after the existing `depends:` lines:
```
depends: catch2 >= 3.3.0
```

**`libworld-tests/tests/buildfile`** -- add import alongside the existing one:
```
# before
libs =
import libs += libworld%lib{world}

# after
libs =
import libs += libworld%lib{world}
import libs += catch2%lib{catch2}
```

---

## Notes

- The exact `bpkg` target names (`fmt%lib{fmt}`, `spdlog%lib{spdlog}`,
  `catch2%lib{catch2}`) should be verified with `bpkg rep-info` or by
  inspecting the packages' own buildfiles after fetching.
- Because `spdlog` depends on `fmt`, both will land in the same external
  configuration. This means a single `bdep.lock` entry for `fmt` pins the
  version used by both `libhello` (directly) and `spdlog` (as its own dep),
  which is a good stress-test for the lockfile's multi-package batching logic.
- The commented-out `depends: libhello ^1.0.0` in `libworld-tests/manifest` is
  a pre-existing issue (wrong package name, wrong version constraint) and is
  left for a separate fix.
