# Add Third-Party Dependencies

Packages are available from:
- `https://pkg.cppget.org/1/stable`
- `https://pkg.cppget.org/1/testing`

---

## Chosen dependencies

| Package | Third-party dep | Rationale |
|---------|----------------|-----------|
| libhello | `fmt` | String formatting (implementation-only, private) |
| libworld | `spdlog` | Logging (implementation-only, private); depends on `fmt` transitively |
| libhello-tests | `catch2` | Test framework |
| libworld-tests | `catch2` | Test framework |
| lockfile | -- | No change needed |

`fmt` and `spdlog` are interface-independent implementation details, so both
go into `impl_libs`. `catch2` is linked directly into the test executables.

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

---

## Changes per file

### libhello

**`libhello/manifest`** -- add after the existing `depends:` lines:
```
depends: fmt >= 10.0.0
```

**`libhello/libhello/buildfile`** -- replace the empty `impl_libs` line:
```
# before
impl_libs = # Implementation dependencies.

# after
impl_libs =
import impl_libs += fmt%lib{fmt}
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
```

**`libhello-tests/tests/buildfile`** -- add import alongside the existing one:
```
# before
libs =
import libs += libhello%lib{hello}

# after
libs =
import libs += libhello%lib{hello}
import libs += catch2%lib{catch2}
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
