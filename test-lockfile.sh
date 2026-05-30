#!/usr/bin/env bash
# Lockfile validation test suite.
# Run from the project root: bash test-lockfile.sh [--quiet] [--case=N[,N...]]
#
# --quiet      suppress per-command output (only show PASS/FAIL lines)
# --case=N     run only the listed case numbers (comma-separated); e.g.
#              --case=5 or --case=5,6,21
#
# Each test is self-contained: it establishes its own preconditions, runs b,
# checks the output, then the run_test wrapper resets to baseline state.

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

for _arg in "$@"; do
  case "$_arg" in
    --quiet)   QUIET=true ;;
    --case=*)  CASE_FILTER="${_arg#--case=}" ;;
    *) printf 'unknown argument: %s\n' "$_arg" >&2; exit 1 ;;
  esac
done
unset _arg

_pass() { printf "${GREEN}[PASS]${NC} %s\n" "$*"; (( ++PASS_COUNT )) || true; }
_fail() { printf "${RED}[FAIL]${NC} %s\n" "$*"; (( ++FAIL_COUNT )) || true; }

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

# Extra config vars (Group E only)
BUILD_DIR_EXTRA="${PROJECT_DIR}/../hello-${CONFIG_NAME}-extra"
UUID_EXTRA=$(printf '%s' "hello-${CONFIG_NAME}-extra" | md5sum | \
  awk '{printf "%s-%s-%s-%s-%s",
       substr($1,1,8),substr($1,9,4),substr($1,13,4),substr($1,17,4),substr($1,21,12)}')

# --------------------------------------------------------------------------
# Output helpers
# --------------------------------------------------------------------------

# Run a command, writing live output to fd 3 (original stdout) unless --quiet.
# Use for fire-and-forget setup/teardown commands.
_run() {
  if [ "$QUIET" = true ]; then
    "$@" >/dev/null 2>&1
  else
    "$@" >&3 2>&3
  fi
}

# Run a command and capture its combined stdout+stderr for assertion, while
# also streaming output live to fd 3 (original stdout) unless --quiet.
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
    -d "$BUILD_DIR_EXT"
  _run bdep sync --yes -d "$PROJECT_DIR"
}

reset_lockfile() {
  rm -f "$LOCKFILE"
  b -q config.lockfile.gen=true lockfile/ >/dev/null 2>&1
}

reset_baseline() {
  reset_installed
  reset_lockfile
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

# Assert a package is directly configured in a given bpkg config at an exact
# version.  "Directly" means the status line has no [path] bracket after the
# package name -- a bracket would indicate the package was silently relocated
# to a linked configuration instead.
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
  local desc="$1"
  local fn="$2"
  local detail rc

  if [ -n "$CASE_FILTER" ]; then
    # Extract all numbers from the label prefix (text before the first ':').
    local label nums matched
    label="${desc%%:*}"
    nums=$(printf '%s' "$label" | grep -oE '[0-9]+' | tr '\n' ',')
    matched=false
    IFS=',' read -ra _filter_nums <<< "$CASE_FILTER"
    for _fn in "${_filter_nums[@]}"; do
      if [ -n "$_fn" ] && printf '%s' ",$nums" | grep -qF ",$_fn,"; then
        matched=true
        break
      fi
    done
    unset _filter_nums _fn
    if [ "$matched" = false ]; then
      return 0
    fi
  fi

  detail=$( "$fn" 2>&1 )
  rc=$?

  if [ "$rc" -eq 0 ]; then
    _pass "$desc"
  else
    _fail "$desc"
    if [ -n "$detail" ]; then
      printf '  %s\n' "$detail" | head -10
    fi
  fi

  reset_baseline || true
}

# --------------------------------------------------------------------------
# Group A: No-ops and bypass (cases 1-4, 12-13, 15-17)
# --------------------------------------------------------------------------

t_case1_absent_lockfile() {
  mv "$LOCKFILE" "${LOCKFILE}.bak"
  local out
  out=$(_capture b) || true
  mv "${LOCKFILE}.bak" "$LOCKFILE"
  assert_not_contains "$out" 'pinning'
}

t_case2_empty_lockfile() {
  printf '' > "$LOCKFILE"
  local out
  out=$(_capture b) || true
  assert_not_contains "$out" 'pinning'
}

t_case3_comments_only() {
  printf '# no pins\n\n' > "$LOCKFILE"
  local out
  out=$(_capture b) || true
  assert_not_contains "$out" 'pinning'
}

t_case4_all_versions_match() {
  local out
  out=$(_capture b) || true
  assert_not_contains "$out" 'pinning'
}

t_case12_bdep_sync_false() {
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  local out
  out=$(BDEP_SYNC=false _capture b) || true
  assert_not_contains "$out" 'pinning' || return 1
  assert_version fmt "$FMT_BASE" "$BUILD_DIR_EXT"
}

t_case13_bdep_sync_zero() {
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  local out
  out=$(BDEP_SYNC=0 _capture b) || true
  assert_not_contains "$out" 'pinning' || return 1
  assert_version fmt "$FMT_BASE" "$BUILD_DIR_EXT"
}

t_case15_configure_skip() {
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  local out rc=0
  out=$(_capture b configure: lockfile/) || true
  assert_not_contains "$out" 'pinning' || rc=1
  return $rc
}

t_case16_disfigure_skip() {
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  local out rc=0
  out=$(_capture b disfigure: lockfile/) || true
  assert_not_contains "$out" 'pinning' || rc=1
  b configure: "$BUILD_DIR/" >/dev/null 2>&1 || true
  return $rc
}

t_case17_info_skip() {
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  local out
  out=$(_capture b info: lockfile/) || true
  assert_not_contains "$out" 'pinning'
}

# --------------------------------------------------------------------------
# Group B: Version enforcement (cases 5-10)
# --------------------------------------------------------------------------

t_case5_single_mismatch() {
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  local out
  out=$(_capture b) || true
  assert_contains "$out" 'pinning fmt to 10\.1\.1' || return 1
  assert_version fmt '10.1.1' "$BUILD_DIR_EXT"
}

t_case6_two_packages_same_cfg() {
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  sed -i "s|^entt/.*|entt/3.13.2|" "$LOCKFILE"
  local out
  out=$(_capture b) || true
  assert_contains "$out" 'pinning fmt' || return 1
  assert_contains "$out" 'pinning entt' || return 1
  assert_version fmt '10.1.1' "$BUILD_DIR_EXT" || return 1
  assert_version entt '3.13.2' "$BUILD_DIR_EXT"
}

t_case7_transitive_intf_dep() {
  # spdlog/1.14.1+2 requires fmt ^10.1.1, so 10.1.1 is compatible.
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  local out
  out=$(_capture b) || true
  assert_contains "$out" 'pinning fmt to 10\.1\.1' || return 1
  assert_version fmt '10.1.1' "$BUILD_DIR_EXT" || return 1
  local sync_status
  sync_status=$(bdep status 2>&1)
  assert_contains "$sync_status" 'configured'
}

t_case8_spdlog_fmt_compat() {
  # Both at baseline, lockfile matches: must be a no-op.
  local out
  out=$(_capture b) || true
  assert_not_contains "$out" 'pinning'
}

t_case9_partial_mismatch() {
  # Only entt mismatches; fmt already at pinned version.
  sed -i "s|^entt/.*|entt/3.13.2|" "$LOCKFILE"
  local out
  out=$(_capture b) || true
  assert_contains "$out" 'pinning entt' || return 1
  assert_not_contains "$out" 'pinning fmt' || return 1
  assert_version entt '3.13.2' "$BUILD_DIR_EXT" || return 1
  assert_version fmt "$FMT_BASE" "$BUILD_DIR_EXT"
}

t_case10_revision_suffix() {
  # Strip +2 from spdlog: 1.14.1+2 -> 1.14.1. Enforcer must detect mismatch.
  sed -i 's|^spdlog/\([0-9.]*\)+[0-9]*|spdlog/\1|' "$LOCKFILE"
  local out
  out=$(_capture b) || true
  # bpkg pkg-build may fail (1.14.1 without suffix may not exist); the
  # important check is that the diagnostic fired.
  assert_contains "$out" 'pinning spdlog'
}

# --------------------------------------------------------------------------
# Group C: Edge cases (cases 11, 14, 19, 20)
# --------------------------------------------------------------------------

t_case11_host_config_skip() {
  # xxd lives in @host. The enforcer must skip host-type configs entirely.
  printf 'xxd/1.0.0\n' >> "$LOCKFILE"
  local out
  out=$(_capture b) || true
  assert_not_contains "$out" 'pinning xxd' || return 1
  assert_version xxd '8.2.3075+2' "$BUILD_DIR_HOST"
}

t_case14_crlf_endings() {
  # Replace the fmt line with a CRLF-terminated mismatch.
  sed -i '/^fmt\//d' "$LOCKFILE"
  printf 'fmt/10.1.1\r\n' >> "$LOCKFILE"
  local out
  out=$(_capture b) || true
  # build2 built-in sed strips CR; enforcement must run.
  assert_contains "$out" 'pinning fmt to 10\.1\.1' || return 1
  assert_version fmt '10.1.1' "$BUILD_DIR_EXT"
}

t_case19_testing_repo_version() {
  local rc=0

  # Upgrade entt to testing-repo version.
  sed -i "s|^entt/.*|entt/3.15.0|" "$LOCKFILE"
  local out
  out=$(_capture b) || true
  assert_contains "$out" 'pinning entt to 3\.15\.0' || rc=1

  if [ "$rc" -eq 0 ]; then
    assert_version entt '3.15.0' "$BUILD_DIR_EXT" || rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    # After upgrade, regeneration must capture 3.15.0.
    reset_lockfile
    local lf_content
    lf_content=$(cat "$LOCKFILE")
    assert_contains "$lf_content" 'entt/3\.15\.0' || rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    # Immediately after regeneration, must be a no-op.
    out=$(_capture b) || true
    assert_not_contains "$out" 'pinning' || rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    # Downgrade back to stable.
    sed -i "s|^entt/.*|entt/3.14.0|" "$LOCKFILE"
    out=$(_capture b) || true
    assert_contains "$out" 'pinning entt to 3\.14\.0' || rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    assert_version entt '3.14.0' "$BUILD_DIR_EXT" || rc=1
  fi

  return $rc
}

t_case20_unknown_pin() {
  printf 'libnothere/1.0.0\n' >> "$LOCKFILE"
  local out
  out=$(_capture b) || true
  assert_not_contains "$out" 'pinning libnothere'
}

t_case24_pkg_build_no_repo_in_ext_cfg() {
  # Reproduce: ext config has the package but no remote repos registered.
  # bpkg pkg-build name/ver -d <ext-cfg> fails with "unknown package" because
  # the config has no repo containing that version.
  # Fix: the enforcement must fall back to any linked config that has remote
  # repos -- here the project bpkg config (BUILD_DIR) acts as that fallback.
  # In real projects bdep init populates that config from repositories.manifest.

  local repo_urls rc=0
  repo_urls=$(bpkg rep-list -d "$BUILD_DIR_EXT" | awk '$1 !~ /^dir:/ { print $2 }')

  # Add the same remote repos to the project bpkg config so it can serve as
  # the fallback source for pkg-build when ext config has none.
  _run bpkg rep-add $repo_urls -d "$BUILD_DIR"
  _run bpkg rep-fetch --trust-yes -d "$BUILD_DIR"

  # Remove remote repos from ext config to simulate restricted-repo scenario.
  for url in $repo_urls; do
    _run bpkg rep-remove "$url" -d "$BUILD_DIR_EXT"
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

# --------------------------------------------------------------------------
# Group F: --config-uuid probe (case 25)
# --------------------------------------------------------------------------

t_case25_config_uuid_target_has_repos() {
  # Probe: does 'bpkg pkg-build { --config-uuid=<ext> }+ pkg/ver -d bpkg_cfg'
  # succeed when the target config has remote repos? If yes, the repo-borrowing
  # fallback in lockfile.build can be replaced with a single --config-uuid call.
  local legacy_url='https://pkg.cppget.org/1/legacy'
  local ext_uuid
  ext_uuid=$(bpkg cfg-info -d "$BUILD_DIR_EXT" | awk '/^uuid:/{print $2}')

  # Add legacy repo to ext so fmt/10.1.1 is resolvable from ext's own repos.
  _run bpkg rep-add  "$legacy_url" -d "$BUILD_DIR_EXT"
  _run bpkg rep-fetch --trust-yes -d "$BUILD_DIR_EXT"

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

t_case23_project_package_pin_ignored() {
  # If a bdep.lock entry names an initialized project package (e.g. because
  # the lockfile package is embedded in a larger amalgamation where a project
  # package shares a name with something in bdep.lock), bdep status would
  # error if all names were passed in one call: "initialized package X
  # specified with dependency package Y".  The per-name query in
  # lockfile.build avoids this: the project package produces no [cfg-path]
  # line, so it is silently skipped while real deps are still enforced.
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  # 'lockfile' is an initialized project package in this amalgamation.
  printf 'lockfile/1.0.0\n' >> "$LOCKFILE"
  local out rc=0
  out=$(_capture b) || { rc=$?; }
  assert_not_contains "$out" 'error:' || rc=1
  assert_contains "$out" 'pinning fmt to 10\.1\.1' || rc=1
  assert_not_contains "$out" 'pinning lockfile' || rc=1
  return $rc
}

# --------------------------------------------------------------------------
# Group D: Lockfile generation (case 18)
# --------------------------------------------------------------------------

t_case18_generation_captures_state() {
  rm -f "$LOCKFILE"
  _run b config.lockfile.gen=true lockfile/

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
  out=$(_capture b) || true
  assert_not_contains "$out" 'pinning'
}

# --------------------------------------------------------------------------
# Group E: Multi-config (cases 21-22)
# --------------------------------------------------------------------------

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

t_cases21_22_multi_config() {
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
  out=$(_capture b) || true

  # Two "pinning" diagnostics, one per config.
  assert_contains "$out" 'pinning fmt to 10\.1\.1' || rc=1
  assert_contains "$out" 'pinning entt to 3\.14\.0' || rc=1

  # bdep sync must fire at most once across all config changes.
  # (It may produce no "synchronizing:" output when packages are already in
  # sync after the bpkg builds, so only check it did not fire more than once.)
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

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

if [ ! -f packages.manifest ]; then
  printf "${RED}ERROR${NC}: run this script from the project root (packages.manifest not found)\n"
  exit 1
fi

echo "Running lockfile test suite..."
echo ""

run_test "Case  1: absent lockfile is a no-op"                   t_case1_absent_lockfile
run_test "Case  2: empty lockfile is a no-op"                    t_case2_empty_lockfile
run_test "Case  3: comments-only lockfile is a no-op"            t_case3_comments_only
run_test "Case  4: all versions already match is a no-op"        t_case4_all_versions_match
run_test "Case  5: single package version mismatch enforced"     t_case5_single_mismatch
run_test "Case  6: two packages in same config batched"          t_case6_two_packages_same_cfg
run_test "Case  7: transitive interface dep triggers sync"        t_case7_transitive_intf_dep
run_test "Case  8: spdlog/fmt version compatibility (no-op)"     t_case8_spdlog_fmt_compat
run_test "Case  9: partial mismatch only affects entt"           t_case9_partial_mismatch
run_test "Case 10: +N revision suffix exact string comparison"   t_case10_revision_suffix
run_test "Case 11: host configuration is skipped"                t_case11_host_config_skip
run_test "Case 12: BDEP_SYNC=false bypasses enforcement"         t_case12_bdep_sync_false
run_test "Case 13: BDEP_SYNC=0 bypasses enforcement"             t_case13_bdep_sync_zero
run_test "Case 14: CRLF line endings stripped correctly"         t_case14_crlf_endings
run_test "Case 15: configure meta-operation skips enforcement"   t_case15_configure_skip
run_test "Case 16: disfigure meta-operation skips enforcement"   t_case16_disfigure_skip
run_test "Case 17: info meta-operation skips enforcement"        t_case17_info_skip
run_test "Case 18: generation captures current versions"         t_case18_generation_captures_state
run_test "Case 19: testing-repo version round-trips correctly"   t_case19_testing_repo_version
run_test "Case 20: unknown pin silently skipped"                 t_case20_unknown_pin
run_test "Case 23: project package name in bdep.lock skipped"    t_case23_project_package_pin_ignored
run_test "Case 24: enforcement works when ext cfg has no repos"  t_case24_pkg_build_no_repo_in_ext_cfg
run_test "Case 25: --config-uuid works when target cfg has repos" t_case25_config_uuid_target_has_repos
run_test "Cases 21-22: packages spread across two non-host configs" t_cases21_22_multi_config

echo ""
printf '%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
