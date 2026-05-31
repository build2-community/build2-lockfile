# lockfile

A build2 package that pins external dependency versions for the entire project's
`bpkg` configurations.

## How it works

On every build, `build/lockfile.build` (sourced from `bootstrap.build`) reads
`bdep.lock` from this package's source directory. If the file contains pins and
any pinned package is at a different version than the pin, it enforces the
correct version by:

1. Running `bdep status` with the package names to discover which `bpkg`
   configuration each package lives in.

2. For each configuration with a version mismatch, running:

   ```
   bpkg pkg-build --yes <name>/<ver> ... -d <cfg>
   ```

   This keeps all packages in the configuration they already belong to. `bpkg`
   handles the full dependency graph within that configuration, including any
   same-configuration dependents that need to be reconfigured against the new
   versions. Host-type configurations (build-time tools managed by `bdep`) are
   skipped.

3. Running `bdep sync` once (if any version was changed) to re-configure the
   project packages that were affected.

When all configured versions already match their pins, no packages are rebuilt
(bdep status is still queried to check).

## Workflow

Refresh the lockfile from the current bpkg configuration state (run from the
workspace root, where `b` is the build2 build driver):

```
b config.lockfile.lock=true lockfile/
```

Then commit the updated `bdep.lock`. On every subsequent build, the pinned
versions are enforced automatically.

To skip enforcement for one build:

```
BDEP_SYNC=false b
```

Note: this disables all bdep synchronisation for that build, not just lockfile
enforcement.

## bdep.lock format

One `name/version` entry per line. Lines starting with `#` are comments and
are ignored.
