#!/usr/bin/env bash
# Lockfile validation test suite.
# Run from the project root: bash test-lockfile.sh [--quiet] [--case=N[,N...]] [--list]
#
# --quiet      suppress per-command output (only show PASS/FAIL lines)
# --case=N     run only the listed case numbers (comma-separated)
# --list       print all case numbers and descriptions, then exit
#
# Each test function calls _desc "..." as its very first statement. Case
# numbers are assigned sequentially in the order add_test is called. The
# runner calls _get_desc to extract the description without executing the
# test body, then runs the test proper.

set -uo pipefail

# Save the original stdout before any command-substitution redirects it.
# _run and _capture write live output here so it reaches the terminal even
# when their own stdout is captured by $().
exec 3>&1

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0

QUIET=false
CASE_FILTER=''
LIST_MODE=false

for _arg in "$@"; do
  case "$_arg" in
    --quiet)   QUIET=true ;;
    --case=*)  CASE_FILTER="${_arg#--case=}" ;;
    --list)    LIST_MODE=true ;;
    *) printf 'unknown argument: %s\n' "$_arg" >&2; exit 1 ;;
  esac
done
unset _arg

_pass() { printf "${GREEN}[PASS]${NC} %s\n" "$*"; (( ++PASS_COUNT )) || true; }
_fail() { printf "${RED}[FAIL]${NC} %s\n" "$*"; (( ++FAIL_COUNT )) || true; }

# --------------------------------------------------------------------------
# Test registry
# --------------------------------------------------------------------------

_TESTS=()

add_test() { _TESTS+=("$1"); }

# No-op in normal execution. Overridden in _get_desc's subshell to capture
# just the description without running the test body.
_desc() { :; }

# Extract the description of a test function by overriding _desc in a
# subshell that writes the value and exits immediately.
_get_desc() {
  local fn="$1" tmpf
  tmpf=$(mktemp /tmp/claude/tdesc-XXXXXX)
  (
    _desc() { printf '%s' "$1" > "$tmpf"; exit 0; }
    "$fn" 2>/dev/null
  ) || true
  cat "$tmpf"
  rm -f "$tmpf"
}

# --------------------------------------------------------------------------
# Environment
# --------------------------------------------------------------------------

PROJECT_DIR=$(pwd)
CONFIG_NAME=msvc
CONFIG_NAME_EXT=${CONFIG_NAME}-external
BUILD_DIR_HOST=${PROJECT_DIR}/../hello-host
BUILD_DIR=${PROJECT_DIR}/../hello-${CONFIG_NAME}
BUILD_DIR_EXT=${PROJECT_DIR}/../hello-${CONFIG_NAME_EXT}
LOCKFILE=${PROJECT_DIR}/lockfile/bdep.lock

# Baseline versions
FMT_BASE=10.2.1
SPDLOG_BASE='1.14.1+2'
ENTT_BASE=3.14.0

# Extra config vars (Group F only)
BUILD_DIR_EXTRA="${PROJECT_DIR}/../hello-${CONFIG_NAME}-extra"
UUID_EXTRA=$(printf '%s' "hello-${CONFIG_NAME}-extra" | md5sum | \
  awk '{printf "%s-%s-%s-%s-%s",
       substr($1,1,8),substr($1,9,4),substr($1,13,4),substr($1,17,4),substr($1,21,12)}')

# --------------------------------------------------------------------------
# Output helpers
# --------------------------------------------------------------------------

# Run a command, writing live output to fd 3 (original stdout) unless --quiet.
_run() {
  if [ "$QUIET" = true ]; then
    "$@" >/dev/null 2>&1
  else
    "$@" >&3 2>&3
  fi
}

# Run a command and capture its combined stdout+stderr for assertion, while
# also streaming live to fd 3 unless --quiet.
# Usage: out=$(_capture cmd args...)
_capture() {
  local tmpf rc
  tmpf=$(mktemp /tmp/claude/tl-XXXXXX)
  if [ "$QUIET" = true ]; then
    "$@" >"$tmpf" 2>&1
    rc=$?
  else
    "$@" 2>&1 | tee "$tmpf" >&3
    rc=${PIPESTATUS[0]}
  fi
  cat "$tmpf"
  rm -f "$tmpf"
  return $rc
}

# --------------------------------------------------------------------------
# State helpers
# --------------------------------------------------------------------------

reset_installed() {
  _run bpkg pkg-build --yes \
    "fmt/${FMT_BASE}" \
    "spdlog/${SPDLOG_BASE}" \
    "entt/${ENTT_BASE}" \
    -d "$BUILD_DIR_EXT" || return 1
  _run bdep sync --yes -d "$PROJECT_DIR" || return 1
}

reset_lockfile() {
  git -C "$PROJECT_DIR" checkout -- lockfile/bdep.lock || return 1
}

regenerate_lockfile() {
  _run b -q config.lockfile.lock=true lockfile/ || return 1
}

reset_baseline() {
  reset_installed || return 1
  reset_lockfile  || return 1
}

_init_configs() {
  [ -d "$BUILD_DIR" ] && return 0

  _run bpkg cfg-create --name host \
    --directory "$BUILD_DIR_HOST" --type host --wipe cc \
    config.config.load=~host || return 1
  _run bpkg cfg-create --name "$CONFIG_NAME" \
    --directory "$BUILD_DIR" --wipe cc || return 1
  _run bpkg cfg-create --name "${CONFIG_NAME}-external" \
    --directory "$BUILD_DIR_EXT" --wipe cc || return 1

  _run bpkg rep-add \
    https://pkg.cppget.org/1/stable \
    https://pkg.cppget.org/1/testing \
    -d "$BUILD_DIR_EXT" || return 1
  _run bpkg rep-fetch --trust-yes -d "$BUILD_DIR_EXT" || return 1

  _run bpkg cfg-link \
    --directory "$BUILD_DIR" "$BUILD_DIR_EXT" --relative || return 1

  bdep status 2>/dev/null || _run bdep init --empty || return 1
  _run bdep config add @host \
    "$BUILD_DIR_HOST" --no-default --forward || return 1
  _run bdep config add @"${CONFIG_NAME}-external" \
    "$BUILD_DIR_EXT" --no-default --no-forward || return 1
  _run bdep config add @"$CONFIG_NAME" \
    "$BUILD_DIR" --no-default --no-forward || return 1
  _run bdep config set @"$CONFIG_NAME" --default --forward || return 1

  _run bdep init @"${CONFIG_NAME}-external" \
    -d libhello -d libworld \
    -d libhello-tests -d libworld-tests -d lockfile || return 1
  _run bdep deinit @"${CONFIG_NAME}-external" --force \
    -d libhello -d libworld \
    -d libhello-tests -d libworld-tests -d lockfile || return 1
  _run bpkg pkg-drop \
    --keep-unused --drop-dependent --yes \
    libhello libworld libhello-tests libworld-tests lockfile \
    -d "$BUILD_DIR_EXT" || return 1

  _run bdep init @"$CONFIG_NAME" --no-sync \
    -d libhello -d libworld \
    -d libhello-tests -d libworld-tests -d lockfile || return 1
  _run bdep sync --upgrade --yes || return 1
}

# --------------------------------------------------------------------------
# Assertion helpers
# --------------------------------------------------------------------------

# Assert pattern IS present in output.
assert_contains() {
  local output="$1" pattern="$2"
  if ! printf '%s' "$output" | grep -qE "$pattern"; then
    printf 'expected pattern not found: %s\n' "$pattern"
    return 1
  fi
}

# Assert pattern is NOT present in output.
assert_not_contains() {
  local output="$1" pattern="$2"
  if printf '%s' "$output" | grep -qE "$pattern"; then
    printf 'unexpected pattern found: %s\n' "$pattern"
    return 1
  fi
}

# Assert a package is configured in a bpkg config at an exact version.
assert_version() {
  local pkg="$1" ver="$2" cfg="$3"
  local status
  status=$(bpkg pkg-status "$pkg" -d "$cfg" 2>&1)
  if ! printf '%s' "$status" | grep -qE "^!?${pkg} configured"; then
    printf '%s: expected %s, got: %s\n' "$pkg" "$ver" "$status"
    return 1
  fi
  if ! printf '%s' "$status" | grep -qF "$ver"; then
    printf '%s: expected %s, got: %s\n' "$pkg" "$ver" "$status"
    return 1
  fi
}

# --------------------------------------------------------------------------
# Test runner
# --------------------------------------------------------------------------

run_test() {
  local num="$1" fn="$2"

  if [ -n "$CASE_FILTER" ]; then
    local matched=false
    IFS=',' read -ra _filter_nums <<< "$CASE_FILTER"
    for _fn in "${_filter_nums[@]}"; do
      [ "$_fn" = "$num" ] && matched=true && break
    done
    unset _filter_nums _fn
    [ "$matched" = false ] && return 0
  fi

  local desc detail rc
  desc=$(_get_desc "$fn")

  detail=$( "$fn" 2>&1 )
  rc=$?

  if [ "$rc" -eq 0 ]; then
    _pass "Case $(printf '%2d' "$num"): $desc"
  else
    _fail "Case $(printf '%2d' "$num"): $desc"
    if [ -n "$detail" ]; then
      printf '  %s\n' "$detail" | head -10
    fi
  fi

  reset_baseline || true
}

# --------------------------------------------------------------------------
# Group A: No-ops (cases 1-4)
# --------------------------------------------------------------------------

t_absent_lockfile() {
  _desc "absent lockfile is a no-op"
  mv "$LOCKFILE" "${LOCKFILE}.bak"
  local out
  out=$(_capture b) || return 1
  mv "${LOCKFILE}.bak" "$LOCKFILE"
  assert_not_contains "$out" 'pinning'
}
add_test t_absent_lockfile

t_empty_lockfile() {
  _desc "empty lockfile is a no-op"
  printf '' > "$LOCKFILE"
  local out
  out=$(_capture b) || return 1
  assert_not_contains "$out" 'pinning'
}
add_test t_empty_lockfile

t_comments_only() {
  _desc "comments-only lockfile is a no-op"
  printf '# no pins\n\n' > "$LOCKFILE"
  local out
  out=$(_capture b) || return 1
  assert_not_contains "$out" 'pinning'
}
add_test t_comments_only

t_all_versions_match() {
  _desc "all versions already match is a no-op"
  local out
  out=$(_capture b) || return 1
  assert_not_contains "$out" 'pinning'
}
add_test t_all_versions_match

# --------------------------------------------------------------------------
# Group B: Version enforcement (cases 5-11)
# --------------------------------------------------------------------------
# Dependency topology driving package choices in this group:
#   fmt   -- interface dep of libhello, exported transitively to libworld and
#             both test packages. Pinning it exercises bdep sync re-configuring
#             the full dependent chain. spdlog also depends on fmt internally,
#             so both land in BUILD_DIR_EXT.
#   entt  -- header-only with no cross-package constraints, and has both
#             stable (3.13.x, 3.14.0) and testing-repo (3.15.0+) versions,
#             which makes it ideal for pin-cycling and version round-trips.

t_single_mismatch() {
  _desc "single package version mismatch is enforced"
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  local out
  out=$(_capture b) || return 1
  assert_contains "$out" 'pinning fmt to 10\.1\.1' || return 1
  assert_version fmt '10.1.1' "$BUILD_DIR_EXT"
}
add_test t_single_mismatch

t_two_packages_same_cfg() {
  _desc "two mismatched packages in the same config are batched"
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  sed -i "s|^entt/.*|entt/3.13.2|" "$LOCKFILE"
  local out
  out=$(_capture b) || return 1
  assert_contains "$out" 'pinning fmt' || return 1
  assert_contains "$out" 'pinning entt' || return 1
  assert_version fmt '10.1.1' "$BUILD_DIR_EXT" || return 1
  assert_version entt '3.13.2' "$BUILD_DIR_EXT"
}
add_test t_two_packages_same_cfg

t_transitive_intf_dep() {
  _desc "pinning a transitive interface dep triggers bdep sync on dependents"
  # spdlog/1.14.1+2 requires fmt ^10.1.1, so 10.1.1 is compatible.
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  local out
  out=$(_capture b) || return 1
  assert_contains "$out" 'pinning fmt to 10\.1\.1' || return 1
  assert_version fmt '10.1.1' "$BUILD_DIR_EXT" || return 1
  local sync_status
  sync_status=$(bdep status 2>&1)
  assert_contains "$sync_status" 'configured'
}
add_test t_transitive_intf_dep

t_spdlog_fmt_compat() {
  _desc "spdlog and fmt both at baseline versions is a no-op"
  local out
  out=$(_capture b) || return 1
  assert_not_contains "$out" 'pinning'
}
add_test t_spdlog_fmt_compat

t_partial_mismatch() {
  _desc "partial mismatch only enforces the mismatched package"
  sed -i "s|^entt/.*|entt/3.13.2|" "$LOCKFILE"
  local out
  out=$(_capture b) || return 1
  assert_contains "$out" 'pinning entt' || return 1
  assert_not_contains "$out" 'pinning fmt' || return 1
  assert_version entt '3.13.2' "$BUILD_DIR_EXT" || return 1
  assert_version fmt "$FMT_BASE" "$BUILD_DIR_EXT"
}
add_test t_partial_mismatch

t_revision_no_explicit_n() {
  _desc "pin without +N suffix is a no-op against any installed revision"
  # Strip +2 from spdlog: 1.14.1+2 -> 1.14.1.
  # bpkg treats X.Y.Z as satisfied by X.Y.Z+N, so 1.14.1 must NOT trigger
  # enforcement against an installed 1.14.1+2 -- that would loop forever.
  sed -i 's|^spdlog/\([0-9.]*\)+[0-9]*|spdlog/\1|' "$LOCKFILE"
  local out
  out=$(_capture b) || return 1
  assert_not_contains "$out" 'pinning spdlog'
}
add_test t_revision_no_explicit_n

t_explicit_revision_mismatch() {
  _desc "explicit +N mismatch is detected and bpkg errors if revision unavailable"
  # Change spdlog pin from 1.14.1+2 to 1.14.1+1 (same base, different +N).
  # Enforcer must detect the mismatch and attempt to pin. Since 1.14.1+1 does
  # not exist in the repos, bpkg fails with an error.
  sed -i 's|^spdlog/1\.14\.1+2|spdlog/1.14.1+1|' "$LOCKFILE"
  local out rc=0
  out=$(_capture b) || true
  assert_contains "$out" 'pinning spdlog to 1\.14\.1\+1' || rc=1
  assert_contains "$out" 'error:' || rc=1
  return $rc
}
add_test t_explicit_revision_mismatch

# --------------------------------------------------------------------------
# Group C: Skip conditions (cases 12-18)
# --------------------------------------------------------------------------

t_host_config_skip() {
  _desc "host configuration packages are skipped"
  # xxd lives in @host. The enforcer must skip host-type configs entirely.
  printf 'xxd/1.0.0\n' >> "$LOCKFILE"
  local out
  out=$(_capture b) || return 1
  assert_not_contains "$out" 'pinning xxd' || return 1
  assert_version xxd '8.2.3075+2' "$BUILD_DIR_HOST"
}
add_test t_host_config_skip

t_bdep_sync_false() {
  _desc "BDEP_SYNC=false bypasses enforcement"
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  local out
  out=$(BDEP_SYNC=false _capture b) || return 1
  assert_not_contains "$out" 'pinning' || return 1
  assert_version fmt "$FMT_BASE" "$BUILD_DIR_EXT"
}
add_test t_bdep_sync_false

t_bdep_sync_zero() {
  _desc "BDEP_SYNC=0 bypasses enforcement"
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  local out
  out=$(BDEP_SYNC=0 _capture b) || return 1
  assert_not_contains "$out" 'pinning' || return 1
  assert_version fmt "$FMT_BASE" "$BUILD_DIR_EXT"
}
add_test t_bdep_sync_zero

t_crlf_endings() {
  _desc "CRLF line endings in bdep.lock are stripped and enforcement runs"
  # Replace the fmt line with a CRLF-terminated mismatch.
  sed -i '/^fmt\//d' "$LOCKFILE"
  printf 'fmt/10.1.1\r\n' >> "$LOCKFILE"
  local out
  out=$(_capture b) || return 1
  assert_contains "$out" 'pinning fmt to 10\.1\.1' || return 1
  assert_version fmt '10.1.1' "$BUILD_DIR_EXT"
}
add_test t_crlf_endings

t_configure_skip() {
  _desc "configure meta-operation skips enforcement"
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  local out rc=0
  out=$(_capture b configure: lockfile/) || return 1
  assert_not_contains "$out" 'pinning' || rc=1
  return $rc
}
add_test t_configure_skip

t_disfigure_skip() {
  _desc "disfigure meta-operation skips enforcement"
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  local out rc=0
  out=$(_capture b disfigure: lockfile/) || rc=$?
  assert_not_contains "$out" 'pinning' || rc=1
  _run b configure: "$BUILD_DIR/" || true
  return $rc
}
add_test t_disfigure_skip

t_info_skip() {
  _desc "info meta-operation skips enforcement"
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  local out
  out=$(_capture b info: lockfile/) || return 1
  assert_not_contains "$out" 'pinning'
}
add_test t_info_skip

# --------------------------------------------------------------------------
# Group D: Lockfile generation (case 19)
# --------------------------------------------------------------------------

t_generation_captures_state() {
  _desc "generation captures the current installed state"
  regenerate_lockfile || return 1

  local lf
  lf=$(cat "$LOCKFILE")

  assert_contains "$lf" "fmt/${FMT_BASE}" || return 1
  assert_contains "$lf" 'spdlog/' || return 1
  assert_contains "$lf" "entt/${ENTT_BASE}" || return 1

  assert_not_contains "$lf" 'libhello' || return 1
  assert_not_contains "$lf" 'libworld' || return 1
  assert_not_contains "$lf" 'xxd' || return 1

  # Immediately after generation must be a no-op.
  local out
  out=$(_capture b) || return 1
  assert_not_contains "$out" 'pinning'
}
add_test t_generation_captures_state

# --------------------------------------------------------------------------
# Group E: Edge cases (cases 20-24)
# --------------------------------------------------------------------------

t_testing_repo_version() {
  _desc "testing-repo version upgrades and downgrades round-trip correctly"
  local rc=0

  # Upgrade entt to testing-repo version.
  sed -i "s|^entt/.*|entt/3.15.0|" "$LOCKFILE"
  local out
  out=$(_capture b) || rc=$?
  assert_contains "$out" 'pinning entt to 3\.15\.0' || rc=1

  if [ "$rc" -eq 0 ]; then
    assert_version entt '3.15.0' "$BUILD_DIR_EXT" || rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    # After upgrade, regeneration must capture 3.15.0.
    regenerate_lockfile || rc=$?
    local lf_content
    lf_content=$(cat "$LOCKFILE")
    assert_contains "$lf_content" 'entt/3\.15\.0' || rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    # Immediately after regeneration, must be a no-op.
    out=$(_capture b) || rc=$?
    assert_not_contains "$out" 'pinning' || rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    # Downgrade back to stable.
    sed -i "s|^entt/.*|entt/3.14.0|" "$LOCKFILE"
    out=$(_capture b) || rc=$?
    assert_contains "$out" 'pinning entt to 3\.14\.0' || rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    assert_version entt '3.14.0' "$BUILD_DIR_EXT" || rc=1
  fi

  return $rc
}
add_test t_testing_repo_version

t_unknown_pin() {
  _desc "unknown package name in bdep.lock is silently skipped"
  printf 'libnothere/1.0.0\n' >> "$LOCKFILE"
  local out
  out=$(_capture b) || return 1
  assert_not_contains "$out" 'pinning libnothere'
}
add_test t_unknown_pin

t_project_package_pin_ignored() {
  _desc "project package name in bdep.lock is silently skipped"
  # If a bdep.lock entry names an initialized project package (e.g. because
  # the lockfile package is embedded in a larger amalgamation where a project
  # package shares a name with something in bdep.lock), bdep status would
  # error if all names were passed in one call: "initialized package X
  # specified with dependency package Y".  The per-name query in
  # lockfile.build avoids this: the project package produces no [cfg-path]
  # line, so it is silently skipped while real deps are still enforced.
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  printf 'lockfile/1.0.0\n' >> "$LOCKFILE"
  local out rc=0
  out=$(_capture b) || { rc=$?; }
  assert_not_contains "$out" 'error:' || rc=1
  assert_contains "$out" 'pinning fmt to 10\.1\.1' || rc=1
  assert_not_contains "$out" 'pinning lockfile' || rc=1
  return $rc
}
add_test t_project_package_pin_ignored

t_pkg_build_no_repo_in_ext_cfg() {
  _desc "enforcement falls back to a linked config when ext config has no repos"
  # Reproduce: ext config has the package but no remote repos registered.
  # bpkg pkg-build name/ver -d <ext-cfg> fails with "unknown package" because
  # the config has no repo containing that version.
  # Fix: the enforcement must fall back to any linked config that has remote
  # repos -- here the project bpkg config (BUILD_DIR) acts as that fallback.

  local repo_urls rc=0
  repo_urls=$(bpkg rep-list -d "$BUILD_DIR_EXT" | awk '$1 !~ /^dir:/ { print $2 }')

  # Add the same remote repos to the project bpkg config so it can serve as
  # the fallback source for pkg-build when ext config has none.
  _run bpkg rep-add $repo_urls -d "$BUILD_DIR" || return 1
  _run bpkg rep-fetch --trust-yes -d "$BUILD_DIR" || return 1

  # Remove remote repos from ext config to simulate restricted-repo scenario.
  for url in $repo_urls; do
    _run bpkg rep-remove "$url" -d "$BUILD_DIR_EXT" || return 1
  done

  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  local out
  out=$(_capture b) || rc=$?

  # Restore: re-add repos to ext, remove from project config.
  for url in $repo_urls; do
    _run bpkg rep-add "$url" -d "$BUILD_DIR_EXT"
  done
  _run bpkg rep-fetch --trust-yes -d "$BUILD_DIR_EXT"
  for url in $repo_urls; do
    _run bpkg rep-remove "$url" -d "$BUILD_DIR" || true
  done

  assert_not_contains "$out" 'unknown package' || rc=1
  assert_contains     "$out" 'pinning fmt to 10\.1\.1' || rc=1
  assert_version fmt '10.1.1' "$BUILD_DIR_EXT" || rc=1
  return $rc
}
add_test t_pkg_build_no_repo_in_ext_cfg

t_config_uuid_target_has_repos() {
  _desc "--config-uuid pkg-build succeeds when the target config has its own repos"
  # Probe: does 'bpkg pkg-build { --config-uuid=<ext> }+ pkg/ver -d bpkg_cfg'
  # succeed when the target config has remote repos? If yes, the repo-borrowing
  # fallback in lockfile.build can be replaced with a single --config-uuid call.
  local legacy_url='https://pkg.cppget.org/1/legacy'
  local ext_uuid
  ext_uuid=$(bpkg cfg-info -d "$BUILD_DIR_EXT" | awk '/^uuid:/{print $2}')

  # Add legacy repo to ext so fmt/10.1.1 is resolvable from ext's own repos.
  _run bpkg rep-add  "$legacy_url" -d "$BUILD_DIR_EXT" || return 1
  _run bpkg rep-fetch --trust-yes -d "$BUILD_DIR_EXT" || return 1

  local out rc=0
  out=$(_capture bpkg pkg-build --yes --no-move \
    '{' "--config-uuid=$ext_uuid" '}+' \
    "fmt/10.1.1" \
    -d "$BUILD_DIR") || rc=$?

  if [ "$rc" -ne 0 ]; then
    printf '--config-uuid with target having repos FAILED (rc=%s)\n' "$rc"
    printf '%s\n' "$out"
  else
    assert_version fmt '10.1.1' "$BUILD_DIR_EXT" || rc=1
  fi

  # Restore fmt and remove the borrowed legacy repo regardless of outcome.
  _run bpkg pkg-build --yes "fmt/${FMT_BASE}" -d "$BUILD_DIR_EXT"
  _run bpkg rep-remove "$legacy_url" -d "$BUILD_DIR_EXT"

  return $rc
}
add_test t_config_uuid_target_has_repos

# --------------------------------------------------------------------------
# Group F: Multi-config topologies (case 25)
# --------------------------------------------------------------------------
# bdep disallows the same package from appearing in two linked bdep-managed
# configurations simultaneously -- bdep sync errors. To test per-config
# dispatch, packages must be spread across distinct configs. fmt/spdlog stay
# in BUILD_DIR_EXT; entt is moved to a new BUILD_DIR_EXTRA config for the
# duration of this test.

_setup_extra_config() {
  _run bpkg cfg-create \
    --uuid  "$UUID_EXTRA" \
    --name  "${CONFIG_NAME}-extra" \
    --directory "$BUILD_DIR_EXTRA" \
    --wipe cc || return 1

  _run bpkg rep-add https://pkg.cppget.org/1/stable https://pkg.cppget.org/1/testing \
    -d "$BUILD_DIR_EXTRA" || return 1
  _run bpkg rep-fetch --trust-yes -d "$BUILD_DIR_EXTRA" || return 1
  _run b configure: "$BUILD_DIR_EXTRA/" || return 1

  _run bpkg cfg-link --directory "$BUILD_DIR" "$BUILD_DIR_EXTRA" --relative || return 1

  # Install entt/3.15.0 in extra (this will be the "installed" version).
  _run bpkg pkg-build --yes "entt/3.15.0" -d "$BUILD_DIR_EXTRA" || return 1

  # Drop entt from external (libhello-tests is a cross-config dependent).
  _run bpkg pkg-drop --yes --drop-dependent entt -d "$BUILD_DIR_EXT" || return 1
  _run bdep sync --yes -d "$PROJECT_DIR" || return 1

  _run bdep config add --directory "$PROJECT_DIR" \
    @"${CONFIG_NAME}-extra" "$BUILD_DIR_EXTRA" --no-default --no-forward || return 1
}

_teardown_extra_config() {
  # Re-install entt at baseline in external before removing extra.
  _run bpkg pkg-build --yes "entt/${ENTT_BASE}" -d "$BUILD_DIR_EXT" || true
  _run bpkg pkg-drop --yes --drop-dependent entt -d "$BUILD_DIR_EXTRA" || true
  _run bdep sync --yes -d "$PROJECT_DIR" || true

  _run bdep config remove --directory "$PROJECT_DIR" @"${CONFIG_NAME}-extra" || true
  _run bpkg cfg-unlink --uuid "$UUID_EXTRA" --directory "$BUILD_DIR" || true
  rm -rf "$BUILD_DIR_EXTRA"
}

t_multi_config() {
  _desc "packages spread across two non-host configs are each enforced in their own config"
  _setup_extra_config || { printf 'setup_extra_config failed\n'; return 1; }

  local rc=0

  # fmt at 10.2.1 in external, entt at 3.15.0 in extra.
  # Pin fmt at 10.1.1 and entt at 3.14.0 to create a mismatch in each config.
  cat > "$LOCKFILE" << 'EOF'
entt/3.14.0
fmt/10.1.1
spdlog/1.14.1+2
EOF

  local out
  out=$(_capture b) || rc=$?

  # Two "pinning" diagnostics, one per config.
  assert_contains "$out" 'pinning fmt to 10\.1\.1' || rc=1
  assert_contains "$out" 'pinning entt to 3\.14\.0' || rc=1

  # bdep sync must fire at most once across all config changes.
  local sync_count
  sync_count=$(printf '%s' "$out" | grep -c 'synchronizing' || true)
  if [ "$sync_count" -gt 1 ]; then
    printf 'bdep sync fired %s times (expected at most 1)\n' "$sync_count"
    rc=1
  fi

  # Verify the final installed versions in each config.
  assert_version fmt  '10.1.1' "$BUILD_DIR_EXT"   || rc=1
  assert_version entt '3.14.0' "$BUILD_DIR_EXTRA"  || rc=1

  _teardown_extra_config
  return $rc
}
add_test t_multi_config

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

if [ ! -f packages.manifest ]; then
  printf "${RED}ERROR${NC}: run this script from the project root (packages.manifest not found)\n"
  exit 1
fi

if [ "$LIST_MODE" = true ]; then
  n=1
  for fn in "${_TESTS[@]}"; do
    if [ -n "$CASE_FILTER" ]; then
      matched=false
      IFS=',' read -ra _filter_nums <<< "$CASE_FILTER"
      for _fn in "${_filter_nums[@]}"; do
        [ "$_fn" = "$n" ] && matched=true && break
      done
      unset _filter_nums _fn
      if [ "$matched" = false ]; then
        (( n++ )) || true
        continue
      fi
    fi
    desc=$(_get_desc "$fn")
    printf 'Case %2d: %s\n' "$n" "$desc"
    (( n++ )) || true
  done
  exit 0
fi

echo "Running lockfile test suite..."
echo ""

echo "Initialising build configurations..."
_init_configs || { printf "${RED}ERROR${NC}: failed to initialise build configurations\n"; exit 1; }
echo ""
echo "Establishing baseline state..."
reset_baseline || { printf "${RED}ERROR${NC}: failed to establish baseline state\n"; exit 1; }
echo ""

n=1
for fn in "${_TESTS[@]}"; do
  run_test "$n" "$fn"
  (( n++ )) || true
done

echo ""
printf '%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
