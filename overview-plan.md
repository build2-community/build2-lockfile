# Lockfile Validation: Full Overview Plan

This is the master guide for a fresh session. Follow the phases in order from a
clean repository state to a fully validated, air-tight `lockfile/` package.
All commands assume POSIX tools (MSYS2/Cygwin on Windows) and a shell opened at
the project root.

## Reference documents

| Document | Purpose |
|----------|---------|
| `config-setup.md` | Exact commands to create and wire the three bpkg configurations |
| `initial-package-setup.md` | Project structure and dependency graph overview |
| `add-third-party-deps.md` | Third-party deps chosen and their available versions for pin testing |
| `lockfile-validation.md` | 22 test cases with setup, expectation, and verification for each |
| `build2-commands.md` | Quick reference for bpkg/bdep commands used throughout |
| `lockfile/README.md` | How the lockfile machinery works |
| `lockfile/build/lockfile.build` | The implementation -- primary source to read and fix |

---

## Phase 1: Prerequisites check

Verify tool versions and environment before touching anything.

```sh
b      --version   # build2 >= 0.18.0
bpkg   --version   # bpkg  >= 0.18.0
bdep   --version   # bdep  >= 0.18.0
```

Note: `lockfile.build` invokes `sed` for CRLF stripping, but this is the
build2 in-process pseudo-builtin (ECMAScript regex, `s` command only) -- not
the system `sed`. It is always available and requires no separate check.

Confirm the working directory is the project root (contains `packages.manifest`):

```sh
cat packages.manifest
```

Expected: five entries -- `lockfile/`, `libhello/`, `libworld/`, `libhello-tests/`,
`libworld-tests/`.

---

## Phase 2: Variable definitions

Set these once at the start of every session. Adjust `CONFIG_NAME` for the
compiler in use.

```sh
PROJECT_DIR=$(pwd)
CONFIG_NAME=msvc
CONFIG_NAME_EXT=${CONFIG_NAME}-external

BUILD_DIR_HOST=${PROJECT_DIR}/../hello-host
BUILD_DIR=${PROJECT_DIR}/../hello-${CONFIG_NAME}
BUILD_DIR_EXT=${PROJECT_DIR}/../hello-${CONFIG_NAME_EXT}

# Stable UUIDs derived from config names (md5sum; adjust if md5sum is not available)
UUID_HOST=$(printf '%s' "hello-host"                | md5sum | awk '{printf "%s-%s-%s-%s-%s", substr($1,1,8),substr($1,9,4),substr($1,13,4),substr($1,17,4),substr($1,21,12)}')
UUID_MAIN=$(printf '%s' "hello-${CONFIG_NAME}"      | md5sum | awk '{printf "%s-%s-%s-%s-%s", substr($1,1,8),substr($1,9,4),substr($1,13,4),substr($1,17,4),substr($1,21,12)}')
UUID_EXT=$(printf '%s'  "hello-${CONFIG_NAME_EXT}"  | md5sum | awk '{printf "%s-%s-%s-%s-%s", substr($1,1,8),substr($1,9,4),substr($1,13,4),substr($1,17,4),substr($1,21,12)}')
```

---

## Phase 3: Configuration setup

Full reference: `config-setup.md`. Abbreviated commands below.

### 3.1 Initialize bdep project skeleton (once only)

Skip if `.bdep/` already exists.

```sh
bdep init --empty --directory "$PROJECT_DIR"
```

### 3.2 Create the host configuration (once, reuse across reinits)

```sh
bpkg cfg-create \
  --uuid  "$UUID_HOST" \
  --name  host \
  --directory "$BUILD_DIR_HOST" \
  --type  host \
  --wipe  \
  cc config.config.load=~host
```

### 3.3 Create the main configuration (wipe and recreate each reinit)

```sh
bpkg cfg-create \
  --uuid  "$UUID_MAIN" \
  --name  "$CONFIG_NAME" \
  --directory "$BUILD_DIR" \
  --host-config "$BUILD_DIR_HOST" \
  --wipe  \
  cc
```

### 3.4 Create the external configuration (once, reuse across reinits)

```sh
bpkg cfg-create \
  --uuid  "$UUID_EXT" \
  --name  "$CONFIG_NAME_EXT" \
  --directory "$BUILD_DIR_EXT" \
  --wipe  \
  cc
```

### 3.5 Clean dangling links

```sh
bpkg cfg-unlink --directory "$BUILD_DIR"     --dangling
bpkg cfg-unlink --directory "$BUILD_DIR_EXT" --dangling
bpkg cfg-unlink --directory "$BUILD_DIR_HOST" --dangling
```

### 3.6 Link main to external

```sh
bpkg cfg-link --directory "$BUILD_DIR" "$BUILD_DIR_EXT" --relative
```

### 3.7 Configure all three

```sh
b configure: "$BUILD_DIR_HOST/" config.config.load=~host

b configure: "$BUILD_DIR/"

b configure: "$BUILD_DIR_EXT/"
```

Note: `config.config.load` only accepts file paths or the special `~host`
value. Compiler settings (MSVC on Windows) are auto-detected and require no
extra flags.

### 3.8 Register configurations with the project

```sh
bdep config add --directory "$PROJECT_DIR" @host              "$BUILD_DIR_HOST" --no-default --forward
bdep config add --directory "$PROJECT_DIR" @"$CONFIG_NAME_EXT" "$BUILD_DIR_EXT"  --no-default --no-forward
bdep config add --directory "$PROJECT_DIR" @"$CONFIG_NAME"    "$BUILD_DIR"      --no-default --no-forward
bdep config set --directory "$PROJECT_DIR" @"$CONFIG_NAME"    --default --forward
```

Verify:

```sh
bdep config list --directory "$PROJECT_DIR"
```

Expected: three rows -- `host` (forward), `msvc-external`, `msvc` (default, forward).

---

## Phase 4: Package initialization

### 4.1 Init all local packages into external (pulls third-party deps)

```sh
bdep init @"$CONFIG_NAME_EXT" \
  -d libhello -d libworld \
  -d libhello-tests -d libworld-tests \
  -d lockfile
```

This causes bpkg to fetch `fmt`, `spdlog`, `catch2` (and `spdlog`'s own `fmt`
transitive dep) into `$BUILD_DIR_EXT`. See `add-third-party-deps.md` for the
full version lists.

### 4.2 Remove local packages from external (keep only third-party deps)

```sh
bdep deinit @"$CONFIG_NAME_EXT" --force \
  -d libhello -d libworld \
  -d libhello-tests -d libworld-tests \
  -d lockfile

bpkg pkg-drop --directory "$BUILD_DIR_EXT" \
  --keep-unused --drop-dependent --yes \
  libhello libworld libhello-tests libworld-tests lockfile
```

### 4.3 Init local packages into main (deps resolved via cfg-link to external)

```sh
bdep init @"$CONFIG_NAME" --no-sync \
  -d libhello -d libworld \
  -d libhello-tests -d libworld-tests \
  -d lockfile

bdep sync --upgrade --yes
```

### 4.4 Verify baseline state

```sh
bpkg pkg-status --all -d "$BUILD_DIR_EXT"   # fmt, spdlog, catch2 -- all "configured"
bpkg pkg-status --all -d "$BUILD_DIR"       # libhello, libworld, etc. -- all "configured"
bdep status
```

Record the exact versions reported by `bpkg pkg-status --all -d "$BUILD_DIR_EXT"`.
These are the "installed" versions that bdep.lock will be generated from.

---

## Phase 5: Generate bdep.lock and verify initial no-op

### 5.1 Generate from current configuration state

```sh
b config.lockfile.gen=true lockfile/
```

Inspect the result (backlink in source dir):

```sh
cat lockfile/bdep.lock
```

Expected: one `name/version` line each for `fmt`, `spdlog`, `catch2` (and any
indirect deps bpkg installed). No project-local packages. No host tools.
Versions match exactly what `bpkg pkg-status` reported in step 4.4.

### 5.2 Commit the generated lockfile

```sh
git add lockfile/bdep.lock
git commit -m "Add generated bdep.lock with initial dependency pins."
```

### 5.3 Verify first run is a no-op

```sh
b
```

Expected: no `bdep.lock: pinning ...` diagnostic, no `bpkg pkg-build`, no
`bdep sync`. Build completes silently.

If enforcement fires unexpectedly here, the generated bdep.lock is inconsistent
with the installed state. Re-run step 5.1 and investigate.

---

## Phase 6: Lockfile test suite

Run the test cases from `lockfile-validation.md` in the groups below. The
primary observable for each test is the presence or absence of:

```
bdep.lock: pinning <name> to <ver> in <cfg-path> (was <old-ver>)
```

After every enforcement test, reset to a known state with:

```sh
b config.lockfile.gen=true lockfile/   # regenerate to match current installed
b                                       # confirm no-op
```

### Group A: No-ops and bypass (cases 1-4, 12-13, 15-17)

These tests make no permanent state changes and can be run in any order.

```sh
# Case 1: absent lockfile
mv lockfile/bdep.lock lockfile/bdep.lock.bak
b                                        # expect: silent, no enforcement
mv lockfile/bdep.lock.bak lockfile/bdep.lock

# Case 2: empty lockfile
echo -n "" > lockfile/bdep.lock
b                                        # expect: silent
b config.lockfile.gen=true lockfile/     # restore

# Case 3: comments only
echo "# no pins" > lockfile/bdep.lock
b                                        # expect: silent
b config.lockfile.gen=true lockfile/     # restore

# Case 4: all versions match (already validated in phase 5.3)

# Case 12: BDEP_SYNC=false
# (write a mismatching pin first, then bypass)
ORIG=$(grep '^fmt/' lockfile/bdep.lock)
sed -i 's|^fmt/.*|fmt/10.0.0|' lockfile/bdep.lock   # create mismatch
BDEP_SYNC=false b                                      # expect: silent, no enforcement
b config.lockfile.gen=true lockfile/                   # restore

# Case 13: BDEP_SYNC=0
sed -i 's|^fmt/.*|fmt/10.0.0|' lockfile/bdep.lock
BDEP_SYNC=0 b
b config.lockfile.gen=true lockfile/

# Case 15: configure meta-op
sed -i 's|^fmt/.*|fmt/10.0.0|' lockfile/bdep.lock
b configure:                                          # expect: no enforcement
b config.lockfile.gen=true lockfile/

# Case 16: disfigure
sed -i 's|^fmt/.*|fmt/10.0.0|' lockfile/bdep.lock
b disfigure:                                          # expect: no enforcement
b configure: "$BUILD_DIR/"                            # re-configure after disfigure
b config.lockfile.gen=true lockfile/

# Case 17: info
sed -i 's|^fmt/.*|fmt/10.0.0|' lockfile/bdep.lock
b info:                                               # expect: no enforcement
b config.lockfile.gen=true lockfile/
```

### Group B: Version enforcement (cases 5-10)

Each test changes installed versions. Reset to baseline after each one.

```sh
# Case 5: single package mismatch (fmt)
sed -i 's|^fmt/[^ ]*|fmt/10.1.1|' lockfile/bdep.lock
b      # expect: "pinning fmt to 10.1.1 in ... (was <current>)"
bpkg pkg-status fmt -d "$BUILD_DIR_EXT"   # verify 10.1.1
b config.lockfile.gen=true lockfile/       # reset

# Case 6: two packages in same config (fmt + catch2)
# Edit bdep.lock to pin both to older versions
b config.lockfile.gen=true lockfile/       # start clean
FMTVER=10.1.1
C2VER=3.5.1+1
sed -i "s|^fmt/.*|fmt/${FMTVER}|;s|^catch2/.*|catch2/${C2VER}|" lockfile/bdep.lock
b      # expect: single bpkg pkg-build call with both pins
bpkg pkg-status fmt catch2 -d "$BUILD_DIR_EXT"
b config.lockfile.gen=true lockfile/

# Case 7: transitive interface dep (fmt affects libworld consumers)
sed -i 's|^fmt/.*|fmt/10.0.0|' lockfile/bdep.lock
b      # expect: fmt pinned, bdep sync re-configures libhello + libworld
bdep status   # verify project packages in sync
b config.lockfile.gen=true lockfile/

# Case 8: spdlog/fmt compatibility
# Pin both. If spdlog's own fmt constraint is satisfied, both install.
b config.lockfile.gen=true lockfile/
sed -i "s|^fmt/.*|fmt/10.2.1|;s|^spdlog/.*|spdlog/1.14.1+2|" lockfile/bdep.lock
b      # expect success if compatible; error from bpkg if not
b config.lockfile.gen=true lockfile/

# Case 9: partial mismatch (only catch2 differs, fmt already matches)
b config.lockfile.gen=true lockfile/
sed -i 's|^catch2/.*|catch2/3.3.2|' lockfile/bdep.lock
b      # expect: only catch2 in diagnostic; fmt not mentioned
b config.lockfile.gen=true lockfile/

# Case 10: +N revision suffix exact match
b config.lockfile.gen=true lockfile/
# Find the spdlog line and strip the revision suffix, e.g. 1.14.1+2 -> 1.14.1
sed -i 's|^spdlog/\([0-9.]*\)+[0-9]*|spdlog/\1|' lockfile/bdep.lock
b      # expect: enforcement fires (1.14.1 != 1.14.1+2)
b config.lockfile.gen=true lockfile/
```

### Group C: Edge cases (cases 11, 14, 19, 20)

```sh
# Case 11: host config skip
# Add any host tool that is already configured in @host to bdep.lock at a
# different version. Run b and confirm no bpkg call targets $BUILD_DIR_HOST.
# (Requires a host-type tool to be present; skip if @host has no packages.)

# Case 14: CRLF line endings
b config.lockfile.gen=true lockfile/
printf 'fmt/10.1.1\r\n' > /tmp/crlf-test.lock
# Replace the fmt line in bdep.lock with the CRLF version
sed -i '/^fmt\//d' lockfile/bdep.lock
printf 'fmt/10.1.1\r\n' >> lockfile/bdep.lock
b      # expect: sed strips CR, enforcement runs, fmt corrected
b config.lockfile.gen=true lockfile/

# Case 19: testing-repo version
# Install fmt from the testing repo at 11.1.4
bpkg pkg-build --yes ?fmt/11.1.4 -d "$BUILD_DIR_EXT"
b config.lockfile.gen=true lockfile/
cat lockfile/bdep.lock   # expect: fmt/11.1.4
b                        # expect: no-op
sed -i 's|^fmt/.*|fmt/10.2.1|' lockfile/bdep.lock
b      # expect: enforcement downgrades fmt back to stable
b config.lockfile.gen=true lockfile/

# Case 20: unknown pin (package not in any config)
b config.lockfile.gen=true lockfile/
echo "libnothere/1.0.0" >> lockfile/bdep.lock
b      # expect: silent (no match in bdep status, silently skipped)
b config.lockfile.gen=true lockfile/
```

### Group D: Lockfile generation (cases 18)

```sh
# Case 18: generation captures correct state
bpkg pkg-status --all -d "$BUILD_DIR_EXT"   # note current versions
b config.lockfile.gen=true lockfile/
cat lockfile/bdep.lock                       # compare to noted versions
b                                            # must be a no-op immediately after
```

### Group E: Multi-config (cases 21-22)

These require a package to exist in two separate non-host configurations. In the
standard three-config topology, all third-party deps land in `@<cfg>-external`
and all project packages in `@<cfg>`. To exercise this path, temporarily move
one package (e.g. by initializing `catch2` directly into `@<cfg>` with
`bpkg pkg-build --yes catch2/3.7.1 -d "$BUILD_DIR"`) so it appears in both.
Then pin it in bdep.lock and run `b`. Confirm two `bpkg pkg-build` calls and
exactly one `bdep sync`.

---

## Phase 7: Diagnosing and fixing failures

When a test does not behave as expected, follow this sequence.

### 7.1 Identify the failure mode

| Symptom | Likely cause |
|---------|-------------|
| Enforcement fires when it should not | Guard condition wrong (build.mode, meta_operation, BDEP_SYNC check) |
| Enforcement silent when it should fire | Version comparison wrong, regex not matching pkg-status output |
| bpkg pkg-build called with wrong version | `pver` extraction regex wrong |
| bdep sync called multiple times | `changed` flag reset inside the loop instead of outside |
| Host-config package incorrectly enforced | `cfg_type != 'host'` check not working |
| +N suffix causes false mismatch | Exact string comparison intended; pin must include suffix |
| CRLF not stripped | sed not available or regex wrong |

### 7.2 Add diagnostic traces

The build2 script language has `text` for printing. Insert temporary traces in
`lockfile/build/lockfile.build` to expose intermediate values:

```
text "DEBUG allpins: $allpins"
text "DEBUG linked_cfgs: $linked_cfgs"
text "DEBUG cfg_type: $cfg_type"
text "DEBUG before_pkgs: $before_pkgs"
text "DEBUG pending_pins: $pending_pins"
```

Remove all debug traces before committing a fix.

### 7.3 Apply the fix

Edit `lockfile/build/lockfile.build` only (the bootstrap source). The buildfile
`lockfile/buildfile` handles generation; `lockfile/build/root.build` only
defines the `config.lockfile.gen` variable. Do not modify those unless the
generation logic itself is wrong.

### 7.4 Re-run the affected test case

After editing `lockfile.build`:

```sh
b   # lockfile.build is sourced at bootstrap; the change takes effect immediately
```

No rebuild step is needed -- the file is an interpreted build2 script, not
compiled code.

### 7.5 Re-run the full suite

After all individual test cases pass, do a complete clean sweep:

```sh
b config.lockfile.gen=true lockfile/   # regenerate to known state
b                                       # no-op baseline
# then re-run Groups A through D in sequence
```

---

## Phase 8: Full reset procedure

Use this to return to a clean state at any point, e.g. between full test runs
or after a botched test.

```sh
# 1. Regenerate bdep.lock from actual installed state
b config.lockfile.gen=true lockfile/

# 2. Confirm no-op
b

# 3. If bpkg state is corrupt, reinstall all external deps at the versions
#    that bdep.lock will subsequently pin:
bpkg pkg-build --yes \
  ?fmt/10.2.1 \
  ?spdlog/1.14.1+2 \
  ?catch2/3.7.1 \
  -d "$BUILD_DIR_EXT"

# 4. Regenerate lockfile to match the freshly installed state
b config.lockfile.gen=true lockfile/
b
```

For a complete environment reset (reconfigures everything from scratch), re-run
Phase 3 through Phase 5, skipping only the bdep project skeleton step (3.1).

---

## Iteration guidance for auto-mode

A fresh Claude session should:

1. Run the prerequisites check (Phase 1).
2. Check if `.bdep/` and the three configuration directories already exist.
   - If yes, jump to Phase 5.3 to verify no-op; proceed to Phase 6 if clean.
   - If no, run Phases 2-5 in full.
3. Execute Phase 6 groups A through D in order, using the reset step between
   each group.
4. If any test fails, enter Phase 7, fix `lockfile/build/lockfile.build`, and
   re-run the failing group.
5. After all groups pass without any fix being needed, commit:
   ```sh
   git add lockfile/build/lockfile.build lockfile/bdep.lock
   git commit -m "Fix lockfile enforcement: <short description of what was wrong>."
   ```
6. Run Phase 8 full reset, then re-run all groups from A to D one final time
   to confirm no regressions.
7. If all groups pass cleanly with no fixes applied, the lockfile machinery is
   air-tight. Report the result.
