#!/usr/bin/env bash
# Lockfile validation test suite.
# Run from the project root: bash /tmp/claude/test-lockfile.sh
#
# Each test is self-contained: it establishes its own preconditions, runs b,
# checks the output, then the run_test wrapper resets to baseline state.

set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0

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
CATCH2_BASE=3.7.1
ENTT_BASE=3.14.0

# Extra config vars (Group E only)
BUILD_DIR_EXTRA="${PROJECT_DIR}/../hello-${CONFIG_NAME}-extra"
UUID_EXTRA=$(printf '%s' "hello-${CONFIG_NAME}-extra" | md5sum | \
  awk '{printf "%s-%s-%s-%s-%s",
       substr($1,1,8),substr($1,9,4),substr($1,13,4),substr($1,17,4),substr($1,21,12)}')

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

reset_installed() {
  bpkg pkg-build --yes \
    "fmt/${FMT_BASE}" \
    "spdlog/${SPDLOG_BASE}" \
    "catch2/${CATCH2_BASE}" \
    "entt/${ENTT_BASE}" \
    -d "$BUILD_DIR_EXT" >/dev/null 2>&1
  bdep sync --yes -d "$PROJECT_DIR" >/dev/null 2>&1
}

reset_lockfile() {
  rm -f "$LOCKFILE"
  b config.lockfile.gen=true lockfile/ >/dev/null 2>&1
}

reset_baseline() {
  reset_installed
  reset_lockfile
}

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

# Assert a package is at an exact version in a given bpkg config.
assert_version() {
  local pkg="$1" ver="$2" cfg="$3"
  local status
  status=$(bpkg pkg-status "$pkg" -d "$cfg" 2>&1)
  if ! printf '%s' "$status" | grep -qF "$ver"; then
    printf '%s: expected %s, got: %s\n' "$pkg" "$ver" "$status"
    return 1
  fi
}

# Run a test function, print PASS/FAIL, always reset baseline.
run_test() {
  local desc="$1"
  local fn="$2"
  local detail rc

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

  reset_baseline 2>/dev/null || true
}

# --------------------------------------------------------------------------
# Group A: No-ops and bypass (cases 1-4, 12-13, 15-17)
# --------------------------------------------------------------------------

t_case1_absent_lockfile() {
  mv "$LOCKFILE" "${LOCKFILE}.bak"
  local out
  out=$(b 2>&1) || true
  mv "${LOCKFILE}.bak" "$LOCKFILE"
  assert_not_contains "$out" 'pinning'
}

t_case2_empty_lockfile() {
  printf '' > "$LOCKFILE"
  local out
  out=$(b 2>&1) || true
  assert_not_contains "$out" 'pinning'
}

t_case3_comments_only() {
  printf '# no pins\n\n' > "$LOCKFILE"
  local out
  out=$(b 2>&1) || true
  assert_not_contains "$out" 'pinning'
}

t_case4_all_versions_match() {
  local out
  out=$(b 2>&1) || true
  assert_not_contains "$out" 'pinning'
}

t_case12_bdep_sync_false() {
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  local out
  out=$(BDEP_SYNC=false b 2>&1) || true
  assert_not_contains "$out" 'pinning' || return 1
  assert_version fmt "$FMT_BASE" "$BUILD_DIR_EXT"
}

t_case13_bdep_sync_zero() {
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  local out
  out=$(BDEP_SYNC=0 b 2>&1) || true
  assert_not_contains "$out" 'pinning' || return 1
  assert_version fmt "$FMT_BASE" "$BUILD_DIR_EXT"
}

t_case15_configure_skip() {
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  local out rc=0
  out=$(b configure: 2>&1) || true
  assert_not_contains "$out" 'pinning' || rc=1
  b configure: "$BUILD_DIR/" >/dev/null 2>&1 || true
  return $rc
}

t_case16_disfigure_skip() {
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  local out rc=0
  out=$(b disfigure: 2>&1) || true
  assert_not_contains "$out" 'pinning' || rc=1
  b configure: "$BUILD_DIR/" >/dev/null 2>&1 || true
  return $rc
}

t_case17_info_skip() {
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  local out
  out=$(b info: 2>&1) || true
  assert_not_contains "$out" 'pinning'
}

# --------------------------------------------------------------------------
# Group B: Version enforcement (cases 5-10)
# --------------------------------------------------------------------------

t_case5_single_mismatch() {
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  local out
  out=$(b 2>&1) || true
  assert_contains "$out" 'pinning fmt to 10\.1\.1' || return 1
  assert_version fmt '10.1.1' "$BUILD_DIR_EXT"
}

t_case6_two_packages_same_cfg() {
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  sed -i "s|^catch2/.*|catch2/3.5.1+1|" "$LOCKFILE"
  local out
  out=$(b 2>&1) || true
  assert_contains "$out" 'pinning fmt' || return 1
  assert_contains "$out" 'pinning catch2' || return 1
  assert_version fmt '10.1.1' "$BUILD_DIR_EXT" || return 1
  assert_version catch2 '3.5.1+1' "$BUILD_DIR_EXT"
}

t_case7_transitive_intf_dep() {
  # spdlog/1.14.1+2 requires fmt ^10.1.1, so 10.1.1 is compatible.
  sed -i "s|^fmt/.*|fmt/10.1.1|" "$LOCKFILE"
  local out
  out=$(b 2>&1) || true
  assert_contains "$out" 'pinning fmt to 10\.1\.1' || return 1
  local sync_status
  sync_status=$(bdep status 2>&1)
  assert_contains "$sync_status" 'configured'
}

t_case8_spdlog_fmt_compat() {
  # Both at baseline, lockfile matches: must be a no-op.
  local out
  out=$(b 2>&1) || true
  assert_not_contains "$out" 'pinning'
}

t_case9_partial_mismatch() {
  # Only catch2 mismatches; fmt already at pinned version.
  sed -i "s|^catch2/.*|catch2/3.3.2|" "$LOCKFILE"
  local out
  out=$(b 2>&1) || true
  assert_contains "$out" 'pinning catch2' || return 1
  assert_not_contains "$out" 'pinning fmt' || return 1
  assert_version catch2 '3.3.2' "$BUILD_DIR_EXT"
}

t_case10_revision_suffix() {
  # Strip +2 from spdlog: 1.14.1+2 -> 1.14.1. Enforcer must detect mismatch.
  sed -i 's|^spdlog/\([0-9.]*\)+[0-9]*|spdlog/\1|' "$LOCKFILE"
  local out
  out=$(b 2>&1) || true
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
  out=$(b 2>&1) || true
  assert_not_contains "$out" 'pinning xxd' || return 1
  assert_version xxd '8.2.3075+2' "$BUILD_DIR_HOST"
}

t_case14_crlf_endings() {
  # Replace the fmt line with a CRLF-terminated mismatch.
  sed -i '/^fmt\//d' "$LOCKFILE"
  printf 'fmt/10.1.1\r\n' >> "$LOCKFILE"
  local out
  out=$(b 2>&1) || true
  # build2 built-in sed strips CR; enforcement must run.
  assert_contains "$out" 'pinning fmt to 10\.1\.1' || return 1
  assert_version fmt '10.1.1' "$BUILD_DIR_EXT"
}

t_case19_testing_repo_version() {
  local rc=0

  # Upgrade entt to testing-repo version.
  sed -i "s|^entt/.*|entt/3.15.0|" "$LOCKFILE"
  local out
  out=$(b 2>&1) || true
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
    out=$(b 2>&1) || true
    assert_not_contains "$out" 'pinning' || rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    # Downgrade back to stable.
    sed -i "s|^entt/.*|entt/3.14.0|" "$LOCKFILE"
    out=$(b 2>&1) || true
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
  out=$(b 2>&1) || true
  assert_not_contains "$out" 'pinning libnothere'
}

# --------------------------------------------------------------------------
# Group D: Lockfile generation (case 18)
# --------------------------------------------------------------------------

t_case18_generation_captures_state() {
  rm -f "$LOCKFILE"
  b config.lockfile.gen=true lockfile/ >/dev/null 2>&1

  local lf
  lf=$(cat "$LOCKFILE")

  assert_contains "$lf" "fmt/${FMT_BASE}" || return 1
  assert_contains "$lf" 'spdlog/' || return 1
  assert_contains "$lf" "catch2/${CATCH2_BASE}" || return 1
  assert_contains "$lf" "entt/${ENTT_BASE}" || return 1

  assert_not_contains "$lf" 'libhello' || return 1
  assert_not_contains "$lf" 'libworld' || return 1
  assert_not_contains "$lf" 'xxd' || return 1

  # Immediately after generation must be a no-op.
  local out
  out=$(b 2>&1) || true
  assert_not_contains "$out" 'pinning'
}

# --------------------------------------------------------------------------
# Group E: Multi-config (cases 21-22)
# --------------------------------------------------------------------------

_setup_extra_config() {
  bpkg cfg-create \
    --uuid  "$UUID_EXTRA" \
    --name  "${CONFIG_NAME}-extra" \
    --directory "$BUILD_DIR_EXTRA" \
    --wipe cc >/dev/null 2>&1 || return 1

  bpkg rep-add https://pkg.cppget.org/1/stable https://pkg.cppget.org/1/testing \
    -d "$BUILD_DIR_EXTRA" >/dev/null 2>&1 || return 1
  bpkg rep-fetch --trust-yes -d "$BUILD_DIR_EXTRA" >/dev/null 2>&1 || return 1
  b configure: "$BUILD_DIR_EXTRA/" >/dev/null 2>&1 || return 1

  bpkg cfg-link --directory "$BUILD_DIR" "$BUILD_DIR_EXTRA" --relative >/dev/null 2>&1 || return 1

  # Install entt/3.15.0 in extra (this will be the "installed" version).
  bpkg pkg-build --yes "entt/3.15.0" -d "$BUILD_DIR_EXTRA" >/dev/null 2>&1 || return 1

  # Drop entt from external (libhello-tests is a cross-config dependent).
  bpkg pkg-drop --yes --drop-dependent entt -d "$BUILD_DIR_EXT" >/dev/null 2>&1 || return 1
  bdep sync --yes -d "$PROJECT_DIR" >/dev/null 2>&1 || return 1

  bdep config add --directory "$PROJECT_DIR" \
    @"${CONFIG_NAME}-extra" "$BUILD_DIR_EXTRA" --no-default --no-forward >/dev/null 2>&1 || return 1
}

_teardown_extra_config() {
  # Re-install entt at baseline in external before removing extra.
  bpkg pkg-build --yes "entt/${ENTT_BASE}" -d "$BUILD_DIR_EXT" >/dev/null 2>&1 || true
  bpkg pkg-drop --yes --drop-dependent entt -d "$BUILD_DIR_EXTRA" >/dev/null 2>&1 || true
  bdep sync --yes -d "$PROJECT_DIR" >/dev/null 2>&1 || true

  bdep config remove --directory "$PROJECT_DIR" @"${CONFIG_NAME}-extra" >/dev/null 2>&1 || true
  bpkg cfg-unlink --uuid "$UUID_EXTRA" --directory "$BUILD_DIR" >/dev/null 2>&1 || true
  rm -rf "$BUILD_DIR_EXTRA"
}

t_cases21_22_multi_config() {
  _setup_extra_config || { printf 'setup_extra_config failed\n'; return 1; }

  local rc=0

  # fmt at 10.2.1 in external, entt at 3.15.0 in extra.
  # Pin fmt at 10.1.1 and entt at 3.14.0 to create a mismatch in each config.
  cat > "$LOCKFILE" << 'EOF'
catch2/3.7.1
entt/3.14.0
fmt/10.1.1
spdlog/1.14.1+2
EOF

  local out
  out=$(b 2>&1) || true

  # Two "pinning" diagnostics, one per config.
  assert_contains "$out" 'pinning fmt to 10\.1\.1' || rc=1
  assert_contains "$out" 'pinning entt to 3\.14\.0' || rc=1

  # Exactly one bdep sync invocation.
  local sync_count
  sync_count=$(printf '%s' "$out" | grep -c 'synchronizing' || true)
  if [ "$sync_count" -ne 1 ]; then
    printf 'expected 1 synchronizing block, got %s\n' "$sync_count"
    rc=1
  fi

  _teardown_extra_config
  return $rc
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

echo "Verifying project root..."
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
run_test "Case  9: partial mismatch only affects catch2"         t_case9_partial_mismatch
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
run_test "Cases 21-22: packages spread across two non-host configs" t_cases21_22_multi_config

echo ""
printf '%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
