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

### Dependency topology in this project

```
libhello  --(intf)-->  fmt        (external config)
libworld  --(impl)-->  spdlog     (external config, depends on fmt)
libhello-tests         catch2     (external config)
libworld-tests         catch2     (external config)
```

`fmt` is an interface dependency of `libhello`, so it is exported transitively
to `libworld` and the test packages as well. `spdlog` also depends on `fmt`
internally. This means `fmt` is a shared transitive dep for multiple packages
and is a key target for lockfile enforcement tests.

---

## Prerequisites

1. Three-config setup in place per `config-setup.md`:
   - `@host`           -- host-type, contains build-time tools
   - `@<cfg>`          -- main config, project packages
   - `@<cfg>-external` -- external/third-party dependencies

2. External packages fetched and configured in `@<cfg>-external`:
   - `fmt` (versions available: 11.1.4 testing, 11.0.2 testing, 10.2.1, 10.1.1, 10.0.0, 9.1.0)
   - `spdlog` (versions available: 1.14.1+2, 1.12.0, 1.11.0+1)
   - `catch2` (versions available: 3.7.1, 3.5.1+1, 3.3.2)

3. `lockfile` package initialized in the main config and `bdep.lock` present in
   `lockfile/`.

4. Baseline `bpkg pkg-status --all -d <ext-cfg>` output captured for reference.

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
- Expect: `allpins` is null, enforcement body never entered.

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

### 5. Single package version mismatch

- Install `fmt` at 10.2.1 in `@<cfg>-external`.
- Write `lockfile/bdep.lock`: `fmt/10.1.1`.
- Run `b`.
- Expect:
  - Diagnostic: `bdep.lock: pinning fmt to 10.1.1 in <ext-cfg-path> (was 10.2.1)`
  - `bpkg pkg-build --yes --no-move ?fmt/10.1.1 -d <ext-cfg>` executed.
  - `bdep sync --yes` executed once.
- Verify: `bpkg pkg-status fmt -d <ext-cfg>` reports 10.1.1.

### 6. Multiple packages in same configuration, both mismatched

- Install `fmt` at 10.2.1 and `catch2` at 3.7.1 in `@<cfg>-external`.
- Write `lockfile/bdep.lock`:
  ```
  fmt/10.1.1
  catch2/3.5.1+1
  ```
- Run `b`.
- Expect:
  - Two diagnostics (one per package).
  - A single `bpkg pkg-build --yes --no-move ?fmt/10.1.1 ?catch2/3.5.1+1 -d <ext-cfg>`
    call (both pins batched into one invocation for the same config).
  - `bdep sync --yes` called once.
- Verify both are at pinned versions.

### 7. Transitive interface dependency: pinning fmt affects libworld consumers

- `fmt` is an interface dep of `libhello`, which `libworld` depends on.
- Pin `fmt` to a different version.
- Run `b`.
- Expect: `bpkg pkg-build ?fmt/<ver>` runs. bpkg reconfigures `spdlog`
  (which also uses `fmt` internally) and any other `fmt` dependents within
  the same configuration automatically.
- Verify: `bpkg pkg-status --all -d <ext-cfg>` shows all dependents still
  configured. `bdep sync` re-configures `libhello` and `libworld` against
  the new `fmt`.

### 8. spdlog/fmt version compatibility

- `spdlog` depends on `fmt`. Pin both independently in `bdep.lock`:
  ```
  fmt/10.2.1
  spdlog/1.14.1+2
  ```
- Run `b`.
- Expect: bpkg resolves `spdlog`'s own `fmt` constraint against the pinned
  `fmt/10.2.1` within the external configuration. If the versions are
  compatible, both are installed. If not, `bpkg pkg-build` will error.
- This test validates that the lockfile enforcer does not need to understand
  inter-package dependency constraints -- it delegates entirely to bpkg.

### 9. Mixed: some pinned versions already match, some do not

- `fmt` is already at its pinned version, `catch2` is not.
- Run `b`.
- Expect:
  - Only `catch2` appears in the diagnostic and in `bpkg pkg-build` args.
  - `fmt` is not mentioned in any `bpkg pkg-build` invocation.

### 10. Version with bpkg revision suffix (+N)

- Install `spdlog` at `1.14.1+2` (has a `+2` bpkg revision suffix).
- Write `lockfile/bdep.lock`: `spdlog/1.14.1+2`.
- Run `b` -- expect no-op (versions match including the suffix).
- Now write `lockfile/bdep.lock`: `spdlog/1.14.1` (suffix omitted).
- Run `b` -- expect: `bver (1.14.1+2) != pver (1.14.1)` triggers enforcement.
- This confirms the enforcer does exact string comparison and `+N` suffixes
  must be written precisely.

### 11. Host configuration is skipped

- A host build tool in `@host` at version H1.
- Pin it at H2 in `bdep.lock`.
- Run `b`.
- Expect: no `bpkg pkg-build` call targets `@host`. Tool remains at H1.
- Confirm: `bpkg cfg-info -d <host-cfg>` returns `type: host`, which is the
  skip-branch trigger in `lockfile.build`.

### 12. BDEP_SYNC=false bypasses enforcement

- Ensure `fmt` in `bdep.lock` pins a version that differs from what is
  installed.
- Run `BDEP_SYNC=false b`.
- Expect: no `bpkg pkg-build`, no `bdep sync`, mismatch not corrected.
- Verify: `bpkg pkg-status fmt -d <ext-cfg>` still shows the old version.

### 13. BDEP_SYNC=0 also bypasses enforcement

- Same setup as case 12 with `BDEP_SYNC=0`.
- Expect: identical no-op behavior.

### 14. CRLF line endings in bdep.lock

- Write `bdep.lock` with CRLF line endings (`printf 'fmt/10.2.1\r\n'`).
- Ensure `fmt` is not at 10.2.1.
- Run `b`.
- Expect: the build2 built-in `sed` (in-process pseudo-command, ECMAScript
  regex) strips the `\r` via `s/\r//`, enforcement runs, `fmt` is corrected
  to 10.2.1.

### 15. Enforcement skipped during configure meta-operation

- Ensure a version mismatch exists.
- Run `b configure:`.
- Expect: lockfile enforcement body not entered (`$build.meta_operation !=
  'configure'` guard), mismatch not corrected.

### 16. Enforcement skipped during disfigure meta-operation

- Same mismatch, run `b disfigure:`.
- Expect: no bpkg/bdep enforcement commands.

### 17. Enforcement skipped during info meta-operation

- Same mismatch, run `b info:`.
- Expect: no enforcement.

### 18. Lockfile generation captures current configured versions

- Have `fmt/10.2.1`, `spdlog/1.14.1+2`, `catch2/3.7.1` configured in
  `@<cfg>-external`.
- Run `b config.lockfile.gen=true lockfile/`.
- Inspect `lockfile/bdep.lock` (accessible via the backlink symlink).
- Expect:
  - Contains `fmt/10.2.1`, `spdlog/1.14.1+2`, `catch2/3.7.1`.
  - Does not contain project-local packages (`libhello`, `libworld`, etc.).
  - Does not contain host build tools.
- Commit the generated file and confirm `b` is a fast no-op immediately after.

### 19. Lockfile generation with testing-repo version

- Downgrade or install `fmt` at `11.1.4` (from the testing repo).
- Run `b config.lockfile.gen=true lockfile/`.
- Expect: `bdep.lock` contains `fmt/11.1.4`.
- Run `b` -- no-op.
- Write `bdep.lock`: `fmt/10.2.1` and run `b` -- enforcement downgrades to stable.
- This validates that testing-repo versions round-trip correctly through
  the lockfile.

### 20. Pinned package not present in any configuration

- Write `bdep.lock` with a package name that is not configured anywhere
  (e.g. `libnothere/1.0.0`).
- Run `b`.
- Expect: `bdep status` output contains no `[<cfg-path>] configured` line for
  `libnothere`, so `linked_cfgs` has no entry for it. The enforcer silently
  skips it (no error, no bpkg call for that name).
- This confirms the machinery degrades gracefully for stale or typo'd pins.

### 21. Packages spread across two non-host configurations

- If the project topology includes packages in both `@<cfg>` (main) and
  `@<cfg>-external`, pin one from each.
- Run `b`.
- Expect: two separate `bpkg pkg-build` calls (one per configuration), then
  exactly one `bdep sync --yes` at the end.

### 22. bdep sync called exactly once after multi-config changes

- Mismatches in two separate non-host configs (see case 21).
- Confirm via output that `bdep sync --yes` appears exactly once regardless
  of how many configs had changes.

---

## Verification Method

For each test:

1. Capture the full `b` output. The primary observable is the diagnostic from
   `lockfile.build` line 107:

   ```
   bdep.lock: pinning <name> to <ver> in <cfg-path> (was <old-ver>)
   ```

2. Run `bpkg pkg-status --all -d <cfg>` before and after to confirm version
   state.

3. Run `bdep status` to confirm project packages are in sync after enforcement.
