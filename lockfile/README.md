# lockfile

A build2 package that pins external dependency versions for the entire project's
`bpkg` configurations.

## How it works

When built (`b lockfile/`), `build/lockfile.build` (sourced from `bootstrap.build`)
reads `bdep.lock` from this package's source directory. If the file contains pins and
any pinned package is at a different version than the pin, it enforces the
correct version by:

1. Running `bdep status` with the package names to discover which `bpkg`
   configuration each package lives in.

2. For each configuration with a version mismatch, running:

   ```
   bpkg pkg-build --yes --configure-only --no-move --leave-dependent <name>/<ver> ... -d <cfg>
   ```

   `--configure-only` and `--no-move` restrict the operation to reconfiguring
   the pinned packages in place. `--leave-dependent` prevents bpkg from touching
   dependents of the pinned packages. Those are handled by `bdep sync` in step 3.
   Host-type configurations (build-time tools managed by `bdep`) are skipped.

3. Running `bdep sync` once (if any version was changed) to re-configure the
   project packages that were affected.

When all configured versions already match their pins, no packages are reconfigured.

## Workflow

Refresh the lockfile from the current bpkg configuration state (run from the
workspace root):

```
b config.lockfile.lock=true lockfile/
```
> **NOTE**: If you're blocked by the `unable to downgrade/upgrade package libxxx` error,
first remove `lockfile/bdep.lock` and run again.

Then commit the updated `bdep.lock`. To enforce the pins, run:

```
b lockfile/
```
> **NOTE**: `bdep sync` and `bdep update` do not trigger enforcement automatically.
The enforcement logic runs in `bootstrap.build`, not as a build target, so neither
command triggers it.
Additionally, `bdep sync` uses the configure meta-operation, which `lockfile.build`
skips by design.

Enforcement is skipped if `BDEP_SYNC` isn't either `1` or `true`:

```
BDEP_SYNC=false b
```

This disables all bdep synchronisation for that build, not just lockfile
enforcement.

## bdep.lock format

One `name/version` entry per line. Lines starting with `#` are comments and
are ignored.
