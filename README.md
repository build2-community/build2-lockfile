# hello

Development workspace for the `lockfile` build2 package. `libhello` and
`libworld` are example C++ libraries that depend on `fmt`, `spdlog`, and
`entt`, providing a realistic multi-package project for exercising `lockfile`
enforcement.

See [`lockfile/README.md`](lockfile/README.md) for documentation on the
`lockfile` package and how to integrate it into your own project.

## Test suite

`test-lockfile.sh` exercises `lockfile` enforcement end-to-end. On each run
it creates a fresh three-config bpkg topology: a host config for build-time
tools, a main config where the local packages are built, and an external config
that holds third-party packages fetched from cppget.org. The main config
resolves external dependencies through a cfg-link to the external config.

The suite covers no-op behaviour when pins already match, version enforcement
for single and multiple packages, transitive dependencies across linked configs,
host-config skipping, the `BDEP_SYNC=false` bypass, CRLF-safe parsing, and
lockfile generation.

```sh
bash test-lockfile.sh [--compiler=<path>] [--quiet] [--case=N] [--list]
```

`--compiler` accepts a compiler path such as `g++` or `/usr/bin/clang++`. If
omitted, the script auto-detects the first of `g++`, `clang++`, or `cl.exe`
found in `PATH`.
