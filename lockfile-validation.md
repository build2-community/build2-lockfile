# Lockfile Validation Plan

## Context

`lockfile` is a build2 package that enforces pinned external dependency
versions on every build. `build/lockfile.build` (sourced at bootstrap time)
reads `bdep.lock`, discovers which bpkg configuration each pinned package
lives in via `bdep status`, and for each non-host configuration with a version
mismatch runs `bpkg pkg-build --yes --no-move ?name/ver ... -d <cfg>`, then
calls `bdep sync` once if anything changed.

The three-config setup from `config-setup.md` (host, main, external) is the
intended stress-test harness: packages are spread across linked configurations
of different types, which exercises the per-configuration dispatch logic, the
host-skip path, and the `bdep sync` re-configuration step.

---

## Prerequisites

1. Three-config setup in place per `config-setup.md`:
   - `@host`           -- host-type, contains build-time tools
   - `@<cfg>`          -- main config, project packages
   - `@<cfg>-external` -- external/third-party dependencies

2. At least two real external packages available from a remote bpkg repository
   (e.g. `libfoo` and `libbar` with multiple versions available) and fetched
   into `@<cfg>-external`.

3. `lockfile` package initialized in the main config and `bdep.lock` present in
   `lockfile/`.

4. Baseline `bpkg pkg-status -d <ext-cfg>` output captured for reference.

---

## Test Cases

### 1. No-op: lockfile file absent

- Remove `lockfile/bdep.lock`.
- Run `b`.
- Expect: no `bpkg pkg-build` or `bdep sync` invocations in output,
  build completes normally.

### 2. No-op: empty lockfile

- Write an empty `lockfile/bdep.lock` (zero bytes or whitespace only).
- Run `b`.
- Expect: same as case 1 -- `allpins` is null, enforcement body never entered.

### 3. No-op: lockfile contains only comments and blank lines

- Write `lockfile/bdep.lock` with lines like `# pinned deps` and blank lines.
- Run `b`.
- Expect: `allpins` is null (regex matches nothing), no enforcement.

### 4. No-op: all pinned versions already match

- Generate the lockfile from current state:
  `b config.lockfile.gen=true lockfile/`
- Immediately run `b` again.
- Expect: no diagnostic of the form `bdep.lock: pinning ...`, no
  `bpkg pkg-build`, no `bdep sync`. The loop iterates but `pending_pins`
  is null for every config.

### 5. Single package version mismatch (single config)

- Install `libfoo` at version X in `@<cfg>-external`.
- Write `lockfile/bdep.lock`: `libfoo/Y` (Y is a different available version).
- Run `b`.
- Expect:
  - Diagnostic: `bdep.lock: pinning libfoo to Y in <ext-cfg-path> (was X)`
  - `bpkg pkg-build --yes --no-move ?libfoo/Y -d <ext-cfg>` executed.
  - `bdep sync --yes` executed once.
- Verify: `bpkg pkg-status libfoo -d <ext-cfg>` reports version Y.

### 6. Multiple packages in same configuration, both mismatched

- Install `libfoo` at vF1, `libbar` at vB1 in `@<cfg>-external`.
- Write `lockfile/bdep.lock`:
  ```
  libfoo/vF2
  libbar/vB2
  ```
- Run `b`.
- Expect:
  - Two diagnostics (one per package).
  - A single `bpkg pkg-build --yes --no-move ?libfoo/vF2 ?libbar/vB2 -d <ext-cfg>`
    call (both pins batched into one invocation for the same config).
  - `bdep sync --yes` called once.
- Verify both are at pinned versions.

### 7. Packages spread across two non-host configurations

- Have `libfoo` in `@<cfg>-external` at wrong version and `libbaz` in `@<cfg>`
  (main config) at wrong version.
- Write both pins in `bdep.lock`.
- Run `b`.
- Expect:
  - Two separate `bpkg pkg-build` calls, one per configuration.
  - `bdep sync --yes` called exactly once at the end (not twice).
- Verify each package corrected in its own config.

### 8. Mixed: some pinned versions already match, some do not

- `libfoo` is already at its pinned version, `libbar` is not.
- Run `b`.
- Expect:
  - Only `libbar` appears in the diagnostic and in `bpkg pkg-build` args.
  - `libfoo` is not mentioned in any `bpkg pkg-build` invocation.

### 9. Host configuration is skipped

- Place a host build tool in `@host` at version H1.
- Pin it at H2 in `bdep.lock`.
- Run `b`.
- Expect: no `bpkg pkg-build` call targets `@host`. Tool remains at H1.
- Confirm: `bpkg cfg-info -d <host-cfg>` returns `type: host`, which is the
  condition that triggers the skip branch in `lockfile.build`.

### 10. BDEP_SYNC=false bypasses enforcement

- Ensure `libfoo` in `bdep.lock` pins a version that differs from what is
  installed.
- Run `BDEP_SYNC=false b`.
- Expect: no `bpkg pkg-build`, no `bdep sync`, mismatch not corrected.
- Verify: `bpkg pkg-status libfoo -d <ext-cfg>` still shows the old version.

### 11. BDEP_SYNC=0 also bypasses enforcement

- Same setup as case 10 with `BDEP_SYNC=0`.
- Expect: identical no-op behavior.

### 12. CRLF line endings in bdep.lock

- Write `bdep.lock` with CRLF line endings (e.g. `printf 'libfoo/1.2.3\r\n'`,
  or create the file on Windows in a text editor that writes CRLF).
- Ensure `libfoo` is not at 1.2.3.
- Run `b`.
- Expect: pin parsed correctly (the `sed -e 's/\r//'` strip in `lockfile.build`
  removes the CR), enforcement runs, `libfoo` is corrected to 1.2.3.

### 13. Enforcement skipped during configure meta-operation

- Ensure a version mismatch exists.
- Run `b configure:`.
- Expect: lockfile enforcement body not entered (`$build.meta_operation !=
  'configure'` guard), mismatch not corrected.

### 14. Enforcement skipped during disfigure meta-operation

- Same mismatch, run `b disfigure:`.
- Expect: no bpkg/bdep enforcement commands.

### 15. Enforcement skipped during info meta-operation

- Same mismatch, run `b info:`.
- Expect: no enforcement.

### 16. Lockfile generation captures current configured versions

- Have `libfoo/1.1.0` and `libbar/2.0.0` configured in `@<cfg>-external`.
- Run `b config.lockfile.gen=true lockfile/`.
- Inspect `lockfile/bdep.lock` (accessible via the backlink symlink).
- Expect:
  - Contains `libfoo/1.1.0` and `libbar/2.0.0`.
  - Does not contain project-local packages.
  - Does not contain host build tools.
- Commit the generated file and confirm `b` is a fast no-op immediately after.

### 17. Dependent graph is reconfigured correctly within a config

- `libbar` depends on `libfoo`; both in `@<cfg>-external`.
- Pin `libfoo` to a different version.
- Run `b`.
- Expect: `bpkg pkg-build ?libfoo/<ver>` runs; bpkg's solver reconfigures
  `libbar` against the new `libfoo` automatically within that config.
- Verify: `bpkg pkg-status --all -d <ext-cfg>` shows `libbar` is still
  configured (not broken/fetched) after the change.

### 18. bdep sync called exactly once for multi-config changes

- Mismatches in two separate non-host configs.
- Run `b`.
- Expect: two `bpkg pkg-build` calls (one per config), then exactly one
  `bdep sync --yes` in the output. The `changed` flag is set after the first
  mismatch and stays set; sync runs once at the end of the outer loop.

---

## Verification Method

For each test:

1. Capture the full `b` output. Look for the `bdep.lock: pinning ...` diagnostic
   lines emitted by `lockfile.build` line 107 to confirm enforcement ran (or
   did not):

   ```
   bdep.lock: pinning <name> to <ver> in <cfg-path> (was <old-ver>)
   ```

2. Run `bpkg pkg-status --all -d <cfg>` before and after to confirm version
   state.

3. Run `bdep status` to confirm project packages are in sync after enforcement.
